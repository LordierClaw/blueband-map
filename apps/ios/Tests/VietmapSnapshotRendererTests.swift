import CoreGraphics
import Foundation
import XCTest
import BlueBandMapCore
@testable import BlueBandMap

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
        ])
    }

    func testUsesOfficialDarkStyleAndDeterministicLowEntropyPaints() throws {
        XCTAssertEqual(
            VietmapSnapshotRenderer.styleURL(tileMapKey: "fixture-key")?.absoluteString,
            "https://maps.vietmap.vn/maps/styles/dm/style.json?apikey=fixture-key"
        )
        XCTAssertEqual(VietmapDarkStyle.colorHex(id: "background", type: "background"), "#050e16")
        XCTAssertEqual(VietmapDarkStyle.colorHex(id: "water", type: "fill"), "#004f6e")
        XCTAssertEqual(VietmapDarkStyle.colorHex(id: "road_primary", type: "line"), "#607062")
        XCTAssertEqual(VietmapDarkStyle.colorHex(id: "road_primary_label", type: "symbol"), "#f4f3e5")
    }

    func testDegradedProfilesRemoveLowPriorityStyleLayers() {
        XCTAssertTrue(VietmapStyleLayerPolicy.keeps(id: "road_minor_label", type: "symbol", zoom: 16, profile: .colors16Labels))
        XCTAssertFalse(VietmapStyleLayerPolicy.keeps(id: "road_minor_label", type: "symbol", zoom: 16, profile: .colors16NoLowPriorityLabels))
        XCTAssertTrue(VietmapStyleLayerPolicy.keeps(id: "road_primary_label", type: "symbol", zoom: 16, profile: .colors16NoLowPriorityLabels))
        XCTAssertFalse(VietmapStyleLayerPolicy.keeps(id: "landuse_residential", type: "fill", zoom: 16, profile: .colors16NoLowPriorityLandUse))
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
            progressIndex: 0,
            matchedPosition: route.points[0],
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

    func testOverlayCommandsKeepRouteGeometryAndManeuverAboveRoads() throws {
        let route = RoutePlan(
            points: [GeoPoint(latitude: 10, longitude: 106), GeoPoint(latitude: 10.01, longitude: 106.01), GeoPoint(latitude: 10.02, longitude: 106.02)],
            instructions: [], distanceMeters: 500
        )
        let request = VietmapSnapshotRequest(
            route: route, progressIndex: 1, matchedPosition: route.points[1],
            headingDegrees: 0, nextManeuver: route.points[2], tileMapKey: "fixture-key"
        )

        XCTAssertEqual(VietmapRouteOverlay.commands(for: request).map(\.kind), [
            .traveled, .upcoming, .maneuver,
        ])
        XCTAssertEqual(VietmapRouteOverlay.commands(for: request).map(\.width), [4, 5, 9])
    }
}
