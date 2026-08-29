import Foundation
import XCTest
@testable import BlueBandCore

final class ApplicationEnvelopeTests: XCTestCase {
    func testRoundTripsMessageAndAcknowledgement() throws {
        let message = ApplicationEnvelope.message(
            id: "i-a1b2c3",
            source: .ios,
            topic: "system.echo",
            body: ["text": .string("PING"), "count": .number(2)]
        )
        let decoded = try ApplicationEnvelope.decode(try message.encoded(), expecting: .band)
        XCTAssertEqual(decoded, message)

        let ack = ApplicationEnvelope.acknowledgement(id: message.id, source: .band)
        XCTAssertEqual(try ApplicationEnvelope.decode(try ack.encoded(), expecting: .ios), ack)
    }

    func testRejectsWrongSourceVersionAndUnknownType() throws {
        let valid = #"{"v":1,"id":"x","src":"ios","type":"ack"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try ApplicationEnvelope.decode(valid, expecting: .ios))

        for json in [
            #"{"v":2,"id":"x","src":"ios","type":"ack"}"#,
            #"{"v":1,"id":"x","src":"ios","type":"future"}"#,
        ] {
            XCTAssertThrowsError(try ApplicationEnvelope.decode(Data(json.utf8), expecting: .band))
        }
    }

    func testEnforcesIdentifierBoundsAndPrintableASCII() {
        for id in ["", String(repeating: "a", count: 33), "line\nbreak", "é"] {
            let envelope = ApplicationEnvelope.acknowledgement(id: id, source: .ios)
            XCTAssertThrowsError(try envelope.encoded(), "accepted invalid id: \(id.debugDescription)")
        }
        XCTAssertNoThrow(try ApplicationEnvelope.acknowledgement(id: String(repeating: "a", count: 32), source: .ios).encoded())
    }

    func testEnforcesTopicAndBodyShape() {
        let body: [String: JSONValue] = ["ok": .bool(true)]
        for topic in ["", "System.echo", "system..echo", ".system", "system_foo", String(repeating: "a", count: 65)] {
            XCTAssertThrowsError(try ApplicationEnvelope.message(id: "x", source: .ios, topic: topic, body: body).encoded())
        }
        XCTAssertNoThrow(try ApplicationEnvelope.message(id: "x", source: .ios, topic: "a.b-2", body: body).encoded())

        let missingBody = ApplicationEnvelope(v: 1, id: "x", src: .ios, type: .message, topic: "system.echo", body: nil)
        let dirtyAck = ApplicationEnvelope(v: 1, id: "x", src: .ios, type: .ack, topic: "system.echo", body: body)
        XCTAssertThrowsError(try missingBody.encoded())
        XCTAssertThrowsError(try dirtyAck.encoded())
    }

    func testRejectsEncodedEnvelopeLargerThan512Bytes() {
        let envelope = ApplicationEnvelope.message(
            id: "x",
            source: .ios,
            topic: "system.echo",
            body: ["text": .string(String(repeating: "x", count: 512))]
        )
        XCTAssertThrowsError(try envelope.encoded())
        XCTAssertThrowsError(try ApplicationEnvelope.decode(Data(repeating: 0x20, count: 513), expecting: .band))
    }
}
