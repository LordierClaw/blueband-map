import CoreGraphics
import Foundation
import XCTest
import BlueBandMapCore
@testable import BlueBandMap

@MainActor
final class VietmapSnapshotRendererTests: XCTestCase {
    private struct Layer: Decodable { let id: String; let type: String }

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
        XCTAssertEqual(configuration.scale, 1)
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

    func testOverlayCommandsKeepRouteGeometryAndManeuverAboveRoads() throws {
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
            .subdued, .traveled, .context, .activeCasing, .active, .maneuver,
        ])
        XCTAssertEqual(VietmapRouteOverlay.commands(for: request).map(\.width), [3, 4, 4, 10, 6, 9])
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
