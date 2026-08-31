# Vietmap SDK snapshot route-map handoff

> Historical release record for iOS `0.2.1 (12)` / RPK `0.3.0 (12)`. The current performance and visual refinement release is documented in [band-map-performance-visual-refinement.md](band-map-performance-visual-refinement.md).

## Release candidate

| Item | Value |
|---|---|
| Source commit | `d6cc579e9c940deac52def18141f5d900c7cfda1` |
| iOS | `0.2.1 (12)` |
| RPK | `0.3.0 (12)` |
| iOS CI | [GitHub Actions run 33410300825](https://github.com/LordierClaw/blueband-map/actions/runs/33410300825) |
| Hardware status | `0.2.0 (11)` failed before Band publication; `0.2.1 (12)` awaits retest |

The IPA is unsigned and was produced only by GitHub Actions. The RPK was produced by the canonical Docker/Make path. Both local artifact directories are ignored by Git.

| Artifact | Local path | Bytes | SHA-256 |
|---|---|---:|---|
| Unsigned IPA | `artifacts/vietmap-snapshot-route-map/ipa-0.2.1/BlueBandMap-unsigned.ipa` | 3,376,848 | `8e401365444398737480e5a5e46476acb5cf7f670f8445a4b5d25361c413bf7b` |
| Debug RPK | `artifacts/vietmap-snapshot-route-map/rpk/dev.lordierclaw.bluebandmap.band.debug.0.3.0.rpk` | 23,639 | `6a4c62fddd7f13256138a4fecf4f024e57e3f04fd3f63f73b4393167ad129f90` |

IPA inspection confirmed bundle `dev.lordierclaw.bluebandmap`, version `0.2.1 (12)`, an arm64 Mach-O executable, no `_CodeSignature`, and no embedded provisioning profile. This is build evidence, not device acceptance.

## What changed

### IPA-affecting

- Fixed an early buffered `render.ready` leaving its prepare timeout active during a slow transfer. The stale timeout could abort a valid upload before publication.
- Added the exact Band render terminal code to redacted diagnostics and moved events before route instructions so a bounded export retains the failure evidence.
- Replaced the historical four-color route-card runtime with a 212×520, scale-1 Vietmap SDK snapshot.
- Pinned the Vietmap iOS SDK revision and simplified the loaded style to navigation-relevant background, land/water, roads, selected buildings, and road labels.
- Drew the real Route v4 polyline, traveled/upcoming segments, maneuver marker, and heading-up camera natively before palette reduction.
- Added ordered 32/16-color degradation, with low-priority labels and land use removed only in later profiles; payload admission remains at 8,192 bytes.
- Added recent-GPS reuse, foreground location/style prewarming, immediate `LOCATING`/`GPS LOW`, bounded prepare/result timeouts, refresh coalescing, and expanded redacted diagnostics.
- Added transfer windows 1/2/4 with default 1. Xiaomi BLE/auth/encryption/transport ACK bytes are unchanged.

### RPK-affecting

No Band source or RPK metadata changed in `0.2.1`; reuse the exact `0.3.0 (12)` artifact above.

- Expanded the raster surface to the full 212×520 display.
- Added a translucent native maneuver header, phone-position marker, exceptional statuses, and pre-map startup status.
- Added bounded 8 KiB admission, multiple application message IDs, strict ordered offsets, matching render cancellation, and atomic pending-to-confirmed image publication.
- A failed refresh preserves the previously confirmed map and reports `LIMITED MAP`.

## Automated evidence

- Local canonical suites: 141 portable Swift tests, 14 RPK tests, and 19 protocol-lab tests passed.
- Local metadata, Vietmap smoke-script, handoff-script, shell syntax, secret scan, lint, and `git diff --check` passed.
- GitHub Actions run 33410300825 passed simulator tests, an unsigned arm64 device build, artifact inspection, and IPA upload.
- The first real-device run on `0.2.0 (11)` reached routing and snapshot rendering but failed before Band image publication. The Band showed the RPK startup surface and echo remained functional. `0.2.1 (12)` fixes the identified stale-timeout path, but hardware acceptance remains unverified until retest.

## Manual test plan

### Focused regression retest for 0.2.1

1. Keep the same iPhone, Band, route, and RPK `0.3.0 (12)` used for the failed run; install only IPA `0.2.1 (12)`.
2. Start navigation and allow the image transfer to exceed 15 seconds if necessary. Confirm it is not aborted by `ASSET_READY_TIMEOUT` and the map replaces `LOCATING` on the Band.
3. After map publication, confirm the native maneuver arrow/header, distance, and street name appear. The arrow is a Band overlay sent after confirmed map publication, not part of the PNG.
4. Repeat five starts, recording total time, payload bytes, chunks, application ACK latency, and the first stable terminal code for any failure.
5. Stop once during transfer, reconnect, and start again. Confirm no stale scene publishes and the next transfer succeeds.
6. Export diagnostics after both success and failure. Events must appear before route steps. If a failure reports `terminal=ASSET_RENDER`, retain the safe export and Band photo for a separate PNG-decoder compatibility investigation; do not infer that failure from the earlier generic code.

### Preconditions and safety

1. Verify the IPA and RPK hashes above before installation.
2. Use an iPhone on iOS 17 or newer, Xiaomi Smart Band 10, recorded Band firmware, valid AuthKey, Vietmap Service key, and Vietmap TileMap key.
3. Record iPhone model/iOS, Band firmware, test route, start time, and selected transfer window. Never place keys, full coordinates, device UUIDs, or raw captures in the result.
4. Complete stationary tests first. During a road test, use a passenger to observe the Band or stop safely before interacting with either device.

### A. Startup and first useful map

Run five starts with a cached GPS fix no older than 10 seconds and accuracy at most 25 m, then five cold-GPS starts.

| Check | Expected |
|---|---|
| Start feedback | Band shows `LOCATING` or `GPS LOW` within 100 ms when no reusable fix exists. |
| Reusable fix | Routing begins without waiting for a new fix. |
| First useful map | p95 at most 5 seconds across the five reusable-fix starts. |
| Snapshot + palette | Warm p95 at most 1.5 seconds. |
| Transfer | p95 at most 3 seconds. |
| Payload | Every PNG is 1–8,192 bytes; no four-color fallback appears. |

Capture the redacted GPS wait, route request, style load, snapshot, palette, transfer prepare, Band write/decode/publication, total, payload, palette, layer counts, cache state, chunks, window, and ACK p50/p95/max metrics.

### B. Visual acceptance

Use an urban route with intersections, minor and major roads, water or park context, buildings, and at least two named roads.

- The map fills 212×520 without black edges, distortion, or a stale previous route.
- The cyan upcoming route is continuous, aligned to roads, and visually stronger than surrounding roads; traveled route is distinct.
- The next maneuver remains inside useful map context and is not hidden by the header.
- Heading-up orientation and the marker location agree with the real direction of travel.
- The translucent header shows maneuver, distance, and up to two street-name lines; ordinary `NAVIGATING` is hidden.
- `GPS LOW`, `LIMITED MAP`, `REROUTING`, `ARRIVED`, and `LOADING MAP` are readable and do not overlap the street name.
- A tester correctly identifies the next maneuver in at least four of five samples.

### C. Live updates and refresh

1. Travel along the route for at least three maneuvers. Confirm marker/instruction changes appear within 1 second and the raster is not regenerated on ordinary 1 Hz updates.
2. Cross the safe viewport boundary and pass a maneuver. Confirm one refreshed snapshot appears while the old confirmed map remains visible until publication completes.
3. Trigger two refresh reasons close together. Confirm only the newest refresh queued before transfer is sent; no stale scene replaces it.
4. Force a successful reroute by leaving the route for three good fixes after the 15-second cooldown. Confirm `REROUTING`, a new route snapshot, and continued navigation.
5. Approach within 25 m of the destination. Confirm `ARRIVED` without a mock-coordinate jump.

### D. Degradation and provider failure

Use routes/styles that exercise each payload profile and record the selected profile.

- 32-color and 16-color labeled maps preserve the cyan route and useful road labels.
- Later profiles remove low-priority road labels, then low-priority land use, in that order.
- If no profile fits 8 KiB on the first map, startup fails with a stable error and publishes no partial image.
- If TileMap/style/snapshot/encode fails during refresh, the confirmed map remains visible and `LIMITED MAP` appears.
- Route-provider failure remains terminal for the initial start and does not leak provider response or keys.

### E. Transfer-window trial

Run five identical transfers for each application window 1, 2, and 4.

- Record total transfer time, chunks, ACK p50/p95/max, retries, and any timeout for all 15 runs.
- Confirm exact increasing offsets, immediate application ACKs, one digest-valid publication, and no `ASSET_BUSY`, missing chunk, Band freeze, reboot, or black screen.
- Select the fastest window with five clean transfers. Keep window 1 unless hardware evidence supports 2 or 4.

### F. Failure, stop, and reconnect

- Stop while waiting for `render.ready`: the prepared generation is released and a new start is accepted.
- Disconnect during begin, middle chunk, end ACK, publication, and live update. No partial/stale image may publish.
- Reconnect, wait for RPK readiness, and start a fresh run. Old ready/result/update messages must not affect it.
- Inject or reproduce wrong offset, duplicate ID, digest mismatch, stale run/scene, and image publication failure. Each produces one bounded failure, cleans ownership, and preserves a prior confirmed map when present.

### G. Stability

Navigate for 30 minutes with at least one reroute, one GPS-low interval, and multiple snapshot refreshes. Expected: no iPhone crash, Band freeze/reboot, growing delay, stale scene replacement, unbounded file accumulation, or secret-bearing diagnostics.

## Result record

Record Pass/Fail/Not run for every section, the five-run latency samples, selected window, first stable error if any, safe screenshot/video filenames, and the redacted diagnostic export. A hardware pass may be claimed only after all mandatory sections pass on the recorded iPhone/Band pair.
