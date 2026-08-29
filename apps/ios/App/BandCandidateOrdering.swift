import Foundation
import BlueBandCore

enum BandCandidateOrdering {
    static func order(
        _ candidates: [BandCandidate],
        remembered: RememberedBand?
    ) -> [BandCandidate] {
        var candidatesByID: [UUID: BandCandidate] = [:]

        for candidate in candidates {
            guard let existing = candidatesByID[candidate.id] else {
                candidatesByID[candidate.id] = candidate
                continue
            }

            candidatesByID[candidate.id] = BandCandidate(
                id: candidate.id,
                name: preferredName(existing.name, candidate.name, id: candidate.id),
                rssi: strongestRSSI(existing.rssi, candidate.rssi)
            )
        }

        var rememberedCandidate: BandCandidate?
        if let remembered {
            if let scanned = candidatesByID.removeValue(forKey: remembered.id) {
                rememberedCandidate = BandCandidate(
                    id: remembered.id,
                    name: preferredName(scanned.name, remembered.name, id: remembered.id),
                    rssi: scanned.rssi
                )
            } else {
                rememberedCandidate = BandCandidate(
                    id: remembered.id,
                    name: remembered.name,
                    rssi: nil
                )
            }
        }

        let remaining = candidatesByID.values.map(normalized).sorted(by: comesBefore)
        return Array(([rememberedCandidate].compactMap { $0 } + remaining).prefix(20))
    }

    private static func normalized(_ candidate: BandCandidate) -> BandCandidate {
        BandCandidate(
            id: candidate.id,
            name: preferredName(candidate.name, candidate.name, id: candidate.id),
            rssi: candidate.rssi
        )
    }

    private static func strongestRSSI(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): return max(lhs, rhs)
        case let (lhs?, nil): return lhs
        case let (nil, rhs?): return rhs
        case (nil, nil): return nil
        }
    }

    private static func preferredName(_ lhs: String, _ rhs: String, id: UUID) -> String {
        let names = [lhs, rhs]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted(by: nameComesBefore)
        return names.first ?? "BLE \(id.uuidString.prefix(8))"
    }

    private static func comesBefore(_ lhs: BandCandidate, _ rhs: BandCandidate) -> Bool {
        let lhsRSSI = lhs.rssi ?? Int.min
        let rhsRSSI = rhs.rssi ?? Int.min
        if lhsRSSI != rhsRSSI { return lhsRSSI > rhsRSSI }
        if lhs.name != rhs.name { return nameComesBefore(lhs.name, rhs.name) }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func nameComesBefore(_ lhs: String, _ rhs: String) -> Bool {
        let lhsFolded = lhs.lowercased()
        let rhsFolded = rhs.lowercased()
        return lhsFolded == rhsFolded ? lhs < rhs : lhsFolded < rhsFolded
    }
}
