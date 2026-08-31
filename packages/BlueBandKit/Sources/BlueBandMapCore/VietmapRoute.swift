import Foundation

public struct GeoPoint: Equatable, Codable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

public enum NavigationManeuver: String, Codable, Sendable {
    case straight, left, right, uTurn, roundabout, arrive
}

public enum NavigationStatus: String, Codable, Sendable {
    case navigating, gpsLow, limitedMap, rerouting, arrived
}

public struct RouteInstruction: Equatable, Sendable {
    public let distanceMeters: Double
    public let headingDegrees: Int
    public let sign: Int
    public let interval: ClosedRange<Int>
    public let streetName: String

    public init(
        distanceMeters: Double,
        headingDegrees: Int,
        sign: Int,
        interval: ClosedRange<Int>,
        streetName: String
    ) {
        self.distanceMeters = distanceMeters
        self.headingDegrees = headingDegrees
        self.sign = sign
        self.interval = interval
        self.streetName = streetName
    }

    public var maneuver: NavigationManeuver {
        switch sign {
        case -8, 8: .uTurn
        case -7, -3, -2, -1: .left
        case 1, 2, 3, 7: .right
        case 4: .arrive
        case 6: .roundabout
        default: .straight
        }
    }
}

public struct RoutePlan: Equatable, Sendable {
    public let points: [GeoPoint]
    public let instructions: [RouteInstruction]
    public let distanceMeters: Double
    public let alternativePathCount: Int

    public init(
        points: [GeoPoint],
        instructions: [RouteInstruction],
        distanceMeters: Double,
        alternativePathCount: Int = 1
    ) {
        self.points = points
        self.instructions = instructions
        self.distanceMeters = distanceMeters
        self.alternativePathCount = alternativePathCount
    }
}

public enum GooglePolyline5 {
    public enum Error: Swift.Error, Equatable, Sendable { case invalidEncoding, invalidCoordinate }

    public static func decode(_ value: String) throws -> [GeoPoint] {
        let bytes = Array(value.utf8)
        var index = 0, latitude = 0, longitude = 0
        var result = [GeoPoint]()
        while index < bytes.count {
            latitude += try component(bytes, index: &index)
            longitude += try component(bytes, index: &index)
            let point = GeoPoint(latitude: Double(latitude) / 100_000, longitude: Double(longitude) / 100_000)
            guard point.isValid else { throw Error.invalidCoordinate }
            result.append(point)
        }
        guard result.count >= 2 else { throw Error.invalidEncoding }
        return result
    }

    private static func component(_ bytes: [UInt8], index: inout Int) throws -> Int {
        var shift = 0, result = 0
        while true {
            guard index < bytes.count, bytes[index] >= 63, shift <= 30 else { throw Error.invalidEncoding }
            let byte = Int(bytes[index] - 63)
            index += 1
            result |= (byte & 0x1F) << shift
            shift += 5
            if byte < 0x20 { break }
        }
        return (result & 1) == 0 ? result >> 1 : ~(result >> 1)
    }
}

public struct VietmapRouteClient: Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidRequest, httpStatus(Int), wrongContentType, invalidResponse, provider(String)
    }

    private let transport: any MapHTTPTransport

    public init(transport: any MapHTTPTransport) { self.transport = transport }

    public func route(
        origin: GeoPoint,
        destination: GeoPoint,
        serviceKey: String,
        headingDegrees: Int? = nil
    ) async throws -> RoutePlan {
        let request = try Self.request(
            origin: origin,
            destination: destination,
            serviceKey: serviceKey,
            headingDegrees: headingDegrees
        )
        let response = try await transport.execute(request)
        guard response.statusCode == 200 else { throw Error.httpStatus(response.statusCode) }
        if let contentType = response.header(named: "Content-Type") {
            guard contentType.lowercased().hasPrefix("application/json") else { throw Error.wrongContentType }
        }
        return try Self.parse(response.body)
    }

    public static func request(
        origin: GeoPoint,
        destination: GeoPoint,
        serviceKey: String,
        headingDegrees: Int?
    ) throws -> MapHTTPRequest {
        let key = serviceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard origin.isValid, destination.isValid, !key.isEmpty, key.utf8.count <= 512,
              headingDegrees.map({ (0...360).contains($0) }) ?? true else { throw Error.invalidRequest }
        var components = URLComponents(string: "https://maps.vietmap.vn/api/route/v4")!
        components.queryItems = [
            URLQueryItem(name: "apikey", value: key),
            URLQueryItem(name: "point", value: decimal(origin.latitude) + "," + decimal(origin.longitude)),
            URLQueryItem(name: "point", value: decimal(destination.latitude) + "," + decimal(destination.longitude)),
            URLQueryItem(name: "points_encoded", value: "true"),
            URLQueryItem(name: "vehicle", value: "motorcycle"),
        ]
        if let headingDegrees { components.queryItems?.append(URLQueryItem(name: "heading", value: String(headingDegrees))) }
        guard let url = components.url else { throw Error.invalidRequest }
        return MapHTTPRequest(
            method: "GET",
            url: url,
            headers: ["Accept": "application/json"],
            body: Data(),
            maximumResponseBytes: 256 * 1_024
        )
    }

    public static func parse(_ data: Data) throws -> RoutePlan {
        struct Response: Decodable {
            struct Path: Decodable {
                struct Instruction: Decodable {
                    let distance: Double
                    let heading: Int
                    let sign: Int
                    let interval: [Int]
                    let streetName: String
                    enum CodingKeys: String, CodingKey {
                        case distance, heading, sign, interval
                        case streetName = "street_name"
                    }
                }
                let distance: Double
                let pointsEncoded: Bool
                let points: String
                let instructions: [Instruction]
                enum CodingKeys: String, CodingKey {
                    case distance, points, instructions
                    case pointsEncoded = "points_encoded"
                }
            }
            let code: String
            let paths: [Path]?
        }
        guard data.count <= 256 * 1_024,
              let response = try? JSONDecoder().decode(Response.self, from: data) else { throw Error.invalidResponse }
        guard response.code == "OK" else { throw Error.provider(response.code) }
        guard let paths = response.paths, !paths.isEmpty else { throw Error.invalidResponse }
        let validRoutes = paths.compactMap { path -> RoutePlan? in
            guard path.pointsEncoded, path.distance.isFinite, path.distance >= 0,
                  let points = try? GooglePolyline5.decode(path.points) else { return nil }
            guard let instructions = try? path.instructions.map({ instruction -> RouteInstruction in
                guard instruction.distance.isFinite, instruction.distance >= 0,
                      (0...360).contains(instruction.heading), instruction.interval.count == 2,
                      instruction.interval[0] >= 0, instruction.interval[0] <= instruction.interval[1],
                      instruction.interval[1] < points.count else { throw Error.invalidResponse }
                return RouteInstruction(
                    distanceMeters: instruction.distance,
                    headingDegrees: instruction.heading,
                    sign: instruction.sign,
                    interval: instruction.interval[0]...instruction.interval[1],
                    streetName: instruction.streetName
                )
            }) else { return nil }
            return RoutePlan(
                points: points,
                instructions: instructions,
                distanceMeters: path.distance,
                alternativePathCount: paths.count
            )
        }
        guard let route = validRoutes.min(by: { $0.distanceMeters < $1.distanceMeters }) else {
            throw Error.invalidResponse
        }
        return route
    }

    private static func decimal(_ value: Double) -> String {
        var result = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
        while result.last == "0" { result.removeLast() }
        if result.last == "." { result.removeLast() }
        return result
    }
}

public struct RouteProgress: Equatable, Sendable {
    public let pointIndex: Int
    public let distanceFromRouteMeters: Double
    public let matchedLocation: GeoPoint?
    public let shouldReroute: Bool
    public let status: NavigationStatus
}

public struct RouteProgressTracker: Sendable {
    private var lastPointIndex = 0
    private var consecutiveOffRouteFixes = 0

    public init() {}

    public mutating func update(
        route: RoutePlan,
        location: GeoPoint,
        horizontalAccuracyMeters: Double
    ) -> RouteProgress {
        guard horizontalAccuracyMeters.isFinite, horizontalAccuracyMeters >= 0, horizontalAccuracyMeters <= 25,
              route.points.count >= 2, location.isValid else {
            return RouteProgress(pointIndex: lastPointIndex, distanceFromRouteMeters: .infinity, matchedLocation: nil, shouldReroute: false, status: .gpsLow)
        }
        let start = min(lastPointIndex, route.points.count - 2)
        var bestIndex = start
        var bestSegmentIndex = start
        var bestDistance = Double.infinity
        var bestFraction = 0.0
        for index in start..<(route.points.count - 1) {
            let match = Self.distanceToSegment(location, route.points[index], route.points[index + 1])
            if match.distance < bestDistance {
                bestDistance = match.distance
                bestIndex = index + (match.fraction >= 0.5 ? 1 : 0)
                bestSegmentIndex = index
                bestFraction = match.fraction
            }
        }
        lastPointIndex = max(lastPointIndex, bestIndex)
        consecutiveOffRouteFixes = bestDistance > 40 ? consecutiveOffRouteFixes + 1 : 0
        let segmentIndex = min(bestSegmentIndex, route.points.count - 2)
        let startPoint = route.points[segmentIndex]
        let endPoint = route.points[segmentIndex + 1]
        let matchedLocation = GeoPoint(
            latitude: startPoint.latitude + (endPoint.latitude - startPoint.latitude) * bestFraction,
            longitude: startPoint.longitude + (endPoint.longitude - startPoint.longitude) * bestFraction
        )
        return RouteProgress(
            pointIndex: lastPointIndex,
            distanceFromRouteMeters: bestDistance,
            matchedLocation: matchedLocation,
            shouldReroute: consecutiveOffRouteFixes >= 3,
            status: .navigating
        )
    }

    private static func distanceToSegment(_ point: GeoPoint, _ start: GeoPoint, _ end: GeoPoint) -> (distance: Double, fraction: Double) {
        let originLatitude = point.latitude * .pi / 180
        let metersPerDegreeLatitude = 111_132.0
        let metersPerDegreeLongitude = 111_320.0 * cos(originLatitude)
        let ax = (start.longitude - point.longitude) * metersPerDegreeLongitude
        let ay = (start.latitude - point.latitude) * metersPerDegreeLatitude
        let bx = (end.longitude - point.longitude) * metersPerDegreeLongitude
        let by = (end.latitude - point.latitude) * metersPerDegreeLatitude
        let dx = bx - ax, dy = by - ay
        let denominator = dx * dx + dy * dy
        let fraction = denominator == 0 ? 0 : max(0, min(1, -(ax * dx + ay * dy) / denominator))
        return (hypot(ax + fraction * dx, ay + fraction * dy), fraction)
    }
}
