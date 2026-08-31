# ADR 0010: live route-card renderer

**Status:** Accepted  
**Date:** 2026-08-31  
**Scope:** Foreground motorcycle navigation on iPhone and Xiaomi Smart Band 10

## Decision

Use one phone-rendered raster route card at exactly 212×360 pixels. The card
contains the real Vietmap Route v4 polyline, up to twelve selected whole road
polylines, a maneuver point, and four indexed colors. The payload is a PNG of
at most 1,024 bytes and is transferred with the existing `render.prepare` and
`map.asset.*` flow. The Band only displays the file and moves a native 8 px
marker from `nav.update` messages.

`nav.update` is bounded to the current scene and monotonic sequence:

```json
{"scene":"scene-...","seq":1,"x":106,"y":320,
 "maneuver":"right","distanceM":120,"street":"Next Road",
 "status":"navigating"}
```

The iPhone owns Core Location, Route v4, progress matching, reroute policy,
style/tile discovery and PNG budgeting. Tile/style failure keeps the route
valid and publishes route-only with `limitedMap`; a Route v4 failure does not
open navigation. No Static Map, vector payload, synthetic scene or runtime
mock is accepted.

## Consequences

The Xiaomi BLE/SPP/authentication/session bytes and ACK behavior are unchanged.
The application layer is deliberately small: one raster renderer, one scene
identity, a seven-data-chunk ceiling, and a one-Hz coalesced navigation state
path. Hardware timing, readability and stability still require iPhone + Band
acceptance; automated tests cannot claim those results.
