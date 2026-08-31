# Vietmap SDK Snapshot Route Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the four-color 212x360 route card with a phone-rendered, palette-reduced 212x520 Vietmap SDK snapshot that remains useful while native Band navigation UI and marker updates continue independently.

**Architecture:** `BlueBandMapCore` owns only portable asset limits, refresh/admission policies, transfer planning, and diagnostics. The official Vietmap binary stays in the iOS adapter, where `MGLMapSnapshotter` loads and simplifies the documented light vector style and Core Graphics draws the Route v4 overlay. The existing authenticated Xiaomi transport and envelope stay unchanged; only application-level chunk scheduling and the Band's atomic full-screen image publication change.

**Tech Stack:** Swift 5.10/6, SwiftUI, CoreLocation, CoreGraphics/ImageIO, Vietmap `VietMap` Swift package pinned at `649eabcb21a36c3d0cfd871c07ccea641924fcdd`, Xiaomi Vela JS/RPK, Node 20 tests, Docker Compose/Make, GitHub Actions macOS/Xcode.

**Spec:** `docs/superpowers/specs/2026-08-31-vietmap-sdk-snapshot-route-map-design.md`

## Global Constraints

- Work directly on `main` as authorized for this rollout; do not create a branch or worktree.
- Run canonical local commands through `make`; do not use host Node/Swift as acceptance evidence.
- Build and test the IPA only through `.github/workflows/ios-checks.yml`; do not build an IPA locally.
- Add a failing behavioral test before every behavior change.
- Preserve Xiaomi BLE, SPP, authentication, encryption, transport ACK, ThirdPartyApp, TOFU, 512-byte envelope, SHA-256, scene/run correlation, and disconnect cleanup bytes and invariants.
- The snapshot is exactly 212x520 at scale 1 and the encoded payload is at most 8,192 bytes.
- Support application acknowledgement windows 1, 2, and 4; default to 1 until hardware evidence selects another value.
- Do not fall back to the old four-color route-card renderer.
- Never commit keys, full coordinates, raw provider bodies/captures, credentials, provisioning/signing material, generated Xcode projects, dependencies, or build artifacts.
- Do not claim iPhone/Smart Band hardware support from local tests, simulator tests, compilation, or GitHub Actions.
- Bump only artifacts whose source changed: iOS version only for IPA-affecting changes; Band version only for RPK-affecting changes.

---

## Task 1: Migrate the portable raster asset contract

**Files:**
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/RenderProtocol.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/RenderTransferPlan.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/NavigationUpdate.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/RenderProtocolTests.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/NavigationUpdateTests.swift`

**Interfaces:**
- `RenderProtocol.viewportWidth == 212`
- `RenderProtocol.viewportHeight == 520`
- `RenderProtocol.maximumPayloadBytes == 8_192`
- `RenderTransferPlan.make(asset:runID:sceneID:)` continues deriving chunk bytes from actual encoded 512-byte envelopes and reconstructs the asset exactly.
- `NavigationUpdate` accepts native marker coordinates only inside the new viewport.

- [x] **Step 1: Write failing contract tests**

Change test assets to 212x520, assert 8,192 bytes are admitted and 8,193 rejected, assert every generated begin/chunk/end envelope is at most 512 bytes, assert all chunks reconstruct the original 8 KiB payload, and assert marker `y == 519` is valid while `y == 520` is rejected.

- [x] **Step 2: Verify RED**

Run: `make test-swift SWIFT_TEST_ARGS='--filter RenderProtocolTests|NavigationUpdateTests'`

Expected: FAIL on old height, old 1 KiB ceiling, old seven-chunk cap, or marker bounds.

- [x] **Step 3: Implement the minimum shared contract change**

Set the new dimensions/payload ceiling and remove the obsolete seven-data-chunk restriction. Retain binary-search envelope sizing and all identifier/hash validation.

- [x] **Step 4: Verify GREEN**

Run: `make test-swift SWIFT_TEST_ARGS='--filter RenderProtocolTests|NavigationUpdateTests' && git diff --check`

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add packages/BlueBandKit
git commit -m "feat: admit full-screen snapshot assets"
```

## Task 2: Add portable snapshot policies and diagnostics

**Files:**
- Create: `packages/BlueBandKit/Sources/BlueBandMapCore/SnapshotMapPolicy.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/SnapshotMapPolicyTests.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/RenderRun.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/RenderRunTests.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/NavigationDebug.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/NavigationDebugTests.swift`

**Interfaces:**
- `SnapshotPaletteProfile`: ordered cases `colors32Labels`, `colors16Labels`, `colors16NoLowPriorityLabels`, `colors16NoLowPriorityLandUse` with palette count and style simplification flags.
- `SnapshotPayloadAdmission.choose(_ candidates: [(SnapshotPaletteProfile, Int)])` returns the first profile at or below 8,192 bytes or `nil`.
- `ReusableLocationPolicy.isReusable(horizontalAccuracyMeters:ageSeconds:)` requires valid `0...25` accuracy and age `0...10` seconds.
- `SnapshotRefreshPolicy.shouldRefresh(_:)` returns true only for marker outside the safe viewport, maneuver-context change, successful reroute, or zoom-context loss.
- `PendingSnapshotCoalescer` keeps at most the newest queued generation and rejects stale completion.
- `RenderRunMetrics` adds GPS, route, style, snapshot, encode, transfer prepare, Band write/decode/publication, palette, retained layer counts, transfer window, and cache state fields without exact coordinates or identifiers.

- [x] **Step 1: Write failing policy and metrics tests**

Cover profile order and admission, GPS boundaries, each refresh trigger/non-trigger, newest-pending replacement, stale generation rejection, p50/p95/max ACKs, new metric serialization, and a redaction assertion that exported diagnostics contain neither provider keys nor full coordinates.

- [x] **Step 2: Verify RED**

Run: `make test-swift SWIFT_TEST_ARGS='--filter SnapshotMapPolicyTests|RenderRunTests|NavigationDebugTests'`

Expected: FAIL because the policies and new metrics are absent.

- [x] **Step 3: Implement the policies as value types**

Use enums/structs only; do not add factories or persistence. Keep the safe viewport as an explicit `ScreenRect`, defaulting to a conservative inner rectangle that excludes the top overlay and display edges.

- [x] **Step 4: Verify GREEN and commit**

Run: `make test-swift SWIFT_TEST_ARGS='--filter SnapshotMapPolicyTests|RenderRunTests|NavigationDebugTests' && git diff --check`

```bash
git add packages/BlueBandKit
git commit -m "feat: define snapshot refresh and admission policy"
```

## Task 3: Add bounded windowed application transfer

**Files:**
- Modify: `apps/ios/App/RouteCardRenderCoordinator.swift`
- Create: `apps/ios/Tests/RouteCardRenderCoordinatorTests.swift`
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `apps/band/src/common/render-protocol.js`
- Modify: `apps/band/test/render-protocol.test.mjs`
- Modify: `apps/band/test/envelope-page.test.mjs`

**Interfaces:**
- `RouteCardRenderCoordinator(... transferWindow: Int = 1)` accepts only 1, 2, or 4.
- Prepare, begin, and end remain ordered barriers; only data chunks have up to `transferWindow` outstanding application acknowledgements.
- The Band accepts multiple unique in-flight envelope IDs for one active asset but writes only the exact next offset; wrong offsets abort the generation.
- A confirmed previous map remains visible until the new digest-valid PNG completes image publication.

- [x] **Step 1: Write failing iOS and Band behavioral tests**

The iOS fake session blocks chunk acknowledgements and records maximum concurrent sends; assert windows 1, 2, and 4 never exceed their bounds, a slot opens after one ACK, and timeout/disconnect/stale completion abort once. Band tests send multiple unique chunk IDs in order, a wrong offset, a duplicate/stale scene, digest mismatch, disconnect, and a second refresh while a confirmed map exists; assert immediate ACKs, cleanup, and atomic publication.

- [x] **Step 2: Verify RED**

Run: `make test-rpk`

Expected: FAIL because the Band still uses 212x360/1 KiB and one active message ID. The iOS tests remain pending for GitHub Actions because they require Xcode.

- [x] **Step 3: Implement bounded windowing and atomic refresh**

Use `withThrowingTaskGroup` for data chunks only, adding the next chunk when one child completes. Do not touch `BandTransport` or Xiaomi transport ACK code. Keep the confirmed URI/map fields until `image @complete`; delete only retired confirmed files after replacement succeeds.

- [x] **Step 4: Verify GREEN locally**

Run: `make test-rpk && make test-ios-metadata && git diff --check`

Expected: Band and metadata checks PASS.

- [x] **Step 5: Commit**

```bash
git add apps/ios/App/RouteCardRenderCoordinator.swift apps/ios/Tests/RouteCardRenderCoordinatorTests.swift apps/band
git commit -m "feat: window snapshot asset transfers"
```

## Task 4: Render and reduce Vietmap SDK snapshots on iOS

**Files:**
- Modify: `apps/ios/project.yml`
- Create: `apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift`
- Create: `apps/ios/Adapters/Rendering/SnapshotPNGEncoder.swift`
- Create: `apps/ios/Tests/Fixtures/vietmap-light-style-layers.json`
- Create: `apps/ios/Tests/VietmapSnapshotRendererTests.swift`
- Create: `apps/ios/Tests/SnapshotPNGEncoderTests.swift`

**Interfaces:**
- XcodeGen package `VietMap` uses `https://github.com/vietmap-company/maps-sdk-ios.git` at exact revision `649eabcb21a36c3d0cfd871c07ccea641924fcdd`; target dependency product is `VietMap` only.
- `VietmapSnapshotRequest` contains route, progress index, matched position, heading, next maneuver coordinate, and TileMap key.
- `VietmapSnapshotRenderer.render(_:) async throws -> VietmapSnapshotOutput` returns a 212x520 `CGImage`, retained layer counts, chosen zoom, style/snapshot timings, and cache state.
- `SnapshotPNGEncoder.encode(_ image: CGImage, profiles: [SnapshotPaletteProfile] = SnapshotPaletteProfile.allCases) throws -> SnapshotPNGOutput` returns the first indexed PNG at or below 8,192 bytes with profile, byte count, color count, and duration.

- [x] **Step 1: Add failing iOS tests and sanitized fixture**

The fixture contains only layer type/id pairs observed from the documented light style. Tests assert the allowlist keeps background, ocean/land, selected park/residential/school/hospital, close-zoom building, useful road casing/fill, and road labels while removing POI/transit/admin/place/3D layers. Test 212x520 scale-1 camera values, zero pitch, heading, 72% vertical position, overlay padding, route overlay order/widths/colors, maneuver ring, snapshot success/error completion, indexed PNG dimensions, ordered profiles, and 8 KiB failure.

- [x] **Step 2: Verify RED in GitHub later**

The new tests must initially fail to compile against absent types. Do not generate/build an Xcode project or IPA locally.

- [x] **Step 3: Implement the SDK adapter and native indexed PNG encoder**

Set `MGLMapSnapshotter.delegate` before `start(overlayHandler:completionHandler:)`; remove non-allowlisted `MGLStyle.layers` in `didFinishLoadingStyle`; draw traveled, upcoming halo/fill, and maneuver via `MGLMapSnapshotOverlay.point(for:)`; retain the delegate strongly until completion; cancel safely. Quantize BGRA pixels to fixed profile palettes with nearest-color distance, store indices as an 8-bit indexed bitmap (Core Graphics does not support 5-bit components), and encode with ImageIO. Never call `RouteCardAssetFactory` as fallback.

- [x] **Step 4: Verify metadata and commit**

Run: `make test-ios-metadata && git diff --check`

```bash
git add apps/ios/project.yml apps/ios/Adapters apps/ios/Tests
git commit -m "feat: render Vietmap navigation snapshots"
```

## Task 5: Integrate GPS prewarm, snapshot refresh, and Band visual design

**Files:**
- Modify: `apps/ios/Adapters/Location/ForegroundLocationClient.swift`
- Modify: `apps/ios/App/AppModel.swift`
- Modify: `apps/ios/App/BlueBandMapApp.swift`
- Modify: `apps/ios/App/ContentView.swift`
- Modify: `apps/ios/App/RouteCardTransferState.swift`
- Modify: `apps/ios/Tests/AppModelPickerTests.swift`
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `apps/band/test/envelope-page.test.mjs`

**Interfaces:**
- `ForegroundLocationClient.startPrewarming()` starts foreground updates and caches the newest valid `CLLocation`; `recentLocation(now:)` applies the portable 25 m/10 s policy; `stop()` clears active streaming but not a still-fresh cached fix.
- `AppModel.navigationScreenActive(_:)` prewarms location and snapshot style only while the foreground navigation/configuration screen is active.
- Start immediately publishes `LOCATING`/`GPS LOW`; a reusable fix routes immediately.
- Initial render failure is terminal; refresh failure keeps the confirmed scene and sends `LIMITED MAP`.
- `nav.update` remains at no more than 1 Hz and moves only the native marker/instruction overlay.

- [x] **Step 1: Write failing lifecycle/runtime/layout tests**

Assert reusable vs stale fixes, immediate Start state, initial failure, confirmed-map retention on refresh failure, reroute refresh, maneuver/viewport/zoom refresh, pending refresh replacement, and no render on ordinary 1 Hz updates. Band source tests assert the 212x520 image fills the page, overlay width 184 and height 116-128 with translucent background, native marker above the map, normal `NAVIGATING` hidden, and exceptional statuses plus `LOADING MAP` visible.

- [x] **Step 2: Verify RED**

Run: `make test-rpk`

Expected: FAIL on old map frame/header/layout assertions; iOS runtime tests await GitHub Actions.

- [x] **Step 3: Integrate the minimum runtime flow**

Replace `RouteCardAssetFactory` composition/use with `VietmapSnapshotRenderer` plus `SnapshotPNGEncoder`. Reuse `VietmapRouteClient`, `RouteProgressTracker`, update coalescer, renderer coordinator, and existing session. Do not delete historical POC types in this task; leave them unreferenced so the diff stays focused and past evidence remains compilable.

- [x] **Step 4: Verify GREEN locally and commit**

Run: `make test-rpk && make test-ios-metadata && make test-swift && git diff --check`

```bash
git add apps/ios apps/band
git commit -m "feat: navigate with full-screen snapshot maps"
```

## Task 6: Version, document, verify, and build artifacts

**Files:**
- Modify only if iOS source changed: `apps/ios/project.yml`, `apps/ios/App/BlueBandMapApp.swift`
- Modify only if Band source changed: `apps/band/src/manifest.json`, `apps/band/package.json`, `apps/band/package-lock.json`, `apps/band/src/pages/index/index.ux`, `apps/band/test/bundle-contract.test.mjs`
- Create: `docs/adr/0011-vietmap-sdk-snapshot-route-map.md`
- Create: `docs/protocol/snapshot-route-map-v1.md`
- Create: `docs/testing/handoffs/vietmap-sdk-snapshot-route-map.md`
- Modify: `README.md`, `CHANGELOG.md`, `docs/testing/hardware-acceptance.md`

**Version rule:** If the preceding diff contains iOS source changes, bump iOS `0.1.9 (10)` to `0.2.0 (11)`. If it contains Band source changes, bump RPK `0.2.9 (11)` to `0.3.0 (12)` consistently. If one artifact has no source change, do not bump it.

- [x] **Step 1: Add failing version/metadata assertions only for changed artifacts**

Update existing bundle/project metadata tests to the selected versions. Verify they fail before changing manifests/source constants.

- [x] **Step 2: Apply matching version bumps and documentation**

Document the exact snapshot/application protocol, unchanged Xiaomi transport boundary, deferred tiled engine, local/CI/hardware evidence boundaries, and the complete manual test matrix from the approved spec.

- [x] **Step 3: Run the canonical local gate**

```bash
make clean
make bootstrap
make test
make lint
scripts/verify-no-secrets.sh
git diff --check
```

Expected: every command exits 0. This does not prove Xcode or hardware behavior.

- [x] **Step 4: Perform final code review and fix findings**

Review the complete `main` diff against the spec, with special attention to envelope size, window bounds, atomic publication, stale generations, key redaction, iOS-only SDK isolation, and version consistency. Re-run the covering tests after fixes.

- [x] **Step 5: Commit and push `main`**

```bash
git add CHANGELOG.md README.md apps docs packages
git commit -m "docs: hand off snapshot route map testing"
git push origin main
```

- [x] **Step 6: Build/test IPA only in GitHub Actions**

Use the push-triggered `iOS checks` run, or dispatch `.github/workflows/ios-checks.yml` on `main` if needed. Wait for the macOS simulator tests and unsigned arm64 device app build. Download the GitHub artifact and verify it with `scripts/verify-ios-artifact.sh`; never run local `xcodebuild` or local IPA packaging.

- [x] **Step 7: Build RPK through the canonical Make path**

Run `make test-rpk`; use the generated RPK only after the bundle verification test passes. Record exact artifact paths, sizes, SHA-256 values, source commit, and which versions changed.

- [x] **Step 8: Deliver the manual test plan**

The handoff must give the owner step-by-step iPhone + Smart Band 10 tests for first feedback <=100 ms, five-start p95 <=5 s with reusable GPS, warm snapshot+encode p95 <=1.5 s, transfer p95 <=3 s, window 1/2/4 trials, <=8 KiB payload, visual readability/alignment/overlay checks, <=1 s marker/instruction updates, reroute/refresh/failure/disconnect recovery, turn-recognition 4/5, and 30-minute stability. Cold GPS is reported separately.
