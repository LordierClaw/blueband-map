# Directional roundabouts and bounded map pipeline

Approved by the user after the source/API investigation. Execute inline on main using systematic-debugging, TDD and executing-plans; no subagents or new dependencies.

## Design and invariants

- Infer relative exit direction from Route v4 geometry, not exit number or heading=0. Recognize a bounded counter-clockwise arc and its approach/exit; ambiguous, degenerate or incomplete geometry stays neutral. Keep roundabout identity distinct from ordinary turns. Use pre-rendered standard directional artwork, no extra HUD text.
- Keep one map transmitting and at most one next render/result. GPS coalesces to the latest request; never queue unbounded frames. Validate navigation generation, route, age and camera before promoting a prepared result. Stop/reset/reroute cannot promote stale work. Rendering may overlap transfer but never another render.
- Add queue/render/encode/transfer/display timing and frame-gap evidence. Preserve 212x520, 8 KiB bound, accepted route/marker/UI, Xiaomi transport bytes and timeout recovery.
- Existing bounded parallel tile cache remains. Extra predictive API prefetch and Band-local image transforms are conditional follow-ups, not enabled without device timing showing their need. No claim of physical one-second latency from CI.

## Execution checklist

- [ ] Geometry: add failing portable behavioral checks in VietmapRouteTests for the observed approach/arc/exit shape, rotated straight/right/left/U-turn shapes, duplicate points and ambiguous/no-exit fallback; run `make test-swift SWIFT_TEST_ARGS='--filter VietmapRouteTests'`. Implement in BlueBandMapCore with an optional bounded direction propagated through preview/live guidance. Add exact application-body vectors and an ADR; Xiaomi bytes unchanged.
- [ ] Band: add failing preview/live direction selection and invalid-field tests in envelope-page.test.mjs; run `make test-rpk-runtime`. Vendor pinned standard directional SVGs under existing attribution, rasterize with existing offline generator, validate bundled assets. Keep numbered neutral fallback for old/no-confidence bodies and street layout unchanged.
- [ ] Pipeline: add failing AppModel integration tests proving render B starts while A awaits display, only latest pending fix survives, cancellation/reroute/reset cannot publish stale results, and diagnostics expose stage/frame timings. Split existing preparation from publication, reuse the current refresh drain with one bounded preparation slot. Verify iOS XCTest through CI; retain supplemental Linux coordinator checks.
- [ ] Release: run `make test`, `make lint`, `git diff --check`; inspect actual PNGs, review inline, bump changed IPA/RPK version and build numbers, push main, obtain passing iOS/Swift/Band/repository CI, verify artifacts and replace artifacts/handoff using the existing script. Include concise manual roundabout and locked-screen acceptance checks with physical latency explicitly unverified.

## Evidence to retain

Route v4 sample at Nguyen Khuyen has sign 6 interval 8...19, approach heading ~343 degrees, small counter-clockwise arc at points 11...19, exit segment 19...20 heading ~326 degrees. The relative direction is nearly straight, not the local right turn used to leave the circle. Source VietMapDirections MBVisualInstruction reads a separate `degrees` field; Route v4 does not supply it in the observed response. Raw captures/keys are not committed.
