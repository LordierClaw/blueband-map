import Foundation

public struct NavigationDebugEntry: Equatable, Sendable {
    public let sequence: Int
    public let elapsedMilliseconds: Int
    public let stage: String
    public let detail: String

    public init(sequence: Int, elapsedMilliseconds: Int, stage: String, detail: String) {
        self.sequence = sequence
        self.elapsedMilliseconds = elapsedMilliseconds
        self.stage = stage
        self.detail = detail
    }
}

public enum NavigationDebugFormatter {
    public static func export(
        state: String,
        start: GeoPoint?,
        destination: GeoPoint?,
        routeDistanceMeters: Double?,
        alternativePathCount: Int?,
        instructions: [RouteInstruction],
        entries: [NavigationDebugEntry]
    ) -> String {
        var lines = [
            "BlueBandMap navigation debug",
            "state=\(oneLine(state))",
            "start=\(coordinateSummary(start))",
            "destination=\(coordinateSummary(destination))",
            "routeDistanceM=\(routeDistanceMeters.map { String(Int($0.rounded())) } ?? "—")",
            "alternativePaths=\(alternativePathCount.map(String.init) ?? "—")",
            "instructionCount=\(instructions.count)",
        ]
        if entries.isEmpty {
            lines.append("events=none")
        } else {
            lines.append("events:")
            for entry in entries {
                lines.append(
                    "[\(max(0, entry.elapsedMilliseconds))ms] #\(max(0, entry.sequence)) " +
                    "\(oneLine(entry.stage)) \(oneLine(entry.detail))"
                )
            }
        }
        for (index, instruction) in instructions.enumerated() {
            lines.append(
                "step[\(index + 1)] maneuver=\(instruction.maneuver.rawValue) " +
                "distanceM=\(Int(instruction.distanceMeters.rounded())) " +
                "interval=\(instruction.interval.lowerBound)...\(instruction.interval.upperBound) " +
                "street=\(oneLine(instruction.streetName))"
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func coordinateSummary(_ point: GeoPoint?) -> String {
        guard let point else { return "—" }
        return String(
            format: "%.3f,%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            point.latitude,
            point.longitude
        )
    }

    private static func oneLine(_ value: String) -> String {
        let sanitized = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return String(sanitized.prefix(160))
    }
}
