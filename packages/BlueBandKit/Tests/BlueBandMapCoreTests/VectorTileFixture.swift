import Foundation

enum VectorTileFixture {
    struct Point {
        let x: Int
        let y: Int
    }

    static func lineTile(
        layerName: String = "road",
        classValue: String = "primary",
        points: [Point] = [Point(x: 1_800, y: 1_800), Point(x: 2_300, y: 2_300)],
        extent: Int = 4_096
    ) -> Data {
        var value = Writer()
        value.string(field: 1, classValue)

        var feature = Writer()
        feature.varint(field: 1, 1)
        feature.bytes(field: 2, packedVarints([0, 0]))
        feature.varint(field: 3, 2)
        feature.bytes(field: 4, geometry(points: points))

        var layer = Writer()
        layer.varint(field: 1, 2)
        layer.string(field: 2, layerName)
        layer.bytes(field: 3, feature.data)
        layer.string(field: 4, "class")
        layer.bytes(field: 5, value.data)
        layer.varint(field: 15, UInt64(extent))

        var tile = Writer()
        tile.bytes(field: 3, layer.data)
        return tile.data
    }

    static func malformedGeometryTile(command: UInt64) -> Data {
        var value = Writer()
        value.string(field: 1, "primary")

        var feature = Writer()
        feature.bytes(field: 2, packedVarints([0, 0]))
        feature.varint(field: 3, 2)
        feature.bytes(field: 4, packedVarints([command]))

        var layer = Writer()
        layer.varint(field: 1, 2)
        layer.string(field: 2, "road")
        layer.bytes(field: 3, feature.data)
        layer.string(field: 4, "class")
        layer.bytes(field: 5, value.data)
        layer.varint(field: 15, 4_096)

        var tile = Writer()
        tile.bytes(field: 3, layer.data)
        return tile.data
    }

    private static func geometry(points: [Point]) -> Data {
        guard let first = points.first else { return Data() }
        var values = [UInt64((1 << 3) | 1)]
        var previous = Point(x: 0, y: 0)
        values.append(zigZag(first.x - previous.x))
        values.append(zigZag(first.y - previous.y))
        previous = first
        if points.count > 1 {
            values.append((UInt64(points.count - 1) << 3) | 2)
            for point in points.dropFirst() {
                values.append(zigZag(point.x - previous.x))
                values.append(zigZag(point.y - previous.y))
                previous = point
            }
        }
        return packedVarints(values)
    }

    private static func zigZag(_ value: Int) -> UInt64 {
        UInt64(bitPattern: Int64(value << 1 ^ value >> 63))
    }

    private static func packedVarints(_ values: [UInt64]) -> Data {
        var writer = Writer()
        for value in values { writer.rawVarint(value) }
        return writer.data
    }

    private struct Writer {
        var data = Data()

        mutating func varint(field: Int, _ value: UInt64) {
            rawVarint((UInt64(field) << 3) | 0)
            rawVarint(value)
        }

        mutating func string(field: Int, _ value: String) {
            bytes(field: field, Data(value.utf8))
        }

        mutating func bytes(field: Int, _ value: Data) {
            rawVarint((UInt64(field) << 3) | 2)
            rawVarint(UInt64(value.count))
            data.append(value)
        }

        mutating func rawVarint(_ value: UInt64) {
            var remaining = value
            while remaining >= 0x80 {
                data.append(UInt8(truncatingIfNeeded: remaining) | 0x80)
                remaining >>= 7
            }
            data.append(UInt8(remaining))
        }
    }
}
