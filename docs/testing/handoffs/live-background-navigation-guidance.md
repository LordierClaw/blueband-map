# Live background navigation guidance handoff

## Versions

- iOS: `0.5.9 (25)`
- RPK: `0.6.11 (26)`
- Target: iPhone on iOS 17+ and Xiaomi Smart Band 10

## Changes

- Vietmap step distances now drive the remaining distance and the following maneuver/street label; street whitespace is trimmed.
- Heading-up maps refresh after one second of meaningful movement or heading change, coalescing to one latest pending snapshot. Turns and U-turns therefore request a newly rotated iOS snapshot while the Band marker remains fixed at `(106,374)`.
- The artificial blue maneuver dot was removed. Existing map, route, marker assets, snapshot compression, `212×520` dimensions, and `8192-byte` admission remain intact.
- Active navigation owns iOS background location/Bluetooth execution; stopping navigation releases it. Foreground prewarming does not enable background execution.
- The Band echo/ping UI was removed. After connection it shows `CHỜ LỆNH TỪ IPHONE…`, and during a map refresh it keeps the latest confirmed-scene guidance visible until the replacement scene is published.
- Application-envelope topics/bodies/version, render protocol, `nav.update`, Xiaomi BLE/SPP/authentication, and ThirdPartyApp bytes did not change.

## Basic manual test

Do not operate the phone while riding; stop safely or ask a passenger to observe.

1. Install RPK `0.6.11 (26)` with AstroBox and IPA `0.5.9 (25)` from the GitHub Actions artifact. Confirm AstroBox does not report `InstallFailed`.
2. Open the RPK, connect from the iPhone, and confirm the Band changes from the connection-loading screen to only `CHỜ LỆNH TỪ IPHONE…`; no echo log, ping button, or clear button is visible.
3. Start a route containing a left turn, right turn, and preferably a U-turn. Confirm each header uses the correct changing maneuver icon, trimmed street being entered, and compact remaining `m`/`km` distance.
4. Inspect route corners. They must remain ordinary joined line corners, with no blue circular dot that could look like a roundabout.
5. Lock the iPhone and move along the route. For ten consecutive GPS updates, compare the exported `map.refresh.scheduled` and `band.displayed` timestamps; each displayed update should use a recent fix and meet the under-five-second hardware target while iOS keeps the session alive.
6. Complete the left/right/U-turn cases. After each direction change, confirm the new map is rotated heading-up, the route leaves the cursor tip straight upward, and the cursor remains fixed at lower centre rather than rotating or drifting.
7. During each 3–4 second replacement transfer, confirm the old map stays visible and the maneuver/distance/street continue updating; there must be no blank frame, stale preview header, `MAP_PAYLOAD_TOO_LARGE`, or `BAND_DISPLAY_FAILED`.
8. Tap **Dừng điều hướng**, lock the iPhone, and wait at least 30 seconds. Confirm the location background indicator ends and no later `map.refresh.scheduled`/`band.displayed` entry is added.

Automated tests and package verification cannot establish the locked-screen latency, continuous BLE delivery, visual rotation, or cleanup on real hardware; record those four cases separately during acceptance.
