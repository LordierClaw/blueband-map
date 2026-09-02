# Band Navigation Visual Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the route locally with the fixed marker, replace both marker presentations with smaller safe assets, and remove the guidance background.

**Architecture:** Keep route geometry and the existing RPK image-overlay path. Correct route-source camera bearing in `GuidancePresentationPolicy`, calculate the destination edge point with the real resource footprint, and regenerate deterministic RGBA assets through the existing script.

**Tech Stack:** Swift 5.10/XCTest, Vela Quick App UX, Node.js test runner, AIoT Toolkit 2.0.5, Docker/Make, GitHub Actions.

---

### Task 1: Make route-source camera bearing follow the local tangent

**Files:**
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/GuidancePresentationTests.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/GuidancePresentation.swift`

- [ ] **Step 1: Write the failing bend regression**

Add a route whose selected maneuver is east of the user but whose immediate segment goes north. Call `stationaryBearing(route:progress:selection:)` and assert `0°`, proving the camera uses the local segment rather than the diagonal chord to the maneuver.

- [ ] **Step 2: Verify RED**

Run `make test-swift SWIFT_TEST_ARGS='--filter GuidancePresentationTests/testStationaryBearingUsesImmediateTangentBeforeLaterBend'`.

Expected: FAIL because the current selection-aware forward point produces a diagonal bearing.

- [ ] **Step 3: Use the immediate route point**

In `stationaryBearing`, keep the public signature but mark `selection` unused and call:

```swift
guard let forward = forwardPoint(route: route, progress: progress, selection: nil) else { return 0 }
```

- [ ] **Step 4: Verify GREEN**

Run the same filtered test. Expected: one test passes.

### Task 2: Keep the complete destination chevron inside the Band mask

**Files:**
- Modify: `apps/ios/App/AppModel.swift`
- Modify: `apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift`
- Modify: `apps/ios/Tests/VietmapSnapshotRendererTests.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/BandDisplaySafeMask.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/BandDisplaySafeMaskTests.swift`

- [ ] **Step 1: Write the failing footprint test**

Call a new `mask.destinationEdgePoint(from:toward:)` contract before it exists. Assert its result satisfies `mask.contains(center:resourceWidth:24,resourceHeight:24)` and lies inward from the old physical `1×1` contour tip.

- [ ] **Step 2: Verify RED**

Run `make test-swift SWIFT_TEST_ARGS='--filter BandDisplaySafeMaskTests/testDestinationEdgePointKeepsTheFull24PixelChevronInsideTheVisualMask'`.

Expected: compilation/test failure because the helper is absent.

- [ ] **Step 3: Implement the footprint at the source**

Add to `BandDisplaySafeMask`:

```swift
public func destinationEdgePoint(from origin: ScreenPoint, toward target: ScreenPoint) -> ScreenPoint {
    edgePoint(from: origin, toward: target, resourceWidth: 24, resourceHeight: 24)
}
```

Use it in `destinationPresentation` instead of `mask.withoutVisualMargin.edgePoint(...1,1)`. Change snapshot marker containment checks from `46×54` to `30×38`; update their existing assertions without altering anchor `(106,374)`.

- [ ] **Step 4: Verify GREEN**

Run `make test-swift`. Expected: all portable Swift and app-source Swift tests available in the container pass.

### Task 3: Generate the approved marker and destination assets

**Files:**
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `apps/band/test/envelope-page.test.mjs`
- Modify: `apps/band/scripts/generate-icon.mjs`
- Modify: `apps/band/scripts/verify-rpk.mjs`
- Modify: `apps/band/src/common/render-protocol.js`
- Replace: `apps/band/src/common/marker-{0...7}.png`
- Replace: `apps/band/src/common/destination-edge-{0...7}.png`

- [ ] **Step 1: Write failing asset contracts**

Require marker PNGs to be `30×38` RGBA, contain only transparent pixels and `#27c76f`, mirror around `x=14.5`, have contiguous rows, widen from the top to a 28-pixel two-row shoulder, then narrow to the bottom. Require edge chevrons to be `24×24` RGBA and fully contained inside their bitmap.

- [ ] **Step 2: Verify RED**

Run `make test-rpk`. Expected: marker and destination dimension/shape assertions fail against the old assets.

- [ ] **Step 3: Generate minimal deterministic assets**

Replace the nested triangle generator with a 30×38 RGBA row-span union: top tip at rows 1–25 widening to 28 pixels, lower opposed triangle at rows 26–36 narrowing from 28 pixels, using `[39,199,111,255]`. Generate eight byte-identical marker files.

Generate each destination chevron on a 24×24 RGBA bitmap around centre `(12,12)` using contained points `[(4,15),(12,3),(20,15)]`, rotated offline. Preserve the dark outline and amber inner stroke.

Update package verification to expect marker `30×38` and destination `24×24`.

- [ ] **Step 4: Verify generated assets**

Run `make test-rpk`. Expected: all Band tests pass and exactly one RPK builds.

### Task 4: Apply the marker anchors and header layout

**Files:**
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `apps/band/test/envelope-page.test.mjs`
- Modify: `apps/band/src/pages/index/index.ux`

- [ ] **Step 1: Write failing layout contracts**

Require all self-marker styles to equal `left:91px;top:355px;`, edge styles to use a 12-pixel centre offset with `24×24`, and require no `nav-panel` elements/classes. Require arrow `(32,28)`, distance `(78,26)`, street `(72,60)`, and status `(72,80)`.

- [ ] **Step 2: Verify RED**

Run `make test-rpk`. Expected: old marker offsets, panel elements, and header positions fail.

- [ ] **Step 3: Apply the exact approved layout**

Change the three marker assignments and marker CSS to `30×38`; update `safeMaskContains` marker dimensions to `30×38`; centre edge assets with `x-12/y-12`; remove both panel divs and CSS rules; apply the four approved header positions. Do not change street overflow behavior.

- [ ] **Step 4: Verify GREEN**

Run `make test-rpk`. Expected: all Band tests and packaged-asset checks pass.

### Task 5: Version, verify, and hand off both changed components

**Files:**
- Modify: `apps/ios/project.yml`
- Modify: `apps/ios/App/BlueBandMapApp.swift`
- Modify: `tools/ios/test-project-metadata.sh`
- Modify: `apps/band/package.json`
- Modify: `apps/band/package-lock.json`
- Modify: `apps/band/src/manifest.json`
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `apps/band/scripts/verify-rpk.mjs`
- Replace ignored handoff files in: `artifacts/handoff/`

- [ ] **Step 1: Bump only changed products**

Set iOS to `MARKETING_VERSION 0.5.6`, `CURRENT_PROJECT_VERSION 22`, and `BlueBandProduct.version 0.5.6`. Set RPK to `0.6.8 (23)` in source, lock file, labels, tests, and package verifier.

- [ ] **Step 2: Run canonical verification**

Run:

```bash
make test
make lint
git diff --check
```

Expected: zero failures and zero diff errors.

- [ ] **Step 3: Commit and push `main`**

Commit the implementation and push `main`. The push must trigger `.github/workflows/ios-checks.yml` because iOS/Core files changed.

- [ ] **Step 4: Obtain the IPA from GitHub Actions**

Wait for the pushed commit's `iOS checks` workflow to pass. Download `blueband-map-ios-<commit>` with `gh run download`; never build the IPA locally.

- [ ] **Step 5: Replace handoff artifacts**

Delete the superseded IPA/RPK from `artifacts/handoff`, copy the GitHub-Actions IPA and verified `0.6.8` RPK, regenerate `SHA256SUMS`, and update `HANDOFF.md` with the changes and basic manual test covering AstroBox installation, local route alignment, both markers, and the background-free header.

- [ ] **Step 6: Final evidence**

Confirm `HEAD == origin/main`, the tracked worktree is clean, handoff checksums pass, the RPK manifest is `0.6.8 (23)` with `minAPILevel:1`, and report CI/package verification separately from physical Band acceptance.
