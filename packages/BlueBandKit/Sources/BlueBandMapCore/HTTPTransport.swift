import Foundation

public struct MapHTTPRequest: Equatable, Sendable {
    public let method: String
    public let url: URL
    public let headers: [String: String]
    public let body: Data

    public init(method: String, url: URL, headers: [String: String], body: Data) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct MapHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public func header(named name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public protocol MapHTTPTransport: Sendable {
    func execute(_ request: MapHTTPRequest) async throws -> MapHTTPResponse
}
