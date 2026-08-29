import Foundation
import BlueBandProtocol

public protocol BandLink: AnyObject, Sendable {
    var maximumWriteLength: Int { get }
    func write(_ data: Data) async throws
    func notifications() async -> AsyncThrowingStream<Data, Swift.Error>
    func close() async
}

public struct BandTransportMessage: Equatable, Sendable {
    public let channel: UInt8
    public let opcode: UInt8
    public let body: Data

    public init(channel: UInt8, opcode: UInt8, body: Data) {
        self.channel = channel
        self.opcode = opcode
        self.body = body
    }
}

public protocol BandTransportProtocol: Sendable {
    func configure() async throws
    func send(channel: UInt8, opcode: UInt8, body: Data) async throws
    func incoming() async -> AsyncThrowingStream<BandTransportMessage, Swift.Error>
    func close() async
}

public actor BandTransport: BandTransportProtocol {
    public enum Error: Swift.Error, Equatable {
        case alreadyConfiguring
        case invalidSessionResponse
        case notConfigured
        case closed
    }

    private static let sessionRequestPayload = Data([
        0x01,
        0x01, 0x03, 0x00, 0x01, 0x00, 0x00,
        0x02, 0x02, 0x00, 0x00, 0xFC,
        0x03, 0x02, 0x00, 0x20, 0x00,
        0x04, 0x02, 0x00, 0x10, 0x27
    ])

    private let link: any BandLink
    private let messageStream: AsyncThrowingStream<BandTransportMessage, Swift.Error>
    private let messageContinuation: AsyncThrowingStream<BandTransportMessage, Swift.Error>.Continuation
    private var reassembler = SPPReassembler()
    private var receiveTask: Task<Void, Never>?
    private var configureContinuation: CheckedContinuation<Void, Swift.Error>?
    private var nextSequence: UInt8 = 0
    private var isConfigured = false
    private var isClosed = false

    public init(link: any BandLink) {
        self.link = link
        var continuation: AsyncThrowingStream<BandTransportMessage, Swift.Error>.Continuation!
        messageStream = AsyncThrowingStream { continuation = $0 }
        messageContinuation = continuation
    }

    public func configure() async throws {
        guard !isClosed else { throw Error.closed }
        if isConfigured { return }
        guard configureContinuation == nil else { throw Error.alreadyConfiguring }
        startReceivingIfNeeded()

        try await withCheckedThrowingContinuation { continuation in
            configureContinuation = continuation
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.write(SPPFrame(packetType: .sessionConfig, sequence: 0, payload: Self.sessionRequestPayload))
                } catch {
                    await self.failConfiguration(error)
                }
            }
        }
    }

    public func send(channel: UInt8, opcode: UInt8, body: Data) async throws {
        guard !isClosed else { throw Error.closed }
        guard isConfigured else { throw Error.notConfigured }
        var payload = Data([channel & 0x0F, opcode])
        payload.append(body)
        let sequence = nextSequence
        nextSequence &+= 1
        try await write(SPPFrame(packetType: .data, sequence: sequence, payload: payload))
    }

    public func incoming() -> AsyncThrowingStream<BandTransportMessage, Swift.Error> { messageStream }

    public func close() async {
        guard !isClosed else { return }
        isClosed = true
        isConfigured = false
        configureContinuation?.resume(throwing: Error.closed)
        configureContinuation = nil
        receiveTask?.cancel()
        receiveTask = nil
        messageContinuation.finish()
        await link.close()
    }

    private func startReceivingIfNeeded() {
        guard receiveTask == nil else { return }
        let link = link
        receiveTask = Task { [weak self, link] in
            let notifications = await link.notifications()
            do {
                for try await bytes in notifications {
                    guard !Task.isCancelled else { return }
                    await self?.consume(bytes)
                }
                await self?.finishIncoming()
            } catch {
                await self?.finishIncoming(throwing: error)
            }
        }
    }

    private func consume(_ bytes: Data) async {
        for frame in reassembler.append(bytes) {
            switch frame.packetType {
            case .ack:
                continue
            case .sessionConfig:
                if frame.payload.first == 0x02 {
                    isConfigured = true
                    configureContinuation?.resume()
                    configureContinuation = nil
                } else {
                    failConfiguration(Error.invalidSessionResponse)
                }
            case .data:
                do {
                    try await write(SPPFrame(packetType: .ack, sequence: frame.sequence, payload: Data()))
                } catch {
                    finishIncoming(throwing: error)
                    return
                }
                guard frame.payload.count >= 2 else { continue }
                messageContinuation.yield(BandTransportMessage(
                    channel: frame.payload[0] & 0x0F,
                    opcode: frame.payload[1],
                    body: Data(frame.payload.dropFirst(2))
                ))
            }
        }
    }

    private func write(_ frame: SPPFrame) async throws {
        let bytes = try frame.encode()
        let chunkSize = max(1, link.maximumWriteLength)
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + chunkSize, bytes.count)
            try await link.write(Data(bytes[offset..<end]))
            offset = end
        }
    }

    private func failConfiguration(_ error: Swift.Error) {
        isConfigured = false
        configureContinuation?.resume(throwing: error)
        configureContinuation = nil
    }

    private func finishIncoming(throwing error: Swift.Error? = nil) {
        if let error {
            configureContinuation?.resume(throwing: error)
            messageContinuation.finish(throwing: error)
        } else {
            configureContinuation?.resume(throwing: Error.closed)
            messageContinuation.finish()
        }
        configureContinuation = nil
    }
}
