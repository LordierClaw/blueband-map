# H1 Hybrid Renderer Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver one H1 iOS/RPK build that fixes CI signal quality, proves bounded Vietmap provider access, lets the iPhone explicitly select raster or vector rendering, records comparable telemetry, and packages one hardware test handoff.

**Architecture:** Vietmap access, vector-tile parsing, projection, simplification, rasterization, and run persistence stay on the iPhone. `BlueBandMapCore` owns portable `NavigationScene`, renderer contracts, fixed-record vector encoding, style/TileJSON/MVT parsing, deterministic raster pixels, and metrics; thin Apple adapters encode indexed PNG and persist/export runs. The Band keeps the existing authenticated envelope and stop-and-wait asset transport, adds a prepare/ready/reject handshake, and renders either one native PNG or at most 40 fixed-record line primitives.

**Tech Stack:** Swift 5.10/6 portable package, SwiftUI, Foundation networking, CoreGraphics/ImageIO, Xiaomi Vela JS/RPK, Node 20 tests, Bash, Docker Compose/Make, GitHub Actions, Vietmap Static Map and documented vector style/TileJSON resources.

---

## Scope and execution rules

- Execute Tasks 1–14 continuously. Automated failures are fixed before moving on, but there is no owner approval gate between tasks.
- H1 includes internal checkpoints P0, P1, P2-R1, P2-R2, P2-V0, and P2-V1. It ends with one IPA, one RPK, and one combined test packet.
- H2 map width/pan/routing/view-mode work is excluded until the owner returns H1 hardware evidence.
- Before Task 2's live style smoke, the owner-provided TileMap key must exist at ignored path `local/vietmap-tilemap-key`, be non-empty, and have mode `600`. The key is never printed or committed.
- Use `/home/hainn/blue/code/blueband-ios` read-only. Do not change verified Xiaomi BLE/SPP/authentication bytes.
- Add a failing behavioral test before each implementation change. Run commands through `make`.
- Never commit provider keys, AuthKeys, UUIDs, live style/tile bodies, raw captures, generated Xcode projects, dependencies, signing material, or test-run exports.

## File structure

### Portable map core

- Create `packages/BlueBandKit/Sources/BlueBandMapCore/RenderProtocol.swift` — renderer enums, prepare/ready/reject/result bodies, validation, and stable codes.
- Create `packages/BlueBandKit/Sources/BlueBandMapCore/RenderAsset.swift` — bounded raster/vector payload identity and hash.
- Create `packages/BlueBandKit/Sources/BlueBandMapCore/RenderTransferPlan.swift` — existing 512-byte envelope-aware stop-and-wait chunks for generic render assets.
- Create `packages/BlueBandKit/Sources/BlueBandMapCore/NavigationScene.swift` — bounded scene domain and synthetic fixtures.
- Create `packages/BlueBandKit/Sources/BlueBandMapCore/VectorSceneCodec.swift` — exact little-endian `BBMV` v1 fixed records.
- Create `packages/BlueBandKit/Sources/BlueBandMapCore/VietmapStyleClient.swift` — documented style/TileJSON discovery without logging keys.
- Create `packages/BlueBandKit/Sources/BlueBandMapCore/MapboxVectorTile.swift` — bounded MVT protobuf/geometry decoder.
- Create `packages/BlueBandKit/Sources/BlueBandMapCore/VietmapSceneBuilder.swift` — Web Mercator projection, road filtering, clipping, and segment reduction.
- Create `packages/BlueBandKit/Sources/BlueBandMapCore/IndexedRaster.swift` — four-color pixel buffer and deterministic integer line drawing.
- Create `packages/BlueBandKit/Sources/BlueBandMapCore/RenderRun.swift` — events, metrics, percentile calculation, and sanitized export model.

### iOS app and adapters

- Create `apps/ios/Adapters/Rendering/IndexedPNGEncoder.swift` — indexed CoreGraphics image to PNG.
- Create `apps/ios/Adapters/Diagnostics/FileRenderRunStore.swift` — Application Support run directories and sanitized export.
- Create `apps/ios/App/H1RenderCoordinator.swift` — prepare/ready/transfer/result state machine and timing.
- Create `apps/ios/App/H1State.swift` — UI-facing test modes and states; replace `M1State.swift` after compatibility tests migrate.
- Create `apps/ios/App/H1TestView.swift` — explicit raster/vector test controls, metrics, and export.
- Modify `AppModel.swift`, `BlueBandMapApp.swift`, and `ContentView.swift` only for composition, key loading, event forwarding, and presentation.

### Band app

- Create `apps/band/src/common/render-protocol.js` — bounded prepare/body/result validation.
- Create `apps/band/src/common/vector-scene.js` — `BBMV` decode and segment-style conversion.
- Modify `apps/band/src/pages/index/index.ux` — integrate handshake, generic transfer, native raster, and bounded vector layers while preserving lifecycle cleanup.
- Create focused Node tests for both modules; retain existing M1 regression tests.

### Tooling and evidence

- Create `scripts/vietmap-smoke.sh` and `tests/scripts/vietmap-smoke.test.sh`.
- Create `tests/scripts/ci-workflows.test.sh`; split Linux CI by impact without adding third-party path-filter actions.
- Create `docs/adr/0009-h1-renderer-application-protocol.md` and `docs/protocol/h1-renderer-v1.md`.
- Create the H1 test packet and immutable handoff at the end.

## Task 1: Restore CI signal and cross-toolchain compatibility

**Files:**
- Create: `tests/scripts/ci-workflows.test.sh`
- Create: `.github/workflows/repo-checks.yml`
- Create: `.github/workflows/swift-checks.yml`
- Create: `.github/workflows/band-checks.yml`
- Create: `.github/workflows/protocol-lab-checks.yml`
- Create: `.gitleaksignore`
- Delete: `.github/workflows/linux-checks.yml`
- Modify: `.github/workflows/ios-checks.yml`
- Modify: `tests/scripts/verify-no-secrets.test.sh`
- Modify: `packages/BlueBandKit/Tests/BlueBandCoreTests/InterconnectSessionTests.swift:525`
- Modify: `Makefile`

- [ ] **Step 1: Add failing CI metadata checks**

```bash
# tests/scripts/ci-workflows.test.sh
set -euo pipefail
test ! -e .github/workflows/linux-checks.yml
grep -Fq "make lint" .github/workflows/repo-checks.yml
grep -Fq "packages/BlueBandKit/**" .github/workflows/swift-checks.yml
grep -Fq "apps/band/**" .github/workflows/band-checks.yml
grep -Fq "tools/protocol-lab/**" .github/workflows/protocol-lab-checks.yml
! grep -Eq 'docker compose|macos-' .github/workflows/repo-checks.yml
grep -Fq 'weak var weakSession = session' packages/BlueBandKit/Tests/BlueBandCoreTests/InterconnectSessionTests.swift
```

Add `test-ci-metadata` to `Makefile` and include it in `test`.

- [ ] **Step 2: Run the failing check**

Run: `make test-ci-metadata`

Expected: FAIL because the split workflows do not exist and `weak let` remains.

- [ ] **Step 3: Implement path-aware workflows and exact leak suppression**

Create one fast Ubuntu `repo-checks` workflow for `make test-ci-metadata && make lint`. Create three path-filtered workflows that run `make test-swift`, `make test-rpk`, or `make test-lab`. Keep `ios-checks.yml` path-filtered and change only `weak let weakSession` to `weak var weakSession`.

Copy the pinned Gitleaks download/hash verification from the old Linux workflow into `repo-checks.yml`, use checkout `fetch-depth: 0`, and run `gitleaks git --redact --no-banner .` after fast repository checks.

Use this exact historical fingerprint in `.gitleaksignore`:

```text
989b21a131083690ab49008a5aebe64c3f19f5a9:tests/scripts/verify-no-secrets.test.sh:generic-api-key:13
```

Construct the current shell fixture at runtime without tracking the 32-character value:

```bash
synthetic_key=$(printf 'x%.0s' {1..32})
printf 'AUTH_KEY=%s\n' "$synthetic_key" >"$fixture_root/unsafe.env"
```

- [ ] **Step 4: Verify the CI foundation**

Run: `make test-ci-metadata && make test-swift && make lint && git diff --check`

Expected: all commands exit 0; no live provider call occurs.

- [ ] **Step 5: Commit**

```bash
git add .github .gitleaksignore Makefile tests/scripts packages/BlueBandKit/Tests/BlueBandCoreTests/InterconnectSessionTests.swift
git commit -m "ci: route checks by affected subsystem"
```

## Task 2: Add bounded manual Vietmap smoke evidence

**Files:**
- Create: `scripts/vietmap-smoke.sh`
- Create: `tests/scripts/vietmap-smoke.test.sh`
- Modify: `Makefile`
- Modify: `docs/research/map-navigation-feasibility.md`

- [ ] **Step 1: Write a fake-curl behavioral test**

The test creates a temporary `curl` executable that consumes config from stdin, writes fixture headers/body, and increments a counter. Assert both modes make exactly one call, reject missing/loose-permission key files, validate PNG versus JSON MIME, write only under `local/provider-smoke`, and never print the key.

```bash
run_static=$(CURL_BIN="$fake_curl" scripts/vietmap-smoke.sh static "$fixture/service-key")
test "$(cat "$fixture/calls")" = 1
grep -Fq 'content_type=image/png' <<<"$run_static"
! grep -Fq "$secret" <<<"$run_static"
```

- [ ] **Step 2: Run the failing test**

Run: `bash tests/scripts/vietmap-smoke.test.sh`

Expected: FAIL because `scripts/vietmap-smoke.sh` does not exist.

- [ ] **Step 3: Implement the one-call script**

Support only:

```text
scripts/vietmap-smoke.sh static local/vietmap-service-key
scripts/vietmap-smoke.sh style  local/vietmap-tilemap-key
```

Require mode `600`, feed key-bearing curl options through `curl --config -`, disable redirects, cap time/body, and record `status`, normalized MIME, bytes, dimensions for PNG, and SHA-256. Static uses the documented multipart endpoint; style uses `https://maps.vietmap.vn/maps/styles/tm/style.json?apikey=...`. Do not print the effective URL or response body.

- [ ] **Step 4: Add Make targets and verify**

```make
test-vietmap-smoke:
	bash tests/scripts/vietmap-smoke.test.sh

vietmap-smoke-static:
	scripts/vietmap-smoke.sh static local/vietmap-service-key

vietmap-smoke-style:
	scripts/vietmap-smoke.sh style local/vietmap-tilemap-key
```

Run: `make test-vietmap-smoke && make lint`

Expected: tests pass with fake curl; no trial call occurs.

- [ ] **Step 5: Execute exactly one live style smoke**

Run:

```bash
test -s local/vietmap-tilemap-key
test "$(stat -c %a local/vietmap-tilemap-key)" = 600
make vietmap-smoke-style
```

Expected: one HTTP 200 `application/json` response is recorded under `local/provider-smoke`; output contains status, MIME, bytes, and SHA-256 but no key or effective URL. Stop without retry on any authorization, quota, MIME, or schema failure.

- [ ] **Step 6: Commit**

```bash
git add Makefile scripts/vietmap-smoke.sh tests/scripts/vietmap-smoke.test.sh docs/research/map-navigation-feasibility.md
git commit -m "feat: add bounded Vietmap smoke probe"
```

## Task 3: Freeze H1 application protocol and generic payload transfer

**Files:**
- Create: `docs/adr/0009-h1-renderer-application-protocol.md`
- Create: `docs/protocol/h1-renderer-v1.md`
- Create: `packages/BlueBandKit/Sources/BlueBandMapCore/RenderProtocol.swift`
- Create: `packages/BlueBandKit/Sources/BlueBandMapCore/RenderAsset.swift`
- Create: `packages/BlueBandKit/Sources/BlueBandMapCore/RenderTransferPlan.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/RenderProtocolTests.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/RenderTransferPlanTests.swift`

- [ ] **Step 1: Write exact failing vectors**

Test `render.prepare`, `render.ready`, `render.reject`, and `render.result` bodies with these enums:

```swift
public enum RenderKind: String, Codable, Sendable { case raster, vector }
public enum RenderRejectCode: String, Codable, Sendable {
    case unsupportedRenderer, unsupportedFormatVersion, busy, payloadTooLarge
    case tooManyPrimitives, invalidDimensions, insufficientStorage
}
```

Assert payloads are non-empty, at most 64 KiB, dimensions are exactly 212×360, vector primitives are 0...40, SHA-256 is 64 lowercase hex, IDs are bounded ASCII, and every generated envelope is at most 512 bytes.

- [ ] **Step 2: Run the failing vectors**

Run: `make test-swift SWIFT_TEST_ARGS='--filter RenderProtocolTests'`

Expected: FAIL because the types do not exist. Update `Makefile` so `SWIFT_TEST_ARGS` is appended to `swift test`.

- [ ] **Step 3: Implement minimal protocol types**

Use `RenderAsset(kind:formatVersion:width:height:data:)`, ID prefix `h1-`, MIME `image/png` or `application/vnd.blueband.map-vector-v1`, and SHA-256 from `swift-crypto`. `RenderTransferPlan` emits the existing `map.asset.begin/chunk/end` topics with `renderer`, `format`, and `primitives` added to begin.

- [ ] **Step 4: Document exact application fields and evidence boundary**

ADR 0009 states that Xiaomi bytes do not change, stop-and-wait remains, 64 KiB is the H1 ceiling, semantic ready/result may race transport ACK and must be buffered, and benchmark failures never auto-fallback.

- [ ] **Step 5: Verify and commit**

Run: `make test-swift SWIFT_TEST_ARGS='--filter Render' && git diff --check`

```bash
git add docs/adr/0009-h1-renderer-application-protocol.md docs/protocol/h1-renderer-v1.md packages/BlueBandKit Makefile
git commit -m "feat: define bounded H1 renderer protocol"
```

## Task 4: Implement NavigationScene and fixed-record vector codec

**Files:**
- Create: `packages/BlueBandKit/Sources/BlueBandMapCore/NavigationScene.swift`
- Create: `packages/BlueBandKit/Sources/BlueBandMapCore/VectorSceneCodec.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/NavigationSceneTests.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/VectorSceneCodecTests.swift`

- [ ] **Step 1: Write failing bounds and literal-byte tests**

Define the domain used by tests:

```swift
public struct ScenePoint: Equatable, Sendable { public let x: UInt16; public let y: UInt16 }
public enum SceneLineClass: UInt8, Sendable { case minor = 0, major = 1, route = 2 }
public struct SceneSegment: Equatable, Sendable {
    public let start: ScenePoint; public let end: ScenePoint; public let lineClass: SceneLineClass
}
public enum ManeuverKind: UInt8, Sendable { case straight, left, right, uTurn, arrive }
```

Assert synthetic scenes contain exactly 8, 20, and 40 total segments. Assert 41 segments and out-of-viewport points fail. Assert the first 22 vector bytes are the literal `BBMV` header/version/viewport/count/position/heading/maneuver/distance in little endian and each segment adds 9 bytes.

- [ ] **Step 2: Run the failing tests**

Run: `make test-swift SWIFT_TEST_ARGS='--filter VectorSceneCodecTests|NavigationSceneTests'`

Expected: FAIL because the scene and codec are absent.

- [ ] **Step 3: Implement validation, fixtures, encode, and decode**

Use magic `[0x42,0x42,0x4d,0x56]`, version `1`, viewport `212×360`, `UInt8` road/route counts, little-endian `UInt16` coordinates/heading, `UInt8` maneuver, little-endian `UInt32` distance, and fixed 9-byte segment records. Decode only after exact total-length and count checks.

- [ ] **Step 4: Verify and commit**

Run: `make test-swift SWIFT_TEST_ARGS='--filter VectorSceneCodecTests|NavigationSceneTests'`

```bash
git add packages/BlueBandKit/Sources/BlueBandMapCore packages/BlueBandKit/Tests/BlueBandMapCoreTests
git commit -m "feat: encode bounded navigation scenes"
```

## Task 5: Discover documented Vietmap vector sources safely

**Files:**
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/HTTPTransport.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/VietmapStaticMapClient.swift`
- Modify: `apps/ios/Adapters/Vietmap/URLSessionHTTPTransport.swift`
- Create: `packages/BlueBandKit/Sources/BlueBandMapCore/VietmapStyleClient.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/VietmapStyleClientTests.swift`
- Modify: `apps/ios/Tests/URLSessionHTTPTransportTests.swift`

- [ ] **Step 1: Write failing style/TileJSON discovery tests**

Add `maximumResponseBytes` to `MapHTTPRequest`. Test a style containing one vector source with either inline `tiles` or a `url`; resolve TileJSON once; accept only HTTPS `maps.vietmap.vn`; replace `{apikey}` without exposing it in errors; select line layers whose `source-layer` or style ID contains a bounded road token (`road`, `street`, `transportation`, `highway`, `bridge`, `tunnel`). Reject redirects, oversized JSON, missing tiles, non-vector sources, and foreign hosts.

- [ ] **Step 2: Run the failing tests**

Run: `make test-swift SWIFT_TEST_ARGS='--filter VietmapStyleClientTests'`

Expected: FAIL because request bounds and style client are absent.

- [ ] **Step 3: Implement request-specific response caps and discovery**

Use 64 KiB for Static Map, 2 MiB for style/TileJSON, and 512 KiB for one vector tile. Keep `URLSessionConfiguration.ephemeral`, no cookies/cache, and no redirect following. Return a `VectorTileTemplate(urlTemplate:sourceLayers:)` whose description/error never contains a key.

- [ ] **Step 4: Verify compatibility and commit**

Run: `make test-swift && make test-ios-metadata && git diff --check`

```bash
git add packages/BlueBandKit apps/ios/Adapters/Vietmap apps/ios/Tests
git commit -m "feat: discover Vietmap vector tile sources"
```

## Task 6: Decode bounded MVT roads and build real scenes

**Files:**
- Create: `packages/BlueBandKit/Sources/BlueBandMapCore/MapboxVectorTile.swift`
- Create: `packages/BlueBandKit/Sources/BlueBandMapCore/VietmapSceneBuilder.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/MapboxVectorTileTests.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/VietmapSceneBuilderTests.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/VectorTileFixture.swift`

- [ ] **Step 1: Write synthetic MVT and geometry failure tests**

Generate a tiny MVT fixture in test code using standard Tile/Layer/Feature fields. Cover packed tags, `MoveTo`, `LineTo`, ZigZag deltas, layer extent, road class properties, truncated varints, unsupported geometry, count overflow, and coordinates outside the tile extent.

- [ ] **Step 2: Run the failing decoder tests**

Run: `make test-swift SWIFT_TEST_ARGS='--filter MapboxVectorTileTests|VietmapSceneBuilderTests'`

Expected: FAIL because decoder/builder are absent.

- [ ] **Step 3: Implement only the MVT subset H1 needs**

Decode line features from selected source layers. Ignore points/polygons and unknown fields. Cap body at 512 KiB, layers at 32, features at 4,096, geometry commands at 16,384, and emitted segments at 40. Convert test center/zoom to Web Mercator tile coordinates, project into 212×360, clip, discard zero-length segments, classify major/minor, and retain route-class segments first when reducing count.

- [ ] **Step 4: Verify deterministic real-scene construction and commit**

Run: `make test-swift SWIFT_TEST_ARGS='--filter MapboxVectorTileTests|VietmapSceneBuilderTests'`

```bash
git add packages/BlueBandKit/Sources/BlueBandMapCore packages/BlueBandKit/Tests/BlueBandMapCoreTests
git commit -m "feat: build bounded scenes from vector tiles"
```

## Task 7: Produce deterministic four-color raster and indexed PNG

**Files:**
- Create: `packages/BlueBandKit/Sources/BlueBandMapCore/IndexedRaster.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/IndexedRasterTests.swift`
- Create: `apps/ios/Adapters/Rendering/IndexedPNGEncoder.swift`
- Create: `apps/ios/Tests/IndexedPNGEncoderTests.swift`

- [ ] **Step 1: Write failing pixel and PNG tests**

Use palette indices `0 background`, `1 minor`, `2 major`, `3 route/current position`. Assert Bresenham output for horizontal, vertical, and diagonal segments; route overwrites roads; all indices are 0...3; and the Apple adapter produces a 212×360 PNG accepted by `PNGInspector` and under 64 KiB for the deterministic scene.

- [ ] **Step 2: Run portable failing tests**

Run: `make test-swift SWIFT_TEST_ARGS='--filter IndexedRasterTests'`

Expected: FAIL because `IndexedRaster` is absent.

- [ ] **Step 3: Implement portable pixels and Apple encoding**

Use integer-only line drawing in `BlueBandMapCore`. On iOS create an indexed `CGColorSpace`, one-byte indices, a four-entry RGB table, `CGImage`, and `CGImageDestination` PNG. Do not add a third-party image library.

- [ ] **Step 4: Verify Linux and metadata**

Run: `make test-swift SWIFT_TEST_ARGS='--filter IndexedRasterTests' && make test-ios-metadata`

The PNG adapter test is expected to run in the macOS iOS workflow; Linux metadata verifies the source is included and contains no unsupported dependency.

- [ ] **Step 5: Commit**

```bash
git add packages/BlueBandKit apps/ios/Adapters/Rendering apps/ios/Tests
git commit -m "feat: rasterize navigation scenes to indexed PNG"
```

## Task 8: Add bounded telemetry and sanitized iPhone run storage

**Files:**
- Create: `packages/BlueBandKit/Sources/BlueBandMapCore/RenderRun.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/RenderRunTests.swift`
- Create: `apps/ios/Adapters/Diagnostics/FileRenderRunStore.swift`
- Create: `apps/ios/Tests/FileRenderRunStoreTests.swift`

- [ ] **Step 1: Write failing metrics/redaction tests**

Assert p50/p95/max from deterministic ACK durations, total/provider/prepare/transfer/validate/render durations, bytes/chunks/retries/primitives, stable terminal code, and provider-call count. Serialize one run and prove known AuthKey, Service key, TileMap key, peripheral UUID, and exact live coordinates are absent.

- [ ] **Step 2: Run the failing core tests**

Run: `make test-swift SWIFT_TEST_ARGS='--filter RenderRunTests'`

Expected: FAIL because run models are absent.

- [ ] **Step 3: Implement models and file adapter**

Store `run.json`, `events.jsonl`, `metrics.json`, `payload.sha256`, and `preview.png` under Application Support `test-runs/<timestamp>-<run>-<renderer>`. Default replay payload retention to false. Produce one sanitized `h1-run-<run>.json` share URL containing identity, events, metrics, and hash but no secrets or private identifiers.

- [ ] **Step 4: Verify and commit**

Run: `make test-swift SWIFT_TEST_ARGS='--filter RenderRunTests' && make test-ios-metadata`

```bash
git add packages/BlueBandKit apps/ios/Adapters/Diagnostics apps/ios/Tests
git commit -m "feat: record sanitized H1 render metrics"
```

## Task 9: Add Band prepare handshake without weakening M1 cleanup

**Files:**
- Create: `apps/band/src/common/render-protocol.js`
- Create: `apps/band/test/render-protocol.test.mjs`
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `apps/band/test/envelope-page.test.mjs`

- [ ] **Step 1: Write failing pure-module and page integration tests**

Test all seven reject codes, 212×360 dimensions, 64 KiB cap, vector 40-segment cap, one prepared run, stale run rejection, prepare while busy, disconnect cleanup, and semantic response envelope size. Prove no asset begin is admitted before matching prepare.

- [ ] **Step 2: Run the failing RPK tests**

Run: `make test-rpk`

Expected: FAIL because `render.prepare` is not recognized.

- [ ] **Step 3: Implement lightweight preparation**

Import the pure JS validator into the one-page RPK. Add `preparedRender` containing only run, scene, renderer, format, bytes, dimensions, primitives, hash, and prepare timestamp. Send one `render.ready` or `render.reject`; do not update progress UI per chunk. Lower `MAX_ASSET_BYTES` to `64 * 1024` while retaining all existing cleanup, deduplication, and one-transfer tests.

- [ ] **Step 4: Verify and commit**

Run: `make test-rpk && git diff --check`

```bash
git add apps/band/src/common/render-protocol.js apps/band/src/pages/index/index.ux apps/band/test
git commit -m "feat: prepare bounded Band renderers"
```

## Task 10: Complete Band raster and vector renderers

**Files:**
- Create: `apps/band/src/common/vector-scene.js`
- Create: `apps/band/test/vector-scene.test.mjs`
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `apps/band/test/envelope-page.test.mjs`

- [ ] **Step 1: Write failing `BBMV` and rendering lifecycle tests**

Use the exact Task 4 bytes. Reject magic/version/length/count/viewport/range errors. Test 8/20/40 segments, 41 rejection, `file.readArrayBuffer` failure, stale callback, disconnect during read, raster native completion, vector publication, renderer replacement cleanup, and one aggregate `render.result`.

- [ ] **Step 2: Run the failing RPK tests**

Run: `make test-rpk`

Expected: FAIL because vector decode/render state is absent.

- [ ] **Step 3: Implement two isolated render paths**

Raster retains native `<image>` publication. Vector reads the verified file once with `file.readArrayBuffer`, decodes at most 40 records, converts each segment once to a positioned/rotated native `div`, publishes `vectorSegments`, and releases the byte buffer. Keep only one renderer visible and resident. Send aggregate prepare/validate/render milliseconds; never append per-chunk logs.

- [ ] **Step 4: Verify archive and commit**

Run: `make test-rpk && git diff --check`

```bash
git add apps/band/src/common/vector-scene.js apps/band/src/pages/index/index.ux apps/band/test
git commit -m "feat: render raster or bounded vector scenes on Band"
```

## Task 11: Build the iPhone H1 coordinator state machine

**Files:**
- Create: `apps/ios/App/H1State.swift`
- Create: `apps/ios/App/H1RenderCoordinator.swift`
- Create: `apps/ios/Tests/H1RenderCoordinatorTests.swift`
- Modify: `apps/ios/App/AppModel.swift`
- Delete: `apps/ios/Tests/M1AppModelTests.swift` after every provider/ACK/result/disconnect/retry behavior is represented in `H1RenderCoordinatorTests.swift`
- Delete: `apps/ios/App/M1State.swift` after migration passes

- [ ] **Step 1: Write failing mode and race tests**

Use these explicit modes:

```swift
enum H1TestMode: String, CaseIterable, Sendable {
    case rasterBaseline, rasterOptimized
    case vectorSynthetic8, vectorSynthetic20, vectorSynthetic40, vectorVietmap
}
```

Test: required key is loaded only for its mode; prepare ACK then ready; ready arriving before ACK is buffered; reject stops before asset begin; stop-and-wait maximum in-flight is one; result before final ACK is buffered; stale run/scene is ignored; vector failure never invokes raster; disconnect/cancel clears ownership; every terminal path closes a run record.

- [ ] **Step 2: Run the failing iOS source metadata test**

Extend `tools/ios/test-project-metadata.sh` to require `H1RenderCoordinator.swift` and forbid `startM1`. Run: `make test-ios-metadata`

Expected: FAIL before migration.

- [ ] **Step 3: Implement coordinator and thin AppModel wiring**

`H1RenderCoordinator` owns operation token, run/scene IDs, semantic prepare continuation, transfer loop, result timeout, ACK timings, and run recorder. `AppModel` loads the appropriate Keychain key, forwards Band envelopes/disconnects, and publishes coordinator state. Reuse the proven M1 timeout/ownership semantics rather than deleting recovery behavior.

Before deleting `M1AppModelTests.swift`, map its assertions into named H1 tests for provider call count, maximum in-flight one, Band failure during transfer, early/late result ordering, stale run isolation, timeout, cancellation, disconnect, reconnect requirement, and safe error mapping.

- [ ] **Step 4: Run focused and full portable tests**

Run: `make test-swift && make test-ios-metadata && git diff --check`

- [ ] **Step 5: Commit**

```bash
git add apps/ios/App apps/ios/Tests tools/ios/test-project-metadata.sh
git commit -m "feat: coordinate H1 renderer evaluation runs"
```

## Task 12: Add explicit iPhone renderer controls and run export

**Files:**
- Create: `apps/ios/App/H1TestView.swift`
- Create: `apps/ios/App/ActivityShareSheet.swift`
- Modify: `apps/ios/App/ContentView.swift`
- Modify: `apps/ios/App/BlueBandMapApp.swift`
- Modify: `apps/ios/project.yml`
- Modify: `apps/ios/Tests/ProjectSmokeTests.swift`
- Modify: `tools/ios/test-project-metadata.sh`

- [ ] **Step 1: Write failing source/UI contract checks**

Assert the UI has a renderer-first selector, separate Raster and Vector groups, synthetic segment choices, one Run button disabled until RPK ready, latest bytes/chunks/ACK p95/total/result labels, and an export action. Assert no automatic fallback label/action exists.

- [ ] **Step 2: Run the failing metadata checks**

Run: `make test-ios-metadata`

Expected: FAIL because H1 UI/composition is absent.

- [ ] **Step 3: Implement the test UI and dependency composition**

Compose style client, MVT scene provider, indexed PNG encoder, file run store, and coordinator in `BlueBandMapApp`. `H1TestView` makes renderer selection explicit before mode details. Present `ActivityShareSheet` with only the sanitized export URL. Keep configuration and Band picker behavior unchanged.

- [ ] **Step 4: Bump H1 source versions**

Set iOS `MARKETING_VERSION: 0.2.0`, `CURRENT_PROJECT_VERSION: 2`, RPK `versionName: 0.3.0`, and `versionCode: 3`; update visible RPK labels and bundle tests.

- [ ] **Step 5: Verify and commit**

Run: `make test-ios-metadata && make test-rpk && git diff --check`

```bash
git add apps/ios apps/band/src/manifest.json apps/band/src/pages/index/index.ux apps/band/test tools/ios/test-project-metadata.sh
git commit -m "feat: expose H1 raster and vector test modes"
```

## Task 13: Write the combined H1 test packet and run full verification

**Files:**
- Create: `docs/testing/results/2026-08-30-h1-hybrid-renderer-test-packet.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Write the hardware packet before claiming readiness**

Include artifact identity fields; stationary safety; config health without values; one-call budgets; renderer prepare/reject checks; five raster-baseline runs; five optimized-raster runs; vector 8 then 20 then 40 stop rule; five real-scene runs only at the accepted lower range; export steps; readability questions; crash/hang stop conditions; and exact `PASS-HW`, `FAIL-HW`, `BLOCKED-ENV`, `NEEDS-MEASURE` feedback.

- [ ] **Step 2: Run canonical local gates**

Run:

```bash
make clean
make bootstrap
make test
make lint
scripts/verify-no-secrets.sh
git diff --check
```

Expected: 0 exit status for every command. Record exact test totals in the eventual handoff; do not pre-write totals.

- [ ] **Step 3: Commit the release candidate**

```bash
git add README.md CHANGELOG.md docs/testing/results/2026-08-30-h1-hybrid-renderer-test-packet.md
git commit -m "docs: add H1 hybrid renderer test packet"
```

## Task 14: Build CI artifacts and package one immutable H1 handoff

**Files:**
- Create after artifact build: commit-derived `docs/testing/handoffs/h1-$h1_short_commit.md`
- Generate ignored: commit-derived `artifacts/h1/$h1_short_commit/`

- [ ] **Step 1: Verify the release-candidate commit and push**

Run:

```bash
git status --short --branch
h1_source_commit=$(git rev-parse HEAD)
h1_short_commit=$(git rev-parse --short=7 "$h1_source_commit")
git push origin main
```

Expected: clean working tree before push; the pushed full SHA is the H1 artifact source commit.

- [ ] **Step 2: Observe relevant CI, not unrelated suites**

Confirm repo, Swift, Band, protocol-lab, and iOS jobs triggered only where their path filters require them. Fix any failure with a failing local regression test and a new commit; never rerun blindly.

- [ ] **Step 3: Dispatch and download one unsigned artifact build**

Run:

```bash
gh workflow run release-artifacts.yml --ref main
h1_run_id=$(gh run list --workflow release-artifacts.yml --branch main --event workflow_dispatch \
  --json databaseId,headSha --jq ".[] | select(.headSha == \"$h1_source_commit\") | .databaseId" | head -n 1)
test -n "$h1_run_id"
gh run watch "$h1_run_id" --exit-status
h1_download_dir=$(mktemp -d /tmp/blueband-h1-artifact.XXXXXX)
gh run download "$h1_run_id" --dir "$h1_download_dir"
h1_ipa=$(find "$h1_download_dir" -type f -name '*.ipa' -print -quit)
h1_rpk=$(find "$h1_download_dir" -type f -name '*.rpk' -print -quit)
test -n "$h1_ipa"
test -n "$h1_rpk"
```

Verify `release-manifest.json` contains `$h1_source_commit`, iOS `0.2.0`, and RPK `0.3.0`; recompute SHA-256; require exactly one unsigned IPA and one debug RPK.

- [ ] **Step 4: Write and commit the factual H1 handoff**

Set `h1_handoff="docs/testing/handoffs/h1-$h1_short_commit.md"` and create that file using the established eight-section contract. State that GitHub/macOS compilation is not hardware acceptance. Include exact paths, bytes, hashes, workflow run URL/ID, test totals, provider-smoke boundary, and link to the combined packet.

- [ ] **Step 5: Package the fixed-directory bundle**

Run:

```bash
scripts/prepare-poc-handoff.sh \
  --poc h1 \
  --commit "$h1_source_commit" \
  --handoff "$h1_handoff" \
  --ipa "$h1_ipa" \
  --rpk "$h1_rpk"
```

Expected: immutable `artifacts/h1/$h1_short_commit/` with `HANDOFF.md`, `SHA256SUMS`, IPA, and RPK. Recompute both hashes from the final bundle.

- [ ] **Step 6: Final documentation commit and handoff**

```bash
git add "$h1_handoff"
git commit -m "docs: record H1 hybrid renderer artifacts"
git push origin main
```

Report the summary, exact test steps, IPA/RPK absolute paths, hashes, CI URL, and the fact that renderer support remains pending owner hardware feedback.

## Plan completion criteria

- One implementation plan produced one H1 evaluation app and RPK; no intermediate owner approval was required.
- CI no longer runs all Docker suites for documentation-only changes and no known gate is permanently red.
- At least one bounded live Static Map smoke remains recorded; style smoke is run once when `local/vietmap-tilemap-key` is available.
- Raster baseline, optimized raster, synthetic vector, and real Vietmap vector are explicit modes in the same app.
- Band preparation occurs before transfer and rejects unsupported/oversized work without allocation.
- Band receives at most 64 KiB and renders at most 40 vector segments.
- Detailed telemetry lives on the iPhone; Band sends sparse aggregate results.
- One source commit has a verified unsigned IPA/RPK pair and immutable H1 handoff.
- No claim exceeds automated, provider-smoke, CI, or hardware evidence actually obtained.
