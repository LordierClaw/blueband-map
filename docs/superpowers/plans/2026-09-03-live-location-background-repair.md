# Live Location and Background Map Repair Plan

**Continuation:** The subsequent completion work and delivery evidence are tracked in [Realtime navigation completion and handoff](2026-09-03-realtime-map-handoff.md). This document retains the earlier investigation and experiment checkpoints; its unintegrated-CPU status below describes that checkpoint, not the later implementation.

> **For agentic workers:** Use `superpowers:executing-plans` for approved implementation, inline on `main`. Do not use subagents or change the renderer before the evidence and visual gates below pass.

**Goal:** Keep real GPS, guidance, heading-up map rendering, and Band publication live during a user-started route, including ordinary iPhone screen lock, without changing the accepted visual or wire contract.

**Architecture:** Retain the existing Core Location manager and bounded scene publisher. Repair session ownership and transient-error handling first, independently of map rendering. A background frame must not depend on the shipped OpenGL ES snapshotter; select a CPU-safe map path only after a small measured visual/latency experiment.

**Tech Stack:** Swift, Core Location, Core Graphics/Core Text, Vietmap Route/TileMap, the existing JPEG encoder, Xiaomi BLE, Docker/Make, GitHub Actions.

**Status:** Approved for implementation on 2026-09-03. GPS lifecycle/permission repairs and diagnostics are in progress. CPU visual, locked-device, and end-to-end latency gates remain open; this is not yet a realtime-map release.

---

## 1. Baseline and evidence

- Repository: `/home/hainn/blue/code/blueband-map`, clean `main` at `4ad102c174faadb3a2afa96ef2dbb0df518aa951` before this document.
- Handoff IPA inspected directly: `0.5.9 (25)`, `UIBackgroundModes = [location, bluetooth-central]`.
- The IPA has `NSLocationWhenInUseUsageDescription`; it has neither an Always-authorization request nor a temporary-full-accuracy usage dictionary.
- Existing log `/home/hainn/Downloads/test-result/BlueBandMap-navigation-debug.txt` is 1,025 bytes, modified 2026-09-02 16:35 +07, predates this IPA, and ends during instruction 6 while `state=transferring`. It cannot establish current GPS/background behavior.
- No current crash report exists in the supplied test-result directory.

### Confirmed defect A: transient GPS failure destroys navigation

`apps/ios/Adapters/Location/ForegroundLocationClient.swift:95` finishes the `AsyncThrowingStream` for every delegate error. Apple explicitly documents `CLError.locationUnknown` as a temporary condition for which location acquisition continues. In this implementation, stream termination schedules `stop()`, disables background updates, invalidates the background session, and ends `runNavigation`.

This is a real code defect whether or not it caused the most recent hardware run.

### Confirmed defect B: previous stream cleanup can stop the next stream

At `ForegroundLocationClient.swift:31`, `onTermination` queues an unscoped `Task { @MainActor in self?.stop() }`. `stop()`/stream replacement finishes the old continuation synchronously, but its cleanup can run after the new stream starts. The old callback then clears the new continuation and stops the new GPS/background session.

`AppModel.runNavigation` also has unscoped deferred cleanup. When stop and start overlap, cleanup from the previous task must not cancel the new task, stream, or snapshot generation.

### Reproduction of A and B

The local diagnostic imports the unchanged production adapter after replacing only its unavailable Apple types with test shims. It does not emulate Apple authorization or radio behavior.

Run from the repository root:

```bash
make -f local/diagnostics/location-runtime/Makefile probe
```

Observed output on 2026-09-03:

```text
first_stream_receives_fix=true
transient_location_unknown_terminates_stream=true
background_after_transient_error=false
restart_background_before_old_cleanup=true
restart_background_after_old_cleanup=false
restart_updating_after_old_cleanup=false
```

The first result also rules out the temporary expression `locations().makeAsyncIterator()` alone ending the first stream in this reproduction.

### Confirmed architecture defect C: background map work still invokes OpenGL ES

`AppModel.publish` always calls `VietmapSnapshotRenderer.render`; neither side selects a background-safe path. The shipped `VietMap.framework/VietMap` binary contains:

```text
/System/Library/Frameworks/OpenGLES.framework/OpenGLES
mbgl::gl::HeadlessBackend
mbgl::gl::EAGLBackendImpl
MGLMapSnapshotter
```

The upstream Mapbox snapshotter design delegates to `mbgl::MapSnapshotter`/the headless renderer. This is corroborating evidence, not a claim that the closed vendor binary has identical source. A background worker queue is not permission to use graphics hardware when the application is in background. Apple prohibits OpenGL ES GPU work there; location background execution does not override that rule. Replacing OpenGL with Metal alone is not a solution either: ordinary background Metal command buffers are rejected.

This makes the current design unsuitable for guaranteed locked-screen map rendering. It does not prove that iOS killed the user's latest process; that specific claim needs a matching crash/termination report.

### Confirmed observability and verification gaps

- The location adapter exports no authorization, accuracy-authorization, raw-fix counter, service lifecycle, or stop reason.
- The UI's `Điểm bắt đầu` is deliberately the fixed route origin, not the current GPS location; there is no independent live-GPS health field.
- Accuracy worse than 25 m blocks route/map advancement, but reduced-accuracy permission is neither checked nor explained to the user.
- `VietmapSnapshotRenderer.complete` discards underlying error details; refresh failures become only `LIMITED_MAP`.
- Snapshot completion has no application-level deadline, so a missing callback can hold the single render slot indefinitely.
- `runNavigation` awaits reroute HTTP work inside its GPS-processing loop, which can block guidance processing for the transport timeout.
- Previous background verification only checked plist values and source strings. There are no behavioral tests for the location adapter or full moving navigation loop.
- The existing one-second/one-metre refresh-policy behavioral test still passes. Lowering these constants again is not a remedy for a stopped producer or blocked renderer.

## 2. Authorization decision

There is no separate iOS authorization named “realtime location”. Standard `startUpdatingLocation()` provides continuous updates. An authorized When-In-Use session started in foreground can continue under the background-location mode and indicator.

The current app does not request Always authorization. That explains the absence of an Always-upgrade prompt, but does not by itself explain a frozen foreground or active locked-screen session. Repeatedly requesting When-In-Use also does not show a new prompt after authorization is decided.

Proposed behavior when the user starts navigation:

1. Read global service availability, authorization, and accuracy authorization.
2. Request When-In-Use only when not determined and the app is active.
3. For denied/restricted or globally disabled location, show the precise reason and a Settings action; do not leave an indefinite waiting screen.
4. For reduced accuracy, explain why navigation needs precise location and request temporary full accuracy with a declared purpose key. If refused, show an explicit limited-accuracy state rather than pretending GPS has stopped.
5. Enable background updates only while the current user-started navigation session owns the stream.
6. Do not add Always access as a workaround. Relaunch after termination/force-quit is outside the accepted scope and is a separate requirement.

## 3. Repair sequence and release gates

### Task 1: Make the failure observable before changing behavior

**Files:** `apps/ios/Adapters/Location/ForegroundLocationClient.swift`, `apps/ios/App/AppModel.swift`, `apps/ios/App/ContentView.swift`, `apps/ios/App/BlueBandMapApp.swift`, `packages/BlueBandKit/Sources/BlueBandMapCore/NavigationDebug.swift` and their tests.

- [ ] Add a small location-health snapshot: authorization, precision, services enabled, stream/session ID, raw and accepted fix counts, last-fix age, background flag, active/inactive/background app state, and last stop/error reason.
- [ ] Record each boundary separately: raw fix received; fix accepted/rejected; refresh eligibility; render start/end/error/timeout; transfer start/result; Band displayed. Correlate using session/scene/fix IDs, not exact coordinates.
- [ ] Include version/build and current health in exported headers so the initial state is not lost when the 120-event ring wraps. Keep diagnostic fields short enough to survive the existing per-line bound.
- [ ] Preserve safe error domain/code and stage, without provider URLs, keys, device identifiers, or raw captures.
- [ ] Test that permission state, raw/accepted counters, stop reason, and render failures remain distinguishable in the export.

**Gate:** A foreground/lock/unlock recording must identify whether the stopped stage is GPS acquisition, GPS acceptance, rendering, transfer, or Band display. No generic “GPS realtime fixed” claim from a metadata check.

### Task 2: Repair location and navigation session ownership

**Files:** `apps/ios/Adapters/Location/ForegroundLocationClient.swift`, `apps/ios/App/AppModel.swift`; new `apps/ios/Tests/ForegroundLocationClientTests.swift` and moving-navigation tests.

- [x] Introduce the smallest injectable manager/background-session seam needed to test the production adapter, not a second implementation of its logic.
- [ ] Add failing cases: temporary `locationUnknown` followed by a valid fix; denied authorization; normal cancellation; stop/start before old termination runs; old task completion after a new session starts; prewarming stopped during navigation; authorization callback while idle.
- [x] Keep the stream alive for documented recoverable errors and publish temporary GPS health. Terminate for actual denied/restricted authorization or explicit session stop; never silently continue an unknown error without recording/classifying it.
- [x] Give each stream/navigation run an identity. An old termination/defer callback may only release resources with the identity it owns. Detach the owned continuation and clear ownership before finishing it, so reentrant termination cannot act on the replacement.
- [x] Only start services from an authorization callback when a prewarm or navigation owner exists. Separate foreground prewarm ownership from active navigation ownership.
- [ ] Maintain continuous latest-fix acquisition while rerouting/rendering/transferring. Reroute failures keep the last valid route and report the failure; they do not destroy GPS delivery.
- [x] Preserve the latest fix during the refresh cooldown and issue its trailing refresh at the due time even if no further location callback arrives after the user stops moving.
- [ ] Repeat start/stop/start and transient-error recovery in simulator tests using injected updates. Confirm the new session still receives the next fix and background activity is released exactly once on stop.

**Gate:** All injected fixes reach the correct live session; no old callback can terminate a new session. GPS and guidance continue while a fake renderer or HTTP request is slow.

### Task 3: Make permission/precision visible and actionable

**Files:** `ForegroundLocationClient.swift`, `ContentView.swift`, `apps/ios/project.yml`, `scripts/verify-ios-artifact.sh`, `tools/ios/test-project-metadata.sh`, new authorization behavior tests.

- [x] Implement the six authorization decisions above and declare the temporary-full-accuracy purpose text in the generated plist.
- [x] Show current GPS age/precision/health independently from the route-origin label.
- [ ] Test not-determined, When-In-Use, denied, restricted, reduced accuracy, permission revoked mid-route, and expired Allow Once. Do not request a system prompt while backgrounded.
- [x] Inspect the built IPA again, not only YAML. Keep `location` and `bluetooth-central` and the existing bundle identity. (Actions inspects the built app before packaging; physical-device acceptance remains open.)

**Gate:** Fresh install and upgraded install both have a clear permission path. Granted When-In-Use plus precise location is sufficient for the ordinary locked-session case; Always is not misrepresented as a realtime prerequisite.

### Task 4: Prove a background-safe map path before replacing the accepted renderer

Three approaches were assessed:

| Approach | Assessment |
|---|---|
| Keep GPU snapshotter and add Always/timers | Rejected: does not remove the OS graphics restriction. |
| Use provider-rendered raster/static images and compose on CPU | Potentially smaller, but current documented Static Map API does not specify heading/dark-style control, and the documented raster tile table lists satellite imagery. Do not invent endpoint capabilities or ship a visual downgrade. |
| Use CPU Core Graphics/Core Text on Vietmap vector data | Recommended experiment for this requirement: use the existing bounded tile transport/cache/MVT decoding and shared projection, preserving roads/buildings/labels. More rendering work than the first two options, so require visual and latency evidence before adoption. |

**Existing reusable files:** `apps/ios/Adapters/Rendering/RouteCardAssetFactory.swift`, `packages/BlueBandKit/Sources/BlueBandMapCore/VietmapStyleClient.swift`, `MapboxVectorTile.swift`, `VietmapVectorTileDecoder.swift`, and the accepted snapshot camera/route geometry. The old four-colour road-card output is not an acceptable replacement for the accepted detailed map.

**Integration boundary after the experiment passes:** `apps/ios/Adapters/Vietmap/VietmapSnapshotRenderer.swift`, `apps/ios/App/AppModel.swift`, and their existing iOS tests. Do not replace the accepted foreground output just to bypass a background failure.

- [ ] Establish exact SDK background failure behavior on the current iPhone: keep raw GPS diagnostics active and record snapshot start/result plus any `.ips` termination report. Never repeatedly retry prohibited GPU work.
- [ ] Build an isolated CPU-rendering experiment before wiring it into the navigation app. Use real Vietmap tile data and the accepted camera positions, heading, scale, colours, road geometry, Vietnamese street labels, and attribution requirements.
- [ ] Compare decoded final transfer images, not just uncompressed source images, at headings 0°, 45°, 90°, 180°, and 270°. Cover dense labels, intersections, curved roads, water/buildings, tile boundaries, and left/right/U-turn sequences.
- [ ] Do not repeatedly rotate/recompress the preceding frame. Render from source geometry into a 2× CPU bitmap, then downsample/encode once with the existing bounded encoder.
- [ ] Prove bitmap generation and encoding work while the real iPhone is locked and never invoke OpenGL ES/Metal rendering. Bound tile cache/memory and fetch the next viewport independently of the Band transfer.
- [ ] Add an explicit render deadline and session identity. A late/error callback cannot hold the render slot forever or clear a new render. Preserve the last confirmed frame on failure.
- [ ] Only after visual approval, select the CPU-safe path for background operation and test foreground/background handover. If foreground/background visual discontinuity remains, evaluate the same CPU path for both; do not silently change both renderers.

**Gate:** Correct projection and cursor anchor, readable labels, no aliasing regression, no lost map features, encoded payload at most 8192 bytes, and successful locked-device CPU rendering. No backend, new service, satellite substitution, or label removal without user approval.

### Task 5: End-to-end acceptance and handoff

- [ ] Run failing behavioral tests before every production change; then `make test`, `make lint`, `scripts/verify-no-secrets.sh`, and `git diff --check`.
- [ ] Add a deterministic moving-route replay that asserts multiple scene publications, maneuver progression, heading changes, fixed cursor `(106,374)`, and one latest pending snapshot under slow transfer.
- [ ] Test on the real iPhone/Band: 2 minutes foreground followed by at least 10 minutes locked, including left/right/U-turn, temporary poor GPS, stop/restart, and lock/unlock during an active transfer.
- [ ] Measure capture-to-display age, including GPS acquisition, render, encode, queued time, and BLE transfer. Require the under-five-second target under agreed good GPS/network/BLE conditions; report every violation rather than resetting the timer at render start. Source-fix age and publication cadence must both be recorded.
- [ ] Confirm the old map remains visible during replacement; no `MAP_PAYLOAD_TOO_LARGE`, `BAND_DISPLAY_FAILED`, stale-session overwrite, or OpenGL background termination.
- [ ] Confirm stop releases background ownership and late callbacks cannot resurrect it. Confirm the RPK idle screen, marker assets, destination placement, and contract are unchanged.
- [ ] Bump only changed components after implementation. Expected scope is iOS only; keep RPK `0.6.11 (26)` unless a separately approved RPK change is required. Build IPA through GitHub Actions, push approved work to `main`, and replace handoff artifacts only after package verification.

**Release rule:** Compilation, injected GPS, simulator tests, and plist verification do not count as locked-iPhone/Band acceptance. Do not describe the feature as verified on hardware until the recorded device run passes.

## 4. Current verification commands

```bash
make -f local/diagnostics/location-runtime/Makefile probe
make test-swift SWIFT_TEST_ARGS='--filter SnapshotMapPolicyTests.testLiveRefreshRunsEverySecondForMovementViewportAndManeuverChanges'
make test-ios-metadata
git diff --check
```

The original diagnostic above is historical red evidence. The canonical replacement is now `make test-location-runtime`: it executes the production location adapter with Apple-type shims and verifies recovery, session ownership, permission transitions, and cache rejection after permission revocation. It does not emulate iOS background execution.

## 4.1 Implementation evidence and outstanding gate (2026-09-03)

- `7ebb963`: session-owned cleanup, recoverable `locationUnknown`, explicit authorization/precision health, background ownership, asynchronous rerouting, latest-pending refresh, safe render errors/deadline, and GPS-to-Band publication metrics.
- [GitHub Actions 33687031077](https://github.com/LordierClaw/blueband-map/actions/runs/33687031077): 68 iOS XCTest cases passed and an unsigned arm64 IPA was built/inspected. That intermediate build retains version 0.5.9 (25); it is **not** the new handoff.
- Follow-up adds a moving-navigation integration test through the actual AppModel, an injected delayed image renderer and Band receiver; it asserts two confirmed scene publications and a latest-fix trailing refresh. Hardware timing remains separate from this injected timing.
- CI `33689235299` rejected a duplicate Swift binding before tests ran; `f528b3c` fixes the compile error. Never count this failed run as behavioral evidence.
- A further production-adapter test exposed cleanup erasing the previous GPS error. The last error is now retained separately in exported health.
- CI `33689564190` compiled and ran 69 iOS tests; the moving test alone exceeded its three-second expectation deadline, although its later scene-publication assertions passed. The app emitted repeated Core Location main-thread performance warnings. Inspection found the new health/UI paths synchronously calling `locationServicesEnabled()` on every read. A behavioral test reproduced those repeated calls. Service checks now run off-main, are coalesced across lifecycle events, and expose cached health; the same three-second moving-test deadline is retained. The canonical runtime harness now has 15 passing assertions, including asynchronous service-disabled handling. Native follow-up CI must confirm the timing result; this evidence does not assign every simulator delay to that one API.
- [GitHub Actions 33690483693](https://github.com/LordierClaw/blueband-map/actions/runs/33690483693), production commit `d80a074d41fbacac1f416a8d3634614ff3270bc2`: **70/70 iOS tests passed**. The moving-navigation replay passed in 1.046 s with its original three-second deadline; the off-main service-query test passed in 0.031 s. The unsigned arm64 **0.5.10 (26)** app passed artifact inspection and was packaged/uploaded. This is an intermediate CI candidate, **not** a locked-screen realtime handoff. Later test/document-only commits do not alter this app source.
- Latest canonical validation after these repairs: `make test` (168 Swift / 28 RPK / 19 lab / 15 location-runtime assertions plus metadata and script tests), `make lint`, secret scan, and `git diff --check` passed. Existing handoff IPA 0.5.9 (25) and RPK 0.6.11 (26) binaries remain unchanged; do not install an intermediate candidate expecting the CPU/background renderer.
- The portable MVT decoder previously discarded all non-LineString geometry. The CPU experiment exposed this omission in dense urban tiles. Independent polygon/hole and multipoint fixtures failed first, then passed after decoding those command types with bounded validation. Existing road geometry behavior and wire bytes are unchanged.
- `make test` passed after the decoder change: 168 portable Swift tests, 28 Band tests, 19 protocol-lab tests, metadata/runtime/script checks. `make lint`, the secret scan, and `git diff --check` also passed. iOS follow-up CI is tracked separately from these Linux checks.

### Isolated CPU visual experiment — not integrated

Reproduce locally (keys and provider responses stay under ignored `local/`):

```bash
make -f local/diagnostics/cpu-map/Makefile inputs decode render
make -f local/diagnostics/cpu-map/Makefile inputs decode render CPU_MAP_CASE=hcm
```

Use only `decode render` to reuse already downloaded tiles. The experiment uses real Vietmap DM style, Route v4, and vector tiles; the decoder is the production Swift decoder. Bitmap drawing currently uses desktop Skia CPU, **not** iOS Core Graphics. Its projection/style reproduction is not yet a shared native implementation. No OpenGL/Metal path is exercised by this experiment.

Corrected dense-HCM final JPEG results:

| Heading | Encoded bytes | JPEG quality | Desktop draw/encode/decode ms |
|---|---:|---:|---:|
| 0° | 8089 | 40 | 1242 |
| 45° | 7947 | 50 | 889 |
| 90° | 8134 | 35 | 864 |
| 180° | 7619 | 30 | 869 |
| 270° | 7991 | 40 | 795 |

These timings exclude network fetch, Swift tile decoding, iPhone scheduling, and BLE. They do **not** establish the five-second target. Final decoded comparison images are `local/diagnostics/cpu-map/comparison.png` and `local/diagnostics/cpu-map/hcm/comparison.png`. The marker in the contact sheet is the existing Band PNG, added only for orientation. Fixed test headings deliberately do not follow the route bearing.

Open experiment gaps: native Core Graphics/Core Text parity, POI symbols, provider attribution review, curved-label placement, tile-boundary/turn replay, cancellation/deadline and memory tests, and locked-device timing. No renderer selection is authorized by machine timings alone.

**Current runtime boundary:** the native SDK renderer now refuses new background renders with `MAP_BACKGROUND_UNAVAILABLE` and cancels when the application becomes inactive. GPS acquisition can continue, but the map keeps its last confirmed frame. The CPU experiment has **not** been wired into navigation. This is not yet a locked-screen realtime-map release; do not replace the accepted handoff or describe <5 s as achieved at this checkpoint.

## 5. Primary references

- [Apple: location-manager errors and temporary locationUnknown](https://developer.apple.com/documentation/corelocation/cllocationmanagerdelegate/locationmanager(_:didfailwitherror:))
- [Apple: When-In-Use authorization and continued standard background updates](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization())
- [Apple: allowsBackgroundLocationUpdates](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates)
- [Apple: temporary full-accuracy authorization](https://developer.apple.com/documentation/corelocation/cllocationmanager/requesttemporaryfullaccuracyauthorization(withpurposekey:))
- [Apple: background OpenGL ES restriction](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/OpenGLES_ProgrammingGuide/ImplementingaMultitasking-awareOpenGLESApplication/ImplementingaMultitasking-awareOpenGLESApplication.html)
- [Apple: background Metal restriction](https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background)
- [Vietmap pinned binary package](https://github.com/vietmap-company/maps-sdk-ios/blob/649eabcb21a36c3d0cfd871c07ccea641924fcdd/Package.swift)
- [Upstream Mapbox snapshotter implementation; corroborating design, not proof of exact vendor source](https://github.com/mapbox/mapbox-gl-native-ios/blob/main/platform/darwin/src/MGLMapSnapshotter.mm)
- [Vietmap TileMap](https://maps.vietmap.vn/docs/map-api/tilemap/)
- [Vietmap Static Map documented capabilities](https://maps.vietmap.vn/docs/map-api/static-map-version/static-map/)
