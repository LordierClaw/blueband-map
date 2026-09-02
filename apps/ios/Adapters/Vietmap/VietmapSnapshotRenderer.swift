import CoreGraphics
import CoreLocation
import Foundation
import UIKit
import VietMap
import BlueBandMapCore

struct EdgeInsets: Equatable, Sendable {
    let top: CGFloat
    let left: CGFloat
    let bottom: CGFloat
    let right: CGFloat
}

struct VietmapSnapshotRequest: Sendable {
    let route: RoutePlan
    let matchedPosition: GeoPoint
    let overlayGeometry: RouteOverlayGeometry
    let headingDegrees: Double
    let nextManeuver: GeoPoint
    let tileMapKey: String
    var profile: SnapshotPaletteProfile = .colors32Labels
}

struct VietmapSnapshotConfiguration: Equatable, Sendable {
    private static let sdkTileSize = 512.0

    let size: CGSize
    let scale: CGFloat
    let pitch: CGFloat
    let heading: Double
    let userVerticalFraction: Double
    let overlayInsets: EdgeInsets
    let zoom: Double
    let center: GeoPoint

    func point(for coordinate: GeoPoint) -> CGPoint {
        let centerWorld = world(center), pointWorld = world(coordinate)
        let angle = heading * .pi / 180
        let x = pointWorld.x - centerWorld.x, y = pointWorld.y - centerWorld.y
        return CGPoint(
            x: size.width / 2 + x * cos(angle) + y * sin(angle),
            y: size.height / 2 - x * sin(angle) + y * cos(angle)
        )
    }

    static func make(_ request: VietmapSnapshotRequest) throws -> Self {
        guard request.route.points.count >= 2,
              request.headingDegrees.isFinite,
              (0...360).contains(request.headingDegrees),
              !request.tileMapKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VietmapSnapshotRenderer.Error.invalidRequest
        }
        let distance = meters(request.matchedPosition, request.nextManeuver)
        var zoom: Double = distance <= 150 ? 17 : distance <= 500 ? 16 : distance <= 1_500 ? 15 : 14
        let size = CGSize(width: RenderProtocol.viewportWidth, height: RenderProtocol.viewportHeight)
        let overlayInsets = EdgeInsets(top: 144, left: 14, bottom: 12, right: 14)
        let desiredPoint = CGPoint(
            x: min(size.width - overlayInsets.right, max(overlayInsets.left, size.width / 2)),
            y: min(size.height - overlayInsets.bottom, max(overlayInsets.top, size.height * 0.72))
        )
        let mask = BandDisplaySafeMask.smartBand10PhotoEstimate
        while zoom >= 10 {
            let center = cameraCenter(
                matched: request.matchedPosition,
                heading: request.headingDegrees,
                zoom: zoom,
                desiredPoint: desiredPoint,
                size: size
            )
            let configuration = Self(
                size: size,
                scale: 2,
                pitch: 0,
                heading: request.headingDegrees,
                userVerticalFraction: 0.72,
                overlayInsets: overlayInsets,
                zoom: zoom,
                center: center
            )
            let user = configuration.point(for: request.matchedPosition)
            let forward = configuration.point(for: request.nextManeuver)
            if forward.y < user.y,
               mask.contains(
                center: ScreenPoint(x: Int(user.x.rounded()), y: Int(user.y.rounded())),
                resourceWidth: 30,
                resourceHeight: 38
               ),
               mask.contains(
                center: ScreenPoint(x: Int(forward.x.rounded()), y: Int(forward.y.rounded())),
                resourceWidth: 1,
                resourceHeight: 1
               ) { return configuration }
            zoom -= 1
        }
        throw VietmapSnapshotRenderer.Error.invalidRequest
    }

    private static func cameraCenter(
        matched: GeoPoint,
        heading: Double,
        zoom: Double,
        desiredPoint: CGPoint,
        size: CGSize
    ) -> GeoPoint {
        let matchedWorld = world(matched, zoom: zoom)
        let screenX = desiredPoint.x - size.width / 2, screenY = desiredPoint.y - size.height / 2
        let angle = heading * .pi / 180
        let worldX = screenX * cos(angle) - screenY * sin(angle)
        let worldY = screenX * sin(angle) + screenY * cos(angle)
        return coordinate(CGPoint(x: matchedWorld.x - worldX, y: matchedWorld.y - worldY), zoom: zoom)
    }

    private func world(_ point: GeoPoint) -> CGPoint { Self.world(point, zoom: zoom) }

    private static func world(_ point: GeoPoint, zoom: Double) -> CGPoint {
        let scale = sdkTileSize * pow(2, zoom)
        let latitude = min(85.051_128_78, max(-85.051_128_78, point.latitude)) * .pi / 180
        return CGPoint(
            x: (point.longitude + 180) / 360 * scale,
            y: (1 - log(tan(latitude) + 1 / cos(latitude)) / .pi) / 2 * scale
        )
    }

    private static func coordinate(_ point: CGPoint, zoom: Double) -> GeoPoint {
        let scale = sdkTileSize * pow(2, zoom)
        let longitude = point.x / scale * 360 - 180
        let n = .pi - 2 * .pi * point.y / scale
        return GeoPoint(latitude: atan(sinh(n)) * 180 / .pi, longitude: longitude)
    }

    private static func meters(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let earth = 6_371_000.0, radians = Double.pi / 180
        let dLatitude = (b.latitude - a.latitude) * radians
        let dLongitude = (b.longitude - a.longitude) * radians
        let latitude1 = a.latitude * radians, latitude2 = b.latitude * radians
        let value = sin(dLatitude / 2) * sin(dLatitude / 2) +
            cos(latitude1) * cos(latitude2) * sin(dLongitude / 2) * sin(dLongitude / 2)
        return earth * 2 * atan2(sqrt(value), sqrt(max(0, 1 - value)))
    }
}

enum VietmapStyleLayerPolicy {
    static func isRoadLabel(id: String) -> Bool {
        let id = id.lowercased()
        return id.hasPrefix("road_") && id.contains("label")
    }

    static func keeps(
        id: String,
        type: String,
        zoom: Double,
        profile: SnapshotPaletteProfile = .colors32Labels
    ) -> Bool {
        let id = id.lowercased(), type = type.lowercased()
        switch type {
        case "background": return id == "background"
        case "fill":
            if id.contains("building") { return zoom >= 16 }
            if !profile.keepsLowPriorityLandUse,
               ["residential", "cemetery", "theme_park"].contains(where: id.contains) {
                return false
            }
            return ["ocean", "island", "water", "landcover_park", "landcover_grass", "landcover_wood",
                    "landuse_residential", "landuse_cemetery", "landuse_hospital", "landuse_school", "landuse_theme_park"]
                .contains { id.contains($0) }
        case "line": return ["road", "tunnel", "bridge"].contains { id.contains($0) }
        case "symbol":
            if isRoadLabel(id: id) {
                if ["minor", "service", "street", "residential"].contains(where: id.contains) {
                    return profile.keepsLowPriorityLabels && zoom >= 16
                }
                return ["motorway", "trunk", "primary", "secondary", "tertiary"].contains(where: id.contains)
            }
            return profile.keepsLowPriorityLabels && zoom >= 16 &&
                ["poi_hospital", "poi_school", "transit_station", "parking"].contains(where: id.contains)
        default: return false
        }
    }
}

enum VietmapRoadLabelStyle {
    static let textSize = 14.0
    static let haloWidth = 1.25
}

enum VietmapDarkStyle {
    static func colorHex(id: String, type: String) -> String {
        let id = id.lowercased()
        switch type.lowercased() {
        case "background": return "#050e16"
        case "fill" where id.contains("water") || id.contains("ocean"): return "#004f6e"
        case "fill" where id.contains("park") || id.contains("grass") || id.contains("wood"): return "#163d2b"
        case "fill" where id.contains("hospital") || id.contains("school"): return "#25304a"
        case "fill" where id.contains("building"): return "#28343f"
        case "fill" where id.contains("residential"): return "#1c2b32"
        case "fill": return "#101c23"
        case "line" where id.contains("casing"): return "#223047"
        case "line" where id.contains("primary") || id.contains("motorway") || id.contains("trunk"): return "#60738f"
        case "line" where id.contains("secondary") || id.contains("tertiary"): return "#465a74"
        case "line": return "#2f4057"
        case "symbol": return "#f4f3e5"
        default: return "#1c2b32"
        }
    }

    static func color(id: String, type: String) -> UIColor {
        color(hex: colorHex(id: id, type: type))
    }

    static func color(hex: String) -> UIColor {
        let hex = hex.dropFirst()
        let value = UInt32(hex, radix: 16) ?? 0
        return UIColor(
            red: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}

struct VietmapRouteOverlay {
    enum Kind: Equatable { case subdued, traveled, context, activeCasing, active, maneuver }
    struct Command: Equatable { let kind: Kind; let width: CGFloat }
    static let subduedColorHex = "#243852"
    static let traveledColorHex = "#41516b"
    static let contextColorHex = "#31577f"
    static let activeCasingColorHex = "#071622"
    static let activeColorHex = "#168cff"

    static func commands(for request: VietmapSnapshotRequest) -> [Command] {
        [Command(kind: .subdued, width: 3), Command(kind: .traveled, width: 4),
         Command(kind: .context, width: 4), Command(kind: .activeCasing, width: 10),
         Command(kind: .active, width: 6),
         Command(kind: .maneuver, width: 9)]
    }

    static func draw(_ request: VietmapSnapshotRequest, on overlay: MGLMapSnapshotOverlay) {
        let context = overlay.context
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        drawPath(request.overlayGeometry.subdued, color: VietmapDarkStyle.color(hex: subduedColorHex).cgColor, width: 3, overlay: overlay)
        drawPath(request.overlayGeometry.traveled, color: VietmapDarkStyle.color(hex: traveledColorHex).cgColor, width: 4, overlay: overlay)
        drawPath(request.overlayGeometry.context, color: VietmapDarkStyle.color(hex: contextColorHex).cgColor, width: 4, overlay: overlay)
        drawPath(request.overlayGeometry.active, color: VietmapDarkStyle.color(hex: activeCasingColorHex).cgColor, width: 10, overlay: overlay)
        drawPath(request.overlayGeometry.active, color: VietmapDarkStyle.color(hex: activeColorHex).cgColor, width: 6, overlay: overlay)
        let point = overlay.point(for: coordinate(request.nextManeuver))
        context.setStrokeColor(VietmapDarkStyle.color(hex: activeColorHex).cgColor)
        context.setLineWidth(3)
        context.strokeEllipse(in: CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9))
        context.restoreGState()
    }

    private static func drawPath(
        _ points: [GeoPoint],
        color: CGColor,
        width: CGFloat,
        overlay: MGLMapSnapshotOverlay
    ) {
        guard points.count >= 2 else { return }
        let context = overlay.context
        context.beginPath()
        context.move(to: overlay.point(for: coordinate(points[0])))
        for point in points.dropFirst() { context.addLine(to: overlay.point(for: coordinate(point))) }
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.strokePath()
    }

    private static func coordinate(_ point: GeoPoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }
}

struct VietmapSnapshotOutput: @unchecked Sendable {
    let image: CGImage
    let retainedFillLayers: Int
    let retainedLineLayers: Int
    let retainedSymbolLayers: Int
    let zoom: Double
    let styleLoadMilliseconds: Int
    let snapshotMilliseconds: Int
    let cacheState: String
    let configuration: VietmapSnapshotConfiguration
}

@MainActor
final class VietmapSnapshotRenderer: NSObject, MGLMapSnapshotterDelegate {
    enum Error: Swift.Error { case invalidRequest, busy, styleLoadFailed, snapshotFailed, imageUnavailable }

    private var snapshotter: MGLMapSnapshotter?
    private var prewarmer: MGLMapSnapshotter?
    private var continuation: CheckedContinuation<VietmapSnapshotOutput, Swift.Error>?
    private var configuration: VietmapSnapshotConfiguration?
    private var startedMilliseconds = 0
    private var styleLoadedMilliseconds = 0
    private var retainedFillLayers = 0
    private var retainedLineLayers = 0
    private var retainedSymbolLayers = 0
    private var hasWarmStyle = false
    private var renderCacheState = "cold"
    private var profile: SnapshotPaletteProfile = .colors32Labels

    func prewarm(tileMapKey: String) {
        guard prewarmer == nil,
              let styleURL = Self.styleURL(tileMapKey: tileMapKey) else { return }
        let camera = MGLMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 0, longitude: 0), altitude: 0, pitch: 0, heading: 0)
        let options = MGLMapSnapshotOptions(styleURL: styleURL, camera: camera, size: CGSize(width: 1, height: 1))
        options.scale = 1
        options.zoomLevel = 0
        let prewarmer = MGLMapSnapshotter(options: options)
        self.prewarmer = prewarmer
        prewarmer.start { [weak self, weak prewarmer] snapshot, error in
            if snapshot != nil, error == nil { self?.hasWarmStyle = true }
            if self?.prewarmer === prewarmer { self?.prewarmer = nil }
        }
    }

    func stopPrewarming() {
        prewarmer?.cancel()
        prewarmer = nil
    }

    func render(_ request: VietmapSnapshotRequest) async throws -> VietmapSnapshotOutput {
        guard snapshotter == nil else { throw Error.busy }
        let configuration = try VietmapSnapshotConfiguration.make(request)
        guard let styleURL = Self.styleURL(tileMapKey: request.tileMapKey) else { throw Error.invalidRequest }
        let camera = MGLMapCamera(
            lookingAtCenter: CLLocationCoordinate2D(latitude: configuration.center.latitude, longitude: configuration.center.longitude),
            altitude: 0,
            pitch: configuration.pitch,
            heading: configuration.heading
        )
        let options = MGLMapSnapshotOptions(styleURL: styleURL, camera: camera, size: configuration.size)
        options.scale = configuration.scale
        options.zoomLevel = configuration.zoom
        let snapshotter = MGLMapSnapshotter(options: options)
        snapshotter.delegate = self
        self.snapshotter = snapshotter
        self.configuration = configuration
        startedMilliseconds = nowMilliseconds()
        styleLoadedMilliseconds = 0
        retainedFillLayers = 0
        retainedLineLayers = 0
        retainedSymbolLayers = 0
        renderCacheState = hasWarmStyle ? "warm" : "cold"
        profile = request.profile

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                snapshotter.start(overlayHandler: { overlay in
                    VietmapRouteOverlay.draw(request, on: overlay)
                }, completionHandler: { [weak self] snapshot, error in
                    self?.complete(snapshot: snapshot, error: error)
                })
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func mapSnapshotter(_ snapshotter: MGLMapSnapshotter, didFinishLoading style: MGLStyle) {
        guard snapshotter === self.snapshotter, let configuration else { return }
        for layer in style.layers.reversed() {
            let type: String
            switch layer {
            case is MGLBackgroundStyleLayer: type = "background"
            case is MGLFillStyleLayer: type = "fill"
            case is MGLLineStyleLayer: type = "line"
            case is MGLSymbolStyleLayer: type = "symbol"
            default: type = "other"
            }
            guard VietmapStyleLayerPolicy.keeps(
                id: layer.identifier,
                type: type,
                zoom: configuration.zoom,
                profile: profile
            ) else {
                style.removeLayer(layer)
                continue
            }
            let color = NSExpression(forConstantValue: VietmapDarkStyle.color(id: layer.identifier, type: type))
            if let layer = layer as? MGLBackgroundStyleLayer { layer.backgroundColor = color }
            if let layer = layer as? MGLFillStyleLayer {
                layer.fillColor = color
                layer.fillOutlineColor = color
            }
            if let layer = layer as? MGLLineStyleLayer { layer.lineColor = color }
            if let layer = layer as? MGLSymbolStyleLayer {
                layer.textColor = color
                layer.textHaloColor = NSExpression(forConstantValue: VietmapDarkStyle.color(id: "background", type: "background"))
                if VietmapStyleLayerPolicy.isRoadLabel(id: layer.identifier) {
                    layer.textFontSize = NSExpression(forConstantValue: VietmapRoadLabelStyle.textSize)
                    layer.textHaloWidth = NSExpression(forConstantValue: VietmapRoadLabelStyle.haloWidth)
                }
            }
            if type == "fill" { retainedFillLayers += 1 }
            if type == "line" { retainedLineLayers += 1 }
            if type == "symbol" { retainedSymbolLayers += 1 }
        }
        styleLoadedMilliseconds = nowMilliseconds()
    }

    func mapSnapshotterDidFail(_ snapshotter: MGLMapSnapshotter, withError error: Swift.Error) {
        guard snapshotter === self.snapshotter else { return }
        complete(snapshot: nil, error: error)
    }

    private func complete(snapshot: MGLMapSnapshot?, error: Swift.Error?) {
        guard let continuation else { return }
        let now = nowMilliseconds()
        let finishedConfiguration = configuration
        self.continuation = nil
        self.snapshotter = nil
        self.configuration = nil
        if error != nil {
            continuation.resume(throwing: styleLoadedMilliseconds == 0 ? Error.styleLoadFailed : Error.snapshotFailed)
        } else if let image = snapshot?.image.cgImage, let finishedConfiguration {
            hasWarmStyle = true
            continuation.resume(returning: VietmapSnapshotOutput(
                image: image,
                retainedFillLayers: retainedFillLayers,
                retainedLineLayers: retainedLineLayers,
                retainedSymbolLayers: retainedSymbolLayers,
                zoom: finishedConfiguration.zoom,
                styleLoadMilliseconds: styleLoadedMilliseconds == 0 ? 0 : max(0, styleLoadedMilliseconds - startedMilliseconds),
                snapshotMilliseconds: max(0, now - max(styleLoadedMilliseconds, startedMilliseconds)),
                cacheState: renderCacheState,
                configuration: finishedConfiguration
            ))
        } else {
            continuation.resume(throwing: Error.imageUnavailable)
        }
    }

    private func cancel() {
        snapshotter?.cancel()
        snapshotter = nil
        configuration = nil
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    private func nowMilliseconds() -> Int { Int(Date().timeIntervalSince1970 * 1_000) }

    static func styleURL(tileMapKey: String) -> URL? {
        let key = tileMapKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 512 else { return nil }
        var components = URLComponents(string: "https://maps.vietmap.vn/maps/styles/dm/style.json")!
        components.queryItems = [URLQueryItem(name: "apikey", value: key)]
        return components.url
    }
}
