import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import BlueBandMapCore

final class URLSessionHTTPTransport: MapHTTPTransport, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case nonHTTPResponse
        case redirectRejected
        case responseTooLarge
    }

    private let timeout: TimeInterval
    private let protocolClasses: [AnyClass]?
    private let router: SessionTaskRouter
    private let session: URLSession

    /// One long-lived ephemeral session per transport: concurrent tile requests share
    /// keep-alive/HTTP/2 connections instead of paying DNS+TCP+TLS on every request.
    init(timeout: TimeInterval = 15, protocolClasses: [AnyClass]? = nil) {
        precondition(timeout.isFinite && timeout > 0)
        self.timeout = timeout
        self.protocolClasses = protocolClasses
        let router = SessionTaskRouter()
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        self.router = router
        session = URLSession(
            configuration: Self.configuration(timeout: timeout, protocolClasses: protocolClasses),
            delegate: router,
            delegateQueue: delegateQueue
        )
    }

    deinit { session.invalidateAndCancel() }

    func makeConfiguration() -> URLSessionConfiguration {
        Self.configuration(timeout: timeout, protocolClasses: protocolClasses)
    }

    private static func configuration(timeout: TimeInterval, protocolClasses: [AnyClass]?) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        return configuration
    }

    func execute(_ request: MapHTTPRequest) async throws -> MapHTTPResponse {
        var urlRequest = URLRequest(
            url: request.url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeout
        )
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.httpShouldHandleCookies = false
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let delegate = StreamingRequestDelegate(maximumBodyBytes: request.maximumResponseBytes)
        return try await delegate.execute(urlRequest, in: session, router: router)
    }

    var activeTaskCountForTesting: Int { router.count }
}

/// Session-level delegate that forwards each task's callbacks to its own request state.
private final class SessionTaskRouter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [Int: StreamingRequestDelegate] = [:]

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return handlers.count
    }

    func register(_ handler: StreamingRequestDelegate, for task: URLSessionTask) {
        lock.lock()
        handlers[task.taskIdentifier] = handler
        lock.unlock()
    }

    private func handler(for task: URLSessionTask, removing: Bool = false) -> StreamingRequestDelegate? {
        lock.lock()
        defer { lock.unlock() }
        return removing ? handlers.removeValue(forKey: task.taskIdentifier) : handlers[task.taskIdentifier]
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let handler = handler(for: task) else {
            completionHandler(nil)
            task.cancel()
            return
        }
        handler.urlSession(session, task: task, willPerformHTTPRedirection: response,
                           newRequest: request, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let handler = handler(for: dataTask) else {
            completionHandler(.cancel)
            return
        }
        handler.urlSession(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        handler(for: dataTask)?.urlSession(session, dataTask: dataTask, didReceive: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
        handler(for: task, removing: true)?.urlSession(session, task: task, didCompleteWithError: error)
    }
}

private final class StreamingRequestDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maximumBodyBytes: Int
    private let lock = NSLock()
    private var continuation: CheckedContinuation<MapHTTPResponse, any Swift.Error>?
    private var completedResult: Result<MapHTTPResponse, any Swift.Error>?
    private var task: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var body = Data()
    private var isCompleted = false

    init(maximumBodyBytes: Int) {
        self.maximumBodyBytes = maximumBodyBytes
        body.reserveCapacity(maximumBodyBytes)
    }

    func execute(_ request: URLRequest, in session: URLSession, router: SessionTaskRouter) async throws -> MapHTTPResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let completedResult {
                    lock.unlock()
                    continuation.resume(with: completedResult)
                    return
                }
                self.continuation = continuation
                let task = session.dataTask(with: request)
                self.task = task
                lock.unlock()
                // Register before resume so the shared router never sees an unknown task.
                router.register(self, for: task)
                task.resume()
            }
        } onCancel: { [weak self] in
            self?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
        task.cancel()
        finish(.failure(URLSessionHTTPTransport.Error.redirectRejected))
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            dataTask.cancel()
            finish(.failure(URLSessionHTTPTransport.Error.nonHTTPResponse))
            return
        }
        if httpResponse.expectedContentLength > Int64(maximumBodyBytes) {
            completionHandler(.cancel)
            dataTask.cancel()
            finish(.failure(URLSessionHTTPTransport.Error.responseTooLarge))
            return
        }
        lock.lock()
        self.response = httpResponse
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let exceedsLimit = data.count > maximumBodyBytes - body.count
        if !exceedsLimit { body.append(data) }
        lock.unlock()
        guard exceedsLimit else { return }
        dataTask.cancel()
        finish(.failure(URLSessionHTTPTransport.Error.responseTooLarge))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
        if let error {
            finish(.failure(error))
            return
        }
        lock.lock()
        let response = self.response
        let body = self.body
        lock.unlock()
        guard let response else {
            finish(.failure(URLSessionHTTPTransport.Error.nonHTTPResponse))
            return
        }

        var headers: [String: String] = [:]
        for (rawName, rawValue) in response.allHeaderFields {
            let name = rawName as? String ?? String(describing: rawName)
            let value = rawValue as? String ?? String(describing: rawValue)
            headers[name] = value
        }
        finish(.success(MapHTTPResponse(
            statusCode: response.statusCode,
            headers: headers,
            body: body
        )))
    }

    private func cancel() {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.cancel()
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<MapHTTPResponse, any Swift.Error>) {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }
        isCompleted = true
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
        } else {
            completedResult = result
            lock.unlock()
        }
    }
}
