# Google-Style Band Route Guidance Design

## Goal

Make the Smart Band navigation scene read like active guidance rather than a short highlighted road fragment: keep the user marker fixed at the horizontal lower-center, show the remaining route through the viewport, present the next actionable maneuver, and place an off-screen destination indicator visually on the display contour.

## Hardware evidence and root causes

The accepted hardware screenshot and `BlueBandMap-navigation-debug.txt` show a 9.49 km route with 130 geometry points and 24 instructions, while the Band displays only the current 66 m fragment. A live Route v4 request for the same redacted endpoints confirms Vietmap instructions describe an action at the start of an interval: a turn instruction begins at the point where the preceding straight interval ends.

The current implementation has four mismatches:

1. `RouteOverlayGeometry.active` ends at the selected instruction's upper bound, and `context` retains only about 80 m after it. The remaining route is therefore subdued or absent instead of visibly continuing through the viewport.
2. Guidance pairs the current interval's maneuver with the distance remaining to that interval's end. Vietmap defines that distance as the distance until the next instruction, so the UI shows `straight 66 m` where the next action is a right turn.
3. The 20×20 off-screen destination ring is kept fully inside the physical contour. Its center must remain about half an icon inward, so it does not look attached to the edge.
4. The marker bitmap is centered mathematically, but its visible green fill is narrow inside a large transparent canvas and dark outline, making it look pinched and optically displaced on hardware.

## Guidance model

`GuidancePresentationPolicy` will first identify the first route instruction section whose upper-bound point is still ahead of the matched segment. The distance from the matched position to that section's upper-bound point is the geometric distance to the next action, while the following instruction supplies the maneuver and street shown in the header. If no later instruction remains, the final instruction is used. Zero-length or already-passed sections are skipped by their geometry boundary, not prematurely by GPS accuracy.

The distance calculation follows route geometry from the matched fractional position to the current section's upper-bound point. It does not use the provider instruction's declared distance as the live remaining distance, because multiple instructions can share a polyline index.

## Route presentation

The camera remains heading-up with zero pitch. The marker stays fixed at `(106, 374)`, horizontally centered and at roughly 72% of the display height. It always points straight up.

The snapshot camera is the authoritative coordinate system for the basemap, route, maneuver point, and destination projection. The renderer must not translate only the route overlay independently of the basemap.

The route layers are:

- subdued dark halo: the complete route for contrast;
- traveled gray: route start through the matched fractional position;
- active blue: matched position through the final route point, clipped naturally by the viewport;
- maneuver ring: the selected next-action point.

This keeps the route visibly continuing beyond the immediate maneuver without changing zoom merely to fit the full multi-kilometre route.

## Band overlays

The user marker remains a 46×54 indexed PNG for protocol compatibility. Its visible shape becomes a symmetric upright solid green triangle with a thin dark outline and substantially less transparent/outline-dominated area. All eight compatibility filenames remain byte-identical because the marker no longer rotates.

An off-screen destination uses one of eight directional chevrons rather than a centered ring. The chevron's outward tip touches the calibrated physical contour while the visible body remains inside it. An in-viewport destination continues to use the existing pin. Preview and live-update validation use the same resource dimensions and contour rule.

The header keeps the existing compact `m`/`km` formatting and displays the selected maneuver glyph, remaining distance, and selected instruction street. No persistent status card is added during normal navigation.

## Data and failure handling

No Xiaomi BLE/SPP/authentication bytes, transport envelopes, Vietmap request parameters, payload ceiling, or refresh cadence change. Invalid or exhausted instructions fall back to the arrival guidance rather than hiding the route. If snapshot publication fails, the previous confirmed scene remains visible as today.

## Verification

Tests are written before production changes and cover:

- a Vietmap-style straight interval followed by a turn at the same boundary selects the turn and its distance;
- active route geometry continues from the matched point through the final route point;
- camera projection places the matched point at `(106,374)` without overlay-only translation;
- marker resources are identical, symmetric, visibly wide, and centered in their canvas;
- all eight destination directions put the chevron tip on the contour and keep its body visible;
- preview and live Band paths render the same marker, destination direction, maneuver, street, and compact distance.

The canonical repository gate remains `make clean && make bootstrap && make test && make lint && scripts/verify-no-secrets.sh && git diff --check`. Hardware acceptance requires another screenshot and debug export from the resulting IPA/RPK.

## Version and handoff policy

Writing this design does not change either product binary and does not bump a version. During implementation, bump only components whose product code or bundled resources change. Completed work is committed and pushed on `main`; IPA packaging is performed only by GitHub Actions; superseded files in `artifacts/handoff` are replaced by the current IPA/RPK set.
