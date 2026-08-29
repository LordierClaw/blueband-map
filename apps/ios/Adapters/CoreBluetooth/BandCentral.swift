@preconcurrency import CoreBluetooth
import Foundation
import BlueBandCore

enum BandBLEError: Swift.Error, Equatable {
    case bluetoothUnavailable
    case candidateNotFound
    case connectionInProgress
    case connectionFailed
    case disconnected
    case serviceMissing
    case characteristicMissing
    case notificationsFailed
    case writeUnsupported
    case writeInProgress
    case closed
}

final class BandCentral: NSObject, BandCentralProtocol, @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.lordierclaw.bluebandmap.ble")
    private var manager: CBCentralManager!
    private var scanContinuation: AsyncThrowingStream<[BandCandidate], Swift.Error>.Continuation?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var candidates: [UUID: BandCandidate] = [:]
    private var pendingConnect: (id: UUID, continuation: CheckedContinuation<any BandLink, Swift.Error>)?
    private var activeLinks: [UUID: CoreBluetoothBandLink] = [:]

    override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: queue)
    }

    func scan() async -> AsyncThrowingStream<[BandCandidate], Swift.Error> {
        await withCheckedContinuation { result in
            queue.async {
                self.scanContinuation?.finish()
                self.candidates.removeAll()
                var streamContinuation: AsyncThrowingStream<[BandCandidate], Swift.Error>.Continuation!
                let stream = AsyncThrowingStream<[BandCandidate], Swift.Error> {
                    streamContinuation = $0
                }
                self.scanContinuation = streamContinuation
                self.startScanIfReady()
                result.resume(returning: stream)
            }
        }
    }

    func stopScan() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.manager.stopScan()
                self.scanContinuation?.finish()
                self.scanContinuation = nil
                continuation.resume()
            }
        }
    }

    func connect(id: UUID) async throws -> any BandLink {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.pendingConnect == nil else {
                    continuation.resume(throwing: BandBLEError.connectionInProgress)
                    return
                }
                let peripheral = self.peripherals[id]
                    ?? self.manager.retrievePeripherals(withIdentifiers: [id]).first
                guard let peripheral else {
                    continuation.resume(throwing: BandBLEError.candidateNotFound)
                    return
                }
                self.peripherals[id] = peripheral
                self.manager.stopScan()
                self.scanContinuation?.finish()
                self.scanContinuation = nil
                self.pendingConnect = (id, continuation)
                self.manager.connect(peripheral, options: nil)
            }
        }
    }

    private func startScanIfReady() {
        guard scanContinuation != nil else { return }
        switch manager.state {
        case .poweredOn:
            for peripheral in manager.retrieveConnectedPeripherals(
                withServices: [BandDiscoveryPlan.connectedService]
            ) {
                publish(peripheral, localName: nil, rssi: nil)
            }
            manager.scanForPeripherals(
                withServices: BandDiscoveryPlan.scanServices,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        case .unknown, .resetting:
            break
        default:
            scanContinuation?.finish(throwing: BandBLEError.bluetoothUnavailable)
            scanContinuation = nil
        }
    }

    private func publish(_ peripheral: CBPeripheral, localName: String?, rssi: Int?) {
        let candidate = BandCandidate(
            id: peripheral.identifier,
            name: BandDiscoveryPlan.displayName(
                peripheralName: peripheral.name,
                localName: localName,
                id: peripheral.identifier
            ),
            rssi: rssi
        )
        peripherals[peripheral.identifier] = peripheral
        candidates[peripheral.identifier] = candidate
        scanContinuation?.yield(candidates.values.sorted {
            ($0.rssi ?? Int.min) > ($1.rssi ?? Int.min)
        })
    }
}

extension BandCentral: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        startScanIfReady()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        publish(peripheral, localName: localName, rssi: RSSI.intValue)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let pending = pendingConnect, pending.id == peripheral.identifier else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        pendingConnect = nil

        let link = CoreBluetoothBandLink(
            peripheral: peripheral,
            queue: queue,
            cancel: { [weak self, weak peripheral] in
                guard let self, let peripheral else { return }
                self.manager.cancelPeripheralConnection(peripheral)
            }
        )
        activeLinks[peripheral.identifier] = link
        Task {
            do {
                try await link.prepare()
                pending.continuation.resume(returning: link)
            } catch {
                pending.continuation.resume(throwing: error)
                queue.async {
                    self.activeLinks.removeValue(forKey: peripheral.identifier)
                    self.manager.cancelPeripheralConnection(peripheral)
                }
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Swift.Error?) {
        guard let pending = pendingConnect, pending.id == peripheral.identifier else { return }
        pendingConnect = nil
        pending.continuation.resume(throwing: BandBLEError.connectionFailed)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Swift.Error?) {
        if let pending = pendingConnect, pending.id == peripheral.identifier {
            pendingConnect = nil
            pending.continuation.resume(throwing: BandBLEError.disconnected)
        }
        activeLinks.removeValue(forKey: peripheral.identifier)?.didDisconnect()
    }
}

private final class CoreBluetoothBandLink: NSObject, BandLink, @unchecked Sendable {
    var maximumWriteLength: Int {
        let type: CBCharacteristicWriteType = writeCharacteristic?.properties.contains(.write) == true
            ? .withResponse
            : .withoutResponse
        return peripheral.maximumWriteValueLength(for: type)
    }

    private let peripheral: CBPeripheral
    private let queue: DispatchQueue
    private let cancelConnection: @Sendable () -> Void
    private let notificationStream: AsyncThrowingStream<Data, Swift.Error>
    private let notificationContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation
    private var notifyCharacteristic: CBCharacteristic?
    private var writeCharacteristic: CBCharacteristic?
    private var prepareContinuation: CheckedContinuation<Void, Swift.Error>?
    private var writeContinuation: CheckedContinuation<Void, Swift.Error>?
    private var pendingWithoutResponse: (data: Data, continuation: CheckedContinuation<Void, Swift.Error>)?
    private var closeContinuation: CheckedContinuation<Void, Never>?
    private var closing = false
    private var closed = false

    init(peripheral: CBPeripheral, queue: DispatchQueue, cancel: @escaping @Sendable () -> Void) {
        self.peripheral = peripheral
        self.queue = queue
        cancelConnection = cancel
        var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        notificationStream = AsyncThrowingStream { continuation = $0 }
        notificationContinuation = continuation
        super.init()
    }

    func prepare() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
            queue.async {
                guard !self.closed else {
                    continuation.resume(throwing: BandBLEError.closed)
                    return
                }
                self.prepareContinuation = continuation
                self.peripheral.delegate = self
                self.peripheral.discoverServices([BandUUID.service])
            }
        }
    }

    func write(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
            queue.async {
                guard !self.closed, self.peripheral.state == .connected else {
                    continuation.resume(throwing: BandBLEError.disconnected)
                    return
                }
                guard let characteristic = self.writeCharacteristic else {
                    continuation.resume(throwing: BandBLEError.characteristicMissing)
                    return
                }

                if characteristic.properties.contains(.write) {
                    guard self.writeContinuation == nil else {
                        continuation.resume(throwing: BandBLEError.writeInProgress)
                        return
                    }
                    self.writeContinuation = continuation
                    self.peripheral.writeValue(data, for: characteristic, type: .withResponse)
                } else if characteristic.properties.contains(.writeWithoutResponse) {
                    if self.peripheral.canSendWriteWithoutResponse {
                        self.peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
                        continuation.resume()
                    } else if self.pendingWithoutResponse == nil {
                        self.pendingWithoutResponse = (data, continuation)
                    } else {
                        continuation.resume(throwing: BandBLEError.writeInProgress)
                    }
                } else {
                    continuation.resume(throwing: BandBLEError.writeUnsupported)
                }
            }
        }
    }

    func notifications() async -> AsyncThrowingStream<Data, Swift.Error> {
        notificationStream
    }

    func close() async {
        await withCheckedContinuation { continuation in
            queue.async {
                guard !self.closed else {
                    continuation.resume()
                    return
                }
                self.closing = true
                self.closeContinuation = continuation
                self.cancelConnection()
                if self.peripheral.state == .disconnected {
                    self.finish(throwing: nil)
                }
            }
        }
    }

    func didDisconnect() {
        finish(throwing: closing ? nil : BandBLEError.disconnected)
    }

    private func finish(throwing error: Swift.Error?) {
        guard !closed else { return }
        closed = true
        if let error {
            prepareContinuation?.resume(throwing: error)
            writeContinuation?.resume(throwing: error)
            pendingWithoutResponse?.continuation.resume(throwing: error)
            notificationContinuation.finish(throwing: error)
        } else {
            prepareContinuation?.resume(throwing: BandBLEError.closed)
            writeContinuation?.resume(throwing: BandBLEError.closed)
            pendingWithoutResponse?.continuation.resume(throwing: BandBLEError.closed)
            notificationContinuation.finish()
        }
        prepareContinuation = nil
        writeContinuation = nil
        pendingWithoutResponse = nil
        closeContinuation?.resume()
        closeContinuation = nil
    }

    private func failPrepare(_ error: Swift.Error) {
        prepareContinuation?.resume(throwing: error)
        prepareContinuation = nil
    }
}

extension CoreBluetoothBandLink: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Swift.Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == BandUUID.service }) else {
            failPrepare(BandBLEError.serviceMissing)
            return
        }
        peripheral.discoverCharacteristics([BandUUID.notify, BandUUID.write], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Swift.Error?
    ) {
        guard error == nil else {
            failPrepare(BandBLEError.characteristicMissing)
            return
        }
        notifyCharacteristic = service.characteristics?.first { $0.uuid == BandUUID.notify }
        writeCharacteristic = service.characteristics?.first { $0.uuid == BandUUID.write }
        guard let notifyCharacteristic, writeCharacteristic != nil else {
            failPrepare(BandBLEError.characteristicMissing)
            return
        }
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Swift.Error?
    ) {
        guard characteristic.uuid == BandUUID.notify else { return }
        guard error == nil, characteristic.isNotifying else {
            failPrepare(BandBLEError.notificationsFailed)
            return
        }
        prepareContinuation?.resume()
        prepareContinuation = nil
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Swift.Error?
    ) {
        guard characteristic.uuid == BandUUID.notify else { return }
        if error != nil {
            notificationContinuation.finish(throwing: BandBLEError.disconnected)
        } else if let value = characteristic.value {
            notificationContinuation.yield(Data(value))
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Swift.Error?
    ) {
        guard characteristic.uuid == BandUUID.write, let continuation = writeContinuation else { return }
        writeContinuation = nil
        if error == nil {
            continuation.resume()
        } else {
            continuation.resume(throwing: BandBLEError.connectionFailed)
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard let pending = pendingWithoutResponse, let characteristic = writeCharacteristic else { return }
        pendingWithoutResponse = nil
        peripheral.writeValue(pending.data, for: characteristic, type: .withoutResponse)
        pending.continuation.resume()
    }
}
