import Foundation

public struct MapboxVectorTile: Equatable, Sendable {
    public enum GeometryType: UInt8, Sendable {
        case unknown = 0
        case point = 1
        case lineString = 2
        case polygon = 3
    }

    public struct TilePoint: Equatable, Sendable {
        public let x: Int
        public let y: Int

        public init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }
    }

    public struct Feature: Equatable, Sendable {
        public let geometryType: GeometryType
        public let properties: [String: String]
        public let lines: [[TilePoint]]

        public init(geometryType: GeometryType, properties: [String: String], lines: [[TilePoint]]) {
            self.geometryType = geometryType
            self.properties = properties
            self.lines = lines
        }
    }

    public struct Layer: Equatable, Sendable {
        public let name: String
        public let extent: Int
        public let features: [Feature]

        public init(name: String, extent: Int, features: [Feature]) {
            self.name = name
            self.extent = extent
            self.features = features
        }
    }

    public enum Error: Swift.Error, Equatable, Sendable {
        case bodyTooLarge
        case truncated
        case varintOverflow
        case invalidFieldNumber
        case invalidLength
        case unsupportedWireType(UInt8)
        case tooManyLayers
        case tooManyFeatures
        case invalidExtent
        case invalidProperties
        case unsupportedGeometryCommand
        case tooManyGeometryCommands
        case coordinateOutOfExtent
    }

    public static let maximumBodyBytes = 3 * 1_024 * 1_024
    public static let maximumLayers = 32
    public static let maximumFeatures = 40_000
    public static let maximumGeometryCommands = 16_384
    public let layers: [Layer]

    public init(layers: [Layer]) {
        self.layers = layers
    }

    public static func decode(_ data: Data) throws -> MapboxVectorTile {
        guard data.count <= maximumBodyBytes else { throw Error.bodyTooLarge }
        var reader = Reader(data: data)
        var layers = [Layer]()
        var featureCount = 0
        while !reader.isAtEnd {
            let (field, wireType) = try reader.readKey()
            if field == 3 {
                guard wireType == 2 else { throw Error.unsupportedWireType(wireType) }
                guard layers.count < maximumLayers else { throw Error.tooManyLayers }
                let layerData = try reader.readBytes()
                layers.append(try decodeLayer(layerData, featureCount: &featureCount))
            } else {
                try reader.skip(wireType)
            }
        }
        return MapboxVectorTile(layers: layers)
    }

    private static func decodeLayer(_ data: Data, featureCount: inout Int) throws -> Layer {
        var reader = Reader(data: data)
        var name = ""
        var extent = 4_096
        var featureData = [Data]()
        var keys = [String]()
        var values = [String]()

        while !reader.isAtEnd {
            let (field, wireType) = try reader.readKey()
            switch field {
            case 1:
                guard wireType == 2 else { throw Error.unsupportedWireType(wireType) }
                name = try decodeString(reader.readBytes())
            case 2:
                guard wireType == 2 else { throw Error.unsupportedWireType(wireType) }
                guard featureCount < maximumFeatures else { throw Error.tooManyFeatures }
                featureData.append(try reader.readBytes())
                featureCount += 1
            case 3:
                guard wireType == 2 else { throw Error.unsupportedWireType(wireType) }
                keys.append(try decodeString(reader.readBytes()))
            case 4:
                guard wireType == 2 else { throw Error.unsupportedWireType(wireType) }
                values.append(try decodeValue(reader.readBytes()))
            case 5:
                guard wireType == 0 else { throw Error.unsupportedWireType(wireType) }
                let rawExtent = try reader.readVarint()
                guard rawExtent <= UInt64(Int.max) else { throw Error.invalidExtent }
                extent = Int(rawExtent)
            case 15:
                guard wireType == 0 else { throw Error.unsupportedWireType(wireType) }
                _ = try reader.readVarint()
            default:
                try reader.skip(wireType)
            }
        }

        guard (1...16_384).contains(extent) else { throw Error.invalidExtent }
        let features = try featureData.map {
            try decodeFeature($0, keys: keys, values: values, extent: extent)
        }
        return Layer(name: name, extent: extent, features: features)
    }

    private static func decodeFeature(
        _ data: Data,
        keys: [String],
        values: [String],
        extent: Int
    ) throws -> Feature {
        var reader = Reader(data: data)
        var tags = Data()
        var rawGeometryType: UInt64 = 0
        var geometry = Data()
        while !reader.isAtEnd {
            let (field, wireType) = try reader.readKey()
            switch field {
            case 1:
                guard wireType == 0 else { throw Error.unsupportedWireType(wireType) }
                _ = try reader.readVarint()
            case 2:
                guard wireType == 2 else { throw Error.unsupportedWireType(wireType) }
                tags = try reader.readBytes()
            case 3:
                guard wireType == 0 else { throw Error.unsupportedWireType(wireType) }
                rawGeometryType = try reader.readVarint()
            case 4:
                guard wireType == 2 else { throw Error.unsupportedWireType(wireType) }
                geometry = try reader.readBytes()
            default:
                try reader.skip(wireType)
            }
        }

        let geometryType = GeometryType(rawValue: UInt8(exactly: rawGeometryType) ?? 0) ?? .unknown
        let properties = try decodeProperties(tags: tags, keys: keys, values: values)
        guard geometryType != .unknown else {
            return Feature(geometryType: geometryType, properties: properties, lines: [])
        }
        return Feature(
            geometryType: geometryType,
            properties: properties,
            lines: try decodeLines(geometry, extent: extent, type: geometryType)
        )
    }

    private static func decodeProperties(tags: Data, keys: [String], values: [String]) throws -> [String: String] {
        var reader = Reader(data: tags)
        var indexes = [UInt64]()
        while !reader.isAtEnd { indexes.append(try reader.readVarint()) }
        guard indexes.count.isMultiple(of: 2) else { throw Error.invalidProperties }
        var properties = [String: String]()
        for index in stride(from: 0, to: indexes.count, by: 2) {
            guard indexes[index] < UInt64(keys.count), indexes[index + 1] < UInt64(values.count) else {
                throw Error.invalidProperties
            }
            properties[keys[Int(indexes[index])]] = values[Int(indexes[index + 1])]
        }
        return properties
    }

    private static func decodeLines(_ data: Data, extent: Int, type: GeometryType) throws -> [[TilePoint]] {
        var reader = Reader(data: data)
        var lines = [[TilePoint]]()
        var currentLine = [TilePoint]()
        var currentX = 0
        var currentY = 0
        var commandCount = 0

        while !reader.isAtEnd {
            let command = try reader.readVarint()
            let commandID = command & 0x07
            let count = command >> 3
            guard count > 0 else { throw Error.unsupportedGeometryCommand }
            guard count <= UInt64(maximumGeometryCommands - commandCount) else {
                throw Error.tooManyGeometryCommands
            }
            commandCount += Int(count)

            switch commandID {
            case 1:
                if type == .polygon, count != 1 || !currentLine.isEmpty {
                    throw Error.unsupportedGeometryCommand
                }
                guard count <= UInt64(Int.max) else { throw Error.tooManyGeometryCommands }
                for _ in 0..<Int(count) {
                    if !currentLine.isEmpty { lines.append(currentLine) }
                    currentLine.removeAll(keepingCapacity: true)
                    let deltaX = try zigZag(try reader.readVarint())
                    let deltaY = try zigZag(try reader.readVarint())
                    (currentX, currentY) = try movedPoint(currentX, currentY, deltaX, deltaY, extent: extent)
                    currentLine.append(TilePoint(x: currentX, y: currentY))
                }
            case 2:
                guard type != .point else { throw Error.unsupportedGeometryCommand }
                guard !currentLine.isEmpty, count <= UInt64(Int.max) else {
                    throw Error.unsupportedGeometryCommand
                }
                for _ in 0..<Int(count) {
                    let deltaX = try zigZag(try reader.readVarint())
                    let deltaY = try zigZag(try reader.readVarint())
                    (currentX, currentY) = try movedPoint(currentX, currentY, deltaX, deltaY, extent: extent)
                    currentLine.append(TilePoint(x: currentX, y: currentY))
                }
            case 7:
                if type == .polygon {
                    guard count == 1, currentLine.count >= 3, let first = currentLine.first else {
                        throw Error.unsupportedGeometryCommand
                    }
                    currentLine.append(first)
                } else if type == .point {
                    throw Error.unsupportedGeometryCommand
                }
                if !currentLine.isEmpty { lines.append(currentLine) }
                currentLine.removeAll(keepingCapacity: true)
            default:
                throw Error.unsupportedGeometryCommand
            }
        }
        if type == .polygon, !currentLine.isEmpty { throw Error.unsupportedGeometryCommand }
        if !currentLine.isEmpty { lines.append(currentLine) }
        return lines
    }

    private static func movedPoint(
        _ x: Int,
        _ y: Int,
        _ deltaX: Int,
        _ deltaY: Int,
        extent: Int
    ) throws -> (Int, Int) {
        let (newX, overflowX) = x.addingReportingOverflow(deltaX)
        let (newY, overflowY) = y.addingReportingOverflow(deltaY)
        let bufferedRange = (-extent)...(extent * 2)
        guard !overflowX, !overflowY,
              bufferedRange.contains(newX), bufferedRange.contains(newY) else {
            throw Error.coordinateOutOfExtent
        }
        return (newX, newY)
    }

    private static func zigZag(_ value: UInt64) throws -> Int {
        let shifted = value >> 1
        guard shifted <= UInt64(Int64.max) else { throw Error.coordinateOutOfExtent }
        let positive = Int64(shifted)
        let signed = (value & 1) == 0 ? positive : -positive - 1
        guard signed >= Int64(Int.min), signed <= Int64(Int.max) else {
            throw Error.coordinateOutOfExtent
        }
        return Int(signed)
    }

    private static func decodeString(_ data: Data) throws -> String {
        guard let value = String(data: data, encoding: .utf8) else { throw Error.invalidProperties }
        return value
    }

    private static func decodeValue(_ data: Data) throws -> String {
        var reader = Reader(data: data)
        var value = ""
        while !reader.isAtEnd {
            let (field, wireType) = try reader.readKey()
            switch field {
            case 1:
                guard wireType == 2 else { throw Error.unsupportedWireType(wireType) }
                value = try decodeString(reader.readBytes())
            case 4, 5, 6:
                guard wireType == 0 else { throw Error.unsupportedWireType(wireType) }
                value = String(try reader.readVarint())
            case 7:
                guard wireType == 0 else { throw Error.unsupportedWireType(wireType) }
                value = (try reader.readVarint()) == 0 ? "false" : "true"
            case 2:
                guard wireType == 5 else { throw Error.unsupportedWireType(wireType) }
                value = String(try reader.readFixed32())
            case 3:
                guard wireType == 1 else { throw Error.unsupportedWireType(wireType) }
                value = String(try reader.readFixed64())
            default:
                try reader.skip(wireType)
            }
        }
        return value
    }

    private struct Reader {
        let data: Data
        var offset = 0

        var isAtEnd: Bool { offset == data.count }

        mutating func readKey() throws -> (Int, UInt8) {
            let key = try readVarint()
            let number = key >> 3
            guard number > 0, number <= UInt64(Int.max) else { throw Error.invalidFieldNumber }
            return (Int(number), UInt8(key & 0x07))
        }

        mutating func readVarint() throws -> UInt64 {
            var value: UInt64 = 0
            for index in 0..<10 {
                let byte = try readByte()
                if index == 9, byte > 1 { throw Error.varintOverflow }
                value |= UInt64(byte & 0x7F) << UInt64(index * 7)
                if byte & 0x80 == 0 { return value }
            }
            throw Error.varintOverflow
        }

        mutating func readBytes() throws -> Data {
            let rawLength = try readVarint()
            guard rawLength <= UInt64(Int.max) else { throw Error.invalidLength }
            let length = Int(rawLength)
            guard length <= data.count - offset else { throw Error.truncated }
            let result = Data(data[offset..<(offset + length)])
            offset += length
            return result
        }

        mutating func readFixed32() throws -> UInt32 {
            guard data.count - offset >= 4 else { throw Error.truncated }
            let value = UInt32(data[offset])
                | (UInt32(data[offset + 1]) << 8)
                | (UInt32(data[offset + 2]) << 16)
                | (UInt32(data[offset + 3]) << 24)
            offset += 4
            return value
        }

        mutating func readFixed64() throws -> UInt64 {
            guard data.count - offset >= 8 else { throw Error.truncated }
            var value: UInt64 = 0
            for index in 0..<8 { value |= UInt64(data[offset + index]) << UInt64(index * 8) }
            offset += 8
            return value
        }

        mutating func skip(_ wireType: UInt8) throws {
            switch wireType {
            case 0: _ = try readVarint()
            case 1: _ = try readFixed64()
            case 2: _ = try readBytes()
            case 5: _ = try readFixed32()
            default: throw Error.unsupportedWireType(wireType)
            }
        }

        mutating private func readByte() throws -> UInt8 {
            guard offset < data.count else { throw Error.truncated }
            defer { offset += 1 }
            return data[offset]
        }
    }
}
