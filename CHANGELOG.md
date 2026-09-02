# Changelog

## iOS 0.5.9 / RPK 0.6.11 - 2026-09-02

- Pair the next Vietmap maneuver and trimmed destination street with the provider distance remaining to that turn, including overlapping instruction intervals observed in hardware logs.
- Refresh the heading-up snapshot after one second of meaningful movement or a 30-degree bearing change, keep only the newest pending refresh, and remove the route-turn ellipse while preserving the fixed lower-centre cursor and accepted destination marker.
- Keep location and Bluetooth active only during an explicit navigation session so locked-screen updates can continue; stop releases the Core Location background activity. A displayed update within five seconds remains a real-device acceptance target.
- Remove the RPK echo/ping screen in favour of a clean iPhone-command waiting state, and keep live guidance visible while a replacement map scene is transferred and published.
- Bump iOS to `0.5.9 (25)` and RPK to `0.6.11 (26)` because both packaged components change. Application-envelope, render/navigation payload, Xiaomi BLE/SPP/authentication, `212×520`, and `8192-byte` contracts remain unchanged.

## iOS 0.5.7 / RPK 0.6.9 - 2026-09-02

- Render heading-up Vietmap snapshots at 2× and downsample once before the existing 16-colour, 212×520, ≤8192-byte admission path; use high-quality interpolation in the iPhone preview.
- Replace the cached triangular Band marker path with the approved dark-green, borderless cursor resource whose tip/notch axis is fixed on the route centreline.
- Move only the off-screen destination chevron from a 6 px to a 2 px visual margin while retaining full curved-mask containment, and widen the transparent street label to x=198.
- Bump iOS to `0.5.7 (23)` and RPK to `0.6.9 (24)` because both packaged components change. Xiaomi BLE/SPP/authentication bytes and the 8192-byte render protocol remain unchanged.

## iOS 0.5.1 / RPK 0.6.0 - 2026-09-01

- Encode the existing 16-color snapshot palette at its native 4-bit indexed PNG depth instead of wasting 8 bits per pixel.
- If every full-detail style still exceeds 8 KiB, retry the already-rendered snapshots with bounded 2×, 4×, then 8× spatial blocks so navigation starts instead of failing with `MAP_PAYLOAD_TOO_LARGE`.
- Bump only iOS to `0.5.1 (17)` because snapshot encoding changes the IPA. RPK remains `0.6.0 (15)`.

## iOS 0.5.0 / RPK 0.6.0 - 2026-09-01

- Keep the road-snapped marker and active route continuous at the exact fractional route match without changing monotonic progress, off-route thresholds, reroute cooldown, or Vietmap Route v4.
- Skip only GPS-indistinguishable completed guidance, use route-tangent heading while stationary, and adopt GPS course after two reliable moving fixes with three-fix fallback and bounded refresh hysteresis.
- Add a curved-safe destination pin and off-screen edge ring, enlarge the green user marker and maneuver arrow, move the HUD inward, and include a Band display calibration screen estimated from the supplied hardware photographs.
- Bump iOS to `0.5.0 (16)` and RPK to `0.6.0 (15)` because both packaged artifacts change. Xiaomi BLE/SPP/authentication bytes remain unchanged.

## iOS 0.4.1 / RPK 0.5.0 - 2026-09-01

- Ignore low-speed or invalid GPS course when requesting the initial route so Vietmap Route v4 is not constrained by a noisy stationary heading.
- Add route-request speed diagnostics and a regression test for reliable heading selection.
- Bump only iOS to `0.4.1 (15)` because only the IPA changes. RPK remains `0.5.0 (14)`.

## iOS 0.4.0 / RPK 0.5.0 - 2026-09-01

- Preserve familiar urban context with dark road hierarchy, buildings, land use, major/secondary labels, and a bounded POI allowlist.
- Prefer PNG8 snapshots up to 5 KiB, use 1 KiB application envelopes and a four-message ACK window to reduce Band transfer round trips.
- Refresh the full map no more often than every 12 seconds unless rerouting, while keeping the latest pending location and updating guidance independently.
- Keep the compact HUD and the larger green directional marker inside Band-safe bounds; render the upcoming route as a flat dark-blue line.
- Bump iOS to `0.4.0 (14)` and RPK to `0.5.0 (14)` because both packaged artifacts changed. Xiaomi BLE/SPP/authentication bytes remain unchanged.

## iOS 0.3.0 / RPK 0.4.0 - 2026-09-01

- Request Vietmap's dark style, normalize retained map layers to a low-entropy dark palette, and draw the route as a flat cyan line without a halo.
- Prefer 16-color indexed PNG snapshots at or below 4 KiB, with the smallest valid candidate up to 8 KiB as a hard fallback.
- Show maneuver, distance, and street from `render.prepare` instead of waiting for map publication.
- Replace the rectangular Band header with the compact B1 full-width fade HUD and replace the dot with eight exact-size M1 directional PNG8 markers.
- Use an application ACK window of two while serializing complete SPP frames on the BLE wire; restore confirmed guidance when a refresh is cancelled or fails.
- Bump iOS to `0.3.0 (13)` and RPK to `0.4.0 (13)` because both packaged artifacts changed. Xiaomi authentication and verified wire bytes remain unchanged.

## 0.2.1 - 2026-08-31

- Fix the buffered `render.ready` timeout remaining active during a slow Band transfer.
- Preserve the exact Band render terminal code in navigation diagnostics and place events before route instructions in exports.
- Bump only iOS to `0.2.1 (12)`; RPK remains `0.3.0 (12)` because Band source is unchanged.

All notable changes are recorded here. The iOS app, RPK, and application-envelope versions are tracked independently in release manifests.

## Unreleased

- Replace the four-color 212×360 route card with a pinned Vietmap SDK 212×520 snapshot, semantic layer reduction, heading-up camera, native route/maneuver overlay, and 16/32-color indexed PNG admission up to 8 KiB.
- Add recent foreground GPS reuse, bounded snapshot refresh, latest-only pending locations, application ACK windows 1/2/4, atomic Band publication, full-screen translucent navigation UI, and expanded redacted timing counters.
- Bump iOS to `0.2.0 (11)` and RPK to `0.3.0 (12)` because both packaged artifacts changed. Xiaomi BLE/SPP/authentication bytes remain unchanged.
- Establish the BlueBand Map foundation design and Linux-first workspace.
- Add the live route-card slice: real Vietmap Route v4 motorcycle routing, foreground GPS progress/reroute, phone-side road-tile rasterization, ≤1,024-byte PNG transfer, and coalesced `nav.update` state for the Band.
- Fix Route v4 responses that contain multiple valid paths by selecting the shortest path, and add an in-app navigation debug export with route-step details.
- Encode the four-color route-card at 2 bits per pixel, clip crossing roads correctly, place the maneuver marker at the instruction endpoint, and export diagnostics as a real text file.
