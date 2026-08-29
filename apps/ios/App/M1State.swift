import BlueBandMapCore

enum M1State: Equatable, Sendable {
    case idle
    case fetching
    case transferring(completed: Int, total: Int)
    case waitingForBand(assetID: String, hashPrefix: String)
    case displayed(assetID: String, hashPrefix: String)
    case failed(code: String)
}

enum M1Configuration {
    static let request = StaticMapRequest(
        latitude: 10.759157,
        longitude: 106.675859,
        zoom: 17,
        width: 212,
        height: 360
    )
    static let maximumProviderCalls = 1
}
