# Familiar dark Band map, safe-area, and urban refresh design

**Date:** 2026-09-01  
**Status:** Approved design; implementation plan pending review  
**Target:** iPhone + Xiaomi Smart Band 10, city riding at 0–50 km/h

## Context

The latest hardware run improved first useful guidance because `render.prepare` now shows the maneuver before map publication. The full map is still too slow and the visual composition still assumes a rectangular 212×520 display.

The observed run reached the route response at 343 ms, produced a 4,723-byte 16-color PNG at 539 ms, and reported Band publication at 51,638 ms. Snapshot and encoding took only 26 ms and 2 ms. The dominant problem is therefore application transfer/publication, not Vietmap rendering. At 30 km/h a rider travels about 425 m in 51 seconds; at 50 km/h, about 708 m. A full map transfer at that cadence cannot keep a city navigation scene centered.

The current style already retains building, land-use, road, and label geometry, but several retained layers collapse into nearly identical dark colors. The map consequently looks more like a route diagram than a familiar 2D map. The current HUD and marker are clamped against a rectangular viewport, while the physical display has strongly rounded top and bottom edges.

## Goals

- Preserve the visual grammar of a familiar 2D road map while simplifying it for a 212×520 dark display and indexed PNG transfer.
- Keep road hierarchy, intersections, building footprints, useful land-use context, water, parks, and selected labels legible.
- Keep the route and current position immediately distinguishable.
- Keep all actionable HUD content and the live marker inside a conservative pill-shaped safe area.
- Keep live guidance near 1 Hz and make full-map refresh practical for city riding at 0–50 km/h.
- Reduce application ACK round trips without changing Xiaomi BLE, SPP, authentication, encryption, transport ACK, or verified wire bytes.

## Non-goals

- Satellite, terrain, traffic, 3D buildings, free pan, or free zoom.
- A dense POI browser or complete reproduction of the phone map.
- Refreshing the bitmap for every GPS fix or every instruction text change.
- Claiming a latency target from simulator, CI, or deterministic tests; Smart Band 10 measurements remain required.

## Selected approach

Use a familiar dark map with controlled detail, not an ultra-minimal route diagram and not a full-detail phone map. Improve transfer independently from visual detail so the map does not need to lose its basic cartographic structure to become faster.

The implementation continues to request Vietmap's official dark style. It retains a bounded set of provider layers, rewrites their paint into a deterministic indexed-friendly palette, draws the active route on iOS, encodes PNG8, and transfers the complete image to the Band. The Band continues drawing the current-position marker and HUD natively over the raster.

## Familiar dark map style

### Always retained

- Background and land mass.
- Water and ocean.
- Parks, grass, and wooded areas.
- Residential, school, and hospital land use.
- Building footprints at zoom 16 and 17.
- Road, bridge, and tunnel geometry, including the provider's width hierarchy.
- Major and secondary road labels; minor road labels only at close zoom.

### Conditionally retained

The familiar-detail profile retains only navigation-relevant POI layers at zoom 16–17 whose lowercase identifiers contain `poi_hospital`, `poi_school`, `transit_station`, or `parking`. The next degradation profile removes all POI layers. The implementation does not synthesize missing POIs or add a second API request.

### Removed

- 3D/extruded buildings, shadows, textures, and decorative effects.
- Administrative boundaries and large regional labels that do not help the current maneuver.
- House numbers, shops, commercial icons, and dense low-priority POIs.
- Transit network detail beyond the small station allowlist.

### Palette and hierarchy

The 16-color palette keeps distinct slots for background, generic land, buildings, residential/clinical land use, park/vegetation, water, minor roads, secondary roads, major roads, road casing, labels, route, and current-position marker.

- Background: near-black navy.
- Buildings: cool slate, visibly separate from generic land.
- Residential: dark blue-gray.
- School/hospital land use: muted indigo.
- Parks/vegetation: restrained dark green.
- Water: restrained dark blue.
- Minor roads: low-contrast blue-gray.
- Secondary roads: medium blue-gray.
- Primary/motorway roads: brighter blue-gray.
- Active upcoming route: flat `#2F6BFF`, no border or halo.
- Traveled route: subdued slate-blue.
- Current-position marker: bright `#66FF7A` with a near-black outline.

Road casing remains only to preserve ordinary road shapes and junction hierarchy. The active route itself remains one flat stroke.

### Payload degradation order

Candidates degrade cartographic detail in this order:

1. Familiar detail: selected POIs, useful road labels, buildings, and land use.
2. Remove selected POIs and minor road labels.
3. Remove low-priority land use while retaining buildings, road hierarchy, water, parks, and major labels.

The preferred candidate ceiling is 5,120 bytes. If no preferred candidate fits, send the smallest valid candidate up to the existing 8,192-byte hard limit. The renderer never removes the active route or collapses all ordinary roads into one visual class merely to meet the preferred ceiling.

## Pill-shaped safe area

The full-width fade may extend to the physical edge because it is decorative. Actionable content must stay centered:

- HUD content rectangle: x 32–180, y 16–92.
- Maneuver image: 38×48, left edge 34.
- Distance and street block: x 78–178.
- Street remains one line; exceptional status remains below it.
- No text or icon may intentionally occupy the top corner regions.

The live marker asset becomes 38×44. Its visible chevron is materially larger than the current marker and retains a transparent margin plus dark outline. The marker center is clamped to x 30–182 and y 130–478, so it remains visible while a replacement snapshot is in flight.

Snapshot refresh uses a stricter inner rectangle, x 36–175 and y 144–463. Leaving that rectangle schedules a recentered map, but the displayed marker remains clamped until the new scene is confirmed.

## Urban update policy

HUD and marker updates remain coalesced and application-acknowledged at approximately 1 Hz. They do not wait for a new bitmap.

A full snapshot refresh is scheduled when any of these conditions occurs:

- The matched position has moved at least 175 m from the confirmed snapshot anchor.
- The projected marker exits the strict snapshot refresh rectangle.
- The next maneuver leaves the snapshot viewport.
- A reroute succeeds.

Changing only the instruction text or interval does not refresh the bitmap if the marker and next maneuver still fit. A minimum 12-second interval applies between ordinary full-map refresh starts. A reroute bypasses the ordinary interval. Existing generation coalescing remains: at most one transfer is active and only the newest pending refresh survives.

For city riding, the intended outcome is a context-dependent full-map refresh roughly every 15–25 seconds while moving, rather than a fixed timer. Slow movement or a long straight segment may reuse the map longer; a turn or reroute may refresh sooner.

## Transfer design

The paired release raises the application-envelope ceiling from 512 to 1,024 encoded JSON bytes. Chunk data is still selected from the actual encoded envelope rather than a fixed raw byte count. Control messages remain below 512 bytes.

The default application ACK window becomes four. Begin and end remain ordered barriers. Complete SPP frames remain serialized on the BLE wire. The iOS coordinator advances only when acknowledgements form a contiguous prefix, and the Band buffers at most the three future chunks permitted by a window of four, rejects overlap, and appends only in offset order.

This is an application-level batching change. Xiaomi BLE/SPP framing, CRC, sequence handling, crypto, authentication, transport acknowledgements, and verified literal bytes do not change.

The target for a 4–6 KiB image is 5–10 seconds from `render.prepare` to confirmed Band publication. This is a hardware acceptance target, not an automated guarantee. If 1,024-byte envelopes or window four are unstable on the physical pair, the release candidate must be changed back and rebuilt; no hidden runtime mode or speculative auto-tuning is added.

## Error and lifecycle behavior

- A confirmed map remains visible until the replacement image is decoded and published successfully.
- The pending instruction preview remains visible during transfer.
- Live updates for the confirmed scene refresh rollback state without overwriting the pending preview.
- Cancel, disconnect, timeout, offset error, overlap, digest mismatch, or image error restores the latest confirmed map and guidance.
- A stale generation never replaces a newer confirmed scene.
- Payload rejection moves to the next degradation profile; exceeding 8,192 bytes ends with the existing bounded error path.

## Version and artifact impact

Both installed components change and must be installed as a pair:

- IPA: bump from `0.3.0 (13)` to `0.4.0 (14)` because style, refresh policy, envelope limit, chunk planning, and route color change.
- RPK: bump from `0.4.0 (13)` to `0.5.0 (14)` because safe-area layout, marker assets, envelope validation, and display behavior change.

The unsigned IPA must be built only by GitHub Actions. The RPK is built through the canonical Docker/Make workflow. No backend service changes.

## Automated testing

Tests are written before implementation and cover:

- Layer allowlist and degradation order, including buildings, road hierarchy, selected POIs, and rejected decorative layers.
- Deterministic paint mapping for each retained cartographic class.
- Flat route color, traveled-route color, and overlay widths.
- 38×44 indexed marker resources, transparent margins, dark outline, green fill, and all eight headings.
- HUD content bounds and marker clamp bounds.
- Distance, safe-viewport, maneuver-viewport, reroute, minimum-interval, and generation-coalescing refresh rules.
- 1,024-byte envelope boundary, envelope-derived chunk reconstruction, and rejection above the ceiling.
- Window-four out-of-order completion, three-future-chunk Band buffering, overlap rejection, disconnect cleanup, and atomic publication.
- PNG8 dimensions, profile order, preferred 5,120-byte admission, and hard 8,192-byte rejection.

Canonical verification remains `make test`, `make lint`, the secret scan, and `git diff --check`, followed by the GitHub Actions iOS workflow.

## Manual hardware acceptance

Use the same iPhone, Band firmware, route area, keys, and approximate conditions as the recorded 4,723-byte/51,638-ms run.

1. Run five cold and five warm starts. Record route, snapshot, encode, prepare, chunk count, ACK p50/p95/max, transfer, publication, and first useful guidance.
2. Confirm every HUD element stays inside the rounded display and long street names do not touch the right edge.
3. Confirm all eight marker headings are visible, bright green, larger than before, and distinct from the blue route.
4. Compare buildings, road classes, intersections, land use, water/parks, labels, and selected POIs against a normal phone map for familiarity.
5. Ride at representative speeds near 10, 30, and 50 km/h. Confirm marker updates near 1 Hz and map recentering does not queue stale scenes.
6. Confirm an ordinary full refresh usually occurs from movement/context rather than every instruction, and measure whether confirmed publication reaches the 5–10-second target.
7. Exercise reroute, cancel, disconnect during chunks, overlapping/wrong offsets, digest failure, and image failure.
8. Run for 30 minutes with at least five refreshes and one reroute. Record clipping, stale map, unreadable detail, payload over 5,120 bytes, transfer over 10 seconds, disconnect, freeze, or Band restart.

Hardware acceptance requires both visual familiarity and stable latency. Passing CI alone does not prove either.
