# Familiar Dark Band Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a familiar, readable dark city map with pill-safe HUD/marker placement and materially fewer transfer ACK rounds for 0–50 km/h navigation.

**Architecture:** Keep Vietmap snapshot rendering on iOS and PNG8 publication to the Band. Reuse the existing palette profiles and atomic scene lifecycle, but refine retained paints, refresh policy, envelope ceiling, chunk window, and native Band overlays. Do not add a backend or change verified Xiaomi wire behavior.

**Tech Stack:** Swift 6, SwiftPM, UIKit/CoreGraphics/ImageIO, VietMap iOS SDK, Vela UX/JavaScript, Node 20 in Docker, XCTest, Node test runner, GitHub Actions/Xcode.

**Spec:** `docs/superpowers/specs/2026-09-01-familiar-dark-map-safe-area-performance-design.md`

## Global Constraints

- Work directly on `main`; do not create a worktree or branch.
- Add a failing behavioral test before each implementation change.
- Use `make`/Docker for canonical local commands.
- Keep the hard PNG payload limit at 8,192 bytes and set the preferred ceiling to 5,120 bytes.
- Raise only the application envelope ceiling to 1,024 bytes; do not change Xiaomi BLE/SPP/auth/crypto/transport ACK bytes.
- Default application ACK window is four; begin/end remain barriers and complete SPP writes remain serialized.
- IPA becomes `0.4.0 (14)` and RPK becomes `0.5.0 (14)` because both installed components change.
- Build the IPA only through GitHub Actions.
- Do not claim latency or visual hardware acceptance from automated tests.

---

### Task 1: Application envelope and window-four transfer

**Files:**
- Modify: `packages/BlueBandKit/Sources/BlueBandCore/ApplicationEnvelope.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandCoreTests/ApplicationEnvelopeTests.swift`
- Modify: `apps/band/src/common/render-protocol.js`
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `apps/ios/App/RouteCardRenderCoordinator.swift`
- Modify: `apps/ios/Tests/RouteCardRenderCoordinatorTests.swift`

**Interfaces:**
- Produces: `ApplicationEnvelope.maximumEncodedSize == 1_024` and `RouteCardRenderCoordinator(... transferWindow: Int = 4)`.
- Preserves: `RenderTransferPlan` derives chunk data size by encoding the real envelope.

- [ ] **Step 1: Write failing contract tests**

Change the Swift boundary test to accept exactly 1,024 bytes and reject 1,025 bytes; assert the Band constants are 1,024; change the coordinator default test to expect four concurrent chunks and no fifth chunk before a contiguous ACK prefix advances.

```swift
func testRejectsEncodedEnvelopeLargerThan1024Bytes() {
    XCTAssertEqual(ApplicationEnvelope.maximumEncodedSize, 1_024)
    XCTAssertThrowsError(try ApplicationEnvelope.decode(Data(repeating: 0x20, count: 1_025), expecting: .band))
}
```

- [ ] **Step 2: Verify RED**

Run: `make test-swift && make test-rpk`
Expected: failures still report 512-byte constants and default window two.

- [ ] **Step 3: Implement the bounded change**

Set the Swift, Band helper, and in-page envelope ceilings to 1,024. Set the coordinator default to four. Keep accepted configurable windows `[1, 2, 4]`, contiguous ACK scheduling, serialized transport writes, three-future-chunk Band buffering, overlap rejection, and barriers unchanged.

- [ ] **Step 4: Verify GREEN and commit**

Run: `make test-swift && make test-rpk && git diff --check`
Expected: all suites pass.

```bash
git add packages/BlueBandKit apps/ios apps/band
git commit -m "feat: reduce Band map transfer round trips"
```

### Task 2: Familiar dark map hierarchy and payload admission

**Files:**
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/SnapshotMapPolicy.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/SnapshotMapPolicyTests.swift`
- Modify: `apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift`
- Modify: `apps/ios/Tests/VietmapSnapshotRendererTests.swift`
- Modify: `apps/ios/Tests/Fixtures/vietmap-light-style-layers.json`

**Interfaces:**
- Produces: `SnapshotPayloadAdmission.preferredMaximumBytes == 5_120`.
- Produces: exact layer predicates and `VietmapDarkStyle.colorHex(id:type:)` mappings for buildings, land use, road hierarchy, casing, labels, and familiar-detail POIs.

- [ ] **Step 1: Write failing layer/palette tests**

Assert the familiar profile retains `poi_hospital`, `poi_school`, `transit_station`, and `parking` only at zoom 16–17; degraded profiles reject them. Assert distinct colors for building, residential, hospital/school, park, water, casing, minor, secondary, and primary roads. Assert preferred admission is 5,120 bytes.

```swift
XCTAssertTrue(VietmapStyleLayerPolicy.keeps(id: "poi_hospital", type: "symbol", zoom: 17, profile: .colors16Labels))
XCTAssertFalse(VietmapStyleLayerPolicy.keeps(id: "poi_hospital", type: "symbol", zoom: 17, profile: .colors16NoLowPriorityLabels))
XCTAssertNotEqual(VietmapDarkStyle.colorHex(id: "building", type: "fill"), VietmapDarkStyle.colorHex(id: "landuse_residential", type: "fill"))
XCTAssertEqual(SnapshotPayloadAdmission.preferredMaximumBytes, 5_120)
```

- [ ] **Step 2: Verify RED**

Run: `make test-swift`
Expected: POIs are rejected, several fills share a color, and preferred admission is 4,096.

- [ ] **Step 3: Implement minimal style policy**

Extend only the existing predicates and color mapper. Keep road widths and provider layout expressions intact. Map casing darker than its corresponding road fill; do not add shadows, 3D layers, a new provider request, or custom POI data.

- [ ] **Step 4: Verify GREEN and commit**

Run: `make test-swift && git diff --check`

```bash
git add packages/BlueBandKit apps/ios
git commit -m "feat: restore familiar dark map context"
```

### Task 3: Flat blue route and urban refresh policy

**Files:**
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/SnapshotMapPolicy.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/SnapshotMapPolicyTests.swift`
- Modify: `apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift`
- Modify: `apps/ios/Tests/VietmapSnapshotRendererTests.swift`
- Modify: `apps/ios/App/AppModel.swift`

**Interfaces:**
- Produces: `SnapshotRefreshContext(marker:safeViewport:distanceFromAnchorMeters:secondsSinceLastRefresh:nextManeuverVisible:rerouteSucceeded:)`.
- Produces: thresholds `minimumRefreshSeconds = 12`, `movementMeters = 175`, and safe viewport `ScreenRect(x: 36, y: 144, width: 140, height: 320)`.

- [ ] **Step 1: Write failing policy and route-color tests**

Cover movement below/at 175 m, elapsed time below/at 12 seconds, marker outside safe bounds, next maneuver outside the viewport, and reroute bypass. Assert upcoming route `#2F6BFF`, traveled slate-blue, no route halo command, and unchanged provider road hierarchy.

- [ ] **Step 2: Verify RED**

Run: `make test-swift`
Expected: old maneuver-change policy and cyan route fail the new assertions.

- [ ] **Step 3: Implement policy and AppModel state**

Track the confirmed snapshot anchor and refresh start time in `AppModel`. Compute movement with the existing meter helper. Schedule ordinary refresh only when at least 12 seconds elapsed and movement/safe-area/maneuver visibility requires it. Let successful reroute bypass the interval. Continue coalescing newest refresh and keep HUD-only instruction changes on `nav.update`.

- [ ] **Step 4: Verify GREEN and commit**

Run: `make test-swift && git diff --check`

```bash
git add packages/BlueBandKit apps/ios
git commit -m "feat: tune urban snapshot refresh policy"
```

### Task 4: Pill-safe HUD and high-contrast position marker

**Files:**
- Modify: `apps/band/scripts/generate-icon.mjs`
- Modify: `apps/band/src/pages/index/index.ux`
- Regenerate: `apps/band/src/common/marker-0.png` through `marker-7.png`
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `apps/band/test/envelope-page.test.mjs`
- Modify: `apps/band/scripts/verify-rpk.mjs`

**Interfaces:**
- Produces: eight indexed 38×44 marker assets with `#66FF7A` fill, dark outline, and transparent edge pixels.
- Produces: HUD content inside x 32–180/y 16–92 and marker-center clamp x 30–182/y 130–478.

- [ ] **Step 1: Write failing resource/layout tests**

Assert marker dimensions 38×44, indexed PNG type, transparent borders, presence of bright green and dark nontransparent palette entries, centered HUD CSS bounds, and clamped marker positions for all four viewport extremes.

- [ ] **Step 2: Verify RED**

Run: `make test-rpk`
Expected: current 26×32 marker, cyan palette, edge clamp, and HUD positions fail.

- [ ] **Step 3: Generate and place minimal assets**

Resize the existing eight deterministic polygons; draw the outer polygon dark and the inner polygon green. Update CSS to a 38×44 marker and move maneuver/distance/street/status inside the approved content rectangle. Update `navMarkerStyle` using center clamps before subtracting marker half-size.

- [ ] **Step 4: Verify GREEN and commit**

Run: `make test-rpk && git diff --check`

```bash
git add apps/band
git commit -m "feat: keep Band guidance inside pill safe area"
```

### Task 5: Versioning, diagnostics, and handoff

**Files:**
- Modify: `apps/ios/project.yml`
- Modify: `apps/ios/App/BlueBandMapApp.swift`
- Modify: `tools/ios/test-project-metadata.sh`
- Modify: `apps/band/src/manifest.json`
- Modify: `apps/band/package.json`
- Modify: `apps/band/package-lock.json`
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `apps/band/scripts/verify-rpk.mjs`
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `CHANGELOG.md`
- Create: `docs/testing/handoffs/familiar-dark-map-safe-area-performance.md`

**Interfaces:**
- Produces: IPA `0.4.0 (14)`, RPK `0.5.0 (14)`, and an explicit IPA/RPK/manual-test handoff.

- [ ] **Step 1: Update version assertions first and verify RED**

Set tests/scripts to expect the new versions, then run `make test-ios-metadata && make test-rpk`; expect old metadata to fail.

- [ ] **Step 2: Update product metadata and documentation**

Apply the exact versions above. Document which changes affect IPA, which affect RPK, the 4,723-byte/51,638-ms baseline, and manual tests for clipping, detail familiarity, marker contrast, 10/30/50 km/h cadence, reroute, failures, and 30-minute stability. Add artifact byte counts and checksums only in Task 6 after the files exist.

- [ ] **Step 3: Verify and commit**

Run: `make test-ios-metadata && make test-rpk && git diff --check`

```bash
git add apps/ios apps/band tools/ios CHANGELOG.md docs/testing/handoffs
git commit -m "chore: version familiar Band map release"
```

### Task 6: Final verification and artifacts

**Files:**
- Update: `docs/testing/handoffs/familiar-dark-map-safe-area-performance.md`
- Produce ignored artifact: `artifacts/familiar-dark-map/ipa-0.4.0/BlueBandMap-unsigned.ipa`
- Produce ignored artifact: `artifacts/familiar-dark-map/rpk/dev.lordierclaw.bluebandmap.band.debug.0.5.0.rpk`

- [ ] **Step 1: Run canonical local verification**

Run: `make test && make lint && git diff --check && git status --short`
Expected: all tests pass and only intentional handoff edits remain.

- [ ] **Step 2: Request one final correctness review**

Review only the completed diff for payload/envelope trust boundaries, refresh lifecycle, pill clipping, route/marker contrast, versioning, and missing tests. Fix every Critical/Important finding with a failing test first.

- [ ] **Step 3: Push `main` and wait for GitHub Actions**

Push the verified commits. Require successful repository, Band, and iOS workflows. The iOS workflow must pass simulator tests, unsigned arm64 device build/inspection, and IPA upload.

- [ ] **Step 4: Download and inspect final artifacts**

Download the IPA only from its successful GitHub Actions run. Copy the Make-built RPK. Record exact byte counts, SHA-256 hashes, source commits, CI URLs, bundle/package IDs, versions, architecture, signing state, and the hardware-not-yet-verified boundary in the handoff.

- [ ] **Step 5: Commit final evidence and verify clean state**

```bash
git add docs/testing/handoffs/familiar-dark-map-safe-area-performance.md CHANGELOG.md
git commit -m "docs: hand off familiar Band map artifacts"
git push origin main
```

Run: `make lint && git diff --check && git status --short --branch`
Expected: `main` matches `origin/main` with a clean tracked worktree.
