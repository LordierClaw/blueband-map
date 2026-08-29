import XCTest
@testable import BlueBandProtocol

final class SPPReassemblerTests: XCTestCase {
    private let first = SPPFrame(packetType: .data, sequence: 7, payload: Data([1, 1, 8, 1]))
    private let second = SPPFrame(packetType: .ack, sequence: 7, payload: Data())

    func testEmitsFrameOnlyAfterLastFragmentArrives() throws {
        var subject = SPPReassembler()
        let bytes = try first.encode()

        for byte in bytes.dropLast() {
            XCTAssertTrue(subject.append(Data([byte])).isEmpty)
        }

        XCTAssertEqual(subject.append(Data([bytes.last!])), [first])
    }

    func testEmitsTwoCoalescedFramesInOrder() throws {
        var subject = SPPReassembler()

        let output = subject.append(try first.encode() + second.encode())

        XCTAssertEqual(output, [first, second])
    }

    func testSkipsGarbageBeforeMagic() throws {
        var subject = SPPReassembler()

        let output = subject.append(Data([0, 1, 2, 0xA5]) + (try first.encode()))

        XCTAssertEqual(output, [first])
    }

    func testRecoversAfterCorruptFrame() throws {
        var subject = SPPReassembler()
        var corrupt = try first.encode()
        corrupt[8] ^= 0xFF

        let output = subject.append(corrupt + (try second.encode()))

        XCTAssertEqual(output, [second])
    }

    func testRetainsSplitMagicByte() throws {
        var subject = SPPReassembler()
        let bytes = try first.encode()

        XCTAssertTrue(subject.append(Data([0x11, 0xA5])).isEmpty)
        XCTAssertEqual(subject.append(bytes.dropFirst()), [first])
    }
}
