import Foundation

public enum VietmapVectorTileDecoder {
    // Vietmap GL JS 6.x applies this vendor transform before protobuf decoding.
    private static let key: [UInt8] = [
        80, 88, 228, 30, 157, 170, 173, 154, 233, 247, 128, 170, 135, 27, 48, 165,
        148, 251, 99, 44, 105, 248, 18, 145, 34, 163, 70, 114, 228, 184, 229, 72,
    ]

    public static func decode(_ data: Data) throws -> MapboxVectorTile {
        guard data.count <= MapboxVectorTile.maximumBodyBytes else {
            throw MapboxVectorTile.Error.bodyTooLarge
        }
        let decoded = Data(data.enumerated().map { index, byte in
            byte ^ key[index % key.count]
        })
        return try MapboxVectorTile.decode(decoded)
    }
}
