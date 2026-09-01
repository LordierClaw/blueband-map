# Hybrid Heading-Up Guidance Hardware Handoff

## Artifact versions

- IPA: `0.5.0 (16)`; build and package only through `.github/workflows/ios-checks.yml`.
- RPK: `0.6.0 (15)`; build through `make test-rpk`.
- The application JSON adds bounded destination overlay fields. Xiaomi BLE/SPP/authentication bytes and Route v4 request behavior are unchanged.

## Curved-display estimate

The initial Smart Band 10 contour is estimated from the supplied wrist photographs and the official 212×520 pill display dimensions. It uses a centered pill with physical inset 12 px, top center y=106, bottom center y=413, independent 94 px cap radii, and 6 px visual margin around each resource. This is conservative but is not a hardware-measured pixel contour.

On the connected diagnostics screen, tap **CALIBRATE DISPLAY**. Photograph the 212×520 calibration image straight-on. It shows 6/10/14/18 px contours, center rulers, and 16 white directional probes. Tap the image to return. If any accepted probe or contour is clipped, adjust only `BandDisplaySafeMask.smartBand10PhotoEstimate` and the matching `safeMaskPixel` constants, regenerate the RPK, and repeat the full checks.

## Manual test plan

Use a passenger or stop safely before observing or operating either device. First complete a stationary route replay, then use a safe 0–50 km/h route containing a straight section, left turn, right turn, crossing road, and parallel road.

1. Install IPA `0.5.0 (16)` and RPK `0.6.0 (15)`, connect, open diagnostics, show the calibration image, and photograph it straight-on. Confirm the 14 px contour and all white probes are fully visible.
2. Start navigation while stationary. Confirm the map faces the route tangent, the enlarged green marker is centered on the active dark-blue route, and neither the HUD nor marker is cut by a curved edge.
3. With GPS accuracy near 10 m, confirm a completed instruction such as “straight 2 m” is replaced by the next actionable turn rather than flickering between steps.
4. Begin moving above 3.6 km/h. Confirm the map changes to travel-course heading only after stable movement and does not rotate for one poor or slow GPS fix.
5. Pass at least three maneuvers. Confirm distance decreases, maneuver/street changes once per turn, and the active route always begins at the user marker.
6. Select a destination outside the current viewport. Confirm an amber ring appears on the correct curved edge, never clips, moves directionally as the route changes, and becomes an amber destination pin when it enters view.
7. Stop and resume, then safely deviate from the route. Confirm GPS-low and rerouting states remain correct, no false bright connector is drawn, and the previous confirmed map remains visible if a refresh fails.
8. Export the sanitized debug log. Confirm it contains GPS quality, speed/course, matched segment/fraction, selected guidance, bearing source/delta, refresh decision, and destination mode without keys, exact raw captures, or device identifiers.

Compilation, simulator tests, and photographs do not establish full moving hardware acceptance. Record Pass/Fail and attach the straight-on calibration photo plus sanitized debug export.
