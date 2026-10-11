import CoreGraphics
import CoreText
import Foundation
import BlueBandMapCore
import BlueBandCore

/// A bitmap-only renderer for an active navigation session while iOS prohibits GPU work.
/// Uses the same camera, provider style selection, route strokes, and final encoder as the SDK.
actor VietmapCPURenderer {
    private var performanceObserver: (@Sendable () -> BandPerformanceObserver?)?
    func setPerformanceObserver(_ observer: @escaping @Sendable () -> BandPerformanceObserver?) { performanceObserver = observer }
    private let transport: any MapHTTPTransport
    private var style: VietmapMapStyle?
    private var styleKey: String?
    private var styleTask: Task<VietmapMapStyle, Swift.Error>?
    private var styleTicket = UUID()
    private var preparationOwner = 0
    private var tiles: [URL: VietmapSceneTile] = [:]
    private var costs: [URL: Int] = [:]
    private var order: [URL] = []
    private var atlasPlane: VietmapSnapshotConfiguration?
    private var atlasKey = ""
    private var atlasProfile: SnapshotPaletteProfile?
    private var atlases: [String: CGImage] = [:]
    private var atlasOrder: [String] = []
    private var atlasGeneration = 0
    private var atlasFlight: (key: String, generation: Int, id: UUID, task: Task<CGImage, Swift.Error>)?

    init(transport: any MapHTTPTransport = URLSessionHTTPTransport(timeout: 8)) {
        self.transport = transport
    }

    func prewarm(tileMapKey: String, owner: Int) {
        guard owner >= preparationOwner, !tileMapKey.isEmpty else { return }
        preparationOwner = owner
        selectSource(tileMapKey)
        if style == nil { _ = startStyleLoad(tileMapKey) }
    }

    func stopPreparation(owner: Int) {
        guard owner >= preparationOwner else { return }
        preparationOwner = owner
        styleTicket = UUID(); styleTask?.cancel(); styleTask = nil
        atlasFlight?.task.cancel(); atlasFlight = nil
        atlases.removeAll(); atlasOrder.removeAll(); atlasGeneration += 1
    }

    private func selectSource(_ key: String) {
        guard styleKey != key else { return }
        styleTicket = UUID(); styleTask?.cancel(); styleTask = nil
        style = nil; styleKey = key
        tiles.removeAll(); costs.removeAll(); order.removeAll()
        atlasFlight?.task.cancel(); atlasFlight = nil
        atlases.removeAll(); atlasOrder.removeAll(); atlasGeneration += 1
    }

    private func startStyleLoad(_ key: String) -> Task<VietmapMapStyle, Swift.Error> {
        if let styleTask { return styleTask }
        let ticket = UUID(), transport = transport, observer = performanceObserver?()
        styleTicket = ticket
        let task = Task { () throws -> VietmapMapStyle in
            let started = ProcessInfo.processInfo.systemUptime
            observer?("provider.start", ["stage": .string("style")])
            do {
                let loaded = try await VietmapStyleClient(transport: transport).loadMapStyle(tileMapKey: key)
                try Task.checkCancellation()
                guard self.styleTicket == ticket, self.styleKey == key else { throw CancellationError() }
                self.style = loaded
                self.styleTask = nil
                observer?("provider.style", ["durationMs": .number((ProcessInfo.processInfo.systemUptime - started) * 1000)])
                return loaded
            } catch {
                if self.styleTicket == ticket { self.styleTask = nil }
                Self.recordFailure(error, stage: "style", started: started, observer: observer)
                throw error
            }
        }
        styleTask = task
        return task
    }

    private func loadStyle(_ key: String) async throws -> VietmapMapStyle {
        selectSource(key)
        if let style { return style }
        let task = startStyleLoad(key), ticket = styleTicket
        let loaded = try await task.value
        guard styleTicket == ticket, styleKey == key else { throw CancellationError() }
        try Task.checkCancellation()
        return loaded
    }

    private nonisolated static func recordFailure(_ error: Swift.Error, stage: String, started: TimeInterval,
                                                  observer: BandPerformanceObserver?) {
        let native = error as NSError
        // Never stringify an error: userInfo may contain a provider URL/key.
        let domain = native.domain == NSURLErrorDomain ? "NSURLErrorDomain" : error is CancellationError ? "cancelled" : "provider"
        observer?("provider.failure", ["stage": .string(stage), "domain": .string(domain),
            "code": .number(Double(native.code)), "cancelled": .bool(error is CancellationError || native.code == NSURLErrorCancelled),
            "durationMs": .number((ProcessInfo.processInfo.systemUptime - started) * 1000)])
    }

    func renderCell(_ request: VietmapSnapshotRequest, plane: VietmapSnapshotConfiguration, cell: CorridorCell) async throws -> Data {
        try Task.checkCancellation()
        selectSource(request.tileMapKey)
        guard abs(cell.column) <= 261, abs(cell.row) <= 261 else { throw VietmapSnapshotRenderer.Error.invalidRequest }
        if atlasPlane != plane || atlasKey != request.tileMapKey || atlasProfile != request.profile {
            atlasFlight?.task.cancel(); atlasFlight = nil
            atlases.removeAll(); atlasOrder.removeAll(); atlasGeneration += 1
            atlasPlane = plane; atlasKey = request.tileMapKey; atlasProfile = request.profile
        }
        let generation = atlasGeneration
        let column = Int(floor(Double(cell.column) / 4)), row = Int(floor(Double(cell.row) / 4))
        let key = "\(column):\(row)"
        // Two 768² @2x base atlases: 18 MiB RGBA. The 128 px gutter preserves edge labels.
        let bounds = CGRect(x: column * 512 - 128, y: row * 512 - 128, width: 768, height: 768)
        let base: CGImage
        performanceObserver?()?("map.atlas", ["hit": .bool(atlases[key] != nil), "retained": .number(Double(atlases.count))])
        if let cached = atlases[key] { base = cached }
        else {
            let flight: (key: String, generation: Int, id: UUID, task: Task<CGImage, Swift.Error>)
            if let existing = atlasFlight, existing.key == key, existing.generation == generation {
                flight = existing
            } else {
                atlasFlight?.task.cancel()
                flight = (key, generation, UUID(), Task {
                    try await self.render(request, configuration: plane.window(bounds), baseOnly: true).image
                })
                atlasFlight = flight
            }
            do {
                base = try await flight.task.value
                try Task.checkCancellation()
                guard generation == atlasGeneration else { throw CancellationError() }
                if atlasFlight?.id == flight.id { atlasFlight = nil }
            } catch {
                if atlasFlight?.id == flight.id, !Task.isCancelled { atlasFlight = nil }
                throw error
            }
            // Evict before retaining the new atlas (one additional render may be in flight).
            while atlasOrder.count >= 2 { atlases.removeValue(forKey: atlasOrder.removeFirst()) }
            atlases[key] = base
        }
        atlasOrder.removeAll { $0 == key }; atlasOrder.append(key)
        let cellBounds = CGRect(x: cell.column * 128, y: cell.row * 128, width: 128, height: 128)
        let crop = CGRect(x: (cellBounds.minX - bounds.minX) * 2, y: (cellBounds.minY - bounds.minY) * 2, width: 256, height: 256)
        guard let pixels = base.cropping(to: crop) else { throw VietmapSnapshotRenderer.Error.imageUnavailable }
        let image = try Self.cellImage(base: pixels, request: request, configuration: plane.window(cellBounds))
        let started = ProcessInfo.processInfo.systemUptime
        let encoded = try SnapshotPNGEncoder.encode(image, profiles: [request.profile]).data
        performanceObserver?()?("map.cell.encode", ["durationMs": .number((ProcessInfo.processInfo.systemUptime - started) * 1000),
            "bytes": .number(Double(encoded.count))])
        return encoded
    }

    nonisolated static func cellImage(base: CGImage, request: VietmapSnapshotRequest,
                                     configuration: VietmapSnapshotConfiguration) throws -> CGImage {
        guard base.width == 256, base.height == 256,
              let context = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 1024,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw VietmapSnapshotRenderer.Error.imageUnavailable
        }
        context.draw(base, in: CGRect(x: 0, y: 0, width: 256, height: 256))
        context.translateBy(x: 0, y: 256); context.scaleBy(x: 2, y: -2)
        VietmapRouteOverlay.draw(request, context: context, project: configuration.point(for:))
        guard let image = context.makeImage() else { throw VietmapSnapshotRenderer.Error.imageUnavailable }
        return image
    }

    func render(_ request: VietmapSnapshotRequest, configuration supplied: VietmapSnapshotConfiguration? = nil,
                baseOnly: Bool = false) async throws -> VietmapSnapshotOutput {
        let observer = performanceObserver?()
        try Task.checkCancellation()
        let started = Date()
        let configuration = try supplied ?? VietmapSnapshotConfiguration.make(request)
        let style = try await loadStyle(request.tileMapKey)
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
        observer?("map.tileCache", ["misses": .number(Double(missing.count)),
            "hits": .number(Double(coordinates.count - missing.count)), "retained": .number(Double(tiles.count))])
        try await withThrowingTaskGroup(of: (URL, VietmapSceneTile, Int).self) { group in
            func enqueue(_ item: (URL, Int, Int)) {
                let (url, x, y) = item
                group.addTask {
                    let fetchStarted = ProcessInfo.processInfo.systemUptime
                    var stage = "tile"
                    observer?("provider.start", ["stage": .string(stage)])
                    do {
                    let response = try await transport.execute(MapHTTPRequest(method: "GET", url: url,
                        headers: ["Accept": "application/vnd.mapbox-vector-tile, application/x-protobuf"],
                        body: Data(), maximumResponseBytes: MapboxVectorTile.maximumBodyBytes))
                    let fetched = ProcessInfo.processInfo.systemUptime
                    observer?("provider.tile", ["fetchMs": .number((fetched - fetchStarted) * 1000),
                        "bytes": .number(Double(response.body.count)), "status": .number(Double(response.statusCode))])
                    guard response.statusCode == 200 else { throw RouteCardAssetFactory.Error.tileHTTPStatus(response.statusCode) }
                    let type = response.header(named: "Content-Type")?.split(separator: ";").first?.lowercased()
                    guard type == nil || ["application/vnd.mapbox-vector-tile", "application/x-protobuf", "application/octet-stream", "text/plain"].contains(type!) else {
                        throw RouteCardAssetFactory.Error.tileWrongContentType
                    }
                    guard !response.body.isEmpty else { throw RouteCardAssetFactory.Error.tileEmpty }
                    try Task.checkCancellation()
                    stage = "decode"
                    let tile = try VietmapVectorTileDecoder.decode(response.body)
                    observer?("provider.decode", ["decodeMs": .number((ProcessInfo.processInfo.systemUptime - fetched) * 1000)])
                    // Account for decoded geometry and strings, not only compressed HTTP bytes.
                    let cost = tile.layers.reduce(0) { total, layer in
                        total + layer.features.reduce(0) { cost, feature in
                            cost + feature.lines.reduce(0) { $0 + $1.count * 16 } +
                                feature.properties.reduce(128) { $0 + $1.key.utf8.count + $1.value.utf8.count + 64 }
                        }
                    }
                    return (url, VietmapSceneTile(tile: tile, zoom: zoom, x: x, y: y), cost)
                    } catch {
                        Self.recordFailure(error, stage: stage, started: fetchStarted, observer: observer)
                        throw error
                    }
                }
            }
            var next = 0
            while next < min(4, missing.count) { enqueue(missing[next]); next += 1 }
            var cost = 0
            for try await (url, tile, tileCost) in group {
                try Task.checkCancellation()
                guard styleKey == request.tileMapKey else { throw CancellationError() }
                cost += tileCost
                guard cost <= 24 * 1024 * 1024 else { throw VietmapSnapshotRenderer.Error.imageUnavailable }
                tiles[url] = tile; costs[url] = tileCost
                order.removeAll { $0 == url }; order.append(url)
                trimCache()
                if next < missing.count { enqueue(missing[next]); next += 1 }
            }
        }
        try Task.checkCancellation()
        let urls = try coordinates.map { try style.template.url(z: zoom, x: $0.x, y: $0.y, tileMapKey: request.tileMapKey) }
        let sourceTiles = urls.compactMap { tiles[$0] }
        for url in urls { order.removeAll { $0 == url }; order.append(url) }
        trimCache()
        guard sourceTiles.count == coordinates.count else { throw VietmapSnapshotRenderer.Error.imageUnavailable }
        let drawStarted = ProcessInfo.processInfo.systemUptime
        let image: CGImage
        do { image = try Self.draw(request, configuration: configuration, style: style, tiles: sourceTiles, baseOnly: baseOnly, observer: observer) }
        catch { Self.recordFailure(error, stage: "draw", started: drawStarted, observer: observer); throw error }
        let layers = Self.layers(style, request: request, configuration: configuration)
        return VietmapSnapshotOutput(image: image,
            retainedFillLayers: layers.filter { $0.type == "fill" }.count,
            retainedLineLayers: layers.filter { $0.type == "line" }.count,
            retainedSymbolLayers: layers.filter { $0.type == "symbol" }.count,
            zoom: configuration.zoom, styleLoadMilliseconds: Int(loaded.timeIntervalSince(started) * 1000),
            snapshotMilliseconds: Int(Date().timeIntervalSince(loaded) * 1000),
            cacheState: missing.isEmpty ? "cpu-warm" : "cpu-cold", configuration: configuration)
    }

    private func trimCache() {
        while order.count > 16 || costs.values.reduce(0, +) > 24 * 1024 * 1024 {
            guard !order.isEmpty else { break }
            let oldest = order.removeFirst()
            tiles.removeValue(forKey: oldest); costs.removeValue(forKey: oldest)
        }
    }

    nonisolated static func tileCoordinates(_ config: VietmapSnapshotConfiguration, zoom: Int) -> [(x: Int, y: Int)] {
        let w = config.size.width + 24, h = config.size.height + 24
        let corners = [CGPoint(x: -24, y: -24), CGPoint(x: w, y: -24), CGPoint(x: -24, y: h), CGPoint(x: w, y: h)]
        let count = Double(1 << zoom)
        let world = corners.map { config.worldPoint(for: $0) }
        let scale = 512 * pow(2, config.zoom - Double(zoom))
        let minX = max(0, Int(floor(world.map(\.x).min()! / scale)))
        let maxX = min(Int(count) - 1, Int(floor(world.map(\.x).max()! / scale)))
        let minY = max(0, Int(floor(world.map(\.y).min()! / scale)))
        let maxY = min(Int(count) - 1, Int(floor(world.map(\.y).max()! / scale)))
        let maximum = config.size.width > 520 || config.size.height > 520 ? 16 : 9
        guard minX <= maxX, minY <= maxY, (maxX - minX + 1) * (maxY - minY + 1) <= maximum else { return [] }
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
                                 style: VietmapMapStyle, tiles: [VietmapSceneTile], baseOnly: Bool = false,
                                 observer: BandPerformanceObserver? = nil) throws -> CGImage {
        let started = ProcessInfo.processInfo.systemUptime
        struct FeatureKey: Hashable { let tile: Int; let layer: String; let feature: Int }
        var boundsCache: [FeatureKey: CGRect] = [:], projections: [FeatureKey: [[CGPoint]]] = [:]
        var cachedVertices = 0, projectedVertices = 0, culled = 0, visited = 0, projectionHits = 0
        let size = configuration.size, scale = configuration.scale
        guard size.width > 0, size.height > 0, size.width <= 1024, size.height <= 1024, scale == 2 else {
            throw VietmapSnapshotRenderer.Error.invalidRequest
        }
        let pixelWidth = Int(size.width * scale), pixelHeight = Int(size.height * scale)
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw VietmapSnapshotRenderer.Error.imageUnavailable
        }
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        context.setFillColor(VietmapDarkStyle.color(id: "background", type: "background").cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let fullFrame = !baseOnly && size == CGSize(width: 212, height: 520)
        var occupied = fullFrame ? [CGRect(x: 75, y: 481, width: 62, height: 18)] : [], names = Set<String>()
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let centerWorld = configuration.worldPoint(for: center)
        let labelBounds = CGRect(x: 4, y: 4, width: size.width - 8, height: size.height - (fullFrame ? 22 : 8))
        let angle = configuration.heading * .pi / 180, cosine = cos(angle), sine = sin(angle)
        for layer in layers(style, request: request, configuration: configuration) {
            try Task.checkCancellation()
            if layer.type == "background" { continue }
            let color = VietmapDarkStyle.color(id: layer.id, type: layer.type).cgColor
            context.setFillColor(color); context.setStrokeColor(color)
            let width = min(128, max(0, layer.number("line-width", zoom: configuration.zoom, fallback: 1)))
            let gap = min(128, max(0, layer.number("line-gap-width", zoom: configuration.zoom, fallback: 0)))
            let cap: CGLineCap = layer.layout?["line-cap"] == .string("round") ? .round : .butt
            let join: CGLineJoin = layer.layout?["line-join"] == .string("round") ? .round : .miter
            var dash: [CGFloat] = []
            if case let .array(values) = layer.paint?["line-dasharray"], values.count <= 16 {
                dash = values.compactMap {
                    guard case let .number(value) = $0, value.isFinite, value > 0 else { return nil }
                    return min(1024, value * width)
                }
            }
            context.setLineWidth(width)
            context.setLineCap(cap); context.setLineJoin(join)
            context.setLineDash(phase: 0, lengths: dash)
            context.setAlpha(min(1, max(0, layer.number(layer.type + "-opacity", zoom: configuration.zoom, fallback: 1))))
            // Conservative bounds include stroke miters and the stable label gutter.
            let gutter = layer.type == "line" ? max(2, (gap + 2 * width) * 5 + 2) : layer.type == "symbol" ? 260.0 : 2.0
            let clipWorld = [CGPoint(x: -gutter, y: -gutter), CGPoint(x: size.width + gutter, y: -gutter),
                             CGPoint(x: -gutter, y: size.height + gutter), CGPoint(x: size.width + gutter, y: size.height + gutter)]
                .map { configuration.worldPoint(for: $0) }
            for (tileIndex, tile) in tiles.enumerated() {
                guard let source = tile.tile.layers.first(where: { $0.name == layer.sourceLayer }) else { continue }
                let scale = 512 * pow(2, configuration.zoom - Double(tile.zoom))
                let clipX = clipWorld.map { ($0.x / scale - Double(tile.x)) * Double(source.extent) }
                let clipY = clipWorld.map { ($0.y / scale - Double(tile.y)) * Double(source.extent) }
                let left = clipX.min()!, right = clipX.max()!, top = clipY.min()!, bottom = clipY.max()!
                for (featureIndex, feature) in source.features.enumerated() where layer.matches(feature) {
                    visited += 1
                    if visited % 128 == 0 { try Task.checkCancellation() }
                    let key = FeatureKey(tile: tileIndex, layer: source.name, feature: featureIndex)
                    let bounds: CGRect
                    if let cached = boundsCache[key] { bounds = cached }
                    else {
                        var x0 = Double.infinity, y0 = Double.infinity, x1 = -Double.infinity, y1 = -Double.infinity
                        for line in feature.lines { for p in line {
                            x0 = min(x0, Double(p.x)); x1 = max(x1, Double(p.x))
                            y0 = min(y0, Double(p.y)); y1 = max(y1, Double(p.y))
                        } }
                        bounds = x0.isFinite ? CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0) : .null
                        boundsCache[key] = bounds
                    }
                    // Inclusive comparisons also retain zero-height/zero-width lines and enclosing polygons.
                    guard !bounds.isNull, bounds.maxX >= left, bounds.minX <= right,
                          bounds.maxY >= top, bounds.minY <= bottom else { culled += 1; continue }
                    let lines: [[CGPoint]]
                    if let cached = projections[key] { lines = cached; projectionHits += 1 }
                    else {
                    lines = feature.lines.map { line in line.map { point in
                        let x = (Double(tile.x) + Double(point.x) / Double(source.extent)) * scale - centerWorld.x
                        let y = (Double(tile.y) + Double(point.y) / Double(source.extent)) * scale - centerWorld.y
                        return CGPoint(x: center.x + x * cosine + y * sine, y: center.y - x * sine + y * cosine)
                    } }
                    let count = lines.reduce(0) { $0 + $1.count }
                    projectedVertices += count
                    if cachedVertices + count <= 100_000 { projections[key] = lines; cachedVertices += count }
                    }
                    if layer.type == "symbol" {
                        let name = layer.text(for: feature)
                        guard !name.isEmpty, !names.contains(name), occupied.count < (baseOnly ? 512 : 48) else { continue }
                        if drawLabel(name, lines: lines, context: context, occupied: &occupied, bounds: labelBounds,
                                     stable: baseOnly) { names.insert(name) }
                        continue
                    }
                    context.beginPath()
                    for line in lines {
                        guard let first = line.first else { continue }
                        context.move(to: first)
                        for point in line.dropFirst() { context.addLine(to: point) }
                        if layer.type == "fill" { context.closePath() }
                    }
                    if layer.type == "fill" {
                        context.drawPath(using: .eoFill)
                    } else if gap > 0, let path = context.path {
                        let line = dash.isEmpty ? path : path.copy(dashingWithPhase: 0, lengths: dash)
                        context.beginPath()
                        context.addPath(line.copy(strokingWithWidth: gap + 2 * width, lineCap: cap, lineJoin: join, miterLimit: 10))
                        context.addPath(line.copy(strokingWithWidth: gap, lineCap: cap, lineJoin: join, miterLimit: 10))
                        context.drawPath(using: .eoFill)
                    } else { context.strokePath() }
                }
            }
        }
        context.setAlpha(1)
        if !baseOnly { VietmapRouteOverlay.draw(request, context: context, project: configuration.point(for:)) }
        if fullFrame { drawText("© Vietmap", at: CGPoint(x: 106, y: 490), angle: 0, size: 9, context: context) }
        guard let image = context.makeImage() else { throw VietmapSnapshotRenderer.Error.imageUnavailable }
        observer?("map.cpu.draw", ["durationMs": .number((ProcessInfo.processInfo.systemUptime - started) * 1000),
            "features": .number(Double(visited)), "culled": .number(Double(culled)),
            "projectedVertices": .number(Double(projectedVertices)), "projectionHits": .number(Double(projectionHits))])
        return image
    }

    // ponytail: labels use the longest visible near-straight run; add glyph-on-curve layout
    // only if device comparisons show a readability loss on curved streets.
    private nonisolated static func drawLabel(_ text: String, lines: [[CGPoint]], context: CGContext,
                                              occupied: inout [CGRect], bounds: CGRect, stable: Bool) -> Bool {
        let font = CTFontCreateUIFontForLanguage(.system, 14, "vi" as CFString)!
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        if stable && width > 240 { return false }
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
                        if stable { candidates.append((first, previous)) }
                        else if let clipped = clip(first, previous, bounds: bounds) { candidates.append(clipped) }
                        run = [previous]
                    }
                }
                run.append(point)
            }
            if let first = run.first, let last = run.last {
                if stable { candidates.append((first, last)) }
                else if let clipped = clip(first, last, bounds: bounds) { candidates.append(clipped) }
            }
        }
        candidates.sort { hypot($0.1.x - $0.0.x, $0.1.y - $0.0.y) > hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        if stable { candidates = Array(candidates.prefix(1)) }
        for (a, b) in candidates where hypot(b.x - a.x, b.y - a.y) >= width + 8 {
            let center = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            var angle = atan2(b.y - a.y, b.x - a.x)
            if angle > .pi / 2 { angle -= .pi }; if angle < -.pi / 2 { angle += .pi }
            let w = abs(cos(angle)) * width + abs(sin(angle)) * 18
            let h = abs(sin(angle)) * width + abs(cos(angle)) * 18
            let box = CGRect(x: center.x - w / 2 - 2, y: center.y - h / 2 - 2, width: w + 4, height: h + 4)
            guard bounds.intersects(box), !occupied.contains(where: { $0.intersects(box) }) else { continue }
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

    private nonisolated static func clip(_ a: CGPoint, _ b: CGPoint, bounds: CGRect) -> (CGPoint, CGPoint)? {
        let dx = b.x - a.x, dy = b.y - a.y
        var lo: CGFloat = 0, hi: CGFloat = 1
        for (p, q) in [(-dx, a.x - bounds.minX), (dx, bounds.maxX - a.x), (-dy, a.y - bounds.minY), (dy, bounds.maxY - a.y)] {
            if p == 0 { if q < 0 { return nil }; continue }
            if p < 0 { lo = max(lo, q / p) } else { hi = min(hi, q / p) }
            if lo > hi { return nil }
        }
        return (CGPoint(x: a.x + lo * dx, y: a.y + lo * dy), CGPoint(x: a.x + hi * dx, y: a.y + hi * dy))
    }
}
