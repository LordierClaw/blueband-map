# BlueBand Map Product Overview

## Product definition

BlueBand Map is an unofficial motorcycle-navigation companion for Xiaomi Smart Band 10. An iPhone uses Vietmap as the Vietnam-focused map and routing provider, then sends a bounded map scene and compact navigation state over the project's existing direct Xiaomi BLE/RPK path.

```text
iPhone = navigation brain
Band   = thin navigation display
```

The iPhone owns location, routing, route progress, reroute, map asset preparation, the in-memory style/tile cache, camera decisions and recovery. The Band stores only the active route-card PNG, displays route/navigation information, and moves a native marker for turns.

## Why development is POC-gated

The direct iOS-to-Band application-message path is hardware-confirmed, but a complete Band 10 map renderer is not. Public documentation also leaves two important product questions open:

- Vietmap publicly lists street maps as vector styles; its listed raster XYZ source is Satellite.
- Vela documents images and 2D transforms but does not establish a general vector-path renderer for route geometry on Band 10.

BlueBand Map therefore proves one uncertainty at a time. The project owner loads each IPA/RPK pair, runs the provided device script and returns feedback. A later phase starts only after the current gate passes on the target devices.

## First target slice

- iPhone 13 Pro Max on iOS 26.
- Xiaomi Smart Band 10 on the firmware installed at test time.
- Motorcycle routing first.
- Vietmap free-trial TileMap and Service keys.
- One remembered Band and one companion app.
- Direct iOS BLE; no Android relay and no Mi Fitness replacement.

## Persistent configuration

The iOS app provides a dedicated Config area.

- Xiaomi AuthKey, Vietmap TileMap key and Vietmap Service key are stored separately in Keychain.
- The selected CoreBluetooth peripheral identifier, display name and last connection time are stored in UserDefaults.
- Connect opens a compact device picker showing up to 20 RSSI-sorted candidates, with the remembered Band highlighted first.
- Forgetting a Band does not delete any key.
- FE95/5E/5F GATT UUIDs are verified protocol constants, not editable settings.

## Map strategy

The intended architecture is a slow asset path and a fast state path:

```text
Slow path
Vietmap → iPhone validation/cache → bounded asset transfer → Band file store

Fast path
location/route progress → compact camera/nav state → Band local transform/UI
```

The project does not stream a newly captured full map image for every GPS update. It renders one 212×360 indexed PNG route card from the real Route v4 polyline and selected phone-side vector tiles, then sends only compact marker/instruction updates at up to 1 Hz. Static Map and Band-side vector payloads are not runtime paths.

## Phase roadmap

| Gate | Proof |
|---|---|
| M0 | Preserve existing hardware-confirmed application-message baseline |
| N1 | Vietmap Route v4 motorcycle contract, polyline decode and progress matching |
| N2 | Live route-card PNG with selected side roads and bounded transfer |
| N3 | Compact `nav.update` marker/instruction state and recovery statuses |
| N4 | Live GPS motorcycle navigation and controlled reroute road test |
| U1 | iOS/Band lifecycle, background and state-snapshot recovery matrix |
| U2 | Coherent configure-once motorcycle navigation vertical slice |

Current route-card status: **Implementation ready for owner hardware acceptance; not hardware-confirmed.** Hardware timing/readability/stability gates remain open.

Detailed gates, stop conditions and evidence rules are in the [approved POC roadmap design](../superpowers/specs/2026-08-29-blueband-map-poc-roadmap-design.md).

## Core UX

The Band screen is 212×520 and prioritizes glanceability:

1. Maneuver and next-turn distance.
2. Street name.
3. Map scene and strong route.
4. Fixed user puck with look-ahead space.
5. Remaining distance and ETA.

Near mode provides immediate road context. Far mode provides a larger forward overview without attempting to fit an arbitrarily long route. Pan is limited to the active working area and recenters; Band is not a free map browser.

## Out of the first slice

- Car and walking.
- Google Maps/Apple Maps Share Extensions.
- Traffic layer.
- Search-heavy or POI-heavy Band UI.
- Full vector map engine on Band.
- Full-route tile preload.
- Production backend/API-key proxy.
- Multiple Band models.

## Success definition

The first slice succeeds when the tester can configure keys once, select or reconnect the remembered Band through the compact dialog, choose an iPhone destination, complete a short motorcycle navigation session with readable map/route/maneuver state and end the session cleanly without re-entering configuration.

Compilation, simulator behavior and deterministic replay are necessary evidence but never sufficient to claim Xiaomi Smart Band 10 hardware support.
