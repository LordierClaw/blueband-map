# Map and Navigation Feasibility Review

**Reviewed:** 2026-08-29

This review records the evidence used to replace product assumptions with POC gates. Links are current official documentation where available; source repositories are pinned to reviewed revisions.

## Findings matrix

| Area | Evidence | Finding | Project consequence |
|---|---|---|---|
| Band display | [Xiaomi Band 10 screen adaptation](https://iot.mi.com/vela/quickapp/en/guide/multi-screens/) | Band 10 is documented as a 212×520 capsule display | Use a tall viewport and hardware-tune overscan/node count |
| Image rendering | [Vela image](https://iot.mi.com/vela/quickapp/en/components/basic/image.html) | Local/cloud PNG and JPG are supported with completion/error events | Raster basemap is a supported primitive, not yet a performance proof |
| Image transfer | [Xiaomi samples](https://iot.mi.com/vela/quickapp/en/samples/) | Official sample fragments Base64 image data over interconnect, assembles it, writes a local file and displays it | M1 follows a provider-independent, officially demonstrated pattern over the project's verified iOS bridge |
| Local files | [Vela file storage](https://iot.mi.com/vela/quickapp/en/features/data/file.html) | `writeArrayBuffer`, read, access and delete are available; docs warn to remove unused files | Use bounded store, atomic publication and explicit eviction |
| Scene transforms | [Vela animation styles](https://iot.mi.com/vela/quickapp/en/components/general/animation-style.html) | 2D translate, scale and rotate are documented | M4 can test heading-up local transforms; supported syntax is not a frame-rate claim |
| Touch | [Vela common events](https://iot.mi.com/vela/quickapp/en/components/general/events.html) | Touch start/move/end expose coordinates and identifiers | M3 can implement bounded pan and double-tap detection |
| Haptic | [Vela vibrator](https://iot.mi.com/vela/quickapp/en/features/system/vibrator.html) | Band 10 supports `vibrate(short|long)` but not the newer programmable start/stop APIs | Use only short/long patterns and deduplicate on iPhone |
| Interconnect | [Vela interconnect](https://iot.mi.com/vela/quickapp/en/features/network/interconnect.html) | Singleton object messaging and lifecycle callbacks are documented | Keep the existing hardware-confirmed direct bridge and add application topics above it |
| Street map | [Vietmap Tilemap](https://maps.vietmap.vn/docs/vi/map-api/tilemap/) | Current street/light/dark/hybrid entries are vector styles | Do not assume public raster street XYZ |
| Raster XYZ | [Vietmap Tilemap](https://maps.vietmap.vn/docs/vi/map-api/tilemap/) | Public raster XYZ entry is Satellite without labels | Use it to prove tile coordinates/grid/cache, not final street appearance |
| Street PNG | [Vietmap Static Map](https://maps.vietmap.vn/docs/vi/map-api/static-map-version/static-map/) | API returns PNG for center, zoom and size | Use it for M1 street-image vertical proof, not realtime screenshot streaming |
| Routing | [Vietmap Route v4](https://maps.vietmap.vn/docs/vi/map-api/route-version/route-v4/) | Supports `motorcycle`, encoded polyline, instructions, distance, duration and documented error codes | Build N1 as a thin HTTP/domain contract before Navigation SDK integration |
| Navigation | [Vietmap iOS Navigation SDK](https://maps.vietmap.vn/docs/vi/sdk-mobile/sdk-ios/navigation/) | Documents progress and reroute delegate events and background location configuration | Defer SDK to N4 after deterministic replay and isolate it at Apple boundary |
| Usage accounting | [Vietmap transaction accounting](https://maps.vietmap.vn/docs/map-api/console/request-to-transaction/) | 25 tile requests count as one transaction; routing depends on waypoint count | Use per-script call budgets, fixture-only tests and cache-hit assertions |
| iOS background location | [Apple background location](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background) | Navigation is a justified background-location case but requires explicit lifecycle configuration | Test in U1, not as a renderer prerequisite |
| iOS background BLE | [Apple Core Bluetooth](https://developer.apple.com/documentation/corebluetooth) and [TN3115](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules) | iOS 26 adds background behavior options; restoration has eligibility limits, including force-quit behavior | Produce an observed recovery matrix and avoid blanket background claims |

## Repository comparisons

### Existing direct iOS/Band baseline

The sibling `blueband-ios` repository at `bae2f51ce4dfb12cff81e72d9146812092cd861e` is the read-only protocol baseline. It confirms direct iOS BLE authentication, ThirdPartyApp routing, RPK `system.interconnect` and acknowledged arbitrary messages on Band 10. BlueBand Map already ports this foundation; map work must not replace it.

### Vietmap iOS map SDK

`vietmap-company/maps-sdk-ios` at `649eabcb21a36c3d0cfd871c07ccea641924fcdd` exposes a Swift package containing a binary XCFramework. This is a useful official integration boundary but not Linux-portable source. Early POCs therefore use explicit HTTP contracts; the Apple binary boundary is introduced only when its rendering/navigation behavior is required.

### Xiaomi Band development workflow

`oryonatan/xiaomi-band-development` at `37c9562102a34451384c70ce4ce2dad4decaee8b` independently records Band 10's 212×520 design size and practical Vela build/sideload workflow. It supports the device/layout assumptions already present in the project baseline, but it does not prove map rendering performance.

### Legacy navigation-only comparison

`satvikpandurangi/MiBandNavigator` at `bee0b32e29f2e9cf03457595d3cb115d79ef90c5` extracts Google Maps notification text and forwards compact turn arrows to legacy bands. It demonstrates the value of navigation-first fallback and duplicate vibration control, but it explicitly does not show a map and uses a different Android notification architecture.

### Full Android navigation comparison

Navigation apps built on a phone map engine commonly separate route progress, heading-up camera, pan-away/recenter and haptic guidance. Those product patterns inform BlueBand Map's UX, but phone-side Android rendering performance does not transfer to Vela Band 10 and is not used as hardware evidence.

## Gaps that require project POCs

No reviewed public repository establishes all of the following together on Xiaomi Smart Band 10:

- Multiple dynamically received map images active as one scene.
- Reliable scene pan and rotation over a 212×520 viewport.
- Stable transform update frequency.
- Dynamic route overlay aligned to that scene.
- Incremental working-set refill over the project's direct iOS BLE path.
- Live Vietmap motorcycle route progress and reroute.

These are not treated as impossible. They are named M2–N4 gates with measured fallbacks.

## Provider questions to resolve before M5

The project owner or developer should ask Vietmap support only for documented, supported capabilities:

1. Does the issued TileMap trial key include a supported raster street XYZ endpoint?
2. Can a custom simplified raster style be issued for a small wearable display?
3. Are client-side cache duration and derived/rasterized atlas storage permitted by the trial/production terms?
4. What exact daily quota and expiry apply to each issued key?
5. Which current iOS navigation integration path is recommended for iOS 26 and Swift Package/XcodeGen projects?

If the answer to raster street availability is no, the next supported experiment is phone-side rendering through Vietmap's documented SDK/style resources. The project will not scrape undocumented tile URLs.

## Conclusion

The project is feasible enough to justify incremental development because every primitive needed for the first vertical proof is documented or already hardware-confirmed: direct messages, image fragments, local files and image display. A full smooth map/navigation product is not yet proven. Raster street sourcing, multi-image performance, route overlay and lifecycle recovery remain explicit decision gates rather than promises.

## Historical provider evidence

The following measurements are retained as evidence for why the original H1
experiments were replaced. They are not runtime behavior.

The provider probe now permits exactly one Route v4 or TileMap style request per invocation, requires the supplied key file to be mode `600`, keeps the key in curl configuration on stdin instead of the process arguments, disables redirect following, caps the response body, and records only status, normalized MIME, byte count, and SHA-256 under the ignored `local/provider-smoke/` directory. The probe never stores or prints the response body or effective URL.

The historical static and style invocations called the documented endpoints. Fake-curl tests exercise MIME, bounds, permission, redaction, and one-call behavior without spending trial quota. A successful local or CI test of the script is not provider acceptance; live Route v4 and style results remain separate, single-call evidence items.

On 2026-08-31 the configured trial keys were exercised against the documented endpoints. Static Map at the H1 coordinate, zoom 16 and 212×360 returned HTTP 200 `image/png` and 22,484 bytes. The documented Static Map contract always renders a marker and either automatic or supplied address text; it exposes no supported switch for removing labels, POIs, the marker or the address card. Pixel quantization can reduce bytes but cannot remove those elements semantically, so H1 no longer uses Static Map as a renderer candidate.

The historical `tm/style.json` response was 113,407 bytes and selected one vector source with `maxzoom=15`. Those observations motivated the current route-card implementation: it fetches a bounded 3×3 working set around the route, keeps whole road polylines on the phone, and rasterizes only selected side roads together with the active Route v4 polyline.

The current Vietmap GL JS v6 transport marks transformed tiles with the three-byte prefix `01 01 01` and applies its current 32-byte XOR transform after removing that prefix. Legacy TileMap data uses the previous transform, while ordinary MVT may be untransformed. The decoder handles these three explicit forms and has independent vectors for each; it does not infer a format from MIME because the live tile response omitted `Content-Type`.

The historical four-color road raster exceeded the new 1,024-byte payload budget. The route-card encoder therefore drops lower-ranked side roads and simplifies only after the route and maneuver are retained; the runtime transfer plan caps data at seven chunks.
