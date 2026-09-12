# Corridor map streaming and roundabout repair

> Execute inline using executing-plans; user explicitly requested no subagents.

**Goal:** Correct the frozen GPS route's roundabout icon and deliver fixed-cursor, demand-loaded map movement with bounded iOS/Band caches.

**Architecture:** Preserve the CPU renderer and verified Xiaomi transport. Introduce a capability-negotiated application-level map mosaic: common camera coordinates, bounded raster cells, scene-bound position updates, visible cells plus a forward corridor. Keep the current full-frame path for older peers and failure recovery. A missing cell must never expose an empty map or replace a confirmed scene prematurely.

**Tech stack:** Swift portable geometry/policy, Core Graphics renderer, existing Vela image/file/interconnect APIs, Docker Make tests and GitHub Actions iOS tests/build.

## 1. Roundabout boundary repair

- [x] Add a behavioral regression using translated E5 deltas from the frozen fake-GPS route (no raw capture committed). Cover interval ending before and after the outlet, geometry rotations, and actual parser-to-guidance output.
- [x] Run `make test-swift SWIFT_TEST_ARGS='--filter VietmapRouteTests'`; observe unknown versus straight failure.
- [x] Find the arc/outlet transition within the instruction as well as immediately after it. Preserve confidence guards and exit-number independence.
- [x] Re-run the route tests and retain malformed/clockwise/missing-outlet rejection.

## 2. Map mosaic contract and bounded cache

- [x] Define exact application vectors and ADR: cell size/count/byte bounds, camera epoch, offsets, coverage, capability negotiation, old-peer fallback. Do not change proprietary wire framing.
- [x] Add failing portable and Band runtime checks for viewport coverage, forward prefetch, visible-cell pinning, eviction, stale scene/sequence rejection, decode failures and reconnect.
- [x] Implement bounded visible-plus-forward cell selection and Band file/decode lifecycle, reusing existing raster transport where compatible.
- [x] Test movement with no full-frame reload, no uncovered pixels, no unbounded file/image retention, and navigation priority over prefetch.

## 3. iOS renderer and realtime integration

- [x] Add failing iOS integration tests for shared-coordinate cell rendering, cache reuse, latest GPS placement, reroute/camera invalidation, background rendering and cancellation.
- [x] Render/cache only requested corridor cells; transmit missing cells serially with bounded lookahead; send small position updates independently of image preparation.
- [x] Keep fixed cursor/HUD and correct destination/route registration. Do not extrapolate indefinitely across stale GPS.
- [ ] Measure GPS age, cell transfer/decode, coverage misses, resident cells and frame cadence separately.

## 4. Verification and handoff

- [x] Run `make test`, `make lint`, `git diff --check`; independently review changed contracts and call sites inline.
- [x] Run full iOS CI including renderer/integration tests. Bump each changed component version/build; package current IPA/RPK with hashes and concise manual checks.
- [ ] Validate Vela transforms, clipping and image resource retirement on real Band, including blur/resume and locked iPhone. Report physical latency separately from automated evidence; do not claim near-realtime hardware behavior without measurements.

## Device feedback follow-up (2026-09-12)

The user tested the latest artifacts: roundabout direction is correct, but movement
still appears only every few seconds and the directional artwork is too thin.
There is no new device log. Do not treat the older 0.5.18 export as evidence for
this release or claim a measured one-second device result.

- [x] Reproduce replacement/decode circular wait in the actual page runtime:
  show view `(0,0)`, request `(0,4)` with its entering row missing, replace `0:0`,
  require `map.cell.decoded` before sending that row. Run `make test-rpk-runtime`;
  expected RED: the replacement node is absent.
- [x] Mount available pending files incrementally in `corridorMap.images()` using
  `wanted ? wanted.keys.map(key => files[key]).filter(Boolean) : []`;
  retain the existing all-decoded promotion and 24-node bound. Run the same test
  and `make test-corridor`; verify old pixels remain until complete coverage and
  28 subsequent cached views move without file writes.
- [x] Inspect sender prefetch scheduling with a slow cell transfer and advancing
  GPS. Only change priority after a failing behavioral test reproduces starvation.
  CI `34694659756` at `80bedda` fails exactly the first-forward-cell priority
  assertion; its other 94 iOS tests pass. Move the existing forward-file loop
  before visible-cell recoloring. The next iOS CI must verify GREEN.
- [x] Preserve upstream Mapbox roundabout geometry, directions and the 44x56 HUD
  footprint; rasterize at higher source resolution with a rounded cyan stroke
  matching the existing Material arrows. Inspect the generated native-size PNGs.
  Keep icon mapping, unrelated artwork and Xiaomi wire bytes unchanged.
- [x] Add persistent export mode/last reset plus separate cell prepare/link timing.
  Portable diagnostic tests fail behaviorally with an empty report, then pass
  with `full/loading/tiles`, sent/displayed sequence and failure reporting.
- [ ] Run `make test`, `make lint`, `git diff --check`, then component-specific
  version/build bumps, CI/package checks and an updated handoff. Report code/test
  evidence separately from the remaining device cadence measurement.

## Previous release checkpoint (2026-09-12)

- Roundabout fixture now passes through the real parser into both preview and live guidance as `straight`; the provider interval includes part of the exit road.
- GPS integration, CPU atlas/cell rendering, content-hash reuse, safe cell replacement, destination registration and capability fallback are implemented. CI `34676221943` at `43dec58` passed 95 iOS tests and built arm64. This is not the final artifact source.
- Final candidate `6db094b` adds path-local recoloring, transient native-cleanup backpressure, retained-map recovery and component versions 0.5.21 (37) / 0.6.16 (31). Its iOS CI `34677326119` passed 95 tests, arm64 artifact inspection and IPA export. Linux: 193 Swift, 48 Band, 19 lab tests, location/metadata/syntax/provider/handoff checks plus lint pass.
- Band replay covers 600 curved movement/content-replacement steps with exact viewport coverage, ≤30 retained cell files and ≤24 mounted cell nodes. Native decoder memory reclamation is still a hardware gate, not proven by these tests.
- `map.stream.displayed` records the confirmed fix timestamp, offset and frame gap; `map.cell.ready` records encoded bytes, total preparation/transfer wait and known file count. Actual hardware write/decode timings, RAM and locked-screen/blur acceptance are still pending. No extrapolated positions or fabricated latency measurements.
- USB checks on this host show no Apple device and inactive usbmuxd. The current uploaded log is build 0.5.18 (34), dated September 7, not evidence for the new version. After all four CI runs passed, the downloaded IPA/RPK were inspected and packaged in `artifacts/handoff` with matching hashes. The previous handoff was copied to `/tmp/blueband-corridor-release.ayWrbG/previous-handoff` before replacement. Hardware acceptance remains open.

## Historical checkpoint (2026-09-10; superseded by the section above)

- Roundabout regression first failed at interval ends 11 and 12, then passed after the shared boundary search. Parser-to-guidance regression still needs the translated fixture through `VietmapRouteClient.parse`.
- Band now accepts scene-bound stream open/view/close plus hash-checked 128×128 PNG cells with 216-byte chunks/window four, displays only fully decoded coverage, retires cache files, and guards late/duplicate write callbacks. Core cache and actual-page tests pass; compiled-entry regression prohibits custom helper modules. The corridor helper is inline in the actual UX entry and tests load that same block (no duplicate reference implementation).
- Swift `CorridorViewport` supplies matching coverage and visible-first forward-prefetch cells. It is not connected to `AppModel` yet.
- Remaining before release: iOS cell rendering/encoding and reliable sender, AppModel GPS/epoch/cache integration, destination/route registration, native clipping/decode lifecycle validation, crash-restart cell-file cleanup, full failure/long-replay checks, component version bumps, CI and new IPA/RPK handoff. Current handoff artifacts remain untouched.
- Latest checkpoint verification: `make test` exit 0 (184 portable Swift tests, 44 Band tests including normal RPK build, 19 protocol-lab tests, iOS metadata/location-runtime/provider-script/handoff checks); `make lint` and `git diff --check` exit 0. No iOS simulator CI or hardware test has run for these new changes.
- Integration constraints found during reading: CPU bitmap size/projection/label clipping are currently hard-coded to the full viewport, and both snapshot encoders reject 128×128 input. Render neighboring cells in a shared plane with stable label placement, not independent camera snapshots. Cached route strokes must not retain stale traveled/active styling; establish safe cell-content replacement or an equivalent aligned overlay before enabling streaming. Destination coordinates must follow the displayed (not merely requested) translation. These remain implementation work, not acceptance claims.
