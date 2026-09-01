# Hybrid Heading-Up Guidance Hardware Handoff

## Artifact versions

- IPA: `0.5.5 (21)`; build and package only through `.github/workflows/ios-checks.yml`.
- RPK: `0.6.5 (20)`; build through `make test-rpk`.
- `render.prepare.preview` adds bounded user and destination overlay fields for atomic first-scene publication. Xiaomi BLE/SPP/authentication bytes and Route v4 request behavior are unchanged.
- IPA `0.5.5` matches the camera projection to the pinned Vietmap/MapLibre 512 px tile world, so the route origin lands at the fixed marker instead of about 115 px below it. The complete remaining route is unchanged and gains a dark casing plus a brighter active line.
- RPK `0.6.5` replaces the asymmetric polygon-rasterized marker with an exactly centered triangle, enlarges the destination overlays to 28 px, centers off-screen destinations on the display contour, and replaces unsupported partial-alpha header shading with binary-alpha dithering.

## Fixed curved-display mask

The user accepted the production Smart Band 10 mask on hardware: canvas 212×520, inset 12 px, top center y=106, bottom center y=413, independent 94 px cap radii, and 6 px visual margin. Runtime calibration UI is intentionally absent; changing these constants requires a separate hardware-calibration task.

## Manual test plan

Use a passenger or stop safely before observing or operating either device. First complete a stationary route replay, then use a safe 0–50 km/h route containing a straight section, left turn, right turn, crossing road, and parallel road.

1. Install the listed IPA and RPK, open both apps, and confirm the Band waiting screen reconnects without touch across repeated page open/close cycles.
2. Start navigation while stationary. Confirm the first visible raster includes an exactly symmetric upright green pointer, with all three corners intact, centered at x=106/y=374. Confirm the blue route meets its center exactly and continues toward the next maneuver.
3. Confirm the header has a clearly visible dark background/fade. With GPS accuracy near 10 m, confirm it pairs the compact distance to the next maneuver with that maneuver's arrow (for example, `66 m` with a right-turn arrow), rather than showing the current straight segment.
4. Begin moving above 3.6 km/h. Confirm the map changes to travel-course heading only after stable movement while the user marker stays fixed and points straight up.
5. Pass at least three maneuvers. Confirm the complete remaining blue route is visible (not only the current short segment), always meets the marker, and distances use compact units (`999 m`, `1 km`, `1.4 km`, `2 km`).
6. Select a destination outside the current viewport. Confirm a large amber directional chevron points outward, is centered on the correct curved edge and is clipped by the screen rim, then becomes a clearly visible amber destination pin when it enters view.
7. Stop and resume, then safely deviate from the route. Confirm GPS-low and rerouting states remain correct, no false bright connector is drawn, and the previous confirmed map remains visible if a refresh fails.
8. Export the sanitized debug log. Confirm it contains `band.displayed` for the current frame and no `BAND_DISPLAY_FAILED`, plus GPS quality, speed/course, matched segment/fraction, selected guidance, bearing source/delta, refresh decision, and destination mode without keys, exact raw captures, or device identifiers.

For payload regression, repeat the 9.36 km route from the `MAP_PAYLOAD_TOO_LARGE encodedBytes=11510` log. Confirm `map.rendered` is present, `bytes` is at most 8192, and record `pixelBlock` (`1` is full detail; `2`, `4`, or `8` means the bounded fallback was required).

Compilation and deterministic tests do not establish Smart Band 10 hardware acceptance. Record Pass/Fail and attach the sanitized debug export.
