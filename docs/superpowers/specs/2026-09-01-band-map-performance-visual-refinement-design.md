# Band map performance and visual refinement design

## Status

Approved for implementation on 2026-09-01. Work is authorized directly on `main`; no branch or worktree is required.

## Evidence and problem statement

The successful Smart Band 10 retest used IPA `0.2.1 (12)` with RPK `0.3.0 (12)`. The Band displayed the map, proving the existing 212×520 PNG8 publication path works on the test hardware.

The exported navigation timeline shows:

- GPS fix at 43 ms.
- Route response at 230 ms.
- Snapshot and PNG ready at 308 ms.
- Band publication at 45,529 ms.
- First `nav.update`, including the street name, only after publication at 45,529 ms.

The dominant delay is therefore application transfer/publication, not Vietmap routing or snapshot generation. The current PNG is 7,813 bytes and the coordinator uses transfer window 1. The current Band UI also waits for confirmed publication before receiving the first instruction, uses a 184×124 rectangular header near the curved edge, draws only a 10 px position dot, and renders the route with a dark halo.

## Goals

- Show the first maneuver, distance, and street name while the map is transferring.
- Reduce the normal map payload toward 4,096 bytes without sacrificing the route, primary road context, or next-street label.
- Use a dark, low-entropy map with a single flat cyan route line.
- Replace the rectangular header with the approved B1 gradient HUD.
- Replace the small dot with the approved M1 directional chevron.
- Use only rendering capabilities appropriate for Vela: local PNG resources, basic image/text/div components, and bounded dynamic positioning.
- Trial transfer window 2 and preserve window bounds 1/2/4.

## Non-goals

- Do not change Xiaomi BLE, FE95/5E/5F, SPP framing, authentication, encryption, or transport ACK bytes.
- Do not introduce WebP, AVIF, SVG, canvas, runtime image rotation, a new backend, or a new dependency.
- Do not reduce the delivered map dimensions below 212×520 or ask the Band to scale the map.
- Do not claim latency or hardware acceptance until the new IPA/RPK pair is tested on the recorded device pair.

## Map source and iOS image pipeline

The snapshotter will request Vietmap's official dark style endpoint:

`https://maps.vietmap.vn/maps/styles/dm/style.json?apikey=<tile-map-key>`

The Static Map API will not be used. It returns a completed PNG but does not provide the current pipeline's heading-up camera, deterministic layer mutation, route overlay, or adaptive payload profiles.

When the SDK finishes loading the dark style, iOS will:

1. Remove layers outside the existing navigation allowlist.
2. Normalize retained background, fill, road, water, and label paints to the fixed 16-color dark palette.
3. Preserve primary road labels and remove only low-priority labels and land-use in later profiles.
4. Draw traveled and upcoming route segments without an outline/halo. The upcoming route is one flat cyan stroke.
5. Encode an 8-bit indexed PNG, which is already hardware-proven and is the Vela-recommended low-color format.

The transfer-optimized profile order is:

1. 16 colors with useful labels.
2. 16 colors without low-priority labels.
3. 16 colors without low-priority labels or low-priority land-use.

iOS stops when a candidate is at most 4,096 bytes. If none meets that target, it sends the smallest valid candidate up to the hard 8,192-byte protocol limit. The 4 KiB value is an optimization target, not a protocol rejection boundary.

## Early instruction preview

`render.prepare` gains a bounded optional `preview` object containing:

- `maneuver`: one existing `NavigationManeuver` raw value.
- `distanceM`: a non-negative integer.
- `street`: UTF-8 truncated to 48 bytes.

The preview is included in the same acknowledged message as asset admission, so it adds no extra application round trip. The Band validates it with the prepare body and immediately populates the B1 HUD. It remains associated with the pending scene and is replaced by normal `nav.update` messages after publication.

## B1 HUD

The HUD uses a full-width, locally bundled PNG8 shade that follows the capsule top and fades into the map. It has no rectangular card.

- Safe top inset: 18 px.
- Maneuver image: 42×54 px at x=23.
- Distance: starts at x=70, bold, one line.
- Street: starts at x=70 below the distance, one line with truncation.
- Ordinary `NAVIGATING` remains hidden; exceptional status stays visible below the primary content.

Maneuver glyphs are exact-size bundled PNG8 resources generated at build time for straight, left, right, U-turn, roundabout, and arrival. The Band does not draw or rotate them.

## M1 position marker

`NavigationUpdate` gains `headingBucket`, an integer from 0 through 7 representing 45-degree heading sectors. iOS derives it from the same course/heading already used by the snapshot camera.

The RPK bundles eight exact-size 26×32 PNG8 chevrons. The page changes the marker source only when the bucket changes and continues using the existing bounded `left`/`top` dynamic position. This avoids SVG, clip paths, and runtime rotation while keeping the marker direction legible.

## Transfer and lifecycle

The production coordinator default changes from window 1 to window 2. Existing ordering, unique message IDs, application ACKs, digest validation, atomic publication, stale-scene rejection, cancellation, and disconnect cleanup remain unchanged.

The early preview must not make an unconfirmed map active. On rejection, cancellation, disconnect, or publication failure, pending preview state is cleared. A previously confirmed map remains visible during refresh exactly as before.

## Diagnostics

Diagnostics continue recording payload bytes, palette, retained layers, chunks, window, ACK p50/p95/max, transfer time, Band write/decode/publication time, and terminal code. The retest compares the new pair against the observed 7,813-byte, 45,529-ms baseline.

## Versions and artifacts

Both products change:

- IPA: bump from `0.2.1 (12)` to `0.3.0 (13)`.
- RPK: bump from `0.3.0 (12)` to `0.4.0 (13)`.

The IPA must be built only by GitHub Actions. The RPK must be built through the canonical Docker/Make target. Neither artifact is hardware-accepted until the manual retest passes.

## Acceptance

- Automated tests prove profile order, 4 KiB preference with 8 KiB fallback, dark style URL/policy, flat route commands, bounded preview, heading buckets, window 2, early HUD state, PNG resources, and cleanup.
- The Band displays preview instruction content before map publication.
- The final map uses the B1 HUD, M1 marker, dark simplified basemap, and flat route.
- Hardware retest records payload size and end-to-end time for five starts, plus stop/reconnect behavior.
