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
    let progressIndex: Int
    let matchedPosition: GeoPoint
    let headingDegrees: Double
    let nextManeuver: GeoPoint
    let tileMapKey: String
}

struct VietmapSnapshotConfiguration: Equatable, Sendable {
    let size: CGSize
    let scale: CGFloat
    let pitch: CGFloat
    let heading: Double
    let userVerticalFraction: Double
    let overlayInsets: EdgeInsets
    let zoom: Double
    let center: GeoPoint

    static func make(_ request: VietmapSnapshotRequest) throws -> Self {
        guard request.route.points.count >= 2,
              request.route.points.indices.contains(request.progressIndex),
              request.headingDegrees.isFinite,
              (0...360).contains(request.headingDegrees),
              !request.tileMapKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VietmapSnapshotRenderer.Error.invalidRequest
        }
        let distance = meters(request.matchedPosition, request.nextManeuver)
        let zoom: Double = distance <= 150 ? 17 : distance <= 500 ? 16 : distance <= 1_500 ? 15 : 14
        return Self(
            size: CGSize(width: RenderProtocol.viewportWidth, height: RenderProtocol.viewportHeight),
            scale: 1,
            pitch: 0,
            heading: request.headingDegrees,
            userVerticalFraction: 0.72,
            overlayInsets: EdgeInsets(top: 144, left: 14, bottom: 12, right: 14),
            zoom: zoom,
            center: interpolate(request.matchedPosition, request.nextManeuver, fraction: 0.22)
        )
    }

    private static func interpolate(_ a: GeoPoint, _ b: GeoPoint, fraction: Double) -> GeoPoint {
        GeoPoint(latitude: a.latitude + (b.latitude - a.latitude) * fraction,
                 longitude: a.longitude + (b.longitude - a.longitude) * fraction)
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
    static func keeps(id: String, type: String, zoom: Double) -> Bool {
        let id = id.lowercased(), type = type.lowercased()
        switch type {
        case "background": return id == "background"
        case "fill":
            if id == "building" { return zoom >= 16 }
            return ["ocean", "island", "water", "landcover_park", "landcover_grass", "landcover_wood",
                    "landuse_residential", "landuse_cemetery", "landuse_hospital", "landuse_school", "landuse_theme_park"]
                .contains { id.contains($0) }
        case "line": return ["road", "tunnel", "bridge"].contains { id.contains($0) }
        case "symbol": return id.hasPrefix("road_") && id.contains("label")
        default: return false
        }
    }
}

struct VietmapRouteOverlay {
    enum Kind: Equatable { case traveled, upcomingHalo, upcoming, maneuver }
    struct Command: Equatable { let kind: Kind; let width: CGFloat }

    static func commands(for request: VietmapSnapshotRequest) -> [Command] {
        [Command(kind: .traveled, width: 4), Command(kind: .upcomingHalo, width: 8),
         Command(kind: .upcoming, width: 5), Command(kind: .maneuver, width: 9)]
    }

    static func draw(_ request: VietmapSnapshotRequest, on overlay: MGLMapSnapshotOverlay) {
        let context = overlay.context
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        drawPath(Array(request.route.points.prefix(request.progressIndex + 1)), color: UIColor(white: 0.24, alpha: 1).cgColor, width: 4, overlay: overlay)
        let upcoming = Array(request.route.points.dropFirst(request.progressIndex))
        drawPath(upcoming, color: UIColor(white: 0.04, alpha: 0.95).cgColor, width: 8, overlay: overlay)
        drawPath(upcoming, color: UIColor(red: 0, green: 0.9, blue: 1, alpha: 1).cgColor, width: 5, overlay: overlay)
        let point = overlay.point(for: coordinate(request.nextManeuver))
        context.setStrokeColor(UIColor(red: 0, green: 0.9, blue: 1, alpha: 1).cgColor)
        context.setLineWidth(3)
        context.strokeEllipse(in: CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9))
        context.restoreGState()
    }

    private static func drawPath(_ points: [GeoPoint], color: CGColor, width: CGFloat, overlay: MGLMapSnapshotOverlay) {
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
}

@MainActor
final class VietmapSnapshotRenderer: NSObject, MGLMapSnapshotterDelegate {
    enum Error: Swift.Error { case invalidRequest, busy, styleLoadFailed, snapshotFailed, imageUnavailable }

    private var snapshotter: MGLMapSnapshotter?
    private var continuation: CheckedContinuation<VietmapSnapshotOutput, Swift.Error>?
    private var configuration: VietmapSnapshotConfiguration?
    private var startedMilliseconds = 0
    private var styleLoadedMilliseconds = 0
    private var retainedFillLayers = 0
    private var retainedLineLayers = 0
    private var retainedSymbolLayers = 0

    func prewarm() {}

    func render(_ request: VietmapSnapshotRequest) async throws -> VietmapSnapshotOutput {
        guard snapshotter == nil else { throw Error.busy }
        let configuration = try VietmapSnapshotConfiguration.make(request)
        let key = request.tileMapKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents(string: "https://maps.vietmap.vn/maps/styles/tm/style.json")!
        components.queryItems = [URLQueryItem(name: "apikey", value: key)]
        guard let styleURL = components.url else { throw Error.invalidRequest }
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
            guard VietmapStyleLayerPolicy.keeps(id: layer.identifier, type: type, zoom: configuration.zoom) else {
                style.removeLayer(layer)
                continue
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
        let zoom = configuration?.zoom ?? 0
        self.continuation = nil
        self.snapshotter = nil
        self.configuration = nil
        if error != nil {
            continuation.resume(throwing: styleLoadedMilliseconds == 0 ? Error.styleLoadFailed : Error.snapshotFailed)
        } else if let image = snapshot?.image.cgImage {
            continuation.resume(returning: VietmapSnapshotOutput(
                image: image,
                retainedFillLayers: retainedFillLayers,
                retainedLineLayers: retainedLineLayers,
                retainedSymbolLayers: retainedSymbolLayers,
                zoom: zoom,
                styleLoadMilliseconds: styleLoadedMilliseconds == 0 ? 0 : max(0, styleLoadedMilliseconds - startedMilliseconds),
                snapshotMilliseconds: max(0, now - max(styleLoadedMilliseconds, startedMilliseconds)),
                cacheState: "unknown"
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
}
