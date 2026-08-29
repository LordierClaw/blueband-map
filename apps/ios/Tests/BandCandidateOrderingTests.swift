import Foundation
import XCTest
import BlueBandCore
@testable import BlueBandMap

final class BandCandidateOrderingTests: XCTestCase {
    func testRememberedCandidateComesFirstAndRemainingCandidatesUseRSSIThenDeterministicTies() {
        let rememberedID = uuid("00000000-0000-0000-0000-000000000099")
        let alphaLaterID = uuid("00000000-0000-0000-0000-000000000003")
        let alphaEarlierID = uuid("00000000-0000-0000-0000-000000000002")
        let candidates = [
            candidate(rememberedID, "Remembered", -90),
            candidate(uuid("00000000-0000-0000-0000-000000000001"), "Zulu", -40),
            candidate(alphaLaterID, "Alpha", -50),
            candidate(alphaEarlierID, "Alpha", -50),
            candidate(uuid("00000000-0000-0000-0000-000000000004"), "Beta", -50),
        ]
        let remembered = RememberedBand(
            id: rememberedID,
            name: "Remembered",
            lastConnectedAt: Date(timeIntervalSince1970: 1)
        )

        let ordered = BandCandidateOrdering.order(candidates, remembered: remembered)

        XCTAssertEqual(ordered.map(\.id), [
            rememberedID,
            uuid("00000000-0000-0000-0000-000000000001"),
            alphaEarlierID,
            alphaLaterID,
            uuid("00000000-0000-0000-0000-000000000004"),
        ])
    }

    func testLimitsResultsToTwentyIncludingRememberedCandidate() {
        let candidates = (0..<25).map { index in
            candidate(
                uuid(String(format: "00000000-0000-0000-0000-%012d", index)),
                "Band \(index)",
                -index
            )
        }

        let ordered = BandCandidateOrdering.order(candidates, remembered: nil)

        XCTAssertEqual(ordered.count, 20)
        XCTAssertEqual(ordered.first?.rssi, 0)
        XCTAssertEqual(ordered.last?.rssi, -19)
    }

    func testSynthesizesAbsentRememberedCandidateWithNilRSSI() {
        let rememberedID = uuid("10000000-0000-0000-0000-000000000000")
        let remembered = RememberedBand(
            id: rememberedID,
            name: "Saved Band",
            lastConnectedAt: Date(timeIntervalSince1970: 2)
        )

        let ordered = BandCandidateOrdering.order([
            candidate(uuid("20000000-0000-0000-0000-000000000000"), "Nearby Band", -30),
        ], remembered: remembered)

        XCTAssertEqual(ordered.first, candidate(rememberedID, "Saved Band", nil))
    }

    func testDuplicatePeripheralIDsChooseStrongestRSSIAndDeterministicUsefulNameWithoutTrapping() {
        let duplicateID = uuid("30000000-0000-0000-0000-000000000000")
        let ordered = BandCandidateOrdering.order([
            candidate(duplicateID, "", -20),
            candidate(duplicateID, "Zulu Band", nil),
            candidate(duplicateID, "Alpha Band", -70),
        ], remembered: nil)

        XCTAssertEqual(ordered, [candidate(duplicateID, "Alpha Band", -20)])
    }

    func testDuplicatePeripheralIDsPreferNonNilRSSIOverNilRSSI() {
        let duplicateID = uuid("40000000-0000-0000-0000-000000000000")

        let ordered = BandCandidateOrdering.order([
            candidate(duplicateID, "Known by iOS", nil),
            candidate(duplicateID, "Scanned", -88),
        ], remembered: nil)

        XCTAssertEqual(ordered.single?.rssi, -88)
    }

    func testWithoutRememberedCandidateOrdersAllCandidatesNormally() {
        let strongestID = uuid("50000000-0000-0000-0000-000000000000")
        let ordered = BandCandidateOrdering.order([
            candidate(uuid("60000000-0000-0000-0000-000000000000"), "Weak", -80),
            candidate(strongestID, "Strong", -25),
        ], remembered: nil)

        XCTAssertEqual(ordered.map(\.id), [
            strongestID,
            uuid("60000000-0000-0000-0000-000000000000"),
        ])
    }

    private func candidate(_ id: UUID, _ name: String, _ rssi: Int?) -> BandCandidate {
        BandCandidate(id: id, name: name, rssi: rssi)
    }

    private func uuid(_ value: String) -> UUID {
        try! XCTUnwrap(UUID(uuidString: value))
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
