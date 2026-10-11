import XCTest
import BlueBandCore
@testable import BlueBandMap

final class NativeTransportDiagnosticsTests: XCTestCase {
    func testCallbackDetailRejectsContradictionsAndKeepsSampleBounded() {
        let valid: [String: JSONValue] = ["v": .number(1), "clockValid": .bool(true), "saturated": .bool(false),
            "ack": .array([5, 1, 0, 3, 1].map { .number(Double($0)) }),
            "message": .array([2, 1, 0, 1, 0].map { .number(Double($0)) }),
            "sample": .array([.number(4), .number(90000), .number(0)]), "duplicate": .number(2), "late": .number(1)]
        XCTAssertEqual(NativeCallbackDiagnostics.validated(.object(valid)), valid)
        var bad = valid; bad["ack"] = .array([5, 1, 0, 5, 0].map { .number(Double($0)) })
        XCTAssertNil(NativeCallbackDiagnostics.validated(.object(bad)))
        bad = valid; bad["sample"] = .array([.number(17), .number(90000), .number(0)])
        XCTAssertNil(NativeCallbackDiagnostics.validated(.object(bad)))
        bad = valid; bad["clockValid"] = .bool(false)
        XCTAssertNil(NativeCallbackDiagnostics.validated(.object(bad)))
        bad["sample"] = .array([.number(4), .null, .number(0)])
        XCTAssertNotNil(NativeCallbackDiagnostics.validated(.object(bad)))
    }

    func testMissingCallbacksRemainPendingAndMalformedCountersAreRejected() {
        let valid: [String: JSONValue] = ["v": .number(1), "clockValid": .bool(true), "saturated": .bool(false),
            "attempted": .number(3), "succeeded": .number(1), "failed": .number(1), "pending": .number(1),
            "peakPending": .number(2), "timeouts204": .number(1), "abandoned": .number(0),
            "lastCallbackMs": .number(20), "maxCallbackMs": .number(20)]
        XCTAssertEqual(NativeTransportDiagnostics.validated(.object(valid)), valid)
        for (key, value) in [("pending", JSONValue.number(-1)), ("attempted", .number(4)),
                             ("timeouts204", .number(2)), ("clockValid", .bool(false)), ("extra", .string("payload"))] {
            var bad = valid; bad[key] = value
            XCTAssertNil(NativeTransportDiagnostics.validated(.object(bad)), key)
        }
        var noCallback = valid
        noCallback["attempted"] = .number(1); noCallback["succeeded"] = .number(0)
        noCallback["failed"] = .number(0); noCallback["timeouts204"] = .number(0)
        noCallback["lastCallbackMs"] = .null; noCallback["maxCallbackMs"] = .null
        XCTAssertNotNil(NativeTransportDiagnostics.validated(.object(noCallback)))
        XCTAssertNil(NativeTransportDiagnostics.validated(nil))
    }
}
