# Hybrid Heading-Up Guidance Hardware Handoff

## Artifact versions

- IPA: `0.5.4 (20)`; build and package only through `.github/workflows/ios-checks.yml`.
- RPK: `0.6.3 (18)`; build through `make test-rpk`.
- `render.prepare.preview` adds bounded user and destination overlay fields for atomic first-scene publication. Xiaomi BLE/SPP/authentication bytes and Route v4 request behavior are unchanged.

## Fixed curved-display mask

The user accepted the production Smart Band 10 mask on hardware: canvas 212×520, inset 12 px, top center y=106, bottom center y=413, independent 94 px cap radii, and 6 px visual margin. Runtime calibration UI is intentionally absent; changing these constants requires a separate hardware-calibration task.

## Manual test plan

Use a passenger or stop safely before observing or operating either device. First complete a stationary route replay, then use a safe 0–50 km/h route containing a straight section, left turn, right turn, crossing road, and parallel road.

1. Install the listed IPA and RPK, open both apps, and confirm the Band waiting screen reconnects without touch across repeated page open/close cycles.
2. Start navigation while stationary. Confirm the first visible raster includes a wide, symmetric upright green pointer at the fixed lower-center position and the blue route meets its center exactly.
3. With GPS accuracy near 10 m, confirm the header pairs the distance to the next maneuver with that maneuver's arrow (for example, `66 m` with a right-turn arrow), rather than showing the current straight segment.
4. Begin moving above 3.6 km/h. Confirm the map changes to travel-course heading only after stable movement while the user marker stays fixed and points straight up.
5. Pass at least three maneuvers. Confirm the complete remaining blue route is visible (not only the current short segment), always meets the marker, and distances use compact units (`999 m`, `1 km`, `1.4 km`, `2 km`).
6. Select a destination outside the current viewport. Confirm an amber directional chevron points outward with its tip touching the correct curved edge, then becomes an amber destination pin when it enters view.
7. Stop and resume, then safely deviate from the route. Confirm GPS-low and rerouting states remain correct, no false bright connector is drawn, and the previous confirmed map remains visible if a refresh fails.
8. Export the sanitized debug log. Confirm it contains GPS quality, speed/course, matched segment/fraction, selected guidance, bearing source/delta, refresh decision, and destination mode without keys, exact raw captures, or device identifiers.

For payload regression, repeat the 9.36 km route from the `MAP_PAYLOAD_TOO_LARGE encodedBytes=11510` log. Confirm `map.rendered` is present, `bytes` is at most 8192, and record `pixelBlock` (`1` is full detail; `2`, `4`, or `8` means the bounded fallback was required).

Compilation and deterministic tests do not establish Smart Band 10 hardware acceptance. Record Pass/Fail and attach the sanitized debug export.
