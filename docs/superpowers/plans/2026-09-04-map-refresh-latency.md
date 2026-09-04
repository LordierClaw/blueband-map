# Map refresh latency and HUD corrections

Inline execution, as requested. Keep accepted map/route/marker geometry and Xiaomi wire bytes.

## Evidence and design

The 0.5.17 device log shows fresh GPS and guidance near 1 Hz. A successful background frame takes 2,675 ms to render and 7,666 ms to transfer/display (7,416 bytes). Other refreshes fail with `MAP_INVALID_REQUEST` within 32 ms, followed by the existing five-second retry cooldown. Camera fitting currently rejects valid hairpins when the upcoming maneuver lies behind the current heading. At frame completion, the old request also overwrites newer guidance (326 m jumps back to 442 m).

Fix camera fitting at its shared configuration function: fit the maneuver when possible, but keep a useful heading-up local camera if it is behind, coincident, or cannot fit. Invalid external inputs must still fail. Publish the new scene with the latest pending guidance, not the frame's old fix.

Keep one bounded full-image transfer and the existing chunk protocol. Compare full-resolution indexed PNG with JPEG before choosing a smaller image; do not blur labels or block pixels to meet an arbitrary byte target. Evaluate the already-supported two-command transfer window with delayed/lost ACK tests before enabling it. Do not introduce tiled composition, larger envelopes, or unbounded prefetch. Existing decoded-tile cache should amortize cold provider work once valid camera refreshes stop failing.

Left-align the existing street label. Replace only maneuver glyphs with Google's Apache-2.0 Material Icons Round, rasterized offline into the existing 44x56 slots. Keep source, attribution, and license; no runtime SVG dependency.

## Execution and verification

- [x] Add failing camera hairpin/coincident, stale-guidance, image-size/quality and street-layout regression checks; observe iOS CI and local RPK failures before fixes.
- [x] Correct shared camera fitting and latest-guidance publication; keep cancellation and post-ACK continuation tests.
- [x] Compare image byte counts/decoded quality and bounded-window latency; enable only supported, tested optimizations. Keep 8 KiB maximum and exact-command retries.
- [x] Vendor licensed maneuver artwork, generate PNGs and visually inspect all six at display size; keep marker/destination hashes unchanged.
- [x] Run `make test`, `make lint`, `git diff --check`, iOS simulator tests and arm64 build. Bump both changed component versions, package fresh IPA/RPK and a concise handoff.

Repository/CI measurements do not prove locked-iPhone or physical-Band latency. Report warm/cold, transmission and hardware acceptance separately; do not call the <5 s device target achieved without a new device log.
