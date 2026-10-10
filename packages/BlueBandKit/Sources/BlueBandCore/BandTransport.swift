import Foundation
import BlueBandProtocol

public typealias BandPerformanceObserver = @Sendable (String, [String: JSONValue]) -> Void

enum BandPerformanceContext {
    @TaskLocal static var operationStartedUptime: TimeInterval?
    struct Command: Sendable {
        let requestID: String
        let topic: String
        let direction: String
    }
    @TaskLocal static var command: Command?
}

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

    private var performanceObserver: BandPerformanceObserver?
    public func setPerformanceObserver(_ observer: BandPerformanceObserver?) { performanceObserver = observer }

    private let link: any BandLink
    private let messageStream: AsyncThrowingStream<BandTransportMessage, Swift.Error>
    private let messageContinuation: AsyncThrowingStream<BandTransportMessage, Swift.Error>.Continuation
    private var reassembler = SPPReassembler()
    private var receiveTask: Task<Void, Never>?
    private var configureContinuation: CheckedContinuation<Void, Swift.Error>?
    private var nextSequence: UInt8 = 0
    private var isConfigured = false
    private var isClosed = false
    private var writeLocked = false
    private var writeWaiters: [CheckedContinuation<Void, Never>] = []

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
                let received = ProcessInfo.processInfo.systemUptime
                let observer = performanceObserver
                do {
                    try await write(SPPFrame(packetType: .ack, sequence: frame.sequence, payload: Data()))
                } catch {
                    finishIncoming(throwing: error)
                    return
                }
                guard frame.payload.count >= 2 else { continue }
                observer?("ble.receive.transport", ["ackWaitMs": .number((ProcessInfo.processInfo.systemUptime - received) * 1000),
                    "operationStartedUptime": .number(received), "wireSequence": .number(Double(frame.sequence))])
                messageContinuation.yield(BandTransportMessage(
                    channel: frame.payload[0] & 0x0F,
                    opcode: frame.payload[1],
                    body: Data(frame.payload.dropFirst(2))
                ))
            }
        }
    }

    private func write(_ frame: SPPFrame) async throws {
        let queued = ProcessInfo.processInfo.systemUptime
        let operationStarted = BandPerformanceContext.operationStartedUptime ?? queued
        let context = BandPerformanceContext.command
        let queueDepth = writeWaiters.count + (writeLocked ? 1 : 0)
        let observer = performanceObserver
        await acquireWrite()
        let acquired = ProcessInfo.processInfo.systemUptime
        var attempted = false, outcome = "failed"
        var nativeWriteCount = 0, attemptedBytes = 0
        defer {
            observer?("ble.write", ["queueMs": .number((acquired - queued) * 1000),
                "writeMs": attempted ? .number((ProcessInfo.processInfo.systemUptime - acquired) * 1000) : .null,
                "attempted": .bool(attempted), "outcome": .string(outcome),
                "requestId": context.map { .string($0.requestID) } ?? .null,
                "topic": context.map { .string($0.topic) } ?? .null,
                "direction": context.map { .string($0.direction) } ?? .null,
                "frameKind": .string(String(describing: frame.packetType)),
                "queueDepth": .number(Double(queueDepth)),
                "nativeWriteCount": .number(Double(nativeWriteCount)), "attemptedBytes": .number(Double(attemptedBytes)),
                "operationStartedUptime": .number(operationStarted),
                "wireSequence": .number(Double(frame.sequence)), "payloadBytes": .number(Double(frame.payload.count)),
                "maximumWriteLength": .number(Double(link.maximumWriteLength))])
        }
        do {
            try Task.checkCancellation()
            guard !isClosed else { throw Error.closed }
            let bytes = try frame.encode()
            let chunkSize = max(1, link.maximumWriteLength)
            var offset = 0
            while offset < bytes.count {
                let end = min(offset + chunkSize, bytes.count)
                attempted = true
                nativeWriteCount += 1
                attemptedBytes += end - offset
                try await link.write(Data(bytes[offset..<end]))
                offset = end
            }
            outcome = "succeeded"
            releaseWrite()
        } catch {
            if error is CancellationError { outcome = "cancelled" }
            else if error as? Error == .closed { outcome = "closed" }
            releaseWrite()
            throw error
        }
    }

    private func acquireWrite() async {
        guard writeLocked else {
            writeLocked = true
            return
        }
        await withCheckedContinuation { writeWaiters.append($0) }
    }

    private func releaseWrite() {
        if writeWaiters.isEmpty { writeLocked = false }
        else { writeWaiters.removeFirst().resume() }
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
