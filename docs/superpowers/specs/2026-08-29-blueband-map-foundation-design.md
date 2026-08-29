# BlueBand Map Foundation Design

**Status:** Approved for implementation on 2026-08-29

**Repository:** `blueband-map`

**License:** Apache License 2.0

## 1. Purpose

BlueBand Map is a reusable, Linux-first foundation for a custom iPhone application to communicate directly with a custom Xiaomi Smart Band 10 Vela application. It derives from the hardware-confirmed BlueBand proof of concept and preserves that project's verified Xiaomi BLE, authentication, SPP v2, ThirdPartyApp, and Vela interconnect behavior.

The foundation is intentionally application-neutral. Its first sample topic is an echo exchange that proves arbitrary bidirectional application data, correlation, and acknowledgement. Product features are built later as topic handlers above the application message session, without changing the Xiaomi transport stack.

The development host is Ubuntu 26.04 with Docker. There is no owned or rented Mac. All routine protocol, crypto-composition, state-machine, RPK, and protocol-lab work must therefore run locally in containers. Standard GitHub-hosted macOS runners provide the Apple-only build and test boundary at no charge because the repository is public.

## 2. Verified Baseline and Evidence Policy

The source baseline is the sibling BlueBand POC repository at commit `bae2f51ce4dfb12cff81e72d9146812092cd861e`, whose handover records the implementation baseline at commit `bf7e2644ab2bc97552d2b4df33a82c4c1918f6ec`.

The verified runtime path is:

```text
BlueBandMap iOS app
    ⇅ CoreBluetooth
Xiaomi FE95 GATT service and Xiaomi SPP v2
    ⇅ authenticated and encrypted protobuf commands
Xiaomi Smart Band 10 firmware
    ⇅ ThirdPartyApp routing
BlueBandMap Vela RPK using system.interconnect
```

Evidence remains classified as one of:

- **Hardware-confirmed:** observed on an iPhone and Xiaomi Smart Band 10.
- **Automated-contract-confirmed:** validated against exact bytes, deterministic vectors, state transitions, or built artifacts.
- **Reference-derived:** inferred from pinned public reference implementations or schemas.
- **Officially documented:** specified by Apple or Xiaomi Vela documentation.

Automated success must never be described as hardware confirmation. Protocol behavior already confirmed on hardware must not be changed without contradictory packet evidence, an architecture decision record, new deterministic tests, and a new hardware acceptance run.

## 3. Scope

### 3.1 Included

- Xiaomi Smart Band 10 only.
- One iPhone companion application and one Vela RPK package.
- Foreground discovery, selection, connect, session ownership, and explicit disconnect.
- FE95 discovery, Xiaomi SPP v2, Xiaomi BLE v2 authentication, proof reads, and ThirdPartyApp routing.
- An existing 16-byte Xiaomi AuthKey entered at runtime.
- A versioned, bounded, general-purpose JSON application envelope.
- Application acknowledgements, delivery timeout, duplicate suppression, and bounded in-memory history.
- RPK package pinning and trust-on-first-use fingerprint verification.
- Linux-first local tests and public GitHub Actions for Apple-only checks and unsigned IPA production.
- Free Apple ID signing and sideloading outside CI.

### 3.2 Excluded

- Other Xiaomi models, multiple bands, or multiple RPK packages.
- AuthKey extraction, Xiaomi account login, or Xiaomi cloud APIs.
- Background BLE, CoreBluetooth restoration, automatic reconnect, or persistent connection ownership.
- Health, workout, weather, calendar, GPS, ANCS, notification, streaming, or large-file features.
- Android relays or an Android runtime dependency.
- App Store, TestFlight, paid Apple Developer Program, rented Mac, or purchased Mac workflows.
- macOS KVM, Hackintosh, or other macOS virtualization on non-Apple hardware as a supported workflow.
- Server accounts, remote authorization, analytics, and cloud persistence.

## 4. Product Identity

The initial identities are fixed:

| Item | Value |
|---|---|
| Repository | `blueband-map` |
| Product and iOS display name | `BlueBandMap` |
| iOS application bundle ID | `dev.lordierclaw.bluebandmap` |
| iOS test bundle ID | `dev.lordierclaw.bluebandmap.tests` |
| Vela RPK package | `dev.lordierclaw.bluebandmap.band` |
| Application envelope version | `1` |

Identity changes require an architecture decision record because they affect Keychain namespaces, sideloaded app upgrades, RPK routing, fingerprint trust, and protocol compatibility.

## 5. Repository Architecture

The project is a monorepo. One Swift package contains several focused targets so module boundaries remain explicit without creating independent package-resolution graphs.

```text
blueband-map/
├── apps/
│   ├── ios/
│   │   ├── App/
│   │   ├── Adapters/
│   │   │   ├── CoreBluetooth/
│   │   │   └── Keychain/
│   │   ├── Tests/
│   │   └── project.yml
│   └── band/
│       ├── src/
│       ├── test/
│       ├── scripts/
│       ├── package.json
│       └── package-lock.json
├── packages/
│   └── BlueBandKit/
│       ├── Package.swift
│       ├── Package.resolved
│       ├── Sources/
│       │   ├── BlueBandProtocol/
│       │   ├── BlueBandCrypto/
│       │   ├── BlueBandCryptoCommonCrypto/
│       │   └── BlueBandCore/
│       └── Tests/
├── tools/
│   └── protocol-lab/
├── tests/
│   └── fixtures/
├── docs/
│   ├── architecture/
│   ├── protocol/
│   ├── security/
│   ├── development/
│   ├── testing/
│   ├── release/
│   └── adr/
├── scripts/
├── .github/workflows/
├── compose.yaml
├── Makefile
├── LICENSE
└── THIRD_PARTY_NOTICES.md
```

### 5.1 Dependency direction

```text
BlueBandMap iOS application
  ├── CoreBluetooth adapter
  ├── Keychain adapter
  ├── BlueBandCryptoCommonCrypto
  └── BlueBandCore
        ├── BlueBandProtocol
        └── BlueBandCrypto
```

The band RPK does not link Swift code. It implements the same application-envelope contract and validates that contract with a fake `system.interconnect` runtime.

### 5.2 Module responsibilities

`BlueBandProtocol` owns byte-level protocol behavior: CRC-16/ARC, SPP v2 frames and reassembly, minimal defensive protobuf primitives, Xiaomi command envelopes, authentication commands, proof commands, and ThirdPartyApp type-20 structures. It has no UI, Bluetooth, storage, or cryptographic system-framework dependency.

`BlueBandCrypto` owns Xiaomi session derivation, proof verification, CTR and CCM composition, constant-time comparison, and an `AESBlockCipher` interface. It accepts domain bytes and returns explicit errors for invalid sizes or authentication failure.

`BlueBandCryptoCommonCrypto` implements `AESBlockCipher` with CommonCrypto for production iOS. It is compiled and tested only at the Apple boundary.

`BlueBandCore` owns the high-level session state machine, transport coordination, proof gating, ThirdPartyApp routing, RPK identity policy, application envelopes, acknowledgements, delivery timeouts, duplicate suppression, and bounded events. It depends on small interfaces such as `BLELink`, `AuthKeyStore`, `RememberedBandStore`, `TrustedRPKStore`, `Clock`, and `NonceGenerator`.

The CoreBluetooth adapter owns scanning, GATT discovery, notification subscription, BLE write fragmentation, delegate-to-async bridging, and cancellation. The Keychain adapter owns only secret and trusted-identity persistence.

The Vela RPK remains a one-page application. It creates `interconnect.instance()` once in `onReady`, registers lifecycle callbacks, uses `getReadyState`, sends small objects, validates incoming envelopes, and detaches callbacks in `onDestroy`.

The protocol lab is not a runtime dependency. It inspects sanitized frames, mirrors selected deterministic transforms, and rejects unsafe fixtures.

## 6. BLE, Xiaomi Transport, and Authentication

The implementation preserves these hardware-confirmed UUID directions:

```text
Service:     0000FE95-0000-1000-8000-00805F9B34FB
Band→phone:  0000005E-0000-1000-8000-00805F9B34FB  notify
Phone→band:  0000005F-0000-1000-8000-00805F9B34FB  write
```

Scanning is not filtered by advertised name or service UUID. Candidates are sorted by RSSI, bounded to 20 visible entries, and validated by FE95 discovery after selection. A remembered CoreBluetooth peripheral identifier is a convenience identifier, not a MAC address or proof of authenticity.

SPP v2 preserves magic `A5 A5`, the masked low-nibble packet type, one-byte sequence, little-endian payload length, little-endian CRC-16/ARC over payload only, the verified literal session-configuration payload, transport acknowledgements, BLE fragmentation, frame coalescing, resynchronization, and bounded buffering.

Authentication preserves the POC's phone/watch nonce exchange, protocol-specific HMAC input order, HKDF expansion with `miwear-auth`, constant-time watch proof, AES-128-CCM device descriptor with a four-byte tag, and post-authentication Xiaomi AES-128-CTR rule. One reconnect is allowed only after the initial HMAC mismatch. Other failures are not retried automatically.

The authenticated state is not exposed until device information and battery proof commands return valid data. The application-ready state is not exposed until the RPK completes the ThirdPartyApp status handshake.

## 7. Runtime State and Failure Semantics

The state machine is:

```text
idle
→ scanning
→ connecting
→ discoveringGatt
→ configuringSpp
→ authenticating
→ readingDeviceProof
→ waitingForRpk
→ applicationReady
→ disconnecting
→ idle
```

Failures are typed by boundary:

- `BluetoothError`
- `GattError`
- `TransportError`
- `AuthenticationError`
- `ProofError`
- `InterconnectError`
- `ApplicationProtocolError`

Every terminal failure completes pending continuations, ends event streams, cancels receive and timeout tasks, clears session keys and active identity, closes the owned BLE link, and prevents stale UI sends. Errors contain safe stage and reason information but never secret or raw authentication material.

Explicit disconnect best-effort sends ThirdPartyApp disconnected status, clears active identity and deduplication state, finishes events, cancels tasks, drops keys, closes BLE, and returns to idle. Mi Fitness must not concurrently own the proprietary Xiaomi session; the UI and documentation make this ownership rule visible.

## 8. RPK Identity Policy

The package name is pinned to `dev.lordierclaw.bluebandmap.band`.

The RPK fingerprint policy is trust on first use within an already authenticated Xiaomi band session:

1. Reject every unexpected package without replying connected.
2. On the first successful expected-package handshake, store the full fingerprint.
3. On later handshakes, require an exact constant-time fingerprint match.
4. Expose a deliberate reset-trusted-RPK action.
5. Resetting trusted RPK identity does not delete the AuthKey or remembered band.

The fingerprint is routing and continuity evidence, not an independently validated certificate chain. This limitation is stated in the threat model. Private RPK signing keys are never committed.

## 9. Application Envelope Version 1

The ThirdPartyApp content is a UTF-8 JSON envelope. A message is:

```json
{
  "v": 1,
  "id": "i-a1b2c3d4e5f6",
  "src": "ios",
  "type": "message",
  "topic": "system.echo",
  "body": {
    "text": "PING"
  }
}
```

Its acknowledgement is:

```json
{
  "v": 1,
  "id": "i-a1b2c3d4e5f6",
  "src": "band",
  "type": "ack"
}
```

Rules are:

- Encoded envelope size is at most 512 bytes.
- `v` is exactly integer `1`.
- `id` is 1 through 32 printable ASCII bytes and is unique within a session with practical probability.
- `src` is `ios` or `band`; a receiver accepts only the opposite source.
- `type` is initially `message` or `ack`.
- `topic` is required for messages, omitted for acknowledgements, uses a lowercase dotted namespace, and is at most 64 ASCII bytes.
- `body` is a small JSON object required for messages and omitted for acknowledgements.
- An acknowledgement reuses the original message ID and updates delivery state instead of creating a visible row.
- Every valid message is acknowledged, including a duplicate.
- Duplicate content is emitted only once.
- The newest 64 received IDs are retained for one session.
- Delivery becomes failed after five seconds without application acknowledgement.
- Automatic application retry is disabled in version 1.

`system.echo` is the sole sample topic. Future product topics register handlers above `BlueBandCore`; they do not modify SPP, Xiaomi authentication, ThirdPartyApp protobuf, or the envelope framing.

## 10. Cryptography Portability

Production iOS retains CommonCrypto for AES block encryption, preserving the hardware-tested implementation boundary. `BlueBandCrypto` composes Xiaomi CCM and CTR using the injected block-cipher interface.

HMAC, SHA-256, and HKDF use Apple's `swift-crypto` package. On Apple platforms it re-exports CryptoKit behavior; on Linux it provides the portable implementation. CryptoSwift is a test-target dependency only and supplies an independent AES block backend for Linux tests. It is not linked into the iOS application.

Both backends run the same NIST AES vectors, independent CCM vectors, NIST CTR vectors, RFC HMAC/HKDF vectors, and synthetic Xiaomi session vectors. CommonCrypto parity is a required macOS check. A crypto dependency update also requires the hardware acceptance matrix before release.

## 11. Public-Repository Security

### 11.1 Secret handling

- AuthKey is entered in the iOS UI, validated as exactly 32 hexadecimal characters, and stored as a generic-password Keychain item with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- AuthKey is never accepted through a committed file, command argument, CI secret, environment file, or analytics event.
- Nonces use `SecRandomCopyBytes` in production.
- Derived keys and active nonces remain in memory only for the session.
- Apple ID credentials remain only in the user's sideloading application.
- RPK private signing keys remain in ignored local storage.

### 11.2 Ignored material

The repository ignores at least:

```text
local/
captures/raw/
sign/
*.p12
*.mobileprovision
*.pem
*.key
.env
.env.*
```

Explicit non-secret example files may use an `.example` suffix.

### 11.3 Fixtures and logs

Committed fixtures are synthetic or explicitly redacted. Each fixture carries metadata declaring `synthetic` or `redacted-hardware`. The protocol lab rejects forbidden secret sequences and unredacted identifiers before a fixture can be accepted.

The app logs stage transitions, safe error codes, sizes, and correlation IDs where appropriate. It does not log AuthKey, keys, nonces, HMACs, authentication payloads, raw decrypted content, or complete device identifiers.

### 11.4 Supply chain

- Gitleaks scans pull requests and commit ranges.
- GitHub secret scanning is enabled for the public repository.
- `Package.resolved`, `package-lock.json`, container image versions, and GitHub action major revisions are committed.
- `THIRD_PARTY_NOTICES.md` records required license and attribution text.
- Dependabot monitors SwiftPM, npm, Docker, and GitHub Actions.
- Forced npm audit upgrades are prohibited for the pinned legacy Vela toolkit because they can invalidate reproducible Band 10 builds.

## 12. Linux-First Development Environment

The host requires Docker Engine, Docker Compose, Git, Make, and access to its working Bluetooth/USB devices. Native Swift and Node installations are optional and are not used by canonical commands.

Canonical commands are:

```text
make doctor
make bootstrap
make test
make test-swift
make test-rpk
make test-lab
make lint
make clean
```

`make doctor` performs read-only checks for Docker, Compose, Git, disk capacity, Bluetooth service/controller, USB visibility, repository cleanliness information, and optional GitHub CLI authentication. It explains unavailable Apple-only capabilities without treating the absence of Xcode as a Linux host failure.

`make bootstrap` pulls or builds pinned toolchain images and installs locked dependencies in Docker-managed volumes. It does not request or create secrets.

`compose.yaml` supplies a pinned official Swift image on Ubuntu LTS and a pinned Node 20 image. The Swift container builds and tests BlueBandKit. The Node container tests and builds the RPK and tests the protocol lab.

The current machine has Docker 29.7.2, Compose 5.4.0, an active KVM-capable Intel host, an active Bluetooth controller, and sufficient storage. Its native Node 16.14.2 cannot run `node --test`; Docker Node 20 already passes all 19 POC protocol-lab tests and all 5 POC RPK tests, including a real RPK archive build.

## 13. macOS Constraint and Virtualization Decision

Xcode, iOS Simulator, CoreBluetooth Apple-framework compilation, and device IPA production remain Apple-only. macOS virtualization on this non-Apple Ubuntu laptop is not a supported solution because Apple's license restricts macOS and its virtual instances to Apple-branded hardware, and unofficial KVM/Hackintosh installations introduce fragile OS, Xcode, signing, USB, and update behavior.

The supported zero-cost strategy is:

- Keep protocol, crypto composition, core state, RPK, and inspection tests local on Linux.
- Keep the iOS application shell and adapters thin.
- Use standard public GitHub-hosted macOS runners only for Apple-specific compilation and tests.
- Use an unsigned IPA artifact and free Apple ID sideloading.

`docs/development/macos-options.md` records the technical and licensing evaluation so the unsupported path is not repeatedly reopened without a material constraint change.

## 14. Continuous Integration and Artifacts

### 14.1 Linux checks

`.github/workflows/linux-checks.yml` runs for pull requests and pushes. It runs Swift package tests, protocol-lab tests, RPK contract tests and archive verification, formatting, linting, secret scanning, fixture safety checks, and license-notice checks.

### 14.2 Apple checks

`.github/workflows/ios-checks.yml` runs only when iOS, Swift package, XcodeGen, or relevant workflow files change. It generates the Xcode project, runs simulator tests, builds an unsigned generic arm64 iPhone application, and verifies identity, version, deployment target, Bluetooth permission, absence of background BLE, absence of an embedded profile, and absence of a signature.

Jobs use concurrency cancellation so superseded commits do not consume time. SwiftPM and npm caches use lockfile-based keys. Standard runners are used; larger runners are excluded because they are billed even for public repositories.

### 14.3 Release workflow

`.github/workflows/release-artifacts.yml` runs manually or for a version tag. It produces:

- Unsigned BlueBandMap IPA.
- Debug-installable BlueBandMap RPK.
- SHA-256 files.
- A release manifest containing iOS version, RPK version, envelope version, and commit SHA.
- Third-party notices and a software bill of materials.

Artifact retention is short enough to remain within free public-repository storage. No workflow receives Apple credentials, AuthKey, private RPK key, or raw device capture.

## 15. Testing Strategy

### 15.1 Deterministic Linux tests

- CRC-16/ARC standard vector.
- SPP header endianness, type masking, literal session configuration, sequence behavior, CRC failure, fragmentation, coalescing, resynchronization, and buffer bounds.
- Protobuf varints, fixed-width values, length bounds, truncation, field zero, unsupported wire types, unknown supported fields, and exact Xiaomi command nesting.
- Standard HMAC, HKDF, AES, CTR, and CCM vectors.
- Synthetic Xiaomi key derivation and watch proof.
- Proof command and response bytes.
- Exact ThirdPartyApp identity, status, and message bytes.
- State transitions, timeout cleanup, initial-HMAC-only retry, proof gating, and disconnect cleanup.
- Package rejection, TOFU enrollment, fingerprint mismatch, deliberate reset, and persistence separation.
- Envelope validation, size and field bounds, source validation, acknowledgements, duplicate behavior, delivery timeout, and history bounds.
- Fake BLE end-to-end authenticated session behavior.
- Fake Vela lifecycle, ready-state, send/receive, acknowledgement correlation, close, error, and teardown behavior.
- RPK manifest, package, permissions, icon, route, compiled page, version display, and archive verification.
- Fixture redaction and secret denylist behavior.

### 15.2 macOS checks

- CommonCrypto parity vectors.
- CoreBluetooth and Keychain adapter compilation and tests.
- Xcode project generation smoke tests.
- iOS simulator application tests.
- Unsigned arm64 device build and IPA security assertions.

### 15.3 Hardware acceptance

A release is hardware-confirmed only after:

1. Mi Fitness is force-closed and BlueBandMap connects to the selected Band 10.
2. Authentication completes and real battery, model, and firmware are displayed.
3. Opening the expected RPK completes the status handshake.
4. `system.echo` messages travel in both directions and correlate with application acknowledgements.
5. Duplicate messages do not duplicate visible content.
6. Closing either side prevents stale sends.
7. Explicit disconnect releases the session and Mi Fitness can resume.
8. A changed RPK fingerprint is rejected until the user explicitly resets trust.

## 16. Documentation and Governance

The repository contains focused documentation for architecture, module boundaries, runtime state, Xiaomi SPP, authentication, ThirdPartyApp, application envelope, threat model, secrets and logging, fixture redaction, Ubuntu setup, macOS options, troubleshooting, hardware acceptance, and unsigned iOS sideloading.

Architecture decisions are append-only records. Initial records cover the monorepo and module boundaries, Linux-first toolchains, rejection of unsupported macOS virtualization, foreground-only ownership, CommonCrypto production boundary, application envelope version 1, and TOFU RPK fingerprint policy.

iOS app, RPK, and application envelope versions are independent. Every artifact records all three versions and its commit SHA. The RPK displays its version on screen to expose installation cache mistakes.

A pull request may merge only when relevant Linux and Apple checks pass, secret scanning is clean, fixture bytes changed intentionally, protocol changes include exact vectors and an architecture record, and hardware-facing changes identify the hardware acceptance cases that must be repeated.

## 17. Implementation Sequence

Implementation proceeds in risk order:

1. Add repository metadata, Apache-2.0 license, ignores, notices, toolchain containers, Make targets, and CI skeleton.
2. Import the POC's verified protocol fixtures and tests before moving implementation code.
3. Extract and test `BlueBandProtocol` without changing verified bytes.
4. Extract `BlueBandCrypto`, introduce the AES provider boundary, and prove parity vectors.
5. Extract `BlueBandCore`, introduce injectable ports, and pass fake-link behavior tests.
6. Create the thin BlueBandMap iOS target and Apple adapters with deterministic XcodeGen configuration.
7. Adapt the one-page RPK to the new identity and envelope while preserving verified Vela lifecycle behavior.
8. Add security gates, full documentation, architecture records, and release workflows.
9. Produce unsigned IPA and RPK artifacts on GitHub Actions.
10. Run the complete iPhone and Xiaomi Smart Band 10 acceptance matrix.

Each implementation task starts with a failing or preserved characterization test, makes the smallest passing change, runs focused and aggregate verification, and commits a coherent unit of work.

## 18. External References

- [BlueBand handover baseline](https://github.com/LordierClaw/blueband-ios/blob/main/BASE_FROM_THIS_PROJECT.md)
- [Xiaomi Vela system.interconnect](https://iot.mi.com/vela/quickapp/en/features/network/interconnect.html)
- [Apple CoreBluetooth](https://developer.apple.com/documentation/corebluetooth)
- [Apple macOS software license](https://www.apple.com/legal/sla/docs/macOSTahoe.pdf)
- [Swift Linux installation](https://www.swift.org/install/linux/ubuntu/)
- [Apple Swift Crypto](https://github.com/apple/swift-crypto)
- [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- [GitHub-hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

