import CoreGraphics
import Foundation
import XCTest
import BlueBandMapCore
@testable import BlueBandMap

@MainActor
final class VietmapSnapshotRendererTests: XCTestCase {
    private struct Layer: Decodable { let id: String; let type: String }

    func testHairpinAndCoincidentManeuversKeepALocalHeadingUpCamera() throws {
        let origin = GeoPoint(latitude: 20.97184, longitude: 105.78985)
        for heading in [0.0, 20, 90, 180, 270, 323, 327] {
            let angle = heading * .pi / 180
            let ahead = GeoPoint(latitude: origin.latitude + 0.0003 * cos(angle),
                longitude: origin.longitude + 0.0003 * sin(angle))
            let behind = GeoPoint(latitude: origin.latitude - 0.0003 * cos(angle),
                longitude: origin.longitude - 0.0003 * sin(angle))
            for maneuver in [behind, origin] {
                let route = RoutePlan(points: [origin, ahead, maneuver], instructions: [], distanceMeters: 100)
                let config = try VietmapSnapshotConfiguration.make(VietmapSnapshotRequest(
                    route: route, matchedPosition: origin,
                    overlayGeometry: .init(subdued: [], traveled: [], active: route.points, context: []),
                    headingDegrees: heading, nextManeuver: maneuver, tileMapKey: "fixture-key"))
                XCTAssertEqual(config.zoom, 17, "do not zoom a hairpin out to a city-wide view")
                XCTAssertEqual(config.heading, heading)
                XCTAssertEqual(config.point(for: origin).x, 106, accuracy: 0.5)
                XCTAssertEqual(config.point(for: origin).y, 374, accuracy: 0.5)
                XCTAssertLessThan(config.point(for: ahead).y, config.point(for: origin).y)
                XCTAssertFalse(VietmapCPURenderer.tileCoordinates(config, zoom: 15).isEmpty)
            }
        }
    }

    func testLockedScreenRenderDoesNotRejectAnActiveNavigationRequest() async throws {
        let origin = GeoPoint(latitude: 10, longitude: 106)
        let forward = GeoPoint(latitude: 10.001, longitude: 106)
        let route = RoutePlan(points: [origin, forward], instructions: [], distanceMeters: 111)
        let transport = CPUMapTestTransport()
        let renderer = VietmapSnapshotRenderer(backgroundRenderer: VietmapCPURenderer(transport: transport))
        renderer.setApplicationActive(false)
        for index in 0..<5 {
            let request = VietmapSnapshotRequest(
                route: route, matchedPosition: origin,
                overlayGeometry: RouteOverlayGeometry(subdued: [], traveled: [], active: route.points, context: []),
                headingDegrees: 0, nextManeuver: forward, tileMapKey: "fixture-key"
            )
            let output = try await renderer.render(request)
            XCTAssertEqual(output.cacheState, index == 0 ? "cpu-cold" : "cpu-warm")
            XCTAssertEqual(output.image.width, 424)
            let encoded = try SnapshotImageEncoder.encode(output.image)
            XCTAssertLessThanOrEqual(encoded.data.count, 8192)
            XCTAssertEqual(output.configuration.point(for: origin).x, 106, accuracy: 0.5)
            XCTAssertEqual(output.configuration.point(for: origin).y, 374, accuracy: 0.5)
        }
        let counts = await transport.counts()
        XCTAssertEqual(counts.style, 1)
        XCTAssertLessThanOrEqual(counts.tiles, 4, "a stationary camera reuses decoded source tiles")
    }

    func testCPUHeadingProjectionGeometryLabelsAndFinalPayload() throws {
        let origin = GeoPoint(latitude: 21.039341, longitude: 106.092286)
        let world = mercator(origin, worldSize: 4096 * pow(2, 15))
        let x = Int(world.x / 4096), y = Int(world.y / 4096)
        let localX = Int(world.x) - x * 4096, localY = Int(world.y) - y * 4096
        func point(_ dx: Int, _ dy: Int) -> MapboxVectorTile.TilePoint { .init(x: localX + dx, y: localY + dy) }
        let source = VietmapSceneTile(tile: MapboxVectorTile(layers: [
            .init(name: "road", extent: 4096, features: [
                .init(geometryType: .lineString, properties: ["name": "Nguyễn Khuyến", "class": "primary"],
                      lines: [[point(-650, -220), point(650, -220)]]),
                .init(geometryType: .lineString, properties: ["name": "Đường Bắc", "class": "primary"],
                      lines: [[point(0, 700), point(0, 0), point(0, -700)]]),
                .init(geometryType: .lineString, properties: ["name": "Đường Cong", "class": "primary"],
                      lines: [[point(-550, 350), point(-350, 150), point(-300, -250), point(-200, -600)]])
            ]),
            .init(name: "water", extent: 4096, features: [
                .init(geometryType: .polygon, properties: [:], lines: [
                    [point(150, -550), point(600, -550), point(600, -300), point(150, -300), point(150, -550)],
                    [point(250, -450), point(250, -350), point(350, -350), point(350, -450), point(250, -450)]
                ])
            ])
        ]), zoom: 15, x: x, y: y)
        let layers = try JSONDecoder().decode([VietmapMapStyle.Layer].self, from: Data(#"""
        [{"id":"water","type":"fill","source-layer":"water"},
         {"id":"road_primary","type":"line","source-layer":"road","paint":{"line-width":12}},
         {"id":"road_primary_label","type":"symbol","source-layer":"road","layout":{"text-field":"{name}"}}]
        """#.utf8))
        let style = VietmapMapStyle(template: .init(urlTemplate: "", sourceLayers: []), layers: layers)
        for heading in [0.0, 45, 90, 180, 270] {
            let radians = heading * .pi / 180
            let forward = GeoPoint(latitude: origin.latitude + 0.0003 * cos(radians),
                                   longitude: origin.longitude + 0.0003 * sin(radians) / cos(origin.latitude * .pi / 180))
            let route = RoutePlan(points: [origin, forward], instructions: [], distanceMeters: 33)
            let request = VietmapSnapshotRequest(route: route, matchedPosition: origin,
                overlayGeometry: .init(subdued: [], traveled: [], active: route.points, context: []),
                headingDegrees: heading, nextManeuver: forward, tileMapKey: "fixture-key")
            let configuration = try VietmapSnapshotConfiguration.make(request)
            let tileCoordinates = VietmapCPURenderer.tileCoordinates(configuration, zoom: 15)
            XCTAssertTrue(tileCoordinates.contains { $0.x == x && $0.y == y })
            XCTAssertLessThanOrEqual(tileCoordinates.count, 4)
            let image = try VietmapCPURenderer.draw(request, configuration: configuration, style: style, tiles: [source])
            let encoded = try SnapshotImageEncoder.encode(image)
            XCTAssertLessThanOrEqual(encoded.data.count, 8192)
            XCTAssertGreaterThan(encoded.data.count, 1000, "roads and text must survive final encoding")
            let marker = configuration.point(for: origin)
            XCTAssertEqual(marker.x, 106, accuracy: 0.5)
            XCTAssertEqual(marker.y, 374, accuracy: 0.5)
            let ahead = configuration.point(for: forward)
            XCTAssertEqual(ahead.x, marker.x, accuracy: 1)
            XCTAssertLessThan(ahead.y, marker.y)
            let attachment = XCTAttachment(data: encoded.data, uniformTypeIdentifier: encoded.format == .jpeg ? "public.jpeg" : "public.png")
            attachment.name = "CPU-map-\(Int(heading))-\(encoded.data.count)bytes"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testFailedSiblingTileDoesNotRefetchSuccessfulTiles() async throws {
        let transport = CPUMapTestTransport(failFirstTile: true)
        let renderer = VietmapCPURenderer(transport: transport)
        let origin = GeoPoint(latitude: 21.039341, longitude: Double(26041) / 32768 * 360 - 180)
        let forward = GeoPoint(latitude: origin.latitude + 0.0003, longitude: origin.longitude)
        let route = RoutePlan(points: [origin, forward], instructions: [], distanceMeters: 33)
        let request = VietmapSnapshotRequest(route: route, matchedPosition: origin,
            overlayGeometry: .init(subdued: [], traveled: [], active: route.points, context: []),
            headingDegrees: 0, nextManeuver: forward, tileMapKey: "fixture-key")
        do { _ = try await renderer.render(request); XCTFail("one tile must fail first") }
        catch RouteCardAssetFactory.Error.tileHTTPStatus(503) {}
        _ = try await renderer.render(request)
        let counts = await transport.tileCounts()
        XCTAssertEqual(counts.values.sorted(), [1, 2], "retry only the failed tile, retaining the successful sibling")
    }

    func testRailDashAndGapRemainDistinctFromSolidRoads() throws {
        let origin = GeoPoint(latitude: 0, longitude: 0)
        let route = RoutePlan(points: [origin, GeoPoint(latitude: 0.001, longitude: 0)], instructions: [], distanceMeters: 111)
        let request = VietmapSnapshotRequest(route: route, matchedPosition: origin,
            overlayGeometry: .init(subdued: [], traveled: [], active: [], context: []),
            headingDegrees: 0, nextManeuver: route.points[1], tileMapKey: "fixture-key")
        let config = try VietmapSnapshotConfiguration.make(request)
        let tile = VietmapSceneTile(tile: .init(layers: [.init(name: "road", extent: 4096,
            features: [.init(geometryType: .lineString, properties: [:], lines: [[.init(x: -500, y: -200), .init(x: 500, y: -200)]])])]),
            zoom: 15, x: 16384, y: 16384)
        func coloredPixels(_ paint: String) throws -> Int {
            let layer = try JSONDecoder().decode(VietmapMapStyle.Layer.self,
                from: Data(("{\"id\":\"road_rail\",\"type\":\"line\",\"source-layer\":\"road\",\"paint\":" + paint + "}").utf8))
            let style = VietmapMapStyle(template: .init(urlTemplate: "", sourceLayers: []), layers: [layer])
            let image = try VietmapCPURenderer.draw(request, configuration: config, style: style, tiles: [tile])
            let bytes = Array(try XCTUnwrap(image.dataProvider?.data) as Data)
            return stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] == 47 && bytes[$0 + 1] == 64 && bytes[$0 + 2] == 87 }.count
        }
        let solid = try coloredPixels(#"{"line-width":8}"#)
        let dashed = try coloredPixels(#"{"line-width":8,"line-dasharray":[0.1,3]}"#)
        XCTAssertGreaterThan(solid, 1000)
        XCTAssertLessThan(dashed, solid / 2, "rail cross-ties must be dashed")
        let thin = try coloredPixels(#"{"line-width":2}"#)
        let rails = try coloredPixels(#"{"line-width":2,"line-gap-width":8}"#)
        XCTAssertGreaterThan(rails, thin * 3 / 2, "gap styling creates two rails, not one center stroke")
    }

    func testRoadLabelsUseReadableSnapshotTypography() {
        XCTAssertTrue(VietmapStyleLayerPolicy.isRoadLabel(id: "road_primary_label"))
        XCTAssertFalse(VietmapStyleLayerPolicy.isRoadLabel(id: "poi_school"))
        XCTAssertEqual(VietmapRoadLabelStyle.textSize, 14)
        XCTAssertEqual(VietmapRoadLabelStyle.haloWidth, 1.25)
    }

    func testSanitizedDarkStyleKeepsOnlyWearableMapContext() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "vietmap-light-style-layers", withExtension: "json"))
        let layers = try JSONDecoder().decode([Layer].self, from: Data(contentsOf: url))
        let retained = layers.filter { VietmapStyleLayerPolicy.keeps(id: $0.id, type: $0.type, zoom: 16) }.map(\.id)

        XCTAssertEqual(retained, [
            "background", "ocean_planet", "island_polygon", "landcover_park",
            "landuse_residential", "landuse_school", "landuse_hospital", "building",
            "road_minor_casing", "road_minor", "road_primary_casing", "road_primary",
            "bridge_primary", "road_primary_label", "road_secondary_label",
            "poi_hospital", "poi_school", "transit_station", "parking",
        ])
    }

    func testUsesOfficialDarkStyleAndDeterministicLowEntropyPaints() throws {
        XCTAssertEqual(
            VietmapSnapshotRenderer.styleURL(tileMapKey: "fixture-key")?.absoluteString,
            "https://maps.vietmap.vn/maps/styles/dm/style.json?apikey=fixture-key"
        )
        XCTAssertEqual(VietmapDarkStyle.colorHex(id: "background", type: "background"), "#050e16")
        XCTAssertEqual(VietmapDarkStyle.colorHex(id: "water", type: "fill"), "#004f6e")
        XCTAssertEqual(VietmapDarkStyle.colorHex(id: "building", type: "fill"), "#28343f")
        XCTAssertEqual(VietmapDarkStyle.colorHex(id: "landuse_hospital", type: "fill"), "#25304a")
        XCTAssertEqual(VietmapDarkStyle.colorHex(id: "road_minor", type: "line"), "#2f4057")
        XCTAssertEqual(VietmapDarkStyle.colorHex(id: "road_primary", type: "line"), "#60738f")
        XCTAssertEqual(VietmapDarkStyle.colorHex(id: "road_primary_label", type: "symbol"), "#f4f3e5")
    }

    func testDegradedProfilesRemoveLowPriorityStyleLayers() {
        XCTAssertTrue(VietmapStyleLayerPolicy.keeps(id: "road_minor_label", type: "symbol", zoom: 16, profile: .colors16Labels))
        XCTAssertFalse(VietmapStyleLayerPolicy.keeps(id: "road_minor_label", type: "symbol", zoom: 15, profile: .colors16Labels))
        XCTAssertFalse(VietmapStyleLayerPolicy.keeps(id: "road_minor_label", type: "symbol", zoom: 16, profile: .colors16NoLowPriorityLabels))
        XCTAssertTrue(VietmapStyleLayerPolicy.keeps(id: "poi_hospital", type: "symbol", zoom: 16, profile: .colors16Labels))
        XCTAssertFalse(VietmapStyleLayerPolicy.keeps(id: "poi_hospital", type: "symbol", zoom: 16, profile: .colors16NoLowPriorityLabels))
        XCTAssertTrue(VietmapStyleLayerPolicy.keeps(id: "road_primary_label", type: "symbol", zoom: 16, profile: .colors16NoLowPriorityLabels))
        XCTAssertTrue(VietmapStyleLayerPolicy.keeps(id: "road_secondary_label", type: "symbol", zoom: 15, profile: .colors16NoLowPriorityLabels))
        XCTAssertFalse(VietmapStyleLayerPolicy.keeps(id: "landuse_residential", type: "fill", zoom: 16, profile: .colors16NoLowPriorityLandUse))
        XCTAssertTrue(VietmapStyleLayerPolicy.keeps(id: "landcover_wood", type: "fill", zoom: 16, profile: .colors16NoLowPriorityLandUse))
        XCTAssertTrue(VietmapStyleLayerPolicy.keeps(id: "water", type: "fill", zoom: 16, profile: .colors16NoLowPriorityLandUse))
    }

    func testSnapshotConfigurationIsFullScreenHeadingUpAndRouteBiased() throws {
        let route = RoutePlan(
            points: [GeoPoint(latitude: 10.0, longitude: 106.0), GeoPoint(latitude: 10.01, longitude: 106.01)],
            instructions: [RouteInstruction(distanceMeters: 300, headingDegrees: 45, sign: 2, interval: 0...1, streetName: "Road")],
            distanceMeters: 300
        )
        let request = VietmapSnapshotRequest(
            route: route,
            matchedPosition: route.points[0],
            overlayGeometry: RouteOverlayGeometry(
                subdued: route.points, traveled: [route.points[0]],
                active: route.points, context: [route.points[1]]
            ),
            headingDegrees: 45,
            nextManeuver: route.points[1],
            tileMapKey: "fixture-key"
        )
        let configuration = try VietmapSnapshotConfiguration.make(request)

        XCTAssertEqual(configuration.size, CGSize(width: 212, height: 520))
        XCTAssertEqual(configuration.scale, 2)
        XCTAssertEqual(configuration.pitch, 0)
        XCTAssertEqual(configuration.heading, 45)
        XCTAssertEqual(configuration.userVerticalFraction, 0.72, accuracy: 0.001)
        XCTAssertEqual(configuration.overlayInsets, EdgeInsets(top: 144, left: 14, bottom: 12, right: 14))
        XCTAssertTrue((14...17).contains(configuration.zoom))
        XCTAssertEqual(configuration.point(for: request.matchedPosition).x, 106, accuracy: 0.5)
        XCTAssertEqual(configuration.point(for: request.matchedPosition).y, 520 * 0.72, accuracy: 0.5)
    }

    func testCameraCenterMatchesPinnedVietmapSDKWorldScale() throws {
        let origin = GeoPoint(latitude: 21.039341, longitude: 106.092286)
        let forward = GeoPoint(latitude: 21.040341, longitude: 106.092286)
        let route = RoutePlan(
            points: [origin, forward],
            instructions: [RouteInstruction(
                distanceMeters: 111, headingDegrees: 0, sign: 0,
                interval: 0...1, streetName: "Road"
            )],
            distanceMeters: 111
        )
        let request = VietmapSnapshotRequest(
            route: route, matchedPosition: origin,
            overlayGeometry: RouteOverlayGeometry(
                subdued: route.points, traveled: [origin], active: route.points, context: []
            ),
            headingDegrees: 0, nextManeuver: forward, tileMapKey: "fixture-key"
        )

        let configuration = try VietmapSnapshotConfiguration.make(request)
        let sdkWorldSize = 512 * pow(2, configuration.zoom)
        let sdkCenter = mercator(configuration.center, worldSize: sdkWorldSize)
        let sdkOrigin = mercator(origin, worldSize: sdkWorldSize)

        XCTAssertEqual(configuration.size.height / 2 + sdkOrigin.y - sdkCenter.y, 520 * 0.72, accuracy: 0.5)
    }

    func testCardinalAndStationaryRouteShapesAlwaysProjectForwardAboveUser() throws {
        let origin = GeoPoint(latitude: 10, longitude: 106)
        let forwardPoints = [
            GeoPoint(latitude: 10.001, longitude: 106),
            GeoPoint(latitude: 10, longitude: 106.001),
            GeoPoint(latitude: 9.999, longitude: 106),
            GeoPoint(latitude: 10, longitude: 105.999),
            GeoPoint(latitude: 10.000_35, longitude: 106.000_18),
            GeoPoint(latitude: 21.065587, longitude: 106.023863)
        ]
        for (index, forward) in forwardPoints.enumerated() {
            let routeOrigin = index == forwardPoints.count - 1
                ? GeoPoint(latitude: 21.039341, longitude: 106.092286) : origin
            let route = RoutePlan(
                points: [routeOrigin, forward],
                instructions: [RouteInstruction(
                    distanceMeters: 100, headingDegrees: 0, sign: 0,
                    interval: 0...1, streetName: "Road"
                )],
                distanceMeters: 100
            )
            var tracker = RouteProgressTracker()
            let progress = tracker.update(
                route: route, location: routeOrigin, horizontalAccuracyMeters: 5
            )
            let selection = try XCTUnwrap(GuidancePresentationPolicy.select(
                route: route, progress: progress, horizontalAccuracyMeters: 5
            ))
            let bearing = GuidancePresentationPolicy.stationaryBearing(
                route: route, progress: progress, selection: selection
            )
            let request = VietmapSnapshotRequest(
                route: route, matchedPosition: routeOrigin,
                overlayGeometry: RouteOverlayGeometry(
                    subdued: route.points, traveled: [routeOrigin], active: route.points, context: []
                ),
                headingDegrees: bearing, nextManeuver: forward, tileMapKey: "fixture-key"
            )
            let configuration = try VietmapSnapshotConfiguration.make(request)
            let user = configuration.point(for: routeOrigin)
            let ahead = configuration.point(for: forward)
            XCTAssertLessThan(ahead.y, user.y, "forward point must be above user for \(forward)")
            let mask = BandDisplaySafeMask.smartBand10PhotoEstimate
            XCTAssertTrue(mask.contains(
                center: ScreenPoint(x: Int(user.x.rounded()), y: Int(user.y.rounded())),
                resourceWidth: 30, resourceHeight: 38
            ))
            XCTAssertTrue(mask.contains(
                center: ScreenPoint(x: Int(ahead.x.rounded()), y: Int(ahead.y.rounded())),
                resourceWidth: 1, resourceHeight: 1
            ))
        }
    }

    func testLocalRouteTangentProjectsStraightAboveUserBeforeLaterBend() throws {
        let origin = GeoPoint(latitude: 10, longitude: 106)
        let north = GeoPoint(latitude: 10.001, longitude: 106)
        let eastAfterBend = GeoPoint(latitude: 10.001, longitude: 106.001)
        let route = RoutePlan(
            points: [origin, north, eastAfterBend],
            instructions: [RouteInstruction(
                distanceMeters: 220, headingDegrees: 90, sign: 2,
                interval: 0...2, streetName: "After Bend"
            )],
            distanceMeters: 220
        )
        var tracker = RouteProgressTracker()
        let progress = tracker.update(
            route: route, location: origin, horizontalAccuracyMeters: 5
        )
        let selection = try XCTUnwrap(GuidancePresentationPolicy.select(
            route: route, progress: progress, horizontalAccuracyMeters: 5
        ))
        let bearing = GuidancePresentationPolicy.stationaryBearing(
            route: route, progress: progress, selection: selection
        )
        let configuration = try VietmapSnapshotConfiguration.make(VietmapSnapshotRequest(
            route: route,
            matchedPosition: origin,
            overlayGeometry: RouteOverlayGeometry(
                subdued: route.points, traveled: [origin], active: route.points, context: []
            ),
            headingDegrees: bearing,
            nextManeuver: eastAfterBend,
            tileMapKey: "fixture-key"
        ))

        let user = configuration.point(for: origin)
        let immediate = configuration.point(for: north)
        XCTAssertEqual(immediate.x, user.x, accuracy: 0.5)
        XCTAssertLessThan(immediate.y, user.y)
    }

    func testOverlayCommandsKeepRouteGeometryAboveRoadsWithoutManeuverDot() throws {
        let route = RoutePlan(
            points: [GeoPoint(latitude: 10, longitude: 106), GeoPoint(latitude: 10.01, longitude: 106.01), GeoPoint(latitude: 10.02, longitude: 106.02)],
            instructions: [RouteInstruction(distanceMeters: 500, headingDegrees: 45, sign: 0, interval: 0...2, streetName: "Road")],
            distanceMeters: 500
        )
        let request = VietmapSnapshotRequest(
            route: route, matchedPosition: route.points[1],
            overlayGeometry: RouteOverlayGeometry(
                subdued: route.points, traveled: Array(route.points.prefix(2)),
                active: Array(route.points.dropFirst(1)), context: [route.points[2]]
            ),
            headingDegrees: 0, nextManeuver: route.points[2], tileMapKey: "fixture-key"
        )

        XCTAssertEqual(VietmapRouteOverlay.commands(for: request).map(\.kind), [
            .subdued, .traveled, .context, .activeCasing, .active,
        ])
        XCTAssertEqual(VietmapRouteOverlay.commands(for: request).map(\.width), [3, 4, 4, 10, 6])
        XCTAssertEqual(VietmapRouteOverlay.traveledColorHex, "#41516b")
        XCTAssertEqual(VietmapRouteOverlay.activeColorHex, "#168cff")
    }

    private func mercator(_ point: GeoPoint, worldSize: Double) -> CGPoint {
        let latitude = min(85.051_128_78, max(-85.051_128_78, point.latitude)) * .pi / 180
        return CGPoint(
            x: (point.longitude + 180) / 360 * worldSize,
            y: (1 - log(tan(latitude) + 1 / cos(latitude)) / .pi) / 2 * worldSize
        )
    }
}

private actor CPUMapTestTransport: MapHTTPTransport {
    private var style = 0
    private var tiles = 0
    private var failFirstTile: Bool
    private var paths: [String: Int] = [:]
    init(failFirstTile: Bool = false) { self.failFirstTile = failFirstTile }
    func tileCounts() -> [String: Int] { paths }
    func counts() -> (style: Int, tiles: Int) { (style, tiles) }
    func execute(_ request: MapHTTPRequest) async throws -> MapHTTPResponse {
        if request.url.path.hasSuffix("style.json") {
            style += 1
            return MapHTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], body: Data(#"""
            {"version":8,"sources":{"map":{"type":"vector","maxzoom":15,"tiles":["https://maps.vietmap.vn/tiles/{z}/{x}/{y}?apikey={apikey}"]}},
             "layers":[{"id":"background","type":"background"},{"id":"road_primary","type":"line","source":"map","source-layer":"road"}]}
            """#.utf8))
        }
        tiles += 1
        paths[request.url.path, default: 0] += 1
        if failFirstTile {
            failFirstTile = false
            try await Task.sleep(for: .milliseconds(100))
            return MapHTTPResponse(statusCode: 503, headers: [:], body: Data())
        }
        // Independent protobuf: one empty layer named road with extent 4096.
        return MapHTTPResponse(statusCode: 200, headers: ["Content-Type": "application/x-protobuf"],
            body: Data([0x1a, 0x0b, 0x0a, 0x04, 0x72, 0x6f, 0x61, 0x64, 0x28, 0x80, 0x20, 0x78, 0x02]))
    }
}
