# Familiar dark map, safe area, and performance handoff

## Release candidate

| Item | Value |
|---|---|
| Source commit | `3be44466227b1760cd62a6c4fc02597f4b34b24f` |
| iOS | `0.4.0 (14)` |
| RPK | `0.5.0 (14)` |
| iOS CI | [GitHub Actions run 33430057644](https://github.com/LordierClaw/blueband-map/actions/runs/33430057644) |
| Hardware status | Build-verified; Smart Band 10 acceptance pending |

The unsigned IPA was produced only by GitHub Actions. The RPK was produced through the canonical Docker/Make path. The artifact directories are ignored by Git.

| Artifact | Local path | Bytes | SHA-256 |
|---|---|---:|---|
| Unsigned IPA | `artifacts/familiar-dark-map/ipa-0.4.0/BlueBandMap-unsigned.ipa` | 3,403,025 | `a556503a59212f0229e33ce1e7b7d9d1e8d25630bbedf9a47d91f1c9898c4b83` |
| Debug RPK | `artifacts/familiar-dark-map/rpk/dev.lordierclaw.bluebandmap.band.debug.0.5.0.rpk` | 30,456 | `c83db4166182308c4355c22a5da8cc4e976cfe9038ee1ed3602ae19cf1543d16` |

IPA inspection confirmed bundle `dev.lordierclaw.bluebandmap`, version `0.4.0 (14)`, minimum iOS 17, iPhone-only device family, an arm64 Mach-O executable, no `_CodeSignature`, and no embedded provisioning profile. RPK inspection confirmed package `dev.lordierclaw.bluebandmap.band`, version `0.5.0 (14)`, and design width 212.

## What changed

### IPA-affecting

- Keeps a familiar dark urban map: water, parks and vegetation, residential/school/hospital land use, buildings at close zoom, road/bridge/tunnel hierarchy, major and secondary labels, close-zoom minor labels, and a small hospital/school/transit/parking POI allowlist.
- Uses a 16-color PNG8 palette that preserves the semantic classes, flat dark-blue upcoming route (`#2f6bff`), subdued traveled route, and bright-green marker color.
- Prefers the detailed candidate through 5,120 bytes, then removes POIs/minor labels and low-priority land use while retaining roads, water, parks, vegetation, and important labels. The hard payload ceiling remains 8,192 bytes.
- Refreshes HUD/marker independently near 1 Hz. Full raster refreshes require at least 12 seconds plus 175 m movement, leaving the safe viewport, or losing the next maneuver; successful reroutes bypass the interval. A running refresh retains only the newest pending request, and failed starts still observe the 12-second floor.
- Increases the bounded application envelope from 512 to 1,024 bytes and the default application ACK window from two to four. Complete Xiaomi SPP frames remain serialized and verified wire bytes are unchanged.
- Bumps iOS from `0.3.0 (13)` to `0.4.0 (14)`.

### RPK-affecting

- Moves the compact HUD content into x 32–180 instead of the rounded screen edges, with a 38×48 maneuver image and tighter distance/street/status layout.
- Replaces the old 26×32 marker with eight 38×44 PNG8 directional markers using bright green with a dark outline and transparent rotation margin.
- Clamps marker center to x 30–182 and y 130–478 so the complete marker remains visible on the rounded Band display.
- Accepts 1,024-byte application envelopes and buffers at most three future chunks for the supported window of four, draining only contiguous non-overlapping offsets.
- Bumps RPK from `0.4.0 (13)` to `0.5.0 (14)`.

No backend or Vietmap API endpoint was added. The iPhone still requests Vietmap's official dark vector style and performs filtering, recoloring, route drawing, palette reduction, and PNG8 encoding locally.

## Automated evidence

- Local canonical gates passed: 143 portable Swift tests, 20 RPK tests, and 19 protocol-lab tests.
- iOS metadata, Vietmap smoke tests, handoff tests, shell syntax, lint, secret scan, current diff, and the complete implementation-range whitespace check passed.
- [Repository checks](https://github.com/LordierClaw/blueband-map/actions/runs/33430057659), [Band checks](https://github.com/LordierClaw/blueband-map/actions/runs/33430057663), [Swift checks](https://github.com/LordierClaw/blueband-map/actions/runs/33430057643), and the iOS run above succeeded for the source commit.
- The iOS run passed simulator tests, unsigned arm64 device build, bundle inspection, and IPA upload. This evidence does not establish real Smart Band latency or visual acceptance.

## Manual test plan

### Preconditions

1. Verify both SHA-256 values above, then install IPA `0.4.0 (14)` and RPK `0.5.0 (14)` together.
2. Use the same iPhone, Band firmware, route area, and Vietmap keys as the prior test where possible. Keep Mi Fitness closed during direct-session testing.
3. Record redacted diagnostics only; never return keys, exact coordinates, device UUIDs, or raw captures.
4. Perform stationary checks first. Use a passenger to operate the phone and record timings during moving tests.

### A. Cold start and transfer latency

Run five cold starts and five starts with a recent accurate GPS fix.

1. Time button press → first guidance, street visible, map rendered, transfer begin, and map visible.
2. Confirm guidance appears before the full map and remains stable during transfer.
3. Export diagnostics and record payload bytes, chunks, window, ACK p50/p95/max, snapshot/encode/transfer/display time, and terminal code.
4. Compare with the observed baseline of 4,723 bytes and 51,638 ms to Band display. Do not mark an improvement without measured hardware data.
5. Expected: detailed profile is preferred at ≤5,120 bytes; a larger image is allowed only as the smallest valid candidate and must remain ≤8,192 bytes.

### B. Rounded-display visual acceptance

Use urban routes containing primary, secondary and minor roads, buildings, a park or water area, and at least one supported POI.

1. Confirm maneuver, distance, street, and exceptional status remain fully visible; no text or image touches or disappears under the rounded top edge.
2. Check all four edges while the map rotates and the marker moves. The complete 38×44 marker must stay visible.
3. Confirm the bright-green marker is clearly distinct from the flat dark-blue route and points in the expected one of eight directions.
4. Confirm the map still reads like a conventional 2D map: road classes differ, buildings/land use provide context, major/secondary labels remain, and close-zoom minor labels are not excessive.
5. Confirm the route has no border/halo and remains distinguishable from every retained road class.

### C. Cadence at 0–50 km/h

Test stationary, approximately 10, 30, and 50 km/h on a safe route.

1. Marker, maneuver, distance, and street should update about once per second without a full-image transfer each time.
2. Stationary or slow movement inside the safe viewport must not cause repeated raster transfers.
3. Full refresh starts must be at least 12 seconds apart during ordinary navigation and should occur only after 175 m movement, safe-viewport exit, or the next maneuver leaving the image.
4. Record the actual full-map interval at each speed. The intended practical range is context-dependent, commonly 15–25 seconds; the hard rule is the 12-second floor plus a real trigger.
5. When a refresh is already running, move again and confirm only the newest pending location is used next; no refresh storm or permanent stale map is allowed.

### D. Reroute, degradation, and failures

1. Deviate safely to trigger reroute. The successful reroute may start a raster refresh immediately, while the confirmed old map remains until atomic publication.
2. Exercise areas of increasing detail. Confirm degradation order: full familiar view → remove POIs/minor labels → remove low-priority land use. Roads, water, parks, vegetation, and major/secondary labels must survive.
3. Disconnect during prepare, middle chunks, end ACK, and pending image publication. Reconnect and start again; stale messages must not publish.
4. Reproduce provider failure, payload rejection, wrong offset, digest mismatch, and image publication failure where possible. The last confirmed map must remain usable and retries must not start every GPS tick.
5. Stop immediately on Band freeze/reboot, black or partial image, repeated `ASSET_OFFSET_INVALID`, or any credential/identifier exposure.

### E. Stability gate

1. Navigate continuously for 30 minutes with at least one reroute and five full-map refreshes.
2. Stop/start navigation five times without restarting the RPK, then close/reopen the RPK ten times without initiating provider calls.
3. Record payload, transfer interval/time, stale UI, clipping, missing context, disconnect, memory symptoms, and Band restart counts.
4. Mark hardware acceptance only after latency, visual familiarity, safe-area, marker direction/contrast, cadence, reroute, failure cleanup, and stability all pass on the recorded iPhone/Band pair.
