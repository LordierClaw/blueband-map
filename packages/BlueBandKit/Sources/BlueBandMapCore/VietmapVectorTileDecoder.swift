import Foundation

public enum VietmapVectorTileDecoder {
    private static let legacyKey: [UInt8] = [
        80, 88, 228, 30, 157, 170, 173, 154, 233, 247, 128, 170, 135, 27, 48, 165,
        148, 251, 99, 44, 105, 248, 18, 145, 34, 163, 70, 114, 228, 184, 229, 72,
    ]
    private static let currentKey: [UInt8] = [
        1, 2, 3, 5, 7, 9, 15, 60, 45, 95, 45, 69, 78, 42, 66, 54,
        99, 57, 54, 33, 22, 11, 66, 99, 99, 77, 55, 23, 45, 65, 72, 35,
    ]

    public static func decode(_ data: Data) throws -> MapboxVectorTile {
        guard data.count <= MapboxVectorTile.maximumBodyBytes else {
            throw MapboxVectorTile.Error.bodyTooLarge
        }
        if data.count >= 3, data.prefix(3).allSatisfy({ $0 == 1 }) {
            let transformed = data.dropFirst(3)
            let decoded = Data(transformed.enumerated().map { index, byte in
                byte ^ currentKey[index % currentKey.count]
            })
            return try MapboxVectorTile.decode(decoded)
        }
        if let tile = try? MapboxVectorTile.decode(data) { return tile }
        let decoded = Data(data.enumerated().map { index, byte in
            byte ^ legacyKey[index % legacyKey.count]
        })
        return try MapboxVectorTile.decode(decoded)
    }
}
