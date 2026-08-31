# Changelog

All notable changes are recorded here. The iOS app, RPK, and application-envelope versions are tracked independently in release manifests.

## Unreleased

- Establish the BlueBand Map foundation design and Linux-first workspace.
- Add the live route-card slice: real Vietmap Route v4 motorcycle routing, foreground GPS progress/reroute, phone-side road-tile rasterization, ≤1,024-byte PNG transfer, and coalesced `nav.update` state for the Band.
- Fix Route v4 responses that contain multiple valid paths by selecting the shortest path, and add an in-app navigation debug export with route-step details.
- Encode the four-color route-card at 2 bits per pixel, clip crossing roads correctly, place the maneuver marker at the instruction endpoint, and export diagnostics as a real text file.
