import CoreGraphics
import CoreText
import Foundation
import BlueBandMapCore

/// A bitmap-only renderer for an active navigation session while iOS prohibits GPU work.
/// Uses the same camera, provider style selection, route strokes, and final encoder as the SDK.
actor VietmapCPURenderer {
    private let transport: any MapHTTPTransport
    private var style: VietmapMapStyle?
    private var styleKey: String?
    private var tiles: [URL: VietmapSceneTile] = [:]
    private var costs: [URL: Int] = [:]
    private var order: [URL] = []

    init(transport: any MapHTTPTransport = URLSessionHTTPTransport(timeout: 2)) {
        self.transport = transport
    }

    func render(_ request: VietmapSnapshotRequest) async throws -> VietmapSnapshotOutput {
        try Task.checkCancellation()
        let started = Date()
        let configuration = try VietmapSnapshotConfiguration.make(request)
        if styleKey != request.tileMapKey {
            style = nil
            tiles.removeAll(); costs.removeAll(); order.removeAll()
            styleKey = request.tileMapKey
        }
        if style == nil {
            let loadedStyle = try await VietmapStyleClient(transport: transport).loadMapStyle(tileMapKey: request.tileMapKey)
            try Task.checkCancellation()
            style = loadedStyle
        }
        guard let style else { throw VietmapSnapshotRenderer.Error.styleLoadFailed }
        let loaded = Date()
        let zoom = min(Int(configuration.zoom), style.template.maximumZoom ?? 15)
        guard zoom >= style.template.minimumZoom ?? 0 else { throw VietmapSnapshotRenderer.Error.invalidRequest }
        let coordinates = Self.tileCoordinates(configuration, zoom: zoom)
        guard !coordinates.isEmpty else { throw VietmapSnapshotRenderer.Error.invalidRequest }
        let missing = try coordinates.compactMap { coordinate -> (URL, Int, Int)? in
            let url = try style.template.url(z: zoom, x: coordinate.x, y: coordinate.y, tileMapKey: request.tileMapKey)
            return tiles[url] == nil ? (url, coordinate.x, coordinate.y) : nil
        }
        let transport = transport
        let fetched = try await withThrowingTaskGroup(of: (URL, VietmapSceneTile, Int).self) { group in
            for (url, x, y) in missing {
                group.addTask {
                    let response = try await transport.execute(MapHTTPRequest(method: "GET", url: url,
                        headers: ["Accept": "application/vnd.mapbox-vector-tile, application/x-protobuf"],
                        body: Data(), maximumResponseBytes: MapboxVectorTile.maximumBodyBytes))
                    guard response.statusCode == 200 else { throw RouteCardAssetFactory.Error.tileHTTPStatus(response.statusCode) }
                    let type = response.header(named: "Content-Type")?.split(separator: ";").first?.lowercased()
                    guard type == nil || ["application/vnd.mapbox-vector-tile", "application/x-protobuf", "application/octet-stream", "text/plain"].contains(type!) else {
                        throw RouteCardAssetFactory.Error.tileWrongContentType
                    }
                    guard !response.body.isEmpty else { throw RouteCardAssetFactory.Error.tileEmpty }
                    try Task.checkCancellation()
                    let tile = try VietmapVectorTileDecoder.decode(response.body)
                    // Account for decoded geometry and strings, not only compressed HTTP bytes.
                    let cost = tile.layers.reduce(0) { total, layer in
                        total + layer.features.reduce(0) { cost, feature in
                            cost + feature.lines.reduce(0) { $0 + $1.count * 16 } +
                                feature.properties.reduce(128) { $0 + $1.key.utf8.count + $1.value.utf8.count + 64 }
                        }
                    }
                    return (url, VietmapSceneTile(tile: tile, zoom: zoom, x: x, y: y), cost)
                }
            }
            var fetched: [(URL, VietmapSceneTile, Int)] = []
            var cost = 0
            for try await value in group {
                cost += value.2
                guard cost <= 24 * 1024 * 1024 else { throw VietmapSnapshotRenderer.Error.imageUnavailable }
                fetched.append(value)
            }
            return fetched
        }
        try Task.checkCancellation()
        for (url, tile, cost) in fetched {
            tiles[url] = tile; costs[url] = cost
        }
        let urls = try coordinates.map { try style.template.url(z: zoom, x: $0.x, y: $0.y, tileMapKey: request.tileMapKey) }
        let sourceTiles = urls.compactMap { tiles[$0] }
        for url in urls { order.removeAll { $0 == url }; order.append(url) }
        while order.count > 16 || costs.values.reduce(0, +) > 24 * 1024 * 1024 {
            guard !order.isEmpty else { break }
            let oldest = order.removeFirst()
            tiles.removeValue(forKey: oldest); costs.removeValue(forKey: oldest)
        }
        guard sourceTiles.count == coordinates.count else { throw VietmapSnapshotRenderer.Error.imageUnavailable }
        let image = try Self.draw(request, configuration: configuration, style: style, tiles: sourceTiles)
        let layers = Self.layers(style, request: request, configuration: configuration)
        return VietmapSnapshotOutput(image: image,
            retainedFillLayers: layers.filter { $0.type == "fill" }.count,
            retainedLineLayers: layers.filter { $0.type == "line" }.count,
            retainedSymbolLayers: layers.filter { $0.type == "symbol" }.count,
            zoom: configuration.zoom, styleLoadMilliseconds: Int(loaded.timeIntervalSince(started) * 1000),
            snapshotMilliseconds: Int(Date().timeIntervalSince(loaded) * 1000),
            cacheState: missing.isEmpty ? "cpu-warm" : "cpu-cold", configuration: configuration)
    }

    nonisolated static func tileCoordinates(_ config: VietmapSnapshotConfiguration, zoom: Int) -> [(x: Int, y: Int)] {
        let corners = [CGPoint(x: -24, y: -24), CGPoint(x: 236, y: -24), CGPoint(x: -24, y: 544), CGPoint(x: 236, y: 544)]
        let count = Double(1 << zoom)
        let world = corners.map { config.worldPoint(for: $0) }
        let scale = 512 * pow(2, config.zoom - Double(zoom))
        let minX = max(0, Int(floor(world.map(\.x).min()! / scale)))
        let maxX = min(Int(count) - 1, Int(floor(world.map(\.x).max()! / scale)))
        let minY = max(0, Int(floor(world.map(\.y).min()! / scale)))
        let maxY = min(Int(count) - 1, Int(floor(world.map(\.y).max()! / scale)))
        guard minX <= maxX, minY <= maxY, (maxX - minX + 1) * (maxY - minY + 1) <= 9 else { return [] }
        return (minY...maxY).flatMap { y in (minX...maxX).map { (x: $0, y: y) } }
    }

    private nonisolated static func layers(_ style: VietmapMapStyle, request: VietmapSnapshotRequest,
                                          configuration: VietmapSnapshotConfiguration) -> [VietmapMapStyle.Layer] {
        style.layers.filter {
            ($0.minzoom ?? 0) <= configuration.zoom && ($0.maxzoom ?? 24) > configuration.zoom &&
            $0.layout?["visibility"] != .string("none") &&
            VietmapStyleLayerPolicy.keeps(id: $0.id, type: $0.type, zoom: configuration.zoom, profile: request.profile)
        }
    }

    nonisolated static func draw(_ request: VietmapSnapshotRequest, configuration: VietmapSnapshotConfiguration,
                                 style: VietmapMapStyle, tiles: [VietmapSceneTile]) throws -> CGImage {
        guard let context = CGContext(data: nil, width: 424, height: 1040, bitsPerComponent: 8, bytesPerRow: 424 * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw VietmapSnapshotRenderer.Error.imageUnavailable
        }
        context.translateBy(x: 0, y: 1040)
        context.scaleBy(x: 2, y: -2)
        context.setFillColor(VietmapDarkStyle.color(id: "background", type: "background").cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 212, height: 520))
        var occupied: [CGRect] = [], names = Set<String>()
        let centerWorld = configuration.worldPoint(for: CGPoint(x: 106, y: 260))
        let angle = configuration.heading * .pi / 180, cosine = cos(angle), sine = sin(angle)
        for layer in layers(style, request: request, configuration: configuration) {
            try Task.checkCancellation()
            if layer.type == "background" { continue }
            let color = VietmapDarkStyle.color(id: layer.id, type: layer.type).cgColor
            context.setFillColor(color); context.setStrokeColor(color)
            context.setLineWidth(min(128, max(0, layer.number("line-width", zoom: configuration.zoom, fallback: 1))))
            context.setLineCap(layer.layout?["line-cap"] == .string("round") ? .round : .butt)
            context.setLineJoin(layer.layout?["line-join"] == .string("round") ? .round : .miter)
            context.setAlpha(min(1, max(0, layer.number(layer.type + "-opacity", zoom: configuration.zoom, fallback: 1))))
            for tile in tiles {
                guard let source = tile.tile.layers.first(where: { $0.name == layer.sourceLayer }) else { continue }
                let scale = 512 * pow(2, configuration.zoom - Double(tile.zoom))
                for feature in source.features where layer.matches(feature) {
                    let lines = feature.lines.map { line in line.map { point in
                        let x = (Double(tile.x) + Double(point.x) / Double(source.extent)) * scale - centerWorld.x
                        let y = (Double(tile.y) + Double(point.y) / Double(source.extent)) * scale - centerWorld.y
                        return CGPoint(x: 106 + x * cosine + y * sine, y: 260 - x * sine + y * cosine)
                    } }
                    if layer.type == "symbol" {
                        let name = layer.text(for: feature)
                        guard !name.isEmpty, !names.contains(name), occupied.count < 48 else { continue }
                        if drawLabel(name, lines: lines, context: context, occupied: &occupied) { names.insert(name) }
                        continue
                    }
                    context.beginPath()
                    for line in lines {
                        guard let first = line.first else { continue }
                        context.move(to: first)
                        for point in line.dropFirst() { context.addLine(to: point) }
                        if layer.type == "fill" { context.closePath() }
                    }
                    if layer.type == "fill" { context.drawPath(using: .eoFill) } else { context.strokePath() }
                }
            }
        }
        context.setAlpha(1)
        VietmapRouteOverlay.draw(request, context: context, project: configuration.point(for:))
        drawText("© Vietmap", at: CGPoint(x: 106, y: 490), angle: 0, size: 9, context: context)
        guard let image = context.makeImage() else { throw VietmapSnapshotRenderer.Error.imageUnavailable }
        return image
    }

    // ponytail: labels use the longest visible near-straight run; add glyph-on-curve layout
    // only if device comparisons show a readability loss on curved streets.
    private nonisolated static func drawLabel(_ text: String, lines: [[CGPoint]], context: CGContext,
                                              occupied: inout [CGRect]) -> Bool {
        let font = CTFontCreateUIFontForLanguage(.system, 14, "vi" as CFString)!
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        var candidates: [(CGPoint, CGPoint)] = []
        for points in lines {
            // Join short collinear MVT segments before finding a readable placement.
            var run: [CGPoint] = []
            for point in points {
                if run.count >= 2 {
                    let first = run[0], previous = run.last!
                    let a = atan2(previous.y - first.y, previous.x - first.x)
                    let b = atan2(point.y - previous.y, point.x - previous.x)
                    if abs(atan2(sin(a - b), cos(a - b))) > 0.18 {
                        if let clipped = clip(first, previous) { candidates.append(clipped) }
                        run = [previous]
                    }
                }
                run.append(point)
            }
            if let first = run.first, let last = run.last, let clipped = clip(first, last) { candidates.append(clipped) }
        }
        candidates.sort { hypot($0.1.x - $0.0.x, $0.1.y - $0.0.y) > hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        for (a, b) in candidates where hypot(b.x - a.x, b.y - a.y) >= width + 8 {
            let center = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            var angle = atan2(b.y - a.y, b.x - a.x)
            if angle > .pi / 2 { angle -= .pi }; if angle < -.pi / 2 { angle += .pi }
            let w = abs(cos(angle)) * width + abs(sin(angle)) * 18
            let h = abs(sin(angle)) * width + abs(cos(angle)) * 18
            let box = CGRect(x: center.x - w / 2 - 2, y: center.y - h / 2 - 2, width: w + 4, height: h + 4)
            guard !occupied.contains(where: { $0.intersects(box) }) else { continue }
            occupied.append(box)
            drawText(text, at: center, angle: angle, size: 14, context: context)
            return true
        }
        return false
    }

    private nonisolated static func drawText(_ text: String, at center: CGPoint, angle: CGFloat,
                                             size: CGFloat, context: CGContext) {
        let font = CTFontCreateUIFontForLanguage(.system, size, "vi" as CFString)!
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
        ]))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.saveGState()
        context.translateBy(x: center.x, y: center.y); context.rotate(by: angle); context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.setLineWidth(2.5)
        context.setLineJoin(.round)
        context.setStrokeColor(VietmapDarkStyle.color(id: "background", type: "background").cgColor)
        context.setFillColor(VietmapDarkStyle.color(id: "label", type: "symbol").cgColor)
        context.setTextDrawingMode(.stroke)
        context.textPosition = CGPoint(x: -width / 2, y: -(CTFontGetAscent(font) - CTFontGetDescent(font)) / 2)
        CTLineDraw(line, context)
        context.setTextDrawingMode(.fill)
        context.textPosition = CGPoint(x: -width / 2, y: -(CTFontGetAscent(font) - CTFontGetDescent(font)) / 2)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private nonisolated static func clip(_ a: CGPoint, _ b: CGPoint) -> (CGPoint, CGPoint)? {
        let dx = b.x - a.x, dy = b.y - a.y
        var lo: CGFloat = 0, hi: CGFloat = 1
        for (p, q) in [(-dx, a.x - 4), (dx, 208 - a.x), (-dy, a.y - 4), (dy, 502 - a.y)] {
            if p == 0 { if q < 0 { return nil }; continue }
            if p < 0 { lo = max(lo, q / p) } else { hi = min(hi, q / p) }
            if lo > hi { return nil }
        }
        return (CGPoint(x: a.x + lo * dx, y: a.y + lo * dy), CGPoint(x: a.x + hi * dx, y: a.y + hi * dy))
    }
}
