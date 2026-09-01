import Foundation
import BlueBandCore

public enum RenderKind: String, Codable, CaseIterable, Sendable {
    case raster
}

public enum RenderFormat: String, Codable, Sendable {
    case raster = "image/png"
}

public enum RenderRejectCode: String, Codable, CaseIterable, Sendable {
    case unsupportedRenderer
    case unsupportedFormatVersion
    case busy
    case payloadTooLarge
    case tooManyPrimitives
    case invalidDimensions
    case insufficientStorage
}

public enum RenderProtocolError: Swift.Error, Equatable, Sendable {
    case invalidIdentifier
    case invalidDimensions
    case invalidFormat
    case unsupportedFormatVersion
    case emptyPayload
    case payloadTooLarge
    case tooManyPrimitives
    case invalidSHA256
    case invalidMilliseconds
    case invalidByteCount
}

public enum RenderProtocol {
    public static let prepareTopic = "render.prepare"
    public static let readyTopic = "render.ready"
    public static let rejectTopic = "render.reject"
    public static let resultTopic = "render.result"

    public static let formatVersion = 1
    public static let viewportWidth = 212
    public static let viewportHeight = 520
    public static let maximumPayloadBytes = 8_192
    public static let maximumPrimitives = 0
    public static let maximumIdentifierBytes = 24

    public static func isValidIdentifier(_ value: String) -> Bool {
        let bytes = value.utf8
        return (1...maximumIdentifierBytes).contains(bytes.count)
            && bytes.allSatisfy { (0x20...0x7E).contains($0) }
    }

    public static func isValidSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    static func validate(
        runID: String,
        sceneID: String,
        renderer: RenderKind,
        format: String,
        formatVersion: Int,
        width: Int,
        height: Int,
        bytes: Int,
        sha256: String,
        primitives: Int
    ) throws {
        guard isValidIdentifier(runID), isValidIdentifier(sceneID) else {
            throw RenderProtocolError.invalidIdentifier
        }
        guard width == viewportWidth, height == viewportHeight else {
            throw RenderProtocolError.invalidDimensions
        }
        guard renderer == .raster, format == RenderFormat.raster.rawValue else {
            throw RenderProtocolError.invalidFormat
        }
        guard formatVersion == Self.formatVersion else {
            throw RenderProtocolError.unsupportedFormatVersion
        }
        guard (1...maximumPayloadBytes).contains(bytes) else {
            throw bytes <= 0 ? RenderProtocolError.emptyPayload : RenderProtocolError.payloadTooLarge
        }
        guard (0...maximumPrimitives).contains(primitives) else {
            throw RenderProtocolError.tooManyPrimitives
        }
        guard isValidSHA256(sha256) else {
            throw RenderProtocolError.invalidSHA256
        }
    }
}

public struct RenderNavigationPreview: Equatable, Codable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidDistance, invalidMarker, invalidHeading, invalidDestination
    }

    public let maneuver: NavigationManeuver
    public let distanceMeters: Int
    public let street: String
    public let x: Int
    public let y: Int
    public let headingBucket: Int
    public let destinationMode: DestinationPresentationMode
    public let destinationX: Int
    public let destinationY: Int

    public init(
        maneuver: NavigationManeuver,
        distanceMeters: Int,
        street: String,
        x: Int,
        y: Int,
        headingBucket: Int,
        destinationMode: DestinationPresentationMode,
        destinationX: Int,
        destinationY: Int
    ) throws {
        guard distanceMeters >= 0 else { throw Error.invalidDistance }
        guard BandDisplaySafeMask.smartBand10PhotoEstimate.contains(
            center: ScreenPoint(x: x, y: y),
            resourceWidth: 46,
            resourceHeight: 54
        ) else { throw Error.invalidMarker }
        guard (0..<8).contains(headingBucket) else { throw Error.invalidHeading }
        if destinationMode == .hidden {
            guard destinationX == 0, destinationY == 0 else { throw Error.invalidDestination }
        } else {
            let height = destinationMode == .visible ? 24 : 20
            let mask = destinationMode == .edge
                ? BandDisplaySafeMask.smartBand10PhotoEstimate.withoutVisualMargin
                : BandDisplaySafeMask.smartBand10PhotoEstimate
            guard mask.contains(
                center: ScreenPoint(x: destinationX, y: destinationY),
                resourceWidth: 20,
                resourceHeight: height
            ) else { throw Error.invalidDestination }
        }
        var boundedStreet = street
        while boundedStreet.utf8.count > 48 { boundedStreet.removeLast() }
        self.maneuver = maneuver
        self.distanceMeters = distanceMeters
        self.street = boundedStreet
        self.x = x
        self.y = y
        self.headingBucket = headingBucket
        self.destinationMode = destinationMode
        self.destinationX = destinationX
        self.destinationY = destinationY
    }

    public func jsonBody() -> [String: JSONValue] {
        [
            "maneuver": .string(maneuver.rawValue),
            "distanceM": .number(Double(distanceMeters)),
            "street": .string(street),
            "x": .number(Double(x)),
            "y": .number(Double(y)),
            "heading": .number(Double(headingBucket)),
            "destinationMode": .string(destinationMode.rawValue),
            "destinationX": .number(Double(destinationX)),
            "destinationY": .number(Double(destinationY)),
        ]
    }
}

public struct RenderPrepareBody: Equatable, Codable, Sendable {
    public let runID: String
    public let sceneID: String
    public let renderer: RenderKind
    public let format: String
    public let formatVersion: Int
    public let width: Int
    public let height: Int
    public let bytes: Int
    public let sha256: String
    public let primitives: Int
    public let preview: RenderNavigationPreview?

    public init(
        runID: String,
        sceneID: String,
        asset: RenderAsset,
        preview: RenderNavigationPreview? = nil
    ) throws {
        try RenderProtocol.validate(
            runID: runID,
            sceneID: sceneID,
            renderer: asset.kind,
            format: asset.format.rawValue,
            formatVersion: asset.formatVersion,
            width: asset.width,
            height: asset.height,
            bytes: asset.byteCount,
            sha256: asset.sha256,
            primitives: asset.primitives
        )
        self.runID = runID
        self.sceneID = sceneID
        self.renderer = asset.kind
        self.format = asset.format.rawValue
        self.formatVersion = asset.formatVersion
        self.width = asset.width
        self.height = asset.height
        self.bytes = asset.byteCount
        self.sha256 = asset.sha256
        self.primitives = asset.primitives
        self.preview = preview
    }

    public func jsonBody() -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "runId": .string(runID),
            "sceneId": .string(sceneID),
            "renderer": .string(renderer.rawValue),
            "format": .string(format),
            "formatVersion": .number(Double(formatVersion)),
            "width": .number(Double(width)),
            "height": .number(Double(height)),
            "bytes": .number(Double(bytes)),
            "sha256": .string(sha256),
            "primitives": .number(Double(primitives)),
        ]
        if let preview { body["preview"] = .object(preview.jsonBody()) }
        return body
    }
}

public struct RenderReadyBody: Equatable, Codable, Sendable {
    public let runID: String
    public let sceneID: String
    public let renderer: RenderKind
    public let formatVersion: Int
    public let width: Int
    public let height: Int
    public let bytes: Int
    public let primitives: Int

    public init(runID: String, sceneID: String, prepare: RenderPrepareBody) {
        self.runID = runID
        self.sceneID = sceneID
        self.renderer = prepare.renderer
        self.formatVersion = prepare.formatVersion
        self.width = prepare.width
        self.height = prepare.height
        self.bytes = prepare.bytes
        self.primitives = prepare.primitives
    }

    public func jsonBody() -> [String: JSONValue] {
        [
            "runId": .string(runID),
            "sceneId": .string(sceneID),
            "renderer": .string(renderer.rawValue),
            "formatVersion": .number(Double(formatVersion)),
            "width": .number(Double(width)),
            "height": .number(Double(height)),
            "bytes": .number(Double(bytes)),
            "primitives": .number(Double(primitives)),
        ]
    }
}

public struct RenderRejectBody: Equatable, Codable, Sendable {
    public let runID: String
    public let sceneID: String
    public let code: RenderRejectCode

    public init(runID: String, sceneID: String, code: RenderRejectCode) {
        self.runID = runID
        self.sceneID = sceneID
        self.code = code
    }

    public func jsonBody() -> [String: JSONValue] {
        [
            "runId": .string(runID),
            "sceneId": .string(sceneID),
            "code": .string(code.rawValue),
        ]
    }
}

public struct RenderResultBody: Equatable, Codable, Sendable {
    public let runID: String
    public let sceneID: String
    public let renderer: RenderKind
    public let formatVersion: Int
    public let success: Bool
    public let bytes: Int
    public let primitives: Int
    public let validateMilliseconds: Int
    public let renderMilliseconds: Int
    public let errorCode: RenderRejectCode?

    public init(
        runID: String,
        sceneID: String,
        renderer: RenderKind,
        formatVersion: Int,
        success: Bool,
        bytes: Int,
        primitives: Int,
        validateMilliseconds: Int,
        renderMilliseconds: Int,
        errorCode: RenderRejectCode? = nil
    ) {
        self.runID = runID
        self.sceneID = sceneID
        self.renderer = renderer
        self.formatVersion = formatVersion
        self.success = success
        self.bytes = bytes
        self.primitives = primitives
        self.validateMilliseconds = validateMilliseconds
        self.renderMilliseconds = renderMilliseconds
        self.errorCode = errorCode
    }

    public func jsonBody() -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "runId": .string(runID),
            "sceneId": .string(sceneID),
            "renderer": .string(renderer.rawValue),
            "formatVersion": .number(Double(formatVersion)),
            "status": .string(success ? "ok" : "error"),
            "bytes": .number(Double(bytes)),
            "primitives": .number(Double(primitives)),
            "validateMs": .number(Double(validateMilliseconds)),
            "renderMs": .number(Double(renderMilliseconds)),
        ]
        if let errorCode {
            body["errorCode"] = .string(errorCode.rawValue)
        }
        return body
    }
}
