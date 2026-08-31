import Foundation

public enum VectorSceneCodec {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidMagic
        case unsupportedVersion
        case invalidLength
        case invalidViewport
        case tooManySegments
        case invalidSegmentClass
        case outOfViewport
        case invalidHeading
        case invalidManeuver
    }

    public static let headerByteCount = 22
    public static let segmentByteCount = 9
    private static let magic: [UInt8] = [0x42, 0x42, 0x4D, 0x56]

    public static func encode(_ scene: NavigationScene) throws -> Data {
        guard scene.segments.count <= RenderProtocol.maximumPrimitives else { throw Error.tooManySegments }
        var output = Data()
        output.reserveCapacity(headerByteCount + scene.segments.count * segmentByteCount)
        output.append(contentsOf: magic)
        output.append(1)
        appendUInt16(RenderProtocol.viewportWidth, to: &output)
        appendUInt16(RenderProtocol.viewportHeight, to: &output)
        output.append(UInt8(scene.roadSegmentCount))
        output.append(UInt8(scene.routeSegmentCount))
        appendUInt16(scene.currentPosition.x, to: &output)
        appendUInt16(scene.currentPosition.y, to: &output)
        appendUInt16(scene.headingDegrees, to: &output)
        output.append(scene.maneuver.rawValue)
        appendUInt32(scene.distanceMeters, to: &output)

        for segment in scene.segments {
            appendUInt16(segment.start.x, to: &output)
            appendUInt16(segment.start.y, to: &output)
            appendUInt16(segment.end.x, to: &output)
            appendUInt16(segment.end.y, to: &output)
            output.append(segment.lineClass.rawValue)
        }
        return output
    }

    public static func decode(_ data: Data) throws -> NavigationScene {
        guard data.count >= headerByteCount else { throw Error.invalidLength }
        guard Array(data.prefix(4)) == magic else { throw Error.invalidMagic }
        guard data[4] == 1 else { throw Error.unsupportedVersion }

        let width = readUInt16(data, at: 5)
        let height = readUInt16(data, at: 7)
        guard width == RenderProtocol.viewportWidth, height == RenderProtocol.viewportHeight else {
            throw Error.invalidViewport
        }

        let roadCount = Int(data[9])
        let routeCount = Int(data[10])
        let segmentCount = roadCount + routeCount
        guard segmentCount <= RenderProtocol.maximumPrimitives else { throw Error.tooManySegments }
        guard data.count == headerByteCount + segmentCount * segmentByteCount else {
            throw Error.invalidLength
        }

        let currentPosition = ScenePoint(x: readUInt16(data, at: 11), y: readUInt16(data, at: 13))
        guard NavigationScene.isInsideViewport(currentPosition) else { throw Error.outOfViewport }
        let heading = readUInt16(data, at: 15)
        guard heading <= 359 else { throw Error.invalidHeading }
        guard let maneuver = ManeuverKind(rawValue: data[17]) else { throw Error.invalidManeuver }
        let distance = readUInt32(data, at: 18)

        var segments = [SceneSegment]()
        segments.reserveCapacity(segmentCount)
        var offset = headerByteCount
        for _ in 0..<segmentCount {
            let start = ScenePoint(x: readUInt16(data, at: offset), y: readUInt16(data, at: offset + 2))
            let end = ScenePoint(x: readUInt16(data, at: offset + 4), y: readUInt16(data, at: offset + 6))
            guard let lineClass = SceneLineClass(rawValue: data[offset + 8]) else {
                throw Error.invalidSegmentClass
            }
            guard NavigationScene.isInsideViewport(start), NavigationScene.isInsideViewport(end) else {
                throw Error.outOfViewport
            }
            segments.append(SceneSegment(start: start, end: end, lineClass: lineClass))
            offset += segmentByteCount
        }

        do {
            return try NavigationScene(
                currentPosition: currentPosition,
                headingDegrees: heading,
                maneuver: maneuver,
                distanceMeters: distance,
                segments: segments
            )
        } catch NavigationScene.Error.tooManySegments {
            throw Error.tooManySegments
        } catch NavigationScene.Error.outOfViewport {
            throw Error.outOfViewport
        } catch NavigationScene.Error.invalidHeading {
            throw Error.invalidHeading
        }
    }

    private static func appendUInt16(_ value: Int, to data: inout Data) {
        appendUInt16(UInt16(value), to: &data)
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
