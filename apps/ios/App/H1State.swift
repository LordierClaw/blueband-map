import BlueBandMapCore

enum H1TestMode: String, CaseIterable, Sendable {
    case rasterStaticCompact
    case rasterTileMap
    case vectorTileMap40
    case vectorTileMap60

    var renderer: RenderKind {
        switch self {
        case .rasterStaticCompact, .rasterTileMap: .raster
        case .vectorTileMap40, .vectorTileMap60: .vector
        }
    }

    var expectedPrimitives: Int {
        switch self {
        case .rasterStaticCompact, .rasterTileMap: 0
        case .vectorTileMap40: 40
        case .vectorTileMap60: 60
        }
    }

    var requiresServiceKey: Bool {
        false
    }

    var requiresTileMapKey: Bool {
        true
    }
}

enum H1State: Equatable, Sendable {
    case idle
    case fetching(mode: H1TestMode)
    case preparing(mode: H1TestMode, runID: String)
    case transferring(mode: H1TestMode, completed: Int, total: Int)
    case waitingForBand(mode: H1TestMode, runID: String, sceneID: String)
    case displayed(mode: H1TestMode, runID: String, hashPrefix: String)
    case failed(mode: H1TestMode, code: String)
}
