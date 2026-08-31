# Band Map Performance and Visual Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce first-map latency and deliver the approved B1 dark HUD and M1 directional marker without relying on unsupported Band drawing features.

**Architecture:** Vietmap's dark vector style remains the source, while iOS removes and recolors layers before snapshotting, draws a flat route, and selects a PNG8 candidate around 4 KiB. The existing application protocol carries a bounded initial instruction preview in `render.prepare`, then uses window 2 for the map and normal `nav.update` messages with an eight-way heading bucket. The RPK renders only exact-size bundled PNG8 resources and basic Vela components.

**Tech Stack:** Swift 6, XCTest, Core Graphics/ImageIO, Vietmap iOS SDK, Vela JS Quick App, Node test runner, Docker/Make, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-01-band-map-performance-visual-refinement-design.md`

## Global Constraints

- Work directly on `main`; do not create a branch or worktree.
- Add and observe a failing behavioral test before every production behavior change.
- Do not change Xiaomi BLE/SPP/auth/encryption/transport bytes.
- Keep the image protocol hard limit at 8,192 bytes and dimensions at 212×520.
- Use only PNG/JPG formats documented by Vela; production remains hardware-proven PNG8.
- Build IPA only with GitHub Actions.
- Build RPK through canonical Docker/Make commands.
- Bump both IPA and RPK because both products change.
- Do not claim latency or hardware acceptance from automated tests.

---

### Task 1: Portable optimization and preview contracts

**Files:**
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/SnapshotMapPolicy.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/RenderProtocol.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/NavigationUpdate.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/SnapshotMapPolicyTests.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/RenderProtocolTests.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/NavigationUpdateTests.swift`

**Interfaces:**
- Produces: `SnapshotPaletteProfile.transferOptimizedOrder`, `SnapshotPayloadAdmission.preferredMaximumBytes`, `RenderNavigationPreview`, `RenderPrepareBody(..., preview:)`, and `NavigationUpdate.headingBucket`.
- Consumes: existing `NavigationManeuver`, `NavigationStatus`, `RenderAsset`, and `JSONValue`.

- [ ] **Step 1: Write failing portable tests**

Add assertions equivalent to:

```swift
XCTAssertEqual(SnapshotPaletteProfile.transferOptimizedOrder, [
    .colors16Labels, .colors16NoLowPriorityLabels, .colors16NoLowPriorityLandUse,
])
XCTAssertEqual(SnapshotPayloadAdmission.preferredMaximumBytes, 4_096)
XCTAssertEqual(SnapshotPayloadAdmission.choose([
    (.colors16Labels, 5_000),
    (.colors16NoLowPriorityLabels, 3_900),
]), .colors16NoLowPriorityLabels)
XCTAssertEqual(SnapshotPayloadAdmission.choose([
    (.colors16Labels, 6_000),
    (.colors16NoLowPriorityLabels, 5_000),
]), .colors16NoLowPriorityLabels)
```

Create a preview and require it in the JSON body:

```swift
let preview = try RenderNavigationPreview(maneuver: .right, distanceMeters: 88, street: "Chu Huy Mân")
let prepare = try RenderPrepareBody(runID: runID, sceneID: sceneID, asset: asset, preview: preview)
XCTAssertEqual(prepare.jsonBody()["preview"], .object(preview.jsonBody()))
XCTAssertLessThanOrEqual(try ApplicationEnvelope.message(
    id: "prepare-0123456789", source: .ios,
    topic: RenderProtocol.prepareTopic, body: prepare.jsonBody()
).encoded().count, ApplicationEnvelope.maximumEncodedSize)
```

Require heading buckets:

```swift
let update = try NavigationUpdate(
    scene: "scene", seq: 0, x: 106, y: 320, headingBucket: 7,
    maneuver: .straight, distanceMeters: 10, street: "Road", status: .navigating
)
XCTAssertEqual(update.jsonBody()["heading"], .number(7))
XCTAssertThrowsError(try NavigationUpdate(
    scene: "scene", seq: 0, x: 106, y: 320, headingBucket: 8,
    maneuver: .straight, distanceMeters: 10, street: "Road", status: .navigating
))
```

- [ ] **Step 2: Verify RED**

Run:

```bash
make test-swift SWIFT_TEST_ARGS='--filter SnapshotMapPolicyTests'
make test-swift SWIFT_TEST_ARGS='--filter RenderProtocolTests'
make test-swift SWIFT_TEST_ARGS='--filter NavigationUpdateTests'
```

Expected: compilation/test failures for the missing order, target, preview, and heading APIs.

- [ ] **Step 3: Implement the minimal portable contracts**

Implement:

```swift
public static let transferOptimizedOrder: [Self] = [
    .colors16Labels, .colors16NoLowPriorityLabels, .colors16NoLowPriorityLandUse,
]
```

`SnapshotPayloadAdmission.choose` must return the first ordered candidate at or below 4,096 bytes; otherwise return the smallest candidate at or below 8,192 bytes.

`RenderNavigationPreview` validates non-negative distance, truncates street to 48 UTF-8 bytes, and emits only `maneuver`, `distanceM`, and `street`. `RenderPrepareBody.preview` is optional so old call sites and decode fixtures remain valid.

`NavigationUpdate.headingBucket` validates `0..<8` and emits key `heading`.

- [ ] **Step 4: Verify GREEN**

Run the three filtered commands again, then `make test-swift`.

- [ ] **Step 5: Commit**

```bash
git add packages/BlueBandKit
git commit -m "feat: add transfer optimized navigation contracts"
```

### Task 2: Dark snapshot and compact PNG admission

**Files:**
- Modify: `apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift`
- Modify: `apps/ios/Adapters/Rendering/SnapshotPNGEncoder.swift`
- Modify: `apps/ios/App/AppModel.swift`
- Modify: `apps/ios/Tests/VietmapSnapshotRendererTests.swift`
- Modify: `apps/ios/Tests/SnapshotPNGEncoderTests.swift`

**Interfaces:**
- Consumes: Task 1's `transferOptimizedOrder`, `preferredMaximumBytes`, and `SnapshotPayloadAdmission.choose`.
- Produces: `VietmapSnapshotRenderer.styleURL(tileMapKey:)`, deterministic dark paint normalization, flat route commands, and smallest valid PNG candidate selection.

- [ ] **Step 1: Write failing iOS tests**

Require:

```swift
XCTAssertEqual(
    VietmapSnapshotRenderer.styleURL(tileMapKey: "fixture-key")?.absoluteString,
    "https://maps.vietmap.vn/maps/styles/dm/style.json?apikey=fixture-key"
)
XCTAssertEqual(VietmapRouteOverlay.commands(for: request).map(\.kind), [
    .traveled, .upcoming, .maneuver,
])
XCTAssertEqual(VietmapRouteOverlay.commands(for: request).map(\.width), [4, 5, 9])
```

Update the solid-image encoder test to expect `.colors16Labels` and 16 colors when passed the optimized profile order. Add a candidate-selection test showing a 3,900-byte degraded candidate wins over a 5,000-byte labeled candidate, while the smallest under-8-KiB candidate is retained when none reaches 4 KiB.

- [ ] **Step 2: Verify RED in GitHub-compatible iOS tests where available and portable metadata locally**

Run:

```bash
make test-swift
make test-ios-metadata
```

Expected locally: portable suite remains green; new iOS source tests are pending macOS CI, while any pure policy tests fail until implementation. Do not claim iOS compile success locally.

- [ ] **Step 3: Implement dark style and flat route**

Expose the style URL helper internally and use `dm/style.json`. In `didFinishLoading`, remove disallowed layers and normalize retained `MGLBackgroundStyleLayer`, `MGLFillStyleLayer`, `MGLLineStyleLayer`, and `MGLSymbolStyleLayer` colors to the existing dark/gray/cyan 16-color palette using constant `NSExpression` values.

Remove `.upcomingHalo` and its draw call. Keep traveled gray, upcoming cyan width 5, and the maneuver ring.

- [ ] **Step 4: Implement target-based candidate selection**

In `AppModel.publish`, render profiles in `transferOptimizedOrder`, keep `(snapshot, encoded)` candidates, stop at the first candidate no larger than 4,096 bytes, and otherwise use the smallest candidate no larger than 8,192 bytes. Preserve route and primary label floors from the style policy.

- [ ] **Step 5: Verify local suites**

Run:

```bash
make test-swift
make test-ios-metadata
git diff --check
```

- [ ] **Step 6: Commit**

```bash
git add apps/ios packages/BlueBandKit
git commit -m "feat: optimize dark snapshot payloads"
```

### Task 3: Early B1 HUD, M1 assets, and window 2

**Files:**
- Modify: `apps/ios/App/AppModel.swift`
- Modify: `apps/ios/App/RouteCardRenderCoordinator.swift`
- Modify: `apps/ios/Tests/RouteCardRenderCoordinatorTests.swift`
- Modify: `apps/band/scripts/generate-icon.mjs`
- Modify: `apps/band/src/common/render-protocol.js`
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `apps/band/test/render-protocol.test.mjs`
- Modify: `apps/band/test/envelope-page.test.mjs`

**Interfaces:**
- Consumes: Task 1's preview and heading contracts.
- Produces: `RouteCardRenderCoordinator.start(asset:diagnostics:preview:)`, default `transferWindow = 2`, generated `/common/nav-shade.png`, maneuver PNGs, marker PNGs, and B1/M1 RPK presentation.

- [ ] **Step 1: Write failing coordinator tests**

Require the prepare message to carry preview and require default concurrency 2:

```swift
let preview = try RenderNavigationPreview(maneuver: .right, distanceMeters: 88, street: "Chu Huy Mân")
await coordinator.start(asset: asset, preview: preview)
XCTAssertEqual(await session.prepareBody?["preview"], .object(preview.jsonBody()))
XCTAssertEqual(await session.maximumConcurrentChunks, 2)
```

Add a heading helper assertion in AppModel-facing tests or a pure static helper:

```swift
XCTAssertEqual(AppModel.headingBucket(0), 0)
XCTAssertEqual(AppModel.headingBucket(44.9), 1)
XCTAssertEqual(AppModel.headingBucket(359), 0)
```

- [ ] **Step 2: Write failing RPK tests**

Extend `prepare()` with a preview and assert immediately after `render.prepare`:

```js
assert.equal(page.navDistance, "88 m")
assert.equal(page.navStreet, "Chu Huy Mân")
assert.equal(page.navArrowPath, "/common/maneuver-right.png")
assert.equal(page.navStatus, "LOADING MAP")
```

Extend `nav.update` with `heading: 3` and assert:

```js
assert.equal(page.navMarkerPath, "/common/marker-3.png")
```

Add source/layout assertions proving `.nav-header` has no rectangular background, uses the shade resource, one-line street text, a 26×32 marker image, and no SVG/canvas/transform dependency.

- [ ] **Step 3: Verify RED**

Run:

```bash
make test-swift SWIFT_TEST_ARGS='--filter RouteCardRenderCoordinatorTests'
make test-rpk
```

Expected: failures for missing preview forwarding, window 2 default, preview validation, marker path, resources, and B1 layout.

- [ ] **Step 4: Implement coordinator/AppModel behavior**

Build `RenderNavigationPreview` before `renderCoordinator.start`, pass it through prepare, and set `transferWindow` default to 2. Derive `headingBucket` with normalized 45-degree sectors and include it in every `NavigationUpdate`.

- [ ] **Step 5: Generate and use exact-size PNG8 resources**

Extend the existing Node generator using only `node:zlib` and `node:fs/promises`. Generate:

- `nav-shade.png` at 212×96.
- Six 42×54 maneuver images.
- Eight 26×32 M1 marker images.

The generator must emit indexed PNG color type 3 at 8 bits, exact dimensions, and deterministic bytes. The page uses local image paths and basic positioning only.

- [ ] **Step 6: Implement preview validation and cleanup**

Validate preview shape, maneuver, distance, and 48-byte street in both `src/common/render-protocol.js` and the self-contained mirrored helper in `index.ux`. Apply it only after prepare admission. Clear pending preview on cancel, failure, disconnect, and teardown; do not change confirmed-map ownership.

- [ ] **Step 7: Implement B1/M1 layout**

Replace the current header card and marker div with:

```html
<image class="nav-shade" if="{{ mapReady || pendingPublication || preparedRender }}" src="/common/nav-shade.png" />
<div class="nav-header" if="{{ mapReady || pendingPublication || preparedRender }}">
  <image class="nav-arrow" src="{{ navArrowPath }}" />
  <text class="nav-distance">{{ navDistance }}</text>
  <text class="nav-street">{{ navStreet }}</text>
</div>
<image class="nav-marker" if="{{ mapReady }}" src="{{ navMarkerPath }}" style="{{ navMarkerStyle }}" />
```

Use the dimensions and offsets from the approved spec. Keep exceptional status text and hide ordinary `NAVIGATING`.

- [ ] **Step 8: Verify GREEN**

Run:

```bash
make test-rpk
make test-swift
git diff --check
```

- [ ] **Step 9: Commit**

```bash
git add apps/ios apps/band packages/BlueBandKit
git commit -m "feat: show compact navigation while maps transfer"
```

### Task 4: Versions, release evidence, and delivery

**Files:**
- Modify: `apps/ios/project.yml`
- Modify: `apps/ios/App/BlueBandMapApp.swift`
- Modify: `tools/ios/test-project-metadata.sh`
- Modify: `apps/band/package.json`
- Modify: `apps/band/package-lock.json`
- Modify: `apps/band/src/manifest.json`
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `CHANGELOG.md`
- Modify: `docs/testing/handoffs/vietmap-sdk-snapshot-route-map.md`

**Interfaces:**
- Produces: IPA `0.3.0 (13)`, RPK `0.4.0 (13)`, GitHub Actions IPA artifact, Make-built RPK artifact, hashes, and hardware retest plan.

- [ ] **Step 1: Make version tests fail**

Change metadata test expectations to iOS `0.3.0 (13)` and RPK tests to `0.4.0 (13)`, then run:

```bash
make test-ios-metadata
make test-rpk
```

Expected: version assertions fail against existing production metadata.

- [ ] **Step 2: Bump both products**

Set iOS marketing/build versions to `0.3.0`/`13` and RPK package/manifest/page versions to `0.4.0`/`13`. Update the lockfile mechanically with the containerized npm workflow. Record that both artifacts changed.

- [ ] **Step 3: Run the canonical local gate**

```bash
make clean && make bootstrap && make test && make lint && scripts/verify-no-secrets.sh && git diff --check
```

- [ ] **Step 4: Request one final review and fix all Critical/Important findings**

Review the full implementation against the spec, especially application protocol bounds, Band cleanup, unsupported UI features, versioning, and evidence claims.

- [ ] **Step 5: Commit and push `main`**

```bash
git add CHANGELOG.md apps packages tools docs
git commit -m "release: prepare faster Band map artifacts"
git push origin main
```

- [ ] **Step 6: Wait for GitHub Actions and download only its IPA**

Require successful simulator tests, unsigned arm64 device build, artifact verification, and upload. Download into a versioned ignored directory and verify bundle, `0.3.0 (13)`, arm64, absence of `_CodeSignature`, and absence of `embedded.mobileprovision`.

- [ ] **Step 7: Build and verify RPK through Make**

```bash
make build-rpk
```

Copy the verified `0.4.0` RPK into the ignored artifact handoff directory, record bytes and SHA-256, and do not rebuild IPA locally.

- [ ] **Step 8: Update handoff and manual test plan**

Record:

- New commits, versions, CI URL, artifact paths, bytes, and hashes.
- Automated counts without claiming hardware performance.
- Five identical cold starts recording route/render, preview-visible, payload, chunks, window, ACK p50/p95/max, map-visible, and street-visible times.
- Visual checks for B1 safe-area fit, primary street readability, M1 heading, flat route contrast, and dark map context.
- Stop during transfer, reconnect, refresh, reroute, GPS-low, and 30-minute stability checks.
- Comparison against the 7,813-byte and 45,529-ms baseline.

- [ ] **Step 9: Commit handoff, push, and verify clean synchronization**

```bash
git add docs/testing/handoffs/vietmap-sdk-snapshot-route-map.md
git commit -m "docs: hand off faster Band map retest"
git push origin main
git status --short
git rev-parse HEAD
git rev-parse origin/main
```

Expected: clean status and identical HEAD/origin SHA.
