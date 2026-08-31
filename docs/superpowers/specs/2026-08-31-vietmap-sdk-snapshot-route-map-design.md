# Vietmap SDK Snapshot Route Map Design

**Status:** Approved in conversation on 2026-08-31

**Target hardware:** iPhone with Xiaomi Smart Band 10, 212×520 capsule display

**Primary acceptance:** A useful, recognizable 2D navigation map appears within five seconds at p95 when a recent accurate foreground GPS fix is available.

## 1. Purpose

Replace the hand-built four-color route-card renderer with a phone-rendered Vietmap map snapshot. The iPhone remains responsible for location, routing, progress, map rendering, image reduction, and transfer scheduling. The Band displays one full-screen image plus a small native navigation overlay and moving position marker.

The first version sends one complete 212×520 snapshot. Splitting the map into independently cached image tiles and composing them on the Band is intentionally deferred until the single-image path proves visual quality and transfer performance on hardware.

## 2. Evidence and diagnosis

The returned hardware log for the 9.5 km route recorded:

- 15.715 seconds waiting for a GPS fix at or below 25 m accuracy;
- about 160 ms for Vietmap Route v4;
- about 391 ms to fetch/render the current route-card;
- a 695-byte PNG containing 12 selected side-road polylines; and
- no `band.displayed` event before the log was exported.

The visual failure is architectural rather than a road-count tuning problem. The current runtime keeps line features only, reduces them to major/minor classes, omits fills and labels, does not preserve the full Vietmap style hierarchy, and renders only four hard-edged colors. It cannot produce a basic 2D map without recreating substantial map-engine behavior.

A bounded live metadata probe with the configured TileMap key confirmed that the current Vietmap light style contains 189 layers: 16 fill, 71 line, 98 symbol, one background, and three fill-extrusion layers. The documented raster style contains one baked raster layer. The vector style therefore contains the semantic detail needed for a simplified wearable map, while the raster style cannot selectively remove baked labels or points of interest.

The official Vietmap iOS package at commit `649eabcb21a36c3d0cfd871c07ccea641924fcdd` contains `MGLMapSnapshotter`, snapshot style customization, camera control, geographic-to-image coordinate conversion, and a Core Graphics overlay hook. This is the selected rendering boundary.

## 3. Product boundary

Version 1 is a foreground motorcycle-navigation display, not a general map browser. The visible map contains:

- land/background context;
- water;
- a restrained subset of land use;
- building footprints only at a close zoom;
- road casing and fills for major and useful minor roads;
- a small number of road labels;
- traveled and upcoming route segments;
- the next maneuver point; and
- the current position marker.

It excludes POI icons, transit detail, house numbers, administrative labels, traffic, terrain, satellite imagery, 3D buildings, free pan, and free zoom.

## 4. Architecture

```text
CoreLocation prewarm
    -> Route v4 and existing RouteProgressTracker
    -> MGLMapSnapshotter with simplified Vietmap light style
    -> Core Graphics route overlay
    -> 212×520 palette reduction and indexed PNG
    -> bounded windowed application transfer
    -> Vela full-screen image
       + translucent native maneuver overlay
       + native moving position marker
```

No Xiaomi BLE, SPP, authentication, encryption, ThirdPartyApp, transport acknowledgement, or TOFU bytes change. Only the map asset contract and the application-level transfer schedule change.

## 5. Location and startup latency

Foreground location starts when the connected navigation/configuration screen becomes active, rather than after the Start button is pressed. A fix is immediately reusable only when:

- its horizontal accuracy is valid and at most 25 m; and
- its age is at most 10 seconds.

Pressing Start produces visible state feedback within 100 ms. With a reusable fix, routing begins immediately. Without one, the UI and Band show `GPS LOW` or `LOCATING`; the GPS wait is measured separately from route, snapshot, encode, and transfer time.

The map style and SDK renderer are warmed while the foreground screen is active. Provider requests are still bounded, and no route request occurs until the user starts navigation.

## 6. Snapshot rendering

### 6.1 SDK scope

Add only the official Vietmap Map SDK binary package. Do not add Vietmap Navigation SDK in this version. Existing `VietmapRouteClient`, `RouteProgressTracker`, off-route detection, and reroute policy remain authoritative.

The SDK is isolated in the iOS adapter layer. Portable route and navigation domain types remain in `BlueBandMapCore` and Linux tests do not import the binary SDK.

### 6.2 Style

Use the documented Vietmap light vector style. After the snapshotter reports that the style has loaded, remove unwanted layers by semantic type and identifier. Keep a small allowlist derived from the live style fixture rather than duplicating the whole upstream style.

The retained hierarchy is:

1. background and land;
2. water;
3. selected park/residential/school/hospital land use;
4. buildings at close zoom;
5. minor-road casing and fill;
6. major-road casing and fill; and
7. selected road-name symbols.

Style discovery failure is terminal for a first navigation start. A previously confirmed map remains visible during a later refresh failure, accompanied by `LIMITED MAP`.

### 6.3 Camera

The snapshot is exactly 212×520 points at scale 1. The map is heading-up with zero pitch. The matched user position is centered horizontally and placed near 72% of the screen height so that more route is visible ahead than behind.

Zoom adapts to the next maneuver and road density within a narrow navigation range. The navigation overlay footprint is included as camera padding so that the route and next maneuver are not hidden under UI.

### 6.4 Route overlay

The snapshot overlay handler draws from the existing real Route v4 polyline using the SDK's coordinate conversion:

- traveled route: muted dark gray, 4 px;
- upcoming route halo: near-black, 8 px;
- upcoming route: cyan, 5 px; and
- maneuver point: cyan ring or dot, never omitted.

The route remains continuous. Image reduction may remove low-priority labels or land-use colors, but never route geometry, major roads, the maneuver point, or the user's marker contrast.

## 7. Image reduction

The source snapshot is reduced on iPhone to an indexed PNG using native Apple frameworks and existing project encoding code. No third-party image dependency is added.

Profiles are attempted in this order:

1. 32-color palette with selected road labels;
2. 16-color palette with selected road labels;
3. 16-color palette with low-priority labels removed; and
4. 16-color palette with low-priority land use removed.

The initial payload admission ceiling is 8 KiB. The target operating range is 4–8 KiB. The encoder reports chosen profile, encoded bytes, color count, and encode duration. It does not fall back to the old four-color route-card.

PNG is preferred over JPEG because thin road strokes and small text must remain crisp. JPEG is not part of version 1.

## 8. Band visual design

The image fills the complete 212×520 page. The map is not placed below a separate opaque header.

A native overlay is centered near the top:

- width: approximately 184 px;
- height: 116–128 px;
- rounded corners: 22–26 px;
- background: approximately `rgba(4, 12, 20, 0.68)`;
- centered maneuver arrow and distance;
- centered street name, at most two lines; and
- exceptional status only.

Normal `NAVIGATING` text is hidden. `GPS LOW`, `REROUTING`, `LIMITED MAP`, and `ARRIVED` remain visible. During initial asset transfer, the overlay reports a useful phase such as `LOADING MAP` rather than `WAITING` over an already visible image.

The current-position marker remains a native element above the map. It is a white center with a cyan outline and moves using compact `nav.update` messages. The route is part of the snapshot image and is not reconstructed from rotated div elements.

## 9. Windowed asset transfer

The 512-byte application-envelope ceiling remains unchanged. Base64 chunk sizing continues to be derived from actual encoded envelope size. SHA-256, offsets, scene/run correlation, duplicate handling, disconnect cleanup, and atomic publication remain mandatory.

The iPhone benchmarks application acknowledgement windows of 1, 2, and 4. The first implementation supports a bounded configurable window and defaults conservatively until hardware evidence selects the fastest stable value.

The Band accepts multiple in-flight chunk message IDs for one prepared asset, writes each validated in-order offset into the preallocated buffer, and acknowledges it immediately. The iPhone sends the next chunk when a slot opens. Any wrong offset, timeout, digest mismatch, or disconnect aborts the generation; it is never guessed or silently skipped.

Windowing changes application scheduling only. Xiaomi transport acknowledgements remain untouched. A stop-and-wait window of 1 remains the safe fallback.

## 10. Runtime refresh

The map image is not regenerated for every location update. `nav.update` continues at no more than 1 Hz and moves the marker plus native instruction UI.

A new snapshot is required only when:

- the matched marker leaves the inner safe viewport;
- the user passes the current maneuver and the next context materially changes;
- a reroute succeeds; or
- the current zoom no longer contains the required maneuver context.

While a refresh is being prepared and transferred, the confirmed previous map remains visible. A newer pending refresh replaces an older queued refresh before transfer begins.

## 11. Diagnostics

The exported debug log records separate durations for:

- GPS wait;
- route request;
- style warm/load;
- snapshot rendering;
- palette reduction;
- transfer prepare;
- chunk transfer;
- Band file write/decode/publication; and
- total time to `band.displayed`.

It also records payload bytes, palette size, retained layer counts, transfer window, chunk count, acknowledgement p50/p95/max, cache state, and stable error code. It continues to omit keys, complete identifiers, raw captures, full coordinates, encrypted data, and signing material.

## 12. Testing

Portable tests cover palette reduction policy, payload admission, refresh decisions, update coalescing, stale generations, and metrics. iOS simulator tests cover SDK adapter construction, style allowlisting against a sanitized fixture, camera configuration, snapshot completion/error handling, route overlay placement, and PNG dimensions. Band tests cover full-screen layout, translucent overlay, exceptional statuses, multiple in-flight IDs, ordered offsets, timeout cleanup, digest rejection, stale scenes, and atomic publication.

The canonical repository gate remains:

```bash
make clean
make bootstrap
make test
make lint
scripts/verify-no-secrets.sh
git diff --check
```

GitHub Actions remains the authority for Xcode compilation, simulator tests, and unsigned IPA production.

## 13. Hardware acceptance

Test on iPhone plus the target Smart Band 10:

- first visible state feedback at most 100 ms after Start;
- with a recent accurate GPS fix, useful map p95 at most 5 seconds over five starts;
- snapshot plus palette reduction p95 at most 1.5 seconds when style resources are warm;
- map transfer p95 at most 3 seconds for the selected payload/profile;
- select the fastest stable window among 1, 2, and 4 over five transfers each;
- payload at most 8 KiB;
- map clearly shows relevant major/minor roads, intersections, water/land context, selected buildings, and useful road labels;
- route is continuous, prominent, correctly aligned, and not obscured by the overlay;
- marker and instruction update p95 at most 1 second;
- a tester identifies the next turn within two seconds in at least four of five samples; and
- 30 minutes without freeze, black screen, RPK crash, or Band reboot.

Cold GPS acquisition is reported separately and cannot be presented as renderer or transfer latency. Automated and simulator success do not replace hardware acceptance.

## 14. Deferred tiled map engine

A later version may divide snapshots into independently identified image tiles, cache them on the Band, load visible tiles progressively, and compose a wider moving scene. That work requires separate hardware evidence for simultaneous image count, memory, seams, publication atomicity, panning, eviction, and recovery.

Version 1 deliberately does not add tile manifests, tile-cache abstractions, Band-side map transforms, or multi-image composition. The existing scene/run identity and atomic asset publication provide enough evidence for designing that protocol after the single-image path has measured payload and throughput.
