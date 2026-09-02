# Live Background Navigation Guidance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct live turn guidance, remove the maneuver dot and echo UI, and refresh/rotate the accepted Band map from background GPS with a hardware target below five seconds.

**Architecture:** Keep the current Vietmap Route v4, local route matcher, iOS `MGLMapSnapshotter`, bounded JPEG encoder, atomic scene publisher, and fixed Band overlays. Resolve guidance from cumulative route distance, coalesce one newest snapshot request, and use native Core Location/Core Bluetooth background modes only during an explicit navigation session. Preserve every existing application and Xiaomi wire contract.

**Tech Stack:** Swift 5.10/SwiftPM, Core Location, Core Bluetooth, VietMap iOS SDK, CoreGraphics/ImageIO, Vela UX/ES5 JavaScript, Node 20 in Docker, XCTest, GitHub Actions/Xcode.

**Spec:** `docs/superpowers/specs/2026-09-02-live-background-navigation-guidance-design.md`

---

### Task 1: Provider-correct guidance selection and street normalization

**Files:**
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/GuidancePresentationTests.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/VietmapRouteTests.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/GuidancePresentation.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/VietmapRoute.swift`

- [ ] **Step 1: Add failing regression tests**

Add a route fixture matching the hardware log's zero-length/overlapping intervals. At route start assert that the current `straight / 37 m` step produces the following `right / Yên Bình` action and approximately `37 m`, then advances monotonically to the following action after cumulative progress crosses 37 m. Add a parser assertion that `"  Yên Bình\n"` becomes `"Yên Bình"`.

- [ ] **Step 2: Verify RED**

Run: `make test-swift`

Expected: the overlapping-interval selection and whitespace assertions fail against the current interval-only/raw-string behavior.

- [ ] **Step 3: Implement the minimum shared fix**

In `GuidancePresentationPolicy.select`, compute geometric distance traveled to `matchedSegmentIndex/matchedFraction`, scale it to the sum of nonnegative provider instruction distances, choose the current cumulative-distance bucket, and present the following instruction with the current bucket's remaining distance. Retain the current interval selector only when total geometry or provider instruction distance is zero. Trim `streetName` in `RouteInstruction.init` with `.whitespacesAndNewlines`.

- [ ] **Step 4: Verify GREEN and commit**

Run: `make test-swift && git diff --check`

```bash
git add packages/BlueBandKit
git commit -m "fix: align live guidance with Vietmap steps"
```

### Task 2: Remove the turn dot and make refresh heading-live

**Files:**
- Modify: `apps/ios/Tests/VietmapSnapshotRendererTests.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/SnapshotMapPolicyTests.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/GuidancePresentationTests.swift`
- Modify: `apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/SnapshotMapPolicy.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandMapCore/GuidancePresentation.swift`
- Modify: `apps/ios/App/AppModel.swift`

- [ ] **Step 1: Add failing renderer and cadence tests**

Assert overlay commands are exactly `subdued`, `traveled`, `context`, `activeCasing`, and `active`, with no `maneuver`. Assert snapshot refresh requires one elapsed second and one metre of matched movement, and bearing refresh accepts a 30-degree change after one second but not before it.

- [ ] **Step 2: Verify RED**

Run: `make test-swift`

Expected: current tests still report the maneuver command and 12-second/175-metre thresholds.

- [ ] **Step 3: Implement coalesced live refresh**

Delete the explicit maneuver ellipse. Set the existing refresh gates to `1.0` second and `1.0` metre and the bearing gate to one second. Keep `scheduleRefresh` as a single active task with one replaceable pending request. Add `map.refresh.scheduled` and `band.displayed` diagnostics containing reason, selected bearing, GPS-fix age, and publication duration; do not add fields to protocol messages.

- [ ] **Step 4: Verify GREEN and commit**

Run: `make test-swift && git diff --check`

```bash
git add apps/ios packages/BlueBandKit
git commit -m "fix: refresh heading-up maps from live progress"
```

### Task 3: Own background navigation only while active

**Files:**
- Modify: `tools/ios/test-project-metadata.sh`
- Modify: `scripts/verify-ios-artifact.sh`
- Modify: `apps/ios/project.yml`
- Modify: `apps/ios/Adapters/Location/ForegroundLocationClient.swift`
- Modify: `apps/ios/App/ContentView.swift`
- Modify: `docs/adr/0004-foreground-session-ownership.md`
- Create: `docs/adr/0013-background-navigation-session.md`
- Modify: `README.md`
- Modify: `docs/security/threat-model.md`

- [ ] **Step 1: Change metadata checks first**

Require generated app metadata to contain `UIBackgroundModes = [location, bluetooth-central]`, require background-location usage text, and remove assertions that the app must remain foreground-only. Add source assertions that the navigation location stream enables `allowsBackgroundLocationUpdates` and owns a `CLBackgroundActivitySession`, while `stop()` disables and invalidates both.

- [ ] **Step 2: Verify RED**

Run: `make test-ios-metadata`

Expected: current project metadata lacks both background modes and the active-session lifecycle.

- [ ] **Step 3: Implement native session lifecycle**

Declare only `location` and `bluetooth-central`. In `locations()`, create `CLBackgroundActivitySession`, enable `allowsBackgroundLocationUpdates` and the visible background indicator before starting standard navigation updates. In `stop()`, disable background updates and invalidate the session. Do not enable background behavior in `startPrewarming()`.

- [ ] **Step 4: Supersede the foreground-only ADR and verify**

Record that explicit start/stop navigation owns background location/BLE, Mi Fitness must remain disconnected, force-quit/relaunch is outside this release, and real-device acceptance is required.

Run: `make test-ios-metadata && git diff --check`

```bash
git add apps/ios tools/ios scripts docs README.md
git commit -m "feat: keep active navigation alive after iPhone lock"
```

### Task 4: Keep live guidance visible and remove the echo screen

**Files:**
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `apps/band/test/envelope-page.test.mjs`
- Modify: `apps/band/src/pages/index/index.ux`

- [ ] **Step 1: Add failing Band behavior tests**

Assert the template has no diagnostics block, echo button, clear button, or visible log; connected idle state says `CHỜ LỆNH TỪ IPHONE`. Publish an old scene, prepare a refresh preview, deliver a newer `nav.update` for the confirmed scene, and assert the newer maneuver/street/distance become visible immediately while the refresh remains pending.

- [ ] **Step 2: Verify RED**

Run: `make test-rpk`

Expected: visible echo controls remain and the refresh test keeps showing the staged preview.

- [ ] **Step 3: Implement the minimal RPK change**

Remove only the echo/diagnostics UI and related CSS; keep `system.echo` message compatibility. Change the idle label to `CHỜ LỆNH TỪ IPHONE…`. Show `render.prepare.preview` only before the first confirmed map. During refresh, apply accepted `nav.update` values to the visible header and also save them as rollback state. Keep marker/destination atomic promotion and all validator limits unchanged.

- [ ] **Step 4: Verify GREEN and commit**

Run: `make test-rpk && git diff --check`

```bash
git add apps/band
git commit -m "fix: keep Band guidance live during map refresh"
```

### Task 5: Version, document, and verify the release

**Files:**
- Modify: `apps/ios/project.yml`
- Modify: `apps/ios/App/BlueBandMapApp.swift`
- Modify: `tools/ios/test-project-metadata.sh`
- Modify: `scripts/verify-ios-artifact.sh`
- Modify: `apps/band/src/manifest.json`
- Modify: `apps/band/package.json`
- Modify: `apps/band/package-lock.json`
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `apps/band/scripts/verify-rpk.mjs`
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `CHANGELOG.md`
- Create: `docs/testing/handoffs/live-background-navigation-guidance.md`

- [ ] **Step 1: Make version assertions fail**

Set tests/verifiers to expect iOS `0.5.9 (25)` and RPK `0.6.11 (26)`, then run `make test-ios-metadata && make test-rpk` and confirm old source versions fail.

- [ ] **Step 2: Update product metadata and handoff guide**

Apply the exact versions above. Document changed versus unchanged contracts, automatic evidence, and hardware cases for correct maneuver sequence, trimmed street, no route dot, screen lock, ≤5-second displayed refresh target, left/right/U-turn map rotation, payload admission, atomic display, and stop-navigation background cleanup.

- [ ] **Step 3: Run canonical verification**

Run: `make clean && make bootstrap && make test && make lint && scripts/verify-no-secrets.sh && git diff --check`

Expected: every local suite passes; this proves code/package contracts only, not hardware latency.

- [ ] **Step 4: Commit and push main**

```bash
git add apps/ios apps/band tools/ios scripts CHANGELOG.md docs
git commit -m "chore: version live background navigation release"
git push origin main
```

- [ ] **Step 5: Build and replace handoff artifacts**

Wait for successful Repository, Swift, Band, and iOS GitHub Actions at the pushed commit. Download the unsigned IPA only from the successful iOS workflow. Build/verify the RPK through `make test-rpk`. Delete the stale files in `artifacts/handoff`, copy only the new IPA and RPK, regenerate `SHA256SUMS`, and update `HANDOFF.md` with exact commit, workflow URL, versions, sizes, hashes, and basic Vietnamese manual test.

- [ ] **Step 6: Final verification**

Run: `make test-handoff && git diff --check && git status --short --branch`

Expected: `main` matches `origin/main`, tracked files are clean, and `artifacts/handoff` contains only the current IPA/RPK plus handoff metadata.
