import BlueBandMapCore

enum H1TestMode: String, CaseIterable, Sendable {
    case rasterBaseline
    case rasterOptimized
    case vectorSynthetic8
    case vectorSynthetic20
    case vectorSynthetic40
    case vectorVietmap

    var renderer: RenderKind {
        switch self {
        case .rasterBaseline, .rasterOptimized: .raster
        case .vectorSynthetic8, .vectorSynthetic20, .vectorSynthetic40, .vectorVietmap: .vector
        }
    }

    var expectedPrimitives: Int {
        switch self {
        case .rasterBaseline, .rasterOptimized: 0
        case .vectorSynthetic8: 8
        case .vectorSynthetic20: 20
        case .vectorSynthetic40: 40
        case .vectorVietmap: 0
        }
    }

    var requiresServiceKey: Bool {
        self == .rasterBaseline || self == .rasterOptimized
    }

    var requiresTileMapKey: Bool {
        self == .vectorVietmap
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
