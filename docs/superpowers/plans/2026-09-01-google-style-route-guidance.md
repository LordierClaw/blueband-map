# Google-Style Band Route Guidance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a fixed lower-center navigation marker, the complete remaining route, the next Google-style maneuver, and a contour-attached off-screen destination indicator on Smart Band 10.

**Architecture:** Keep the snapshot camera as the single projection authority and remove route-only translation. Split guidance into the route section currently being traversed, its endpoint as the next-action location, and the following instruction as the header action; draw the active route from the matched position through the route end. Reuse the destination coordinate fields as the edge-chevron tip and derive its eight-way asset/offset on the Band without adding transport fields.

**Tech Stack:** Swift/XCTest, Vietmap `MGLMapSnapshotter`, Core Graphics, Vela UX JavaScript, indexed PNG generation, Node test runner, Make/Docker, GitHub Actions.

---

### Task 1: Select the next action and retain the complete active route

**Files:**
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/GuidancePresentation.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/GuidancePresentationTests.swift`
- Modify: `apps/ios/App/AppModel.swift`

- [x] **Step 1: Add failing next-action and full-route tests**

Add a Vietmap-shaped route whose first interval is straight `0...1` and whose next instruction is right `1...1`. Assert that progress halfway through segment zero produces `right`, targets route point one, and reports the fractional remaining geometry distance. Also change the overlay assertion from the current maneuver endpoint to the final route point:

```swift
XCTAssertEqual(selection.instruction.maneuver, .right)
XCTAssertEqual(selection.maneuverPointIndex, 1)
XCTAssertEqual(selection.distanceMeters, 1, accuracy: 0.2)
XCTAssertEqual(geometry.active.first, matched)
XCTAssertEqual(geometry.active.last, route.points.last)
```

- [x] **Step 2: Run the Swift suite and verify RED**

Run: `make test-swift`

Expected: compilation fails because `GuidanceSelection` has no `maneuverPointIndex`, and the old active geometry ends at the selected instruction.

- [x] **Step 3: Implement the minimal guidance split**

Add the action point to `GuidanceSelection`:

```swift
public let maneuverPointIndex: Int
```

In `GuidancePresentationPolicy.select`, identify the first instruction section whose upper bound is strictly ahead of the matched segment. Use that section's upper bound as `maneuverPointIndex`, but expose the following instruction as the header action. Keep the accuracy parameter for API compatibility without using it to skip a maneuver before the matched geometry passes its boundary:

```swift
let index = route.instructions.firstIndex {
    $0.interval.upperBound > progress.matchedSegmentIndex
} ?? route.instructions.count - 1
let maneuverPointIndex = min(route.instructions[index].interval.upperBound, route.points.count - 1)
let actionIndex = min(index + 1, route.instructions.count - 1)
return GuidanceSelection(
    instructionIndex: actionIndex,
    instruction: route.instructions[actionIndex],
    maneuverPointIndex: maneuverPointIndex,
    distanceMeters: remaining
)
```

Change `RouteOverlayGeometry.make` so active geometry is the complete remaining route and the maneuver point is no longer inferred from the displayed instruction:

```swift
let active = [matched] + Array(route.points.dropFirst(segment + 1))
let maneuver = min(selection.maneuverPointIndex, route.points.count - 1)
```

Update `forwardPoint` and `AppModel.publish` to use `selection.maneuverPointIndex` for the camera/maneuver ring while continuing to use `selection.instruction` for the header.

- [x] **Step 4: Run Swift tests and verify GREEN**

Run: `make test-swift`

Expected: all Swift package tests pass, including the new Vietmap boundary case and full remaining route assertion.

### Task 2: Make the camera projection authoritative

**Files:**
- Modify: `apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift`
- Modify: `apps/ios/Tests/VietmapSnapshotRendererTests.swift`

- [x] **Step 1: Add a failing no-translation renderer test**

Replace the translation-helper test with an assertion that the configuration itself projects the matched location to the fixed anchor and that route drawing exposes no translation helper:

```swift
let configuration = try VietmapSnapshotConfiguration.make(request)
let anchor = configuration.point(for: request.matchedPosition)
XCTAssertEqual(anchor.x, 106, accuracy: 0.5)
XCTAssertEqual(anchor.y, 374, accuracy: 0.5)
```

The source inspection assertion must reject `VietmapRouteOverlay.translated` and per-path `offset` parameters.

- [x] **Step 2: Run the iOS source/metadata checks and verify RED**

Run:

```bash
bash tools/ios/test-project-metadata.sh
rg -n 'translated|offset:' apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift
```

Expected: metadata passes, while the source check finds the route-only translation.

- [x] **Step 3: Remove overlay-only translation**

Project and draw every coordinate directly with `overlay.point(for:)`, including the maneuver ring:

```swift
drawPath(request.overlayGeometry.active, color: activeColor, width: 5, overlay: overlay)
let point = overlay.point(for: coordinate(request.nextManeuver))
```

Delete `fixedAnchor`, `translated`, and the `offset` parameter. The camera center produced by `VietmapSnapshotConfiguration.make` remains responsible for placing the matched point at `(106,374)`.

- [x] **Step 4: Run Swift and iOS syntax checks and verify GREEN**

Run `make test-swift`, `bash tools/ios/test-project-metadata.sh`, and parse the modified iOS Swift files with the available Swift frontend command used by this repository.

Expected: tests and syntax checks pass, and `rg -n 'translated|offset:' apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift` returns no route-translation matches.

### Task 3: Replace the pinched marker and inset destination ring

**Files:**
- Modify: `apps/band/scripts/generate-icon.mjs`
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `apps/band/scripts/verify-rpk.mjs`
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `apps/band/test/envelope-page.test.mjs`

- [x] **Step 1: Add failing bitmap and page tests**

Assert the marker remains 46×54 and identical in all eight filenames, its green bounding box is at least 28 px wide, and its visible bounds are symmetric around x=23. Assert eight `destination-edge-0.png` through `destination-edge-7.png` resources exist and each outward tip reaches the corresponding edge/corner of its 20×20 bitmap.

Add page tests for deterministic direction selection:

```javascript
assert.equal(page.destinationDirection(106, 374, 106, 22), 0)
assert.equal(page.destinationDirection(106, 374, 190, 290), 1)
assert.equal(page.destinationDirection(106, 374, 199, 260), 1)
assert.equal(page.destinationDirection(106, 374, 22, 374), 6)
```

For an edge update at `(199,260)`, assert `navDestinationPath === "/common/destination-edge-1.png"` and that the north-east bitmap is positioned with its tip at `(199,260)`.

- [x] **Step 2: Run RPK tests and verify RED**

Run: `make test-rpk`

Expected: the marker green width assertion fails, the directional destination resources are missing, and the page still selects `destination-edge.png`.

- [x] **Step 3: Generate the wider marker and eight chevrons**

Keep the 46×54 marker canvas but widen its fill:

```javascript
fillPolygon(marker, 46, 54, [[23, 3], [42, 47], [4, 47]], 1)
fillPolygon(marker, 46, 54, [[23, 7], [37, 43], [9, 43]], 2)
```

Generate one 20×20 outward chevron and rotate it in 45-degree steps around `(10,10)` into `destination-edge-0.png` through `destination-edge-7.png`. Use only transparent, dark-outline, amber-fill, and pale-tip palette entries so the assets remain firmware-safe indexed PNGs.

- [x] **Step 4: Select the chevron from the existing destination coordinates**

Add one Band helper with up as bucket zero and clockwise buckets:

```javascript
destinationDirection(markerX, markerY, destinationX, destinationY) {
  var angle = Math.atan2(destinationX - markerX, markerY - destinationY)
  return (Math.round(angle / (Math.PI / 4)) + 8) % 8
}
```

Use it in both live and staged-preview paths:

```javascript
this.navDestinationPath = preview.destinationMode === "visible"
  ? "/common/destination-pin.png"
  : "/common/destination-edge-" + this.destinationDirection(106, 374, preview.destinationX, preview.destinationY) + ".png"
```

For `edge`, treat `destinationX/Y` as the tip coordinate and position the bitmap using its direction-specific tip offset. For `visible`, keep the existing center-coordinate pin behavior. Do not add envelope fields.

- [x] **Step 5: Run RPK tests and verify GREEN**

Run: `make test-rpk`

Expected: all resource, bundle, preview, and live navigation tests pass.

### Task 4: Component versions, full verification, and handoff

**Files:**
- Modify only if iOS product code changed: `apps/ios/project.yml`, `apps/ios/App/BlueBandMapApp.swift`, `tools/ios/test-project-metadata.sh`
- Modify only if RPK product code/resources changed: `apps/band/package.json`, `apps/band/package-lock.json`, `apps/band/src/manifest.json`, `apps/band/scripts/verify-rpk.mjs`, `apps/band/test/bundle-contract.test.mjs`
- Modify: `docs/testing/handoffs/hybrid-heading-up-guidance.md`

- [x] **Step 1: Apply component-only version bumps after confirming the diff**

Because this plan changes both iOS navigation code and RPK code/resources, update IPA `0.5.3 (19)` to `0.5.4 (20)` and RPK `0.6.2 (17)` to `0.6.3 (18)`. If implementation produces no diff for a component, leave that component unchanged instead.

- [x] **Step 2: Update the manual hardware checks**

Document these acceptance points: fixed lower-center symmetric marker, route continuing beyond the next maneuver, correct next-turn glyph/distance/street, eight-direction contour chevron, in-view destination pin, and no regression in refresh/error behavior.

- [x] **Step 3: Run the complete canonical gate**

Run:

```bash
make clean && make bootstrap && make test && make lint && scripts/verify-no-secrets.sh && git diff --check
```

Expected: all commands exit zero. This is deterministic/CI evidence, not Smart Band hardware acceptance.

- [ ] **Step 4: Commit and push directly on main**

```bash
git add apps packages tools docs
git commit -m "fix: show complete google-style route guidance"
git push origin main
```

- [ ] **Step 5: Wait for CI and replace the handoff atomically**

Wait for Repository, Swift, Band, and iOS workflows for the pushed commit. Download the IPA only from the successful iOS workflow and use the successful Band artifact RPK. Run `scripts/prepare-poc-handoff.sh --poc handoff ...`, then verify `SHA256SUMS`, embedded IPA/RPK versions, exactly one current IPA and one current RPK, no superseded artifact, and `HEAD == origin/main` with a clean worktree.
