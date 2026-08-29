# Module boundaries

| Module | Owns | Must not own |
|---|---|---|
| `BlueBandProtocol` | CRC, SPP frames/reassembly, defensive protobuf, Xiaomi commands, ThirdPartyApp codec | Crypto frameworks, Bluetooth, UI, storage |
| `BlueBandCrypto` | HMAC/HKDF, key derivation, CTR/CCM composition, constant-time equality | Apple Security or CommonCrypto imports |
| `BlueBandCryptoCommonCrypto` | Production AES-128 block provider | Session policy |
| `BlueBandCore` | Authentication, proof gating, session state, RPK trust, envelope ACK/dedup/timeout | CoreBluetooth, Keychain, SwiftUI |
| `apps/ios` | Apple adapters, composition root, user interaction | Protocol duplication |
| `apps/band` | Vela lifecycle, envelope v1 peer, one-page echo UI | Xiaomi BLE framing |
| `tools/protocol-lab` | Offline parsing and redaction | Runtime secrets or production state |

Dependencies point inward. Apple adapters conform to package interfaces; package code never constructs adapters.
