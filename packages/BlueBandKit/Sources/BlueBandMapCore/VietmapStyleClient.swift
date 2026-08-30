import Foundation
import CoreFoundation

public struct VectorTileTemplate: Equatable, Sendable {
    public let urlTemplate: String
    public let sourceLayers: [String]
    public let minimumZoom: Int?
    public let maximumZoom: Int?

    public init(
        urlTemplate: String,
        sourceLayers: [String],
        minimumZoom: Int? = nil,
        maximumZoom: Int? = nil
    ) {
        self.urlTemplate = urlTemplate
        self.sourceLayers = sourceLayers
        self.minimumZoom = minimumZoom
        self.maximumZoom = maximumZoom
    }

    public func url(z: Int, x: Int, y: Int, tileMapKey: String) throws -> URL {
        guard z >= 0, x >= 0, y >= 0 else { throw VietmapStyleError.invalidTileTemplate }
        let key = try VietmapStyleClient.validatedKey(tileMapKey)
        let expanded = urlTemplate
            .replacingOccurrences(of: "{z}", with: String(z))
            .replacingOccurrences(of: "{x}", with: String(x))
            .replacingOccurrences(of: "{y}", with: String(y))
            .replacingOccurrences(of: "{apikey}", with: VietmapStyleClient.percentEncodedQueryValue(key))
        guard let url = URL(string: expanded), VietmapStyleClient.isAllowedHTTPSHost(url) else {
            throw VietmapStyleError.invalidTileTemplate
        }
        return url
    }
}

public enum VietmapStyleError: Swift.Error, Equatable, Sendable {
    case missingTileMapKey
    case invalidKey
    case httpStatus(Int)
    case wrongContentType
    case responseTooLarge
    case invalidJSON
    case unsupportedSource
    case missingTiles
    case foreignHost
    case invalidTileTemplate
    case noRoadLayers
}

public struct VietmapStyleClient: Sendable {
    private struct ResolvedTileSource: Equatable {
        let template: String
        let minimumZoom: Int?
        let maximumZoom: Int?
    }

    private static let styleMaximumResponseBytes = 2 * 1_024 * 1_024
    private let transport: any MapHTTPTransport

    public init(transport: any MapHTTPTransport) {
        self.transport = transport
    }

    public func discover(tileMapKey: String) async throws -> VectorTileTemplate {
        let key = try Self.validatedKey(tileMapKey)
        let styleURL = try Self.authorizedURL(
            "https://maps.vietmap.vn/maps/styles/tm/style.json?apikey={apikey}",
            key: key
        )
        let style = try await fetchJSONObject(styleURL, key: key)
        guard let sources = style["sources"] as? [String: Any],
              let layers = style["layers"] as? [[String: Any]] else {
            throw VietmapStyleError.invalidJSON
        }

        var selectedLayersBySource: [String: Set<String>] = [:]
        for layer in layers {
            guard (layer["type"] as? String)?.lowercased() == "line",
                  let source = layer["source"] as? String else { continue }
            let sourceLayer = layer["source-layer"] as? String ?? ""
            let layerID = layer["id"] as? String ?? ""
            let searchable = (sourceLayer + " " + layerID).lowercased()
            guard Self.roadTokens.contains(where: { searchable.contains($0) }) else { continue }
            selectedLayersBySource[source, default: []].insert(sourceLayer.isEmpty ? layerID : sourceLayer)
        }
        guard !selectedLayersBySource.isEmpty else { throw VietmapStyleError.noRoadLayers }

        var discoveredSource: ResolvedTileSource?
        var selectedSourceLayers = Set<String>()
        for (sourceName, sourceLayers) in selectedLayersBySource {
            guard let source = sources[sourceName] as? [String: Any],
                  (source["type"] as? String)?.lowercased() == "vector" else {
                throw VietmapStyleError.unsupportedSource
            }
            let resolvedSource = try await resolveTileSource(source: source, key: key)
            if let discoveredSource, discoveredSource != resolvedSource {
                throw VietmapStyleError.unsupportedSource
            }
            discoveredSource = resolvedSource
            selectedSourceLayers.formUnion(sourceLayers)
        }

        guard let discoveredSource else { throw VietmapStyleError.missingTiles }
        return VectorTileTemplate(
            urlTemplate: discoveredSource.template,
            sourceLayers: selectedSourceLayers.sorted(),
            minimumZoom: discoveredSource.minimumZoom,
            maximumZoom: discoveredSource.maximumZoom
        )
    }

    private func resolveTileSource(source: [String: Any], key: String) async throws -> ResolvedTileSource {
        let sourceBounds = try Self.zoomBounds(source)
        if let tiles = source["tiles"] as? [String], let first = tiles.first {
            return ResolvedTileSource(
                template: try Self.sanitizedTileTemplate(first, key: key),
                minimumZoom: sourceBounds.minimum,
                maximumZoom: sourceBounds.maximum
            )
        }
        if let tileJSONURL = source["url"] as? String {
            guard let parsed = URL(string: tileJSONURL), Self.isAllowedHTTPSHost(parsed) else {
                throw VietmapStyleError.foreignHost
            }
            let authorized = try Self.authorizedURL(tileJSONURL, key: key)
            let tileJSON = try await fetchJSONObject(authorized, key: key)
            guard let tiles = tileJSON["tiles"] as? [String], let first = tiles.first else {
                throw VietmapStyleError.missingTiles
            }
            let tileJSONBounds = try Self.zoomBounds(tileJSON)
            let minimumZoom = sourceBounds.minimum ?? tileJSONBounds.minimum
            let maximumZoom = sourceBounds.maximum ?? tileJSONBounds.maximum
            try Self.validateZoomRange(minimum: minimumZoom, maximum: maximumZoom)
            return ResolvedTileSource(
                template: try Self.sanitizedTileTemplate(first, key: key),
                minimumZoom: minimumZoom,
                maximumZoom: maximumZoom
            )
        }
        throw VietmapStyleError.missingTiles
    }

    private static func zoomBounds(_ object: [String: Any]) throws -> (minimum: Int?, maximum: Int?) {
        let minimum = try zoomBound(object["minzoom"])
        let maximum = try zoomBound(object["maxzoom"])
        try validateZoomRange(minimum: minimum, maximum: maximum)
        return (minimum, maximum)
    }

    private static func zoomBound(_ raw: Any?) throws -> Int? {
        guard let raw else { return nil }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw VietmapStyleError.unsupportedSource
        }
        let value = number.doubleValue
        guard value.isFinite, value.rounded(.towardZero) == value, (0...22).contains(value) else {
            throw VietmapStyleError.unsupportedSource
        }
        return Int(value)
    }

    private static func validateZoomRange(minimum: Int?, maximum: Int?) throws {
        if let minimum, let maximum, minimum > maximum {
            throw VietmapStyleError.unsupportedSource
        }
    }

    private func fetchJSONObject(_ url: URL, key: String) async throws -> [String: Any] {
        let request = MapHTTPRequest(
            method: "GET",
            url: url,
            headers: ["Accept": "application/json"],
            body: Data(),
            maximumResponseBytes: Self.styleMaximumResponseBytes
        )
        let response = try await transport.execute(request)
        guard response.body.count <= Self.styleMaximumResponseBytes else {
            throw VietmapStyleError.responseTooLarge
        }
        guard response.statusCode == 200 else {
            throw VietmapStyleError.httpStatus(response.statusCode)
        }
        guard let contentType = response.header(named: "Content-Type") else {
            throw VietmapStyleError.wrongContentType
        }
        let mediaType = String(contentType.split(separator: ";", maxSplits: 1)[0])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard mediaType == "application/json" else { throw VietmapStyleError.wrongContentType }
        guard let object = try? JSONSerialization.jsonObject(with: response.body),
              let dictionary = object as? [String: Any] else {
            throw VietmapStyleError.invalidJSON
        }
        _ = key
        return dictionary
    }

    static func validatedKey(_ key: String) throws -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 512 else {
            throw VietmapStyleError.missingTileMapKey
        }
        guard trimmed.utf8.allSatisfy({ $0 > 31 && $0 != 127 }) else {
            throw VietmapStyleError.invalidKey
        }
        return trimmed
    }

    static func isAllowedHTTPSHost(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "maps.vietmap.vn"
            && url.user == nil
            && url.password == nil
    }

    static func percentEncodedQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#/?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private static func authorizedURL(_ raw: String, key: String) throws -> URL {
        let replaced = raw.replacingOccurrences(of: "{apikey}", with: percentEncodedQueryValue(key))
        guard var components = URLComponents(string: replaced),
              let initialURL = components.url,
              isAllowedHTTPSHost(initialURL) else {
            throw VietmapStyleError.foreignHost
        }
        var queryItems = components.queryItems ?? []
        if let index = queryItems.firstIndex(where: { $0.name.lowercased() == "apikey" }) {
            queryItems[index].value = percentEncodedQueryValue(key)
        } else {
            queryItems.append(URLQueryItem(name: "apikey", value: key))
        }
        components.queryItems = queryItems
        guard let url = components.url, isAllowedHTTPSHost(url) else {
            throw VietmapStyleError.foreignHost
        }
        return url
    }

    private static func sanitizedTileTemplate(_ raw: String, key: String) throws -> String {
        let withPlaceholder = raw.replacingOccurrences(of: key, with: "{apikey}")
        let candidate: String
        if withPlaceholder.contains("{apikey}") {
            candidate = withPlaceholder
        } else if var components = URLComponents(string: raw), let url = components.url {
            guard isAllowedHTTPSHost(url) else { throw VietmapStyleError.foreignHost }
            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "apikey", value: "{apikey}"))
            components.queryItems = queryItems
            candidate = components.string ?? raw
        } else {
            throw VietmapStyleError.invalidTileTemplate
        }

        let validationURL = candidate
            .replacingOccurrences(of: "{z}", with: "0")
            .replacingOccurrences(of: "{x}", with: "0")
            .replacingOccurrences(of: "{y}", with: "0")
            .replacingOccurrences(of: "{apikey}", with: percentEncodedQueryValue(key))
        guard candidate.contains("{z}"), candidate.contains("{x}"), candidate.contains("{y}"),
              let url = URL(string: validationURL), isAllowedHTTPSHost(url) else {
            throw VietmapStyleError.invalidTileTemplate
        }
        return candidate
    }

    private static let roadTokens = ["road", "street", "transportation", "highway", "bridge", "tunnel"]
}
