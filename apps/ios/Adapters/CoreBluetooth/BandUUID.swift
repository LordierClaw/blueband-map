import CoreBluetooth

enum BandUUID {
    static let service = CBUUID(string: "0000FE95-0000-1000-8000-00805F9B34FB")
    static let notify = CBUUID(string: "0000005E-0000-1000-8000-00805F9B34FB")
    static let write = CBUUID(string: "0000005F-0000-1000-8000-00805F9B34FB")
}

enum BandDiscoveryPlan {
    // Foreground discovery intentionally shows every BLE peripheral, like AstroBox.
    // FE95 and the device name are never used to hide a selectable device.
    static let scanServices: [CBUUID]? = nil
    static let connectedService = BandUUID.service

    static func displayName(peripheralName: String?, localName: String?, id: UUID) -> String {
        for name in [localName, peripheralName] {
            if let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return "BLE \(id.uuidString.prefix(8))"
    }
}
