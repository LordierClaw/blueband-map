import Foundation
import BlueBandCore

/// The bounded subset of the provider's style needed by the wearable CPU renderer.
public struct VietmapMapStyle: Sendable {
    public let template: VectorTileTemplate
    public let layers: [Layer]

    public init(template: VectorTileTemplate, layers: [Layer]) {
        self.template = template
        self.layers = layers
    }

    public struct Layer: Decodable, Sendable {
        public let id: String
        public let type: String
        public let source: String?
        public let sourceLayer: String?
        public let minzoom: Double?
        public let maxzoom: Double?
        public let filter: JSONValue?
        public let paint: [String: JSONValue]?
        public let layout: [String: JSONValue]?

        enum CodingKeys: String, CodingKey {
            case id, type, source, minzoom, maxzoom, filter, paint, layout
            case sourceLayer = "source-layer"
        }

        public func matches(_ feature: MapboxVectorTile.Feature) -> Bool {
            guard let filter else { return true }
            return Self.matches(filter, feature: feature, depth: 0)
        }

        public func number(_ property: String, zoom: Double, fallback: Double) -> Double {
            let value = paint?[property] ?? layout?[property]
            if case let .number(number) = value, number.isFinite { return number }
            guard zoom.isFinite, case let .object(function) = value,
                  case let .array(rawStops) = function["stops"] else { return fallback }
            let stops: [(Double, Double)] = rawStops.compactMap {
                guard case let .array(pair) = $0, pair.count == 2,
                      case let .number(z) = pair[0], case let .number(v) = pair[1],
                      z.isFinite, v.isFinite else { return nil }
                return (z, v)
            }
            guard stops.count == rawStops.count, let first = stops.first else { return fallback }
            if zoom <= first.0 { return first.1 }
            let base: Double
            if case let .number(value) = function["base"] { base = value } else { base = 1 }
            guard base.isFinite, base > 0 else { return fallback }
            for (low, high) in zip(stops, stops.dropFirst()) {
                guard high.0 > low.0 else { return fallback }
                if zoom < high.0 {
                    let fraction = base == 1 ? (zoom - low.0) / (high.0 - low.0) :
                        (pow(base, zoom - low.0) - 1) / (pow(base, high.0 - low.0) - 1)
                    let result = low.1 + (high.1 - low.1) * fraction
                    return result.isFinite ? result : fallback
                }
            }
            return stops.last!.1
        }

        public func text(for feature: MapboxVectorTile.Feature) -> String {
            guard case let .string(template) = layout?["text-field"] else { return "" }
            // Provider v8 text tokens; unknown properties become empty, never literal braces.
            let parts = template.split(separator: "{", omittingEmptySubsequences: false)
            var text = String(parts.first ?? "")
            for part in parts.dropFirst() {
                guard let end = part.firstIndex(of: "}") else { return "" }
                text += feature.properties[String(part[..<end])] ?? ""
                text += part[part.index(after: end)...]
            }
            return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        }

        private static func matches(_ value: JSONValue, feature: MapboxVectorTile.Feature, depth: Int) -> Bool {
            guard depth < 16, case let .array(items) = value,
                  let first = items.first, case let .string(op) = first else { return false }
            let children = items.dropFirst()
            switch op {
            case "all": return children.allSatisfy { matches($0, feature: feature, depth: depth + 1) }
            case "any": return children.contains { matches($0, feature: feature, depth: depth + 1) }
            case "none": return !children.contains { matches($0, feature: feature, depth: depth + 1) }
            default: break
            }
            guard items.count >= 2, case let .string(key) = items[1] else { return false }
            let actual = key == "$type" ? ["Unknown", "Point", "LineString", "Polygon"][Int(feature.geometryType.rawValue)] : feature.properties[key]
            if op == "has" { return actual != nil }
            if op == "!has" { return actual == nil }
            let values = items.dropFirst(2).compactMap { value -> String? in
                switch value {
                case let .string(v): return v
                case let .number(v): return String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), v)
                case let .bool(v): return v ? "true" : "false"
                default: return nil
                }
            }
            guard !values.isEmpty else { return false }
            switch op {
            case "==": return actual == values[0]
            case "!=": return actual != values[0]
            case "in": return actual.map(values.contains) ?? false
            case "!in": return !(actual.map(values.contains) ?? false)
            case ">=", ">", "<=", "<":
                guard let actual, let a = Double(actual), let b = Double(values[0]) else { return false }
                switch op { case ">=": return a >= b; case ">": return a > b; case "<=": return a <= b; default: return a < b }
            default: return false
            }
        }
    }
}
