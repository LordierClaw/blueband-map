# BlueBand Map Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a professional, public, Linux-first foundation for a custom iPhone app and a custom Xiaomi Smart Band 10 Vela RPK to exchange acknowledged application messages through the hardware-confirmed BlueBand protocol stack.

**Architecture:** Preserve the POC's verified bytes and hardware-facing behavior while moving portable code into a multi-target `BlueBandKit` Swift package. Keep CoreBluetooth, Keychain, CommonCrypto, and SwiftUI in a thin iOS shell; run portable Swift, RPK, and protocol-lab checks in pinned Docker toolchains; use public GitHub macOS runners only for Apple-specific compilation and unsigned IPA artifacts.

**Tech Stack:** Swift 6 toolchain in Swift 5 language mode, SwiftPM, SwiftUI, CoreBluetooth, Security, CryptoKit/swift-crypto, CommonCrypto, XCTest, XcodeGen, Node.js 20, Xiaomi Vela `aiot-toolkit` 2.0.5, Docker Compose, Make, GitHub Actions, Gitleaks, Apache-2.0.

---

## Source Baseline and Execution Rules

The source baseline is `/home/hainn/blue/code/blueband-ios` at `bae2f51ce4dfb12cff81e72d9146812092cd861e`. Never edit that repository. Import code by adding files with `apply_patch`, then make narrowly scoped module and identity changes in `blueband-map`.

Canonical verification runs through Docker. Native Node 16 on the host is not a supported test path. Apple-only commands run in GitHub Actions because the host has no Xcode.

Every task follows this loop:

1. Add or preserve a failing/characterization test.
2. Run the smallest relevant test command and observe the expected failure.
3. Add the minimum implementation.
4. Run focused and aggregate tests.
5. Run `git diff --check`.
6. Commit the coherent change.

## Locked File Structure

```text
.github/
  dependabot.yml
  workflows/
    ios-checks.yml
    linux-checks.yml
    release-artifacts.yml
apps/
  band/
    package.json
    package-lock.json
    scripts/
    src/
    test/
  ios/
    Adapters/CoreBluetooth/
    Adapters/Keychain/
    App/
    Tests/
    project.yml
docs/
  adr/
  architecture/
  development/
  protocol/
  release/
  security/
  testing/
packages/
  BlueBandKit/
    Package.swift
    Sources/
      BlueBandCore/
      BlueBandCrypto/
      BlueBandCryptoCommonCrypto/
      BlueBandProtocol/
    Tests/
      BlueBandCoreTests/
      BlueBandCryptoTests/
      BlueBandProtocolTests/
scripts/
  doctor.sh
  verify-no-secrets.sh
tests/fixtures/
tools/protocol-lab/
.dockerignore
.editorconfig
.gitignore
AGENTS.md
CHANGELOG.md
CONTRIBUTING.md
LICENSE
Makefile
README.md
SECURITY.md
THIRD_PARTY_NOTICES.md
compose.yaml
```

### Task 1: Repository contract, license, and Linux toolchains

**Files:**
- Create: `LICENSE`
- Create: `README.md`
- Create: `CONTRIBUTING.md`
- Create: `SECURITY.md`
- Create: `CHANGELOG.md`
- Create: `THIRD_PARTY_NOTICES.md`
- Create: `AGENTS.md`
- Create: `.editorconfig`
- Create: `.gitignore`
- Create: `.dockerignore`
- Create: `compose.yaml`
- Create: `Makefile`
- Create: `scripts/doctor.sh`
- Test: canonical `make doctor` and `make help` output

- [ ] **Step 1: Add repository policy files**

Use the canonical Apache-2.0 text in `LICENSE`. `README.md` must state the Band 10-only scope, unofficial Xiaomi protocol status, Linux-first workflow, public-repository secret policy, and links to the design and handover. `SECURITY.md` must direct vulnerability reports away from public issues and explicitly prohibit posting AuthKeys or raw captures. `AGENTS.md` must require `make test`, forbid editing the sibling POC, forbid committing secrets, and require an ADR plus exact vectors for wire changes.

- [ ] **Step 2: Add secret-safe ignore rules**

Use this minimum `.gitignore` contract:

```gitignore
.build/
.swiftpm/
DerivedData/
build/
dist/
node_modules/
*.xcodeproj/
*.xcworkspace/
local/
captures/raw/
sign/
*.p12
*.mobileprovision
*.pem
*.key
.env
.env.*
!.env.example
.DS_Store
```

- [ ] **Step 3: Add pinned development services**

Create `compose.yaml` with services named `swift`, `node-rpk`, and `node-lab`. Mount the repository at `/workspace`, use `/workspace` as the Swift working directory, and use the relevant app/tool directory for Node. Pin Node to the Node 20 Bookworm line and Swift to an official Ubuntu-LTS image compatible with the chosen `swift-tools-version`. Use named volumes for SwiftPM and npm caches; never mount `local/` into CI services.

- [ ] **Step 4: Add stable Make targets**

`Makefile` must expose `help`, `doctor`, `bootstrap`, `test`, `test-swift`, `test-rpk`, `test-lab`, `lint`, and `clean`. `test` invokes the three focused test targets. `clean` removes only explicit generated paths inside this repository and never uses a broad recursive target.

- [ ] **Step 5: Add a read-only host doctor**

`scripts/doctor.sh` must run with `set -eu`, never use sudo, and report PASS/WARN/FAIL for Git, Docker, Compose, Make, free disk, Bluetooth service, Bluetooth controller, `/dev/kvm`, USB visibility, `gh` availability/authentication, and Xcode absence. Xcode absence is informational on Linux. Exit nonzero only when a canonical local dependency is missing.

- [ ] **Step 6: Verify the workspace contract**

Run:

```bash
make help
make doctor
docker compose config --quiet
git diff --check
```

Expected: help lists every canonical target; doctor passes Docker/Compose/Git/Make and reports Apple-only tools as unavailable without failing; Compose configuration is valid.

- [ ] **Step 7: Commit**

```bash
git add LICENSE README.md CONTRIBUTING.md SECURITY.md CHANGELOG.md THIRD_PARTY_NOTICES.md AGENTS.md .editorconfig .gitignore .dockerignore compose.yaml Makefile scripts/doctor.sh
git commit -m "chore: establish Linux-first repository foundation"
```

### Task 2: Preserve the protocol laboratory and fixture safety

**Files:**
- Create: `tools/protocol-lab/package.json`
- Create: `tools/protocol-lab/package-lock.json`
- Create: `tools/protocol-lab/CAPTURE.md`
- Create: `tools/protocol-lab/src/*.mjs`
- Create: `tools/protocol-lab/test/*.test.mjs`
- Create: `tools/protocol-lab/fixtures/README.md`
- Create: `scripts/verify-no-secrets.sh`
- Modify: `Makefile`
- Modify: `THIRD_PARTY_NOTICES.md`

- [ ] **Step 1: Import the POC protocol-lab characterization tests first**

Add exact copies of the seven test files from `/home/hainn/blue/code/blueband-ios/protocol-lab/test` and the test-only fixture README. Preserve all 19 assertions before importing implementation.

- [ ] **Step 2: Confirm missing implementation fails**

Run:

```bash
docker run --rm -v "$PWD/tools/protocol-lab:/work:ro" -w /work node:20-bookworm npm test
```

Expected: FAIL because the imported test modules under `src/` do not exist.

- [ ] **Step 3: Import the POC protocol-lab implementation**

Add exact copies of:

```text
decrypt-ctr.mjs
inspect.mjs
protobuf-wire.mjs
redact.mjs
session-crypto.mjs
spp-v2.mjs
```

Preserve the POC package scripts and lockfile. Update only package name to `blueband-map-protocol-lab` and repository-relative documentation links.

- [ ] **Step 4: Add a repository secret gate**

`scripts/verify-no-secrets.sh` must reject committed `.env`, private-key, provisioning-profile, raw-capture paths, and obvious 32-hex assignments named `authKey`, `auth_key`, or `AUTH_KEY`. It must scan tracked files only and print filenames without printing matched secret content.

- [ ] **Step 5: Verify all lab contracts**

Run:

```bash
make test-lab
scripts/verify-no-secrets.sh
```

Expected: 19 Node tests pass and the tracked-file secret gate exits zero.

- [ ] **Step 6: Commit**

```bash
git add tools/protocol-lab scripts/verify-no-secrets.sh Makefile THIRD_PARTY_NOTICES.md
git commit -m "test: preserve BlueBand protocol laboratory"
```

### Task 3: Create BlueBandKit and extract byte-level protocol code

**Files:**
- Create: `packages/BlueBandKit/Package.swift`
- Create: `packages/BlueBandKit/Sources/BlueBandProtocol/*.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandProtocolTests/*.swift`
- Modify: `Makefile`

- [ ] **Step 1: Define the Swift package and targets**

Create products `BlueBandProtocol`, `BlueBandCrypto`, `BlueBandCryptoCommonCrypto`, and `BlueBandCore`. Set the package to Swift 5 language mode under a Swift 6-capable tools version. Add `swift-crypto` as the only runtime package dependency. Add CryptoSwift only to `BlueBandCryptoTests`; no application target may depend on it.

- [ ] **Step 2: Import protocol tests before sources**

Map these POC tests into `BlueBandProtocolTests`:

```text
CRC16ARCTests.swift
SPPFrameTests.swift
SPPReassemblerTests.swift
ProtoWireTests.swift
BandCommandsTests.swift
ThirdPartyAppCodecTests.swift
TestHex.swift
```

Add `@testable import BlueBandProtocol` and remove the implicit app-module dependency. Preserve literal bytes and assertions unchanged except for product identity where the spec explicitly requires a new value.

- [ ] **Step 3: Observe the empty-target failure**

Run:

```bash
make test-swift
```

Expected: FAIL with missing symbols such as `CRC16ARC`, `SPPFrame`, or `ProtoWire`.

- [ ] **Step 4: Import focused protocol sources**

Map these source files into `BlueBandProtocol`:

```text
CRC16ARC.swift
SPPFrame.swift
SPPReassembler.swift
ProtoWire.swift
BandCommands.swift
ThirdPartyAppCodec.swift
AuthKey.swift
```

Make only the access-control changes required for use across package targets. Preserve algorithms, literal session bytes, protobuf field numbers, status values, UUID-independent behavior, and decoding bounds.

- [ ] **Step 5: Add the new identity constant test**

Add a test asserting:

```swift
XCTAssertEqual(BlueBandIdentity.rpkPackage, "dev.lordierclaw.bluebandmap.band")
```

Add `BlueBandIdentity` to the protocol target as a namespace with immutable package and envelope-version constants.

- [ ] **Step 6: Verify byte parity**

Run:

```bash
make test-swift
make test-lab
git diff --check
```

Expected: all imported Swift protocol tests and all 19 Node lab tests pass.

- [ ] **Step 7: Commit**

```bash
git add packages/BlueBandKit Makefile
git commit -m "feat: extract portable Xiaomi protocol package"
```

### Task 4: Extract crypto composition behind an AES provider

**Files:**
- Create: `packages/BlueBandKit/Sources/BlueBandCrypto/*.swift`
- Create: `packages/BlueBandKit/Sources/BlueBandCryptoCommonCrypto/*.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandCryptoTests/*.swift`
- Modify: `packages/BlueBandKit/Package.swift`
- Modify: `THIRD_PARTY_NOTICES.md`

- [ ] **Step 1: Add portable crypto characterization tests**

Import POC `SessionCryptoTests.swift`, then split its AES construction from the tested Xiaomi composition. Preserve RFC 4231 HMAC, RFC 5869 HKDF, synthetic Xiaomi derivation, watch HMAC, NIST CTR, independent CCM, transform roundtrip, and dimension-rejection assertions.

Add an `AESBlockCipher` test double backed by CryptoSwift in the test target. The runtime `BlueBandCrypto` target must not import CryptoSwift.

- [ ] **Step 2: Confirm missing crypto target behavior fails**

Run:

```bash
make test-swift
```

Expected: FAIL because `SessionCrypto`, `SessionKeys`, or `AESBlockCipher` is unavailable.

- [ ] **Step 3: Extract portable crypto composition**

Move HMAC, HKDF, key splitting, proof calculation, constant-time comparison, CTR counter composition, and CCM formatting into `BlueBandCrypto`. Use conditional imports:

```swift
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
```

Define:

```swift
public protocol AESBlockCipher: Sendable {
    func encrypt(block: Data, key: Data) throws -> Data
}
```

Inject the provider into operations that require AES. Preserve the POC's four-byte CCM tag and Xiaomi key-as-IV CTR behavior.

- [ ] **Step 4: Add the production CommonCrypto provider**

Create `CommonCryptoAESBlockCipher` in `BlueBandCryptoCommonCrypto`. Guard the system import with `#if canImport(CommonCrypto)` and provide a typed unsupported-platform error on non-Apple systems. The provider validates 16-byte block and key lengths and uses AES-128 ECB for the single-block primitive exactly as the POC did.

- [ ] **Step 5: Verify portable vectors**

Run:

```bash
make test-swift
```

Expected: protocol and portable crypto tests pass on Linux. CommonCrypto parity remains a required `ios-checks.yml` test in Task 8.

- [ ] **Step 6: Record attribution and commit**

Add swift-crypto and CryptoSwift license/role statements to `THIRD_PARTY_NOTICES.md`.

```bash
git add packages/BlueBandKit THIRD_PARTY_NOTICES.md
git commit -m "feat: make Xiaomi session crypto Linux-testable"
```

### Task 5: Build BlueBandCore transport, identity, and envelope behavior

**Files:**
- Create: `packages/BlueBandKit/Sources/BlueBandCore/BandLink.swift`
- Create: `packages/BlueBandKit/Sources/BlueBandCore/BandTransport.swift`
- Create: `packages/BlueBandKit/Sources/BlueBandCore/BandAuthenticator.swift`
- Create: `packages/BlueBandKit/Sources/BlueBandCore/BandSession.swift`
- Create: `packages/BlueBandKit/Sources/BlueBandCore/ApplicationEnvelope.swift`
- Create: `packages/BlueBandKit/Sources/BlueBandCore/InterconnectSession.swift`
- Create: `packages/BlueBandKit/Sources/BlueBandCore/TrustedRPKStore.swift`
- Create: `packages/BlueBandKit/Sources/BlueBandCore/SessionState.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandCoreTests/*.swift`

- [ ] **Step 1: Import transport and session characterization tests**

Adapt POC `BandTransportTests`, `BandAuthenticatorTests`, and `BandSessionTests` to package imports and injected `AESBlockCipher`, `NonceGenerator`, and `Clock`. Preserve session configuration, ACK, fragmentation, retry-only-on-first-HMAC-mismatch, proof gating, encrypted routing, and cleanup assertions.

- [ ] **Step 2: Add envelope version 1 tests**

Replace chat-specific tests with `ApplicationEnvelopeTests` covering this exact model:

```swift
public struct ApplicationEnvelope: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case ios, band }
    public enum MessageType: String, Codable, Sendable { case message, ack }

    public let v: Int
    public let id: String
    public let src: Source
    public let type: MessageType
    public let topic: String?
    public let body: [String: JSONValue]?
}
```

Tests cover 512-byte encoding, printable 1-32-byte IDs, lowercase dotted 1-64-byte topics, opposite source, message/body requirements, ack omissions, and unknown version/type rejection.

- [ ] **Step 3: Add fingerprint continuity tests**

Create an in-memory `TrustedRPKStore` fake and tests for first-use enrollment, exact subsequent match, mismatch rejection without connected reply, explicit reset, and independence from AuthKey/remembered-band state.

- [ ] **Step 4: Add delivery semantics tests**

Test that every valid message is acknowledged, duplicate content emits once but ACKs each time, 64 received IDs are retained, ACK updates the original ID, send before handshake fails, and a fake clock marks delivery failed after five seconds without automatic retry.

- [ ] **Step 5: Observe focused failures**

Run:

```bash
make test-swift
```

Expected: FAIL on missing core types and new envelope/identity behavior.

- [ ] **Step 6: Extract transport and authentication implementation**

Move POC `BandTransport`, `BandAuthenticator`, and `BandSession` into `BlueBandCore`. Replace concrete Apple objects with package interfaces. Preserve all byte-level behavior and typed cleanup. Model visible states with the approved state names from `idle` through `applicationReady` and `disconnecting`.

- [ ] **Step 7: Implement the general envelope and interconnect session**

Replace `ChatMessage` and chat-only events with topic-based application events. Keep `system.echo` as the only registered sample topic. Implement bounded ID history, ACK correlation, five-second delivery failure through injected `Clock`, and no automatic retry.

- [ ] **Step 8: Implement TOFU fingerprint policy**

On an expected-package status request, enroll an absent fingerprint or compare the stored fingerprint in constant time. Reply connected only after policy success. Expose reset through the store interface, not through protocol internals.

- [ ] **Step 9: Verify aggregate core behavior**

Run:

```bash
make test-swift
make test-lab
git diff --check
```

Expected: all protocol, crypto, transport, session, identity, and envelope tests pass.

- [ ] **Step 10: Commit**

```bash
git add packages/BlueBandKit
git commit -m "feat: add reusable authenticated Band session core"
```

### Task 6: Create the thin iOS application and adapters

**Files:**
- Create: `apps/ios/project.yml`
- Create: `apps/ios/App/BlueBandMapApp.swift`
- Create: `apps/ios/App/AppModel.swift`
- Create: `apps/ios/App/ContentView.swift`
- Create: `apps/ios/Adapters/CoreBluetooth/BandCentral.swift`
- Create: `apps/ios/Adapters/CoreBluetooth/BandUUID.swift`
- Create: `apps/ios/Adapters/Keychain/KeychainAuthKeyStore.swift`
- Create: `apps/ios/Adapters/Keychain/KeychainTrustedRPKStore.swift`
- Create: `apps/ios/Adapters/Keychain/UserDefaultsRememberedBandStore.swift`
- Create: `apps/ios/Tests/*.swift`

- [ ] **Step 1: Add deterministic XcodeGen configuration**

Use product `BlueBandMap`, bundle `dev.lordierclaw.bluebandmap`, tests `dev.lordierclaw.bluebandmap.tests`, iOS 17 minimum, portrait iPhone only, generated Info.plist, and a Bluetooth usage description. Do not add `UIBackgroundModes`. Reference local package `../../packages/BlueBandKit` and link the four required products.

- [ ] **Step 2: Import Apple adapter tests before implementation**

Adapt POC `BandUUIDTests`, `AuthKeyStoreTests`, `RememberedBandStoreTests`, `ProjectSmokeTests`, and the AppModel tests that cover secret-safe errors, scan bounds, proof projection, remembered band, explicit disconnect, handshake gating, message projection, and reset state.

Add trusted-RPK Keychain tests using an injectable Security client, mirroring the existing AuthKey store test pattern.

- [ ] **Step 3: Add the application composition root**

`BlueBandMapApp.swift` defines immutable identity constants, constructs real CoreBluetooth, CommonCrypto, Keychain, and defaults adapters, injects them into `BlueBandCore`, and gives one `AppModel` to SwiftUI. No adapter may be constructed inside package code.

- [ ] **Step 4: Adapt CoreBluetooth without protocol changes**

Move POC `BandCentral` and `BandUUID` into the iOS adapter. Keep nil service scan filtering, no name gate, FE95 validation, 5E notification, 5F write, dedicated delegate queue, owned `Data`, maximum-write fragmentation, write-with-response preference, backpressure for without-response, and continuation cleanup.

- [ ] **Step 5: Implement persistence adapters**

AuthKey uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Trusted RPK fingerprint uses a separate Keychain service/account. Remembered peripheral UUID and display name use non-secret preferences. Each reset method affects only its own namespace.

- [ ] **Step 6: Adapt AppModel and UI**

Rename POC identity and chat copy to BlueBandMap and `system.echo`. The UI exposes save/delete AuthKey, scan/stop/clear, remembered device, connect/disconnect, proof snapshot, RPK check, echo send, delivery state, clear events, forget band, and reset trusted RPK. It shows safe boundary errors and version information.

- [ ] **Step 7: Add project metadata assertions**

Tests or CI script must assert bundle IDs, iOS 17 minimum, Bluetooth permission, absence of background modes, and the local package dependency.

- [ ] **Step 8: Commit**

Apple compilation is deferred to Task 8 CI, but Linux package tests must remain green.

```bash
make test
git diff --check
git add apps/ios
git commit -m "feat: add thin BlueBandMap iOS companion"
```

### Task 7: Adapt the one-page Band 10 RPK

**Files:**
- Create: `apps/band/package.json`
- Create: `apps/band/package-lock.json`
- Create: `apps/band/scripts/*.mjs`
- Create: `apps/band/src/app.ux`
- Create: `apps/band/src/config-watch.json`
- Create: `apps/band/src/manifest.json`
- Create: `apps/band/test/*.test.mjs`
- Modify: `Makefile`

- [ ] **Step 1: Import POC RPK contract tests and build scripts**

Preserve icon, manifest, one-page lifecycle, real archive, and ACK-correlation tests. Change expected package to `dev.lordierclaw.bluebandmap.band`, product label to `BLUEBAND MAP`, and version to the new initial RPK version.

- [ ] **Step 2: Observe identity and envelope failures**

Run:

```bash
make test-rpk
```

Expected: FAIL because the new manifest/page is absent.

- [ ] **Step 3: Adapt the verified one-page implementation**

Import POC `app.ux`, `manifest.json`, and watch config. Preserve singleton creation in `onReady`, lifecycle callbacks, `result.status`, self-closing input buttons, bounded rows, explicit ready check, visible version, and callback teardown. Remove chat-only fixed messages and implement `system.echo` version-1 message/ack envelopes with the approved validation bounds.

- [ ] **Step 4: Keep the reproducible toolkit**

Pin `aiot-toolkit` to `2.0.5`, `@aiot-toolkit/jsc` to `1.0.3`, and Node engine `>=18`. Do not apply forced audit upgrades. Build and verify the archive inside Node 20.

- [ ] **Step 5: Verify RPK and all Linux checks**

Run:

```bash
make test-rpk
make test
git diff --check
```

Expected: RPK contract and real build tests pass; all Swift and protocol-lab tests remain green.

- [ ] **Step 6: Commit**

```bash
git add apps/band Makefile
git commit -m "feat: add BlueBandMap Band 10 RPK"
```

### Task 8: Add CI, Apple verification, and unsigned artifacts

**Files:**
- Create: `.github/workflows/linux-checks.yml`
- Create: `.github/workflows/ios-checks.yml`
- Create: `.github/workflows/release-artifacts.yml`
- Create: `.github/dependabot.yml`
- Create: `scripts/verify-ios-artifact.sh`
- Create: `scripts/release-manifest.sh`

- [ ] **Step 1: Add Linux required checks**

Run `make test`, `make lint`, `scripts/verify-no-secrets.sh`, and Gitleaks on pull requests and pushes. Cache by lockfile hashes. Use concurrency cancellation keyed by workflow and ref. Upload no routine build artifacts.

- [ ] **Step 2: Add path-filtered Apple checks**

Use a standard public macOS runner. Install a pinned XcodeGen release with a checked SHA-256, generate `apps/ios/BlueBandMap.xcodeproj`, run package/CommonCrypto tests and iOS simulator tests, then build a generic arm64 device app with signing disabled.

- [ ] **Step 3: Verify the unsigned application**

`scripts/verify-ios-artifact.sh` must check:

```text
CFBundleIdentifier = dev.lordierclaw.bluebandmap
MinimumOSVersion = 17.0
UIDeviceFamily contains iPhone only
NSBluetoothAlwaysUsageDescription exists
UIBackgroundModes is absent
_CodeSignature is absent
embedded.mobileprovision is absent
main executable contains arm64
```

- [ ] **Step 4: Add release artifacts**

On manual dispatch or a `v*` tag, package `Payload/BlueBandMap.app` as an unsigned IPA, build the debug RPK, generate SHA-256 files and a manifest containing iOS version, RPK version, envelope version `1`, and commit SHA, and upload notices plus SBOM. Set short artifact retention and never accept signing or AuthKey inputs.

- [ ] **Step 5: Add dependency monitoring**

Configure weekly Dependabot entries for SwiftPM, npm in both Node workspaces, Docker, and GitHub Actions. Group patch/minor development updates but keep crypto and Vela toolkit updates ungrouped for deliberate review.

- [ ] **Step 6: Validate workflow syntax locally**

Run:

```bash
docker compose config --quiet
make test
scripts/verify-no-secrets.sh
git diff --check
```

Expected: all local checks pass. Apple workflow execution is verified after the repository is pushed to GitHub.

- [ ] **Step 7: Commit**

```bash
git add .github scripts/verify-ios-artifact.sh scripts/release-manifest.sh
git commit -m "ci: add zero-cost Linux and iOS verification"
```

### Task 9: Complete architecture, security, release, and acceptance documentation

**Files:**
- Create: `docs/architecture/overview.md`
- Create: `docs/architecture/module-boundaries.md`
- Create: `docs/architecture/runtime-state-machine.md`
- Create: `docs/protocol/xiaomi-spp-v2.md`
- Create: `docs/protocol/authentication.md`
- Create: `docs/protocol/third-party-app.md`
- Create: `docs/protocol/application-envelope-v1.md`
- Create: `docs/security/threat-model.md`
- Create: `docs/security/secrets-and-logging.md`
- Create: `docs/security/fixture-redaction.md`
- Create: `docs/development/ubuntu-setup.md`
- Create: `docs/development/macos-options.md`
- Create: `docs/development/troubleshooting.md`
- Create: `docs/testing/hardware-acceptance.md`
- Create: `docs/release/unsigned-ios-sideload.md`
- Create: `docs/adr/0001-*.md` through the approved initial ADR set
- Modify: `README.md`

- [ ] **Step 1: Document exact module and protocol contracts**

Translate the approved design into focused documents without duplicating implementation details. Protocol documents preserve exact UUIDs, SPP layout, session bytes, crypto derivation, protobuf fields, identity policy, and envelope limits.

- [ ] **Step 2: Document the threat model and safe evidence workflow**

Cover malicious RPK identity, first-use trust limitation, leaked AuthKey, unsafe logs/captures, stale session ownership, dependency compromise, public CI logs, and recovery actions. State explicitly that TOFU does not validate a certificate chain.

- [ ] **Step 3: Document Ubuntu and macOS decisions**

Ubuntu setup uses only the canonical Make/Docker path. The macOS options document cites Apple's Apple-branded-hardware restriction, explains KVM/Hackintosh fragility, excludes paid Mac services under the zero-cost requirement, and records public standard GitHub macOS runners as the supported Apple boundary.

- [ ] **Step 4: Document sideload and hardware acceptance**

Describe unsigned artifact hash verification, Sideloadly/free Apple ID signing, Developer Mode, trust, seven-day expiry, clean RPK uninstall/install, Mi Fitness ownership, proof reads, bidirectional echo, ACKs, disconnect, fingerprint mismatch, reset, and normal Mi Fitness resumption.

- [ ] **Step 5: Add initial ADRs**

Record monorepo/module boundaries, Linux-first toolchains, unsupported non-Apple macOS virtualization, foreground-only ownership, CommonCrypto production provider, envelope version 1, and TOFU fingerprint continuity.

- [ ] **Step 6: Verify documentation and links**

Run:

```bash
rg -n 'TB[D]|TO[D]O|FIXM[E]' README.md docs --glob '*.md'
make test
git diff --check
```

Expected: the incomplete-marker scan returns no matches, tests pass, and Markdown has no whitespace errors.

- [ ] **Step 7: Commit**

```bash
git add README.md docs
git commit -m "docs: complete BlueBandMap engineering handbook"
```

### Task 10: Final local and cloud-ready verification

**Files:**
- Modify only files required to fix observed verification failures
- Record hardware execution later in `docs/testing/hardware-acceptance.md` without committing device secrets

- [ ] **Step 1: Start from a clean dependency state**

Run the canonical clean and bootstrap targets, then confirm no tracked files change solely from dependency installation or generated project output.

```bash
make clean
make bootstrap
git status --short
```

Expected: only intentional source changes are present before the final commit; generated dependencies and projects are ignored.

- [ ] **Step 2: Run all Linux verification**

```bash
make test
make lint
scripts/verify-no-secrets.sh
docker compose config --quiet
git diff --check
```

Expected: every command exits zero; protocol lab reports 19 or more passing tests; RPK reports its expanded contract suite and a verified archive; Swift reports all protocol, crypto, and core tests passing.

- [ ] **Step 3: Inspect repository boundaries**

```bash
git ls-files | rg '(\.env$|\.p12$|\.mobileprovision$|\.pem$|\.key$|captures/raw|node_modules|DerivedData|\.xcodeproj)'
```

Expected: no output.

- [ ] **Step 4: Push and verify public GitHub workflows**

After an origin exists and the user authorizes pushing, push the branch and verify `linux-checks.yml` and `ios-checks.yml`. Download the unsigned IPA once, compare SHA-256, and inspect it with `scripts/verify-ios-artifact.sh` or the documented equivalent.

- [ ] **Step 5: Run manual release workflow**

Verify that it produces unsigned IPA, debug RPK, hashes, release manifest, notices, and SBOM without requesting any credential.

- [ ] **Step 6: Run device acceptance**

Use the exact hardware matrix in the documentation. Do not mark hardware acceptance complete from CI output. Record only versions, pass/fail stages, safe error codes, and artifact hashes.

- [ ] **Step 7: Commit verification fixes**

```bash
git add -A
git commit -m "test: verify BlueBandMap foundation"
```

If no tracked fixes were needed, do not create an empty commit.

## Completion Criteria

The foundation is implementation-complete when:

- Canonical Docker/Make commands work on the current Ubuntu host.
- Portable Swift protocol, crypto composition, transport, session, identity, and envelope tests pass locally.
- Protocol lab and real RPK build tests pass locally.
- Repository secret and fixture gates pass.
- Public GitHub Linux and iOS checks pass.
- Release workflow produces verified unsigned IPA and RPK artifacts without secrets.
- Documentation covers architecture, protocol, security, Ubuntu development, macOS constraints, sideloading, and hardware acceptance.

Hardware support is claimed only after the separate iPhone and Xiaomi Smart Band 10 acceptance matrix passes.
