import Foundation

/// Route v4 intervals can include a long approach followed by the circle.
/// Recognize the arc before using the outlet; a local right exit is not the net turn.
enum RoundaboutGeometry {
    static func direction(points: [GeoPoint], interval: ClosedRange<Int>) -> NavigationManeuver? {
        guard interval.lowerBound >= 0, interval.upperBound < points.count - 1,
              interval.count >= 5 else { return nil }
        // Bound work to the end of the instruction, independent of route length.
        let start = max(interval.lowerBound, interval.upperBound - 96)
        var segments: [(heading: Double, meters: Double)] = []
        for index in start..<interval.upperBound {
            guard let segment = segment(points[index], points[index + 1]) else { return nil }
            if segment.meters >= 1 { segments.append(segment) }
        }
        guard segments.count >= 4,
              let outlet = segment(points[interval.upperBound], points[interval.upperBound + 1]),
              outlet.meters >= 5, let last = segments.last,
              (15...140).contains(delta(last.heading, outlet.heading)) else { return nil }

        var sweep = 0.0, length = last.meters, count = 1
        for index in stride(from: segments.count - 2, through: 0, by: -1) {
            let previous = segments[index], next = segments[index + 1]
            let turn = delta(previous.heading, next.heading)
            if turn >= 20 {
                guard count >= 3, sweep >= 40, sweep <= 355, length <= 300,
                      previous.meters >= 5 else { return nil }
                let turn = delta(previous.heading, outlet.heading)
                if abs(turn) <= 35 { return .straight }
                if abs(turn) >= 145 { return .uTurn }
                return turn > 0 ? .right : .left
            }
            // ponytail: supports clearly sampled right-hand-traffic circles only.
            // Sparse/irregular arcs retain the neutral icon; use provider angles if supplied later.
            guard turn >= -75, turn <= 10, previous.meters <= 100 else { return nil }
            sweep -= turn
            length += previous.meters
            count += 1
            guard length <= 300 else { return nil }
        }
        return nil
    }

    private static func delta(_ from: Double, _ to: Double) -> Double {
        (to - from + 540).truncatingRemainder(dividingBy: 360) - 180
    }

    private static func segment(_ a: GeoPoint, _ b: GeoPoint) -> (heading: Double, meters: Double)? {
        guard a.isValid, b.isValid else { return nil }
        let north = (b.latitude - a.latitude) * 111_195
        let east = (b.longitude - a.longitude) * 111_195 * cos((a.latitude + b.latitude) / 2 * .pi / 180)
        return ((atan2(east, north) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360), hypot(east, north))
    }
}
