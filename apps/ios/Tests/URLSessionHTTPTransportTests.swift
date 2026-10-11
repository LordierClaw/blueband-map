import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import BlueBandMapCore
@testable import BlueBandMap

final class URLSessionHTTPTransportTests: XCTestCase {
    override func tearDown() {
        TestURLProtocol.handler = nil
        super.tearDown()
    }

    func testUsesEphemeralCacheCookieDisabledTimeoutConfiguration() {
        let transport = URLSessionHTTPTransport(
            timeout: 7,
            protocolClasses: [TestURLProtocol.self]
        )
        let configuration = transport.makeConfiguration()

        XCTAssertEqual(configuration.identifier, nil)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 7)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 7)
    }

    func testBuildsExactRequestAndStreamsSuccessfulResponse() async throws {
        let expectedBody = Data("request-body".utf8)
        TestURLProtocol.handler = { protocolInstance in
            XCTAssertEqual(protocolInstance.request.httpMethod, "POST")
            XCTAssertEqual(protocolInstance.requestBody, expectedBody)
            XCTAssertEqual(protocolInstance.request.value(forHTTPHeaderField: "apikey"), "service-key")
            XCTAssertEqual(protocolInstance.request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertFalse(protocolInstance.request.httpShouldHandleCookies)
            protocolInstance.respond(status: 200, headers: ["Content-Type": "image/png"])
            protocolInstance.load(Data([1, 2]))
            protocolInstance.load(Data([3, 4]))
            protocolInstance.finish()
        }
        let transport = URLSessionHTTPTransport(protocolClasses: [TestURLProtocol.self])

        let response = try await transport.execute(MapHTTPRequest(
            method: "POST",
            url: URL(string: "https://maps.example/static")!,
            headers: ["apikey": "service-key"],
            body: expectedBody
        ))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.header(named: "content-type"), "image/png")
        XCTAssertEqual(response.body, Data([1, 2, 3, 4]))
    }

    func testRejectsRedirectWithoutIssuingRedirectedRequest() async {
        let requestCount = TestLockedCounter()
        TestURLProtocol.handler = { protocolInstance in
            requestCount.increment()
            let redirect = URLRequest(url: URL(string: "https://redirected.example/map.png")!)
            let response = HTTPURLResponse(
                url: protocolInstance.request.url!,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": redirect.url!.absoluteString]
            )!
            protocolInstance.client?.urlProtocol(
                protocolInstance,
                wasRedirectedTo: redirect,
                redirectResponse: response
            )
        }
        let transport = URLSessionHTTPTransport(protocolClasses: [TestURLProtocol.self])

        do {
            _ = try await transport.execute(request())
            XCTFail("Expected redirect rejection")
        } catch {
            XCTAssertEqual(error as? URLSessionHTTPTransport.Error, .redirectRejected)
        }
        XCTAssertEqual(requestCount.value, 1)
    }

    func testRejectsOversizedContentLengthBeforeLoadingBody() async {
        TestURLProtocol.handler = { protocolInstance in
            protocolInstance.respond(status: 200, headers: [
                "Content-Length": String(256 * 1_024 + 1),
                "Content-Type": "image/png",
            ])
            protocolInstance.finish()
        }
        let transport = URLSessionHTTPTransport(protocolClasses: [TestURLProtocol.self])

        do {
            _ = try await transport.execute(request())
            XCTFail("Expected size rejection")
        } catch {
            XCTAssertEqual(error as? URLSessionHTTPTransport.Error, .responseTooLarge)
        }
    }

    func testRejectsStreamingBodyAsSoonAsCapIsExceededWithoutContentLength() async {
        TestURLProtocol.handler = { protocolInstance in
            protocolInstance.respond(status: 200, headers: ["Content-Type": "image/png"])
            protocolInstance.load(Data(repeating: 0, count: 256 * 1_024))
            protocolInstance.load(Data([1]))
            protocolInstance.finish()
        }
        let transport = URLSessionHTTPTransport(protocolClasses: [TestURLProtocol.self])

        do {
            _ = try await transport.execute(request())
            XCTFail("Expected streaming size rejection")
        } catch {
            XCTAssertEqual(error as? URLSessionHTTPTransport.Error, .responseTooLarge)
        }
    }

    func testUsesRequestSpecificResponseCap() async {
        TestURLProtocol.handler = { protocolInstance in
            protocolInstance.respond(status: 200, headers: ["Content-Type": "application/json"])
            protocolInstance.load(Data(repeating: 0, count: 65))
            protocolInstance.finish()
        }
        let transport = URLSessionHTTPTransport(protocolClasses: [TestURLProtocol.self])
        do {
            _ = try await transport.execute(MapHTTPRequest(
                method: "GET",
                url: URL(string: "https://maps.example/style.json")!,
                headers: [:],
                body: Data(),
                maximumResponseBytes: 64
            ))
            XCTFail("Expected request-specific cap rejection")
        } catch {
            XCTAssertEqual(error as? URLSessionHTTPTransport.Error, .responseTooLarge)
        }
    }

    func testConcurrentRequestsOnOneSessionReceiveTheirOwnBodies() async throws {
        TestURLProtocol.handler = { protocolInstance in
            let path = protocolInstance.request.url!.lastPathComponent
            protocolInstance.respond(status: 200, headers: ["Content-Type": "application/x-protobuf"])
            protocolInstance.load(Data(path.utf8))
            protocolInstance.load(Data("|end".utf8))
            protocolInstance.finish()
        }
        let transport = URLSessionHTTPTransport(protocolClasses: [TestURLProtocol.self])
        let bodies = try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for index in 0..<12 {
                group.addTask {
                    let response = try await transport.execute(MapHTTPRequest(
                        method: "GET", url: URL(string: "https://maps.example/tile/\(index)")!, headers: [:], body: Data()))
                    return (index, response.body)
                }
            }
            var collected: [Int: Data] = [:]
            for try await (index, body) in group { collected[index] = body }
            return collected
        }
        for index in 0..<12 { XCTAssertEqual(bodies[index], Data("\(index)|end".utf8)) }
        XCTAssertEqual(transport.activeTaskCountForTesting, 0, "completed tasks must leave the shared router")
    }

    func testRejectedAndCancelledRequestsDoNotPoisonTheSharedSession() async throws {
        let transport = URLSessionHTTPTransport(protocolClasses: [TestURLProtocol.self])
        TestURLProtocol.handler = { protocolInstance in
            protocolInstance.respond(status: 200, headers: ["Content-Length": String(256 * 1_024 + 1)])
            protocolInstance.finish()
        }
        do {
            _ = try await transport.execute(request())
            XCTFail("Expected size rejection")
        } catch {
            XCTAssertEqual(error as? URLSessionHTTPTransport.Error, .responseTooLarge)
        }
        TestURLProtocol.handler = { _ in }
        let stalled = Task { try await transport.execute(self.request()) }
        try await Task.sleep(for: .milliseconds(50))
        stalled.cancel()
        do {
            _ = try await stalled.value
            XCTFail("Expected cancellation")
        } catch {}
        TestURLProtocol.handler = { protocolInstance in
            protocolInstance.respond(status: 200, headers: [:])
            protocolInstance.load(Data([9]))
            protocolInstance.finish()
        }
        let response = try await transport.execute(request())
        XCTAssertEqual(response.body, Data([9]))
        for _ in 0..<100 where transport.activeTaskCountForTesting > 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(transport.activeTaskCountForTesting, 0)
    }

    private func request() -> MapHTTPRequest {
        MapHTTPRequest(
            method: "GET",
            url: URL(string: "https://maps.example/static")!,
            headers: [:],
            body: Data()
        )
    }
}

private final class TestURLProtocol: URLProtocol {
    static var handler: ((TestURLProtocol) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(self) }
    override func stopLoading() {}

    var requestBody: Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4 * 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    func respond(status: Int, headers: [String: String]) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    func load(_ data: Data) { client?.urlProtocol(self, didLoad: data) }
    func finish() { client?.urlProtocolDidFinishLoading(self) }
}

private final class TestLockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}
