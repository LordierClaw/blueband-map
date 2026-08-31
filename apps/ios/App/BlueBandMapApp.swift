import SwiftUI
import BlueBandCore
import BlueBandCryptoCommonCrypto
import BlueBandMapCore

enum BlueBandProduct {
    static let displayName = "BlueBandMap"
    static let version = "0.1.9"
    static let bundleIdentifier = "dev.lordierclaw.bluebandmap"
    static let rpkPackage = "dev.lordierclaw.bluebandmap.band"
}

@main
struct BlueBandMapApp: App {
    @StateObject private var model: AppModel

    init() {
        let central = BandCentral()
        let cipher = CommonCryptoAESBlockCipher()
        let trustStore = KeychainTrustedRPKStore()
        let vietmapKeyStore = KeychainVietmapKeyStore()
        let vietmapTransport = URLSessionHTTPTransport()
        let session = BandSession(
            central: central,
            authenticator: BandAuthenticator(cipher: cipher),
            cipher: cipher,
            trustedRPKStore: trustStore,
            expectedPackage: BlueBandProduct.rpkPackage
        )
        let routeCardAssetFactory = RouteCardAssetFactory(
            styleClient: VietmapStyleClient(transport: vietmapTransport),
            tileTransport: vietmapTransport
        )
        _model = StateObject(wrappedValue: AppModel(
            keyStore: KeychainAuthKeyStore(),
            vietmapKeyStore: vietmapKeyStore,
            bandStore: UserDefaultsRememberedBandStore(),
            trustedRPKStore: trustStore,
            central: central,
            session: session,
            routeClient: VietmapRouteClient(transport: vietmapTransport),
            assetFactory: routeCardAssetFactory,
            locationClient: ForegroundLocationClient(),
            routeCardSession: BandSessionRouteCardSender(session: session)
        ))
    }

    var body: some Scene {
        WindowGroup { ContentView(model: model) }
    }
}
