# H1 bounded hybrid renderer — owner hardware handoff

This packet applies only to the artifacts listed below. CI proves compilation and deterministic behavior; only the owner test on the iPhone and Smart Band 10 can prove hardware acceptance.

## Artifact identity

- Source commit: `464b3def233ed89165f8c2014e2ad51c8fba3222`
- IPA: `artifacts/h1-hybrid/BlueBandMap-unsigned.ipa`
- IPA version/build: `0.1.6 (7)`
- IPA bytes / SHA-256: `806331` / `db5993108cb541f2b250796a17b3e3f44c65c05978a263c3b5cdcd2ab1c2a50a`
- RPK: `artifacts/h1-hybrid/dev.lordierclaw.bluebandmap.band.debug.0.2.9.rpk`
- RPK version/code: `0.2.9 (11)`
- RPK bytes / SHA-256: `25136` / `638d8263d55d5bb274e85feaad01ef301a558e73e0727f25f5c2c5099508e90c`
- Both files changed. Replace both previous artifacts; uninstall the old RPK before installing `0.2.9 (11)`.

The IPA is unsigned. Keep signing credentials, profiles and private keys outside this repository.

## What changed

- Removed the 212×360 Static Map baseline. Its observed 21,567-byte payload required about 117 data chunks and is no longer selectable.
- Every H1 run now has a hard limit of 60 `map.asset.chunk` messages. A larger payload fails locally with `ASSET_TOO_MANY_CHUNKS` before transfer.
- Chunk sizing now uses the actual run and scene IDs. The 512-byte application envelope carries 186–189 binary bytes per data chunk; raising the old 320-byte candidate cap alone cannot increase it.
- Static Compact requests 159×270 at zoom 16 and applies adaptive 16-color quantization on the iPhone before transfer.
- TileMap Raster decodes the real Vietmap legacy vector tile, selects/simplifies up to 200 nearby connected road segments, and produces one four-color 212×360 indexed PNG on the iPhone.
- TileMap Vector has separate 40- and 60-road budgets. Nearly straight geometry is merged before selection; walking paths are removed; nearby connected streets are preferred.
- Band vector roads use one lightweight node per segment with a border and fill, producing two visible road edges without doubling the node count.
- Vector errors remain terminal and never silently fall back to raster.

## Measured transfer budget

Measurements used the live POC coordinate, actual ID lengths and the exact 512-byte JSON envelope.

| Candidate | Payload | Data chunks | Decision |
|---|---:|---:|---|
| Static original 212×360 | 21,567 B | about 117 | removed |
| Static 159×270 z16, provider PNG | 14,546 B | 79 | removed |
| Static Compact 159×270 z16, 16 colors | about 7,014 B | 38 | retained |
| TileMap Raster, real tile and 200-road scene | about 3,394 B | 19 | retained |
| TileMap Vector 40 | at most 382 B | at most 3 | retained |
| TileMap Vector 60 | at most 562 B | at most 4 | retained as stress mode |

Provider PNG sizes can vary, but the runtime 60-chunk gate is authoritative.

## Preconditions

- iPhone 13 Pro Max on the intended iOS 26 build.
- Xiaomi Smart Band 10 on the latest firmware; Mi Fitness fully closed during the session.
- AuthKey, Vietmap Service key and Vietmap TileMap key show `SAVED` in Config.
- RPK `0.2.9 (11)` and IPA `0.1.6 (7)` installed.
- Test while stationary.

## Test sequence and expected output

Run one mode at a time. Disconnect and reconnect after every terminal failure. Export the JSON after every run.

1. Open the Band app.
   - Expected: `BLUEBAND MAP`, link status and `RPK 0.2.9` appear immediately.
   - Stop if the screen is black, frozen or shows another version.
2. Connect from the device dialog and complete authentication/trust.
   - Expected iPhone state: `Đã xác thực`.
3. Run `Raster · Static Compact 16 colors`.
   - Expected: a recognizable scaled Vietmap image, correct road layout, no more than 60 data chunks, `displayed`, and a responsive Band.
4. Reconnect and run `Raster · TileMap 200 roads`.
   - Expected: a lightweight four-color street map with connected junctions around the center marker; no scattered meaningless dashes; no more than 60 data chunks.
5. Reconnect and run `Vector · TileMap 40 roads`.
   - Expected: 1–40 primitives, connected double-edge/cased roads, `displayed`, and a responsive Band.
6. Reconnect and run `Vector · TileMap 60 roads` last.
   - Expected: 1–60 primitives and the same map structure with more local streets. Stop immediately and report `FAIL-HW` if the Band becomes black, freezes or reboots.
7. Tap `Export log H1` after each terminal run.
   - Expected: the iOS share sheet opens and exports valid sanitized JSON containing bytes, chunk count, total time and ACK metrics.

If a provider mode fails before transfer, return its bounded code such as `STYLE_HTTP_###`, `TILE_HTTP_###`, `STYLE_MIME`, `TILE_MIME`, `PROVIDER_DATA` or `ASSET_TOO_MANY_CHUNKS`. Do not retry a rate-limited request.

## Evidence to return

For every mode return:

- terminal status or bounded error code;
- bytes / primitives and chunk count;
- total time and ACK p95;
- whether the Band remained responsive;
- exported JSON;
- clear Band screenshot.

Never return AuthKey, Vietmap keys, CoreBluetooth UUIDs, raw BLE captures, nonces, HMACs, derived keys or signing material.

Use one disposition:

- `PASS-HW`: all four modes display correctly and the Band remains responsive.
- `FAIL-HW`: a reproducible crash, hang, reboot, render mismatch or provider failure occurred.
- `BLOCKED-ENV`: artifact, signing, key, device or firmware prerequisites are unavailable.
- `NEEDS-MEASURE`: behavior ran but required metrics/evidence are missing.

H2 pan/zoom, multi-tile viewport, routing, navigation instructions and view switching remain out of scope until H1 receives owner hardware evidence.
