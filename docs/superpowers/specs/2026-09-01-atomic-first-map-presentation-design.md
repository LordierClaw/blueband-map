# Atomic First Map Presentation Design

**Date:** 2026-09-01

**Status:** Approved in conversation; awaiting written-spec review

## Goal

Make the first visible Band map immediately understandable: the road ahead points upward, the green user marker and amber destination indicator appear with the same confirmed scene, and the waiting screen reconnects automatically without a button or unstable polling. Keep the currently calibrated Smart Band 10 safe mask as fixed production data.

## Evidence and root causes

The supplied log reaches `map.rendered bytes=4130 palette=16 pixelBlock=1` but is exported while `state=transferring`; it has no `band.displayed` or `nav.update`. The Band promotes the raster in `mapComplete`, explicitly hides `navMarkerVisible` and `navDestinationVisible`, and sends `render.result` afterward. iOS cannot send the first scene-bound `nav.update` until that result arrives. The raster and its native overlays therefore do not become visible atomically.

The blue ring baked into the raster is the selected maneuver, not the user marker. Without the green marker, the user cannot tell which end of the active route is the current position, making an upward route look reversed.

The user has tested the current default curved safe-area values on hardware and accepted them. Runtime calibration UI is no longer required.

## Atomic initial guidance

Extend the existing bounded `render.prepare.preview`; do not add a new topic or send `nav.update` against an unconfirmed scene. In addition to maneuver, distance, and street, the preview carries:

- user marker center and heading bucket;
- destination mode (`visible`, `edge`, or `hidden`) and bounded center;
- all coordinates projected using the snapshot configuration that produced the transferred raster.

The RPK validates the complete preview atomically. It stages these fields while the old confirmed map remains visible. In `mapComplete`, it promotes the new raster and staged user/destination overlays in the same synchronous state change, then sends `render.result`. Later `nav.update` messages continue moving the overlays at the existing bounded rate.

Invalid or partial initial overlay fields reject `render.prepare`; the Band must not guess coordinates. Refresh failure keeps the old confirmed raster and old confirmed overlays.

## Heading-up invariant

The selected forward route point is the selected maneuver when it is non-degenerate; otherwise it is the next non-degenerate route point. The stationary snapshot bearing is derived from the accepted matched position toward that forward point. The snapshot projection must satisfy:

```text
forwardPoint.y < userMarker.y
```

with both points inside the current fixed safe mask. This is the user-facing definition of “route ahead points upward.” Moving-course behavior, two-fix activation, three-fix fallback, 30-degree hysteresis, route matching, and reroute thresholds remain unchanged.

The same snapshot configuration is authoritative for raster overlay drawing and preview marker/destination coordinates. Tests cover north, east, south, west, and the supplied stationary-route shape so camera sign or a 180-degree reversal cannot regress silently.

## Fixed curved display mask

Keep the accepted production constants unchanged:

- canvas `212×520`;
- inset `12`;
- top center y `106`, bottom center y `413`;
- top and bottom radius `94`;
- visual margin `6`.

Remove the calibration button, calibration screen state, generated calibration PNG, and calibration instructions from the normal handoff. Safe-mask tests remain; future changes require a new explicit hardware-calibration task rather than runtime UI.

## Automatic waiting screen

Replace `CHECK CONNECTION` with a static waiting view such as `ĐANG CHỜ KẾT NỐI…`. Connection probing is automatic:

- run one immediate probe in `onReady`;
- retry every 2 seconds only while disconnected;
- allow at most one probe in flight;
- reuse the page's single interconnect instance and existing ownership/epoch checks;
- do not append one log row per failed probe;
- stop the timer immediately after connection succeeds;
- clear the timer and detach handlers in `onDestroy`;
- restart bounded polling only when the page returns to the disconnected state.

The waiting UI is always renderable without transport data. Polling never allocates map buffers, starts asset transfer, or touches confirmed map files, reducing the risk of a black screen or lifecycle crash.

## Version and artifact impact

Both installed components change. Bump IPA from `0.5.1 (17)` to `0.5.2 (18)` and RPK from `0.6.0 (15)` to `0.6.1 (16)`. Build IPA only through GitHub Actions. Final handoff contains exactly one IPA and one RPK; delete superseded local artifacts.

## Verification

- Portable Swift: complete preview validation/JSON, forward-point bearing, and upward projection invariants.
- RPK: staged overlays stay hidden over the old map, appear atomically with the new map, invalid partial preview is rejected, automatic polling has one timer/one in-flight probe, and `onDestroy` clears it.
- Existing route, reroute, envelope, digest, transfer, stale-scene, and navigation coalescing tests remain green.
- GitHub Actions: iOS simulator tests, unsigned device build, artifact inspection.
- Hardware: first visible raster already has green user marker and amber destination indication; active route continues from the marker toward the top; waiting screen reconnects without touch and survives repeated page open/close cycles without black screen.

Compilation and deterministic tests do not establish Smart Band 10 hardware acceptance.
