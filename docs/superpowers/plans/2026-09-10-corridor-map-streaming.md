# Corridor map streaming and roundabout repair

> Execute inline using executing-plans; user explicitly requested no subagents.

**Goal:** Correct the frozen GPS route's roundabout icon and deliver fixed-cursor, demand-loaded map movement with bounded iOS/Band caches.

**Architecture:** Preserve the CPU renderer and verified Xiaomi transport. Introduce a capability-negotiated application-level map mosaic: common camera coordinates, bounded raster cells, scene-bound position updates, visible cells plus a forward corridor. Keep the current full-frame path for older peers and failure recovery. A missing cell must never expose an empty map or replace a confirmed scene prematurely.

**Tech stack:** Swift portable geometry/policy, Core Graphics renderer, existing Vela image/file/interconnect APIs, Docker Make tests and GitHub Actions iOS tests/build.

## 1. Roundabout boundary repair

- [ ] Add a behavioral regression using translated E5 deltas from the frozen fake-GPS route (no raw capture committed). Cover interval ending before and after the outlet, geometry rotations, and actual parser-to-guidance output.
- [x] Run `make test-swift SWIFT_TEST_ARGS='--filter VietmapRouteTests'`; observe unknown versus straight failure.
- [x] Find the arc/outlet transition within the instruction as well as immediately after it. Preserve confidence guards and exit-number independence.
- [x] Re-run the route tests and retain malformed/clockwise/missing-outlet rejection.

## 2. Map mosaic contract and bounded cache

- [ ] Define exact application vectors and ADR: cell size/count/byte bounds, camera epoch, offsets, coverage, capability negotiation, old-peer fallback. Do not change proprietary wire framing.
- [ ] Add failing portable and Band runtime checks for viewport coverage, forward prefetch, visible-cell pinning, eviction, stale scene/sequence rejection, decode failures and reconnect.
- [ ] Implement bounded visible-plus-forward cell selection and Band file/decode lifecycle, reusing existing raster transport where compatible.
- [ ] Test movement with no full-frame reload, no uncovered pixels, no unbounded file/image retention, and navigation priority over prefetch.

## 3. iOS renderer and realtime integration

- [ ] Add failing iOS integration tests for shared-coordinate cell rendering, cache reuse, latest GPS placement, reroute/camera invalidation, background rendering and cancellation.
- [ ] Render/cache only requested corridor cells; transmit missing cells serially with bounded lookahead; send small position updates independently of image preparation.
- [ ] Keep fixed cursor/HUD and correct destination/route registration. Do not extrapolate indefinitely across stale GPS.
- [ ] Measure GPS age, cell transfer/decode, coverage misses, resident cells and frame cadence separately.

## 4. Verification and handoff

- [ ] Run `make test`, `make lint`, `git diff --check`; independently review changed contracts and call sites inline.
- [ ] Run full iOS CI including renderer/integration tests. Bump each changed component version/build; package current IPA/RPK with hashes and concise manual checks.
- [ ] Validate Vela transforms, clipping and image resource retirement on real Band, including blur/resume and locked iPhone. Report physical latency separately from automated evidence; do not claim near-realtime hardware behavior without measurements.

## Implementation checkpoint (2026-09-10)

- Roundabout regression first failed at interval ends 11 and 12, then passed after the shared boundary search. Parser-to-guidance regression still needs the translated fixture through `VietmapRouteClient.parse`.
- Band now accepts scene-bound stream open/view/close plus hash-checked 128×128 PNG cells with 216-byte chunks/window four, displays only fully decoded coverage, retires cache files, and guards late/duplicate write callbacks. Core cache and actual-page tests pass; compiled-entry regression prohibits custom helper modules. The corridor helper is inline in the actual UX entry and tests load that same block (no duplicate reference implementation).
- Swift `CorridorViewport` supplies matching coverage and visible-first forward-prefetch cells. It is not connected to `AppModel` yet.
- Remaining before release: iOS cell rendering/encoding and reliable sender, AppModel GPS/epoch/cache integration, destination/route registration, native clipping/decode lifecycle validation, crash-restart cell-file cleanup, full failure/long-replay checks, component version bumps, CI and new IPA/RPK handoff. Current handoff artifacts remain untouched.
- Latest checkpoint verification: `make test` exit 0 (184 portable Swift tests, 44 Band tests including normal RPK build, 19 protocol-lab tests, iOS metadata/location-runtime/provider-script/handoff checks); `make lint` and `git diff --check` exit 0. No iOS simulator CI or hardware test has run for these new changes.
- Integration constraints found during reading: CPU bitmap size/projection/label clipping are currently hard-coded to the full viewport, and both snapshot encoders reject 128×128 input. Render neighboring cells in a shared plane with stable label placement, not independent camera snapshots. Cached route strokes must not retain stale traveled/active styling; establish safe cell-content replacement or an equivalent aligned overlay before enabling streaming. Destination coordinates must follow the displayed (not merely requested) translation. These remain implementation work, not acceptance claims.
