# Band map performance and visual refinement handoff

## Release candidate

| Item | Value |
|---|---|
| Source commit | `2ab53f990bd8230ce128dd419929da5fef7e14c0` |
| iOS | `0.3.0 (13)` |
| RPK | `0.4.0 (13)` |
| iOS CI | [GitHub Actions run 33421025418](https://github.com/LordierClaw/blueband-map/actions/runs/33421025418) |
| Hardware status | Build-verified; Smart Band 10 retest pending |

The IPA was produced only by GitHub Actions. The RPK was produced through the canonical Docker/Make workflow. Both artifact directories are ignored by Git.

| Artifact | Local path | Bytes | SHA-256 |
|---|---|---:|---|
| Unsigned IPA | `artifacts/band-map-performance/ipa-0.3.0/BlueBandMap-unsigned.ipa` | 3,396,903 | `79c0b1344d4f91d659161164e0bff1eb7578bea8f78802468ae42887b0cb2605` |
| Debug RPK | `artifacts/band-map-performance/rpk/dev.lordierclaw.bluebandmap.band.debug.0.4.0.rpk` | 29,693 | `a4eaf80ed194b7ca236a5b4341424c867ca5897268559fe90cfc31033337a949` |

IPA inspection confirmed bundle `dev.lordierclaw.bluebandmap`, version `0.3.0 (13)`, minimum iOS 17, iPhone-only device family, an arm64 Mach-O executable, no `_CodeSignature`, and no embedded provisioning profile. RPK inspection confirmed package `dev.lordierclaw.bluebandmap.band`, version `0.4.0 (13)`.

## What changed

### IPA-affecting

- Requests Vietmap's official dark style and rewrites retained background, water, land, road, and text paints to a deterministic low-entropy palette before snapshotting.
- Draws traveled and upcoming route segments without an outline; the upcoming route is one flat cyan stroke.
- Tries the three 16-color transfer profiles in degradation order, stops at the first PNG at most 4,096 bytes, and otherwise sends the smallest valid PNG up to 8,192 bytes.
- Adds a bounded instruction preview to `render.prepare`, so the Band can show maneuver, distance, and street before the map finishes transferring.
- Sends an eight-sector heading bucket for the M1 marker.
- Changes the default application ACK window to two. Complete SPP frames remain serialized on the BLE wire, preventing concurrent CoreBluetooth writes and chunk reordering while allowing two application acknowledgements to overlap.
- Bumps iOS from `0.2.1 (12)` to `0.3.0 (13)`.

### RPK-affecting

- Replaces the rectangular instruction card with the B1 212×96 full-width PNG8 fade HUD, one-line street name, exact-size maneuver images, and exceptional status line.
- Replaces the 10 px dot with eight 26×32 PNG8 directional chevrons. Every orientation has a transparent margin and requires no runtime rotation, SVG, or clipping.
- Validates and shows the prepare preview immediately, hides diagnostics behind it, preserves it through successful publication, and restores confirmed guidance if a refresh is cancelled, disconnected, or fails.
- Packages and verifies every HUD/marker resource and bumps RPK from `0.3.0 (12)` to `0.4.0 (13)`.

No backend service was added or changed. iOS directly requests the Vietmap dark-style endpoint and performs the final layer reduction, route drawing, and PNG8 encoding locally.

## Automated evidence

- Canonical local suites passed: 143 portable Swift tests, 19 RPK tests, and 19 protocol-lab tests.
- Vietmap smoke tests, iOS metadata, handoff checks, shell syntax, secret scan, lint, and `git diff --check` passed.
- GitHub Actions run 33421025418 passed simulator tests, an unsigned arm64 device build, artifact inspection, and IPA upload.
- Automated evidence does not prove Smart Band 10 latency or visual acceptance.

## Manual test plan

### Preconditions

1. Verify both SHA-256 values above before installation.
2. Install IPA `0.3.0 (13)` and RPK `0.4.0 (13)` together; do not mix them with the previous pair.
3. Use the same iPhone, Band firmware, route area, AuthKey, and Vietmap keys as the 45,529 ms baseline where possible.
4. Record only redacted diagnostics. Do not save keys, exact coordinates, device UUIDs, or raw captures.
5. Perform stationary checks first; use a passenger for any moving road test.

### A. First useful guidance and latency

Run five cold starts and five starts with a recent accurate GPS fix.

1. Start navigation and time these milestones independently: button press, GPS fix, route response, PNG ready, preview visible, map visible, and street visible.
2. Confirm the B1 HUD shows the maneuver, distance, street, and `LOADING MAP` during transfer instead of waiting for map publication.
3. Confirm the map later appears without clearing or briefly replacing the preview with `—`.
4. Export diagnostics and record payload bytes, palette, chunks, window, ACK p50/p95/max, transfer time, Band write/decode/publication time, and terminal code.
5. Compare each run against the recorded baseline: 7,813-byte PNG and 45,529 ms to Band publication. Report measured values; do not infer improvement from automated tests.
6. Expected payload behavior: prefer at most 4,096 bytes; a larger payload is acceptable only when it is the smallest valid fallback and remains at most 8,192 bytes.

### B. B1 visual acceptance

Use an urban route with left/right turns, a roundabout if available, named roads, minor/major roads, and water or park context.

- HUD follows the rounded top of the Band through the full-width fade; no cut rectangular card is visible.
- Maneuver glyph, distance, and street are readable at a glance and occupy only the top 96 px.
- Long street names stay on one line without overlapping distance or exceptional status.
- Normal `NAVIGATING` is hidden. `GPS LOW`, `LIMITED MAP`, `REROUTING`, `ARRIVED`, and `LOADING MAP` remain readable.
- Basemap is dark and visually quiet; the route is a single flat cyan line with no border/halo.
- Road labels remain readable where retained; no black edges, scaling blur, or stale previous route appears.

### C. M1 marker and live navigation

1. Test all eight approximate travel headings by changing direction safely or using a controlled route loop.
2. Confirm the marker is materially larger and clearer than the old dot, points in the expected direction, never touches/crops at its own bitmap edge, and stays within the Band viewport near map edges.
3. Travel through at least three maneuvers. Marker, distance, maneuver, and street updates should arrive without regenerating the raster for ordinary location updates.
4. Confirm straight, left, right, U-turn, roundabout, and arrival images are distinct and understandable whenever the route supplies those maneuvers.

### D. Refresh and failure lifecycle

1. Trigger a map refresh, then cancel it before publication. The old confirmed map and its guidance must return; the pending preview must not remain.
2. Repeat with a disconnect during begin, middle chunk, end ACK, and pending image publication. Reconnect and confirm a fresh run succeeds without a stale scene.
3. Trigger two refresh reasons close together. Only the newest pending refresh should publish.
4. Force or reproduce wrong offset, digest mismatch, provider failure, and image publication failure. Each must terminate once, clean ownership, and preserve the confirmed map when one exists.
5. Confirm no `writeInProgress`, `ASSET_OFFSET_INVALID`, Band freeze, reboot, black screen, or partial image occurs with the default window of two.

### E. Stability and acceptance record

1. Run navigation continuously for at least 30 minutes with at least one reroute and five snapshot refreshes.
2. Stop and restart navigation five times without restarting the RPK.
3. Record any payload above 4 KiB, transfer above the local median by more than 2×, stale HUD/map, clipped marker, missing label, disconnect, or Band restart.
4. Mark hardware acceptance only after the latency, B1 visual, M1 direction, refresh cleanup, and stability checks pass on the recorded iPhone/Band pair.
