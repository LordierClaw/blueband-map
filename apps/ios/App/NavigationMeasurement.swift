import Foundation
import UIKit
import BlueBandCore

struct NavigationMeasurement: Equatable {
    enum GPSSource: String, CaseIterable { case unknown, device, replay }
    enum MapMode: String, CaseIterable { case automatic, full }
    enum Phase: String, CaseIterable { case startup, cached, coverage, turn, recovery }
    let caseID: String
    let gpsSource: GPSSource
    let mapMode: MapMode
    let visualMarker: Bool

    init(caseID: String, gpsSource: GPSSource, mapMode: MapMode, visualMarker: Bool) {
        let safe = caseID.utf8.filter { (65...90).contains($0) || (97...122).contains($0) ||
            (48...57).contains($0) || $0 == 45 || $0 == 95 }
        self.caseID = String(decoding: safe.prefix(32), as: UTF8.self)
        self.gpsSource = gpsSource; self.mapMode = mapMode; self.visualMarker = visualMarker
    }

    @MainActor var metadata: [String: JSONValue] {
        var system = utsname()
        let model: String
        if uname(&system) == 0 {
            model = withUnsafeBytes(of: &system.machine) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
        } else { model = "unknown" }
        return ["measurementVersion": .number(2), "testCaseID": .string(caseID),
            "gpsSource": .string(gpsSource.rawValue), "mapMode": .string(mapMode.rawValue),
            "visualMarker": .bool(visualMarker), "osVersion": .string(UIDevice.current.systemVersion),
            "deviceModel": .string(model)]
    }
}

enum NativeTransportDiagnostics {
    static func validated(_ value: JSONValue?) -> [String: JSONValue]? {
        guard case let .object(metrics)? = value, metrics["v"] == .number(1),
              case let .bool(clockValid)? = metrics["clockValid"],
              case let .bool(saturated)? = metrics["saturated"] else { return nil }
        let counters = ["attempted", "succeeded", "failed", "pending", "peakPending", "timeouts204", "abandoned"]
        let allowed = Set(counters + ["v", "clockValid", "saturated", "lastCallbackMs", "maxCallbackMs"])
        guard Set(metrics.keys) == allowed else { return nil }
        var numbers: [String: Double] = [:]
        for key in counters {
            guard case let .number(n)? = metrics[key], n.isFinite, (0...2147483647).contains(n), n.rounded() == n else { return nil }
            numbers[key] = n
        }
        for key in ["lastCallbackMs", "maxCallbackMs"] {
            if metrics[key] == .null { continue }
            guard clockValid, case let .number(n)? = metrics[key], n.isFinite, (0...60_000).contains(n) else { return nil }
        }
        guard saturated || (numbers["attempted"]! == numbers["succeeded"]! + numbers["failed"]! + numbers["pending"]! + numbers["abandoned"]! &&
            numbers["peakPending"]! >= numbers["pending"]! && numbers["timeouts204"]! <= numbers["failed"]!) else { return nil }
        return metrics
    }
}
