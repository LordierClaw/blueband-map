# Changelog

All notable changes are recorded here. The iOS app, RPK, and application-envelope versions are tracked independently in release manifests.

## Unreleased

- Replace the four-color 212×360 route card with a pinned Vietmap SDK 212×520 snapshot, semantic layer reduction, heading-up camera, native route/maneuver overlay, and 16/32-color indexed PNG admission up to 8 KiB.
- Add recent foreground GPS reuse, bounded snapshot refresh, latest-only pending locations, application ACK windows 1/2/4, atomic Band publication, full-screen translucent navigation UI, and expanded redacted timing counters.
- Bump iOS to `0.2.0 (11)` and RPK to `0.3.0 (12)` because both packaged artifacts changed. Xiaomi BLE/SPP/authentication bytes remain unchanged.
- Establish the BlueBand Map foundation design and Linux-first workspace.
- Add the live route-card slice: real Vietmap Route v4 motorcycle routing, foreground GPS progress/reroute, phone-side road-tile rasterization, ≤1,024-byte PNG transfer, and coalesced `nav.update` state for the Band.
- Fix Route v4 responses that contain multiple valid paths by selecting the shortest path, and add an in-app navigation debug export with route-step details.
- Encode the four-color route-card at 2 bits per pixel, clip crossing roads correctly, place the maneuver marker at the instruction endpoint, and export diagnostics as a real text file.
