import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import BlueBandMapCore

struct URLSessionHTTPTransport: MapHTTPTransport, Sendable {
    func execute(_ request: MapHTTPRequest) async throws -> MapHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        var headers: [String: String] = [:]
        for (rawName, rawValue) in httpResponse.allHeaderFields {
            let name = rawName as? String ?? String(describing: rawName)
            headers[name] = rawValue as? String ?? String(describing: rawValue)
        }
        return MapHTTPResponse(
            statusCode: httpResponse.statusCode,
            headers: headers,
            body: data
        )
    }
}
