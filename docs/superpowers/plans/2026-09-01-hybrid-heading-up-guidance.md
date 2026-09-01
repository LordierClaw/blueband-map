# Hybrid Heading-Up Guidance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver continuous road-snapped route guidance, useful maneuvers, stable heading-up snapshots, curved-screen-safe overlays, and destination direction on Xiaomi Smart Band 10.

**Architecture:** Keep `RouteProgressTracker` and reroute behavior authoritative. Add small presentation policies in `BlueBandMapCore`, feed their output through the existing snapshot and `nav.update` paths, and use one calibrated capsule model in Swift and equivalent tested constants in the RPK. The initial contour is conservatively estimated from the supplied Band photographs and remains a single calibration seam.

**Tech Stack:** Swift 5.10, CoreLocation, VietMap snapshot SDK, Vela UX/ES5 JavaScript, Node test runner, Make/Docker, GitHub Actions for IPA.

---

### Task 1: Presentation policies without navigation behavior changes

**Files:**
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/VietmapRoute.swift`
- Create: `packages/BlueBandKit/Sources/BlueBandMapCore/GuidancePresentation.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/VietmapRouteTests.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/GuidancePresentationTests.swift`

- [ ] Add failing tests proving fractional match metadata, exact matched location, useful-instruction skipping at `max(8, min(20, accuracy))`, route-tangent fallback, two-fix course activation, three-fix fallback, and 30-degree/12-second refresh hysteresis.
- [ ] Run `make test-swift SWIFT_TEST_ARGS='--filter GuidancePresentationTests'` and confirm failures are caused by missing APIs.
- [ ] Add `matchedSegmentIndex` and `matchedFraction` to `RouteProgress` while preserving the existing segment search, monotonic `pointIndex`, 40 m threshold, and three-fix reroute rule.
- [ ] Implement `GuidancePresentationPolicy` and `GuidanceBearingPolicy` as value types with no dependency or timer ownership.
- [ ] Run the targeted tests, then `make test-swift`.

### Task 2: Continuous overlay and curved-screen destination projection

**Files:**
- Modify: `apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift`
- Modify: `apps/ios/Tests/VietmapSnapshotRendererTests.swift`

- [ ] Add failing tests proving traveled route ends and active route begins at `matchedPosition`, post-turn context is bounded, and destination projection returns visible/edge/hidden coordinates within the calibrated contour under cardinal and diagonal bearings.
- [ ] Run the iOS test target through the repository's GitHub Actions workflow and confirm the new tests fail before implementation.
- [ ] Extend `VietmapSnapshotRequest` with matched segment/fraction and selected maneuver; split overlay commands at the fractional match and use flat dark-blue active geometry without a border.
- [ ] Add the minimal `BandDisplaySafeMask` capsule model: 212×520, 12 px conservative physical inset estimated from the supplied photos, independent top/bottom cap fields, and resource-specific erosion. Keep all tunable values in this one model.
- [ ] Implement destination ray intersection against the resource-safe contour and retain confirmed-snapshot coordinates until atomic publication.
- [ ] Re-run the iOS workflow tests and record the run URL.

### Task 3: Integrate useful guidance and hybrid heading in AppModel

**Files:**
- Modify: `apps/ios/App/AppModel.swift`
- Modify: `apps/ios/Tests/AppModelPickerTests.swift` or create a focused `apps/ios/Tests/NavigationPresentationTests.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/NavigationUpdate.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/NavigationUpdateTests.swift`

- [ ] Add failing portable tests for atomic `destinationMode/destinationX/destinationY` validation and JSON emission; add iOS policy tests for selected maneuver and bearing inputs.
- [ ] Run the affected portable tests and confirm the expected failures.
- [ ] Extend `NavigationUpdate` with bounded destination presentation fields while leaving topic, envelope, Xiaomi transport bytes, and ACK behavior unchanged.
- [ ] In `AppModel`, compute presentation after each accepted tracker update, use route bearing while stationary, activate course only after two eligible fixes, fall back after three ineligible fixes, and schedule bearing refresh only at 30 degrees and 12 seconds.
- [ ] Use the selected instruction consistently for preview, HUD, distance, next-maneuver visibility, and snapshot request. Preserve reroute conditions and refresh coalescing.
- [ ] Add sanitized debug fields for accuracy/speed/course, segment/fraction, selected instruction, bearing source/delta/reason, and destination mode/center.
- [ ] Run `make test-swift` and the iOS GitHub Actions test workflow.

### Task 4: RPK overlays, larger resources, and photo-estimated safe layout

**Files:**
- Modify: `apps/band/scripts/generate-icon.mjs`
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `apps/band/test/envelope-page.test.mjs`
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `apps/band/src/manifest.json`

- [ ] Add failing RPK tests for complete destination fields, hidden zero coordinates, 46×54 user markers, 44×56 maneuver display, 20×24 destination pin, 20×20 edge ring, curved clamp output, and inset HUD bounds.
- [ ] Run `make test-rpk` and confirm the new assertions fail for the old resources/layout.
- [ ] Generate larger indexed marker resources and amber destination resources with transparent margins; do not add a graphics dependency.
- [ ] Add destination overlay below the user marker, render visible pin/edge ring atomically, and use one ES5 curved clamp matching the Swift calibration values.
- [ ] Generate one indexed 212×520 calibration screen with 16 directional probes and 6/10/14/18 px candidate contours; expose it from the existing diagnostics view and dismiss it by tapping the screen.
- [ ] Move the HUD inward based on the observed clipping in the supplied photographs and enlarge the arrow while keeping distance and street readable.
- [ ] Bump RPK from 0.5.0(14) to 0.6.0(15), update visible version strings, and run `make test-rpk`.

### Task 5: Release metadata, verification, review, and IPA workflow

**Files:**
- Modify: `apps/ios/project.yml`
- Modify: `CHANGELOG.md`
- Modify: `docs/testing/handoffs/live-route-card.md` or create a focused hardware handoff under `docs/testing/handoffs/`

- [ ] Bump IPA from 0.4.1(15) to 0.5.0(16) because Swift/iOS navigation logic changes.
- [ ] Document the estimated contour, its photographic evidence boundary, exact manual calibration procedure, and the outdoor 0–50 km/h test matrix.
- [ ] Run `make clean && make bootstrap && make test && make lint && scripts/verify-no-secrets.sh` and `git diff --check`.
- [ ] Request one final read-only review agent; resolve only verified findings and rerun affected tests.
- [ ] Commit and push `main`, trigger the existing GitHub Actions IPA workflow, wait for success, download the unsigned IPA artifact, and verify it with `scripts/verify-ios-artifact.sh`.
- [ ] Report code changes, IPA/RPK impact and versions, workflow URL, artifact path/hash, automated evidence, hardware limitations, and a Vietnamese manual test plan.
