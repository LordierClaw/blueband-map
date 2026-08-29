import Foundation
import XCTest
@testable import BlueBandCore
import BlueBandProtocol

final class BandTransportTests: XCTestCase {
    func testConfigureSendsLiteralSessionRequestWithoutConsumingDataSequence() async throws {
        let link = FakeBandLink(maximumWriteLength: 512)
        let transport = BandTransport(link: link)

        async let configuring: Void = transport.configure()
        let request = try SPPFrame.decode(await link.nextWrite())
        XCTAssertEqual(request.packetType, .sessionConfig)
        XCTAssertEqual(request.sequence, 0)
        XCTAssertEqual(request.payload, Data([
            0x01,
            0x01, 0x03, 0x00, 0x01, 0x00, 0x00,
            0x02, 0x02, 0x00, 0x00, 0xFC,
            0x03, 0x02, 0x00, 0x20, 0x00,
            0x04, 0x02, 0x00, 0x10, 0x27
        ]))

        await link.emit(try SPPFrame(packetType: .sessionConfig, sequence: 0, payload: Data([0x02])).encode())
        try await configuring

        try await transport.send(channel: 1, opcode: 1, body: Data([0xAA]))
        let firstDataWrite = await link.nextWrite()
        XCTAssertEqual(try SPPFrame.decode(firstDataWrite).sequence, 0)
    }

    func testSendMasksChannelAndIncrementsSequence() async throws {
        let (transport, link) = try await configuredTransport()
        try await transport.send(channel: 0xF1, opcode: 2, body: Data([0xAA]))
        try await transport.send(channel: 1, opcode: 1, body: Data([0xBB]))

        let first = try SPPFrame.decode(await link.nextWrite())
        let second = try SPPFrame.decode(await link.nextWrite())
        XCTAssertEqual(first.sequence, 0)
        XCTAssertEqual(first.payload, Data([0x01, 0x02, 0xAA]))
        XCTAssertEqual(second.sequence, 1)
        XCTAssertEqual(second.payload, Data([0x01, 0x01, 0xBB]))
    }

    func testIncomingDataIsAcknowledgedAndDelivered() async throws {
        let (transport, link) = try await configuredTransport()
        var iterator = await transport.incoming().makeAsyncIterator()
        await link.emit(try SPPFrame(packetType: .data, sequence: 9, payload: Data([1, 2, 0xAA, 0xBB])).encode())

        let ackWrite = await link.nextWrite()
        let message = try await iterator.next()
        XCTAssertEqual(try SPPFrame.decode(ackWrite), SPPFrame(packetType: .ack, sequence: 9, payload: Data()))
        XCTAssertEqual(message, BandTransportMessage(channel: 1, opcode: 2, body: Data([0xAA, 0xBB])))
    }

    func testNotificationFragmentsAndCoalescedFramesAreHandledOnce() async throws {
        let (transport, link) = try await configuredTransport()
        var iterator = await transport.incoming().makeAsyncIterator()
        let first = try SPPFrame(packetType: .data, sequence: 4, payload: Data([1, 1, 0x10])).encode()
        let second = try SPPFrame(packetType: .data, sequence: 5, payload: Data([1, 1, 0x20])).encode()
        await link.emit(Data(first.prefix(5)))
        await link.emit(Data(first.dropFirst(5)) + second)
        _ = await link.nextWrite()
        _ = await link.nextWrite()
        let firstMessage = try await iterator.next()
        let secondMessage = try await iterator.next()
        XCTAssertEqual(firstMessage?.body, Data([0x10]))
        XCTAssertEqual(secondMessage?.body, Data([0x20]))
    }

    func testLargeFrameIsSplitAtLinkMaximumWriteLength() async throws {
        let (transport, link) = try await configuredTransport(maximumWriteLength: 10)
        try await transport.send(channel: 1, opcode: 1, body: Data(repeating: 0xAA, count: 17))
        let chunks = [await link.nextWrite(), await link.nextWrite(), await link.nextWrite()]
        XCTAssertEqual(chunks.map(\.count), [10, 10, 7])
        XCTAssertNoThrow(try SPPFrame.decode(chunks.reduce(Data(), +)))
    }

    func testCloseFinishesIncomingAndClosesLink() async throws {
        let (transport, link) = try await configuredTransport()
        var iterator = await transport.incoming().makeAsyncIterator()
        await transport.close()
        let closed = await link.isClosed
        let finalMessage = try await iterator.next()
        XCTAssertTrue(closed)
        XCTAssertNil(finalMessage)
    }

    private func configuredTransport(maximumWriteLength: Int = 512) async throws -> (BandTransport, FakeBandLink) {
        let link = FakeBandLink(maximumWriteLength: maximumWriteLength)
        let transport = BandTransport(link: link)
        async let configuring: Void = transport.configure()
        var request = Data()
        while request.count < 30 { request.append(await link.nextWrite()) }
        _ = try SPPFrame.decode(request)
        await link.emit(try SPPFrame(packetType: .sessionConfig, sequence: 0, payload: Data([0x02])).encode())
        try await configuring
        return (transport, link)
    }
}

private actor FakeBandLink: BandLink {
    nonisolated let maximumWriteLength: Int
    private var pendingWrites: [Data] = []
    private var waiters: [CheckedContinuation<Data, Never>] = []
    private let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private(set) var isClosed = false

    init(maximumWriteLength: Int) {
        self.maximumWriteLength = maximumWriteLength
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        stream = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }

    func write(_ data: Data) async throws {
        if waiters.isEmpty { pendingWrites.append(data) } else { waiters.removeFirst().resume(returning: data) }
    }
    func notifications() async -> AsyncThrowingStream<Data, Error> { stream }
    func close() async { isClosed = true; continuation.finish() }
    func emit(_ data: Data) { continuation.yield(data) }
    func nextWrite() async -> Data {
        if !pendingWrites.isEmpty { return pendingWrites.removeFirst() }
        return await withCheckedContinuation { waiters.append($0) }
    }
}
