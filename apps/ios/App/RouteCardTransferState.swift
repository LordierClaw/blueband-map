import BlueBandMapCore

enum RouteCardMode: String, CaseIterable, Sendable {
    case routeCard

    var renderer: RenderKind {
        .raster
    }

    var expectedPrimitives: Int {
        0
    }

}

struct RouteCardRenderInput: Sendable {
    let route: RoutePlan
    let progressIndex: Int
}

enum RouteCardTransferState: Equatable, Sendable {
    case idle
    case fetching(mode: RouteCardMode)
    case preparing(mode: RouteCardMode, runID: String)
    case transferring(mode: RouteCardMode, completed: Int, total: Int)
    case waitingForBand(mode: RouteCardMode, runID: String, sceneID: String)
    case displayed(mode: RouteCardMode, runID: String, hashPrefix: String)
    case failed(mode: RouteCardMode, code: String)
}
