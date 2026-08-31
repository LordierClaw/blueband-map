import SwiftUI
import BlueBandCore
import BlueBandCryptoCommonCrypto
import BlueBandMapCore

enum BlueBandProduct {
    static let displayName = "BlueBandMap"
    static let version = "0.1.7"
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
        let staticMapProvider = VietmapStaticMapClient(transport: vietmapTransport)
        let h1AssetFactory = H1AssetFactory(
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
            staticMapProvider: staticMapProvider,
            m1Session: BandSessionM1Sender(session: session),
            h1Session: BandSessionH1Sender(session: session),
            h1AssetProvider: h1AssetFactory.provider
        ))
    }

    var body: some Scene {
        WindowGroup { ContentView(model: model) }
    }
}
