# H1 native road renderer — owner hardware handoff

CI proves compilation and deterministic behavior. Only the owner test on the iPhone and Smart Band 10 proves hardware acceptance.

## Artifact identity

- Source commit: `7bb6e06a8c34afd473c7fda2d472197ff1059e4f`
- IPA: `artifacts/h1-hybrid/BlueBandMap-unsigned.ipa`
- IPA version/build: `0.1.7 (8)`
- IPA bytes / SHA-256: `805850` / `4dc9071219f75eaa584743add422555c40009a567efbf2a8c172e4b253e0cf63`
- RPK: `artifacts/h1-hybrid/dev.lordierclaw.bluebandmap.band.debug.0.2.9.rpk`
- RPK version/code: `0.2.9 (11)`
- RPK bytes / SHA-256: `25136` / `638d8263d55d5bb274e85feaad01ef301a558e73e0727f25f5c2c5099508e90c`
- Replace only the IPA. The RPK did not change and must not be reinstalled.

The IPA is unsigned. Keep signing credentials, profiles and private keys outside this repository.

## What changed

- Removed the old provider Static Map mode from H1. It exposed no useful controls for removing labels, POIs, address text or marker detail.
- Both raster presets now decode Vietmap TileMap roads on the iPhone and render a small native indexed PNG: no labels, POIs or address text.
- The renderer fetches every parent tile crossed by the 212×360 viewport, then overzooms those tiles into one consistent display coordinate system. This fixes the previous offset and fragmented geometry.
- Removed artificial polyline stretching and excluded railway layers from road discovery.
- Added support for raw MVT, current Vietmap marker/XOR tiles and the legacy Vietmap XOR format observed in earlier responses.
- Roads use a dark casing plus a light fill so streets and connected junctions remain readable.
- The four TileMap requests are parallel. Every run is rejected locally before BLE transfer if its calculated data chunk count exceeds 60.

## Calculated transfer budget

These are exact local encoder/transfer-plan measurements at the fixed POC coordinate; live provider geometry can change, so the runtime 60-chunk gate remains authoritative.

| Mode | Native payload | Data chunks | Decision |
|---|---:|---:|---|
| Raster Native Compact, 80 roads | about 1.84 KB | about 10 | primary |
| Raster Native Detail, 200 roads | about 3.44 KB | about 19 | primary |
| Vector Native, 40 roads | at most 382 B | at most 3 | secondary |
| Vector Native, 60 roads | at most 562 B | at most 4 | stress only |

## Preconditions

- iPhone 13 Pro Max on the intended iOS 26 build.
- Xiaomi Smart Band 10 on the latest firmware; Mi Fitness fully closed during the session.
- AuthKey and Vietmap TileMap key show `SAVED` in Config.
- IPA `0.1.7 (8)` and existing RPK `0.2.9 (11)` installed.
- Test while stationary. Disconnect and reconnect after every terminal failure.

## Test sequence and expected output

1. Open the Band app, connect from the device dialog and complete authentication/trust.
   - Expected: Band UI is immediately responsive; iPhone reports `Đã xác thực`.
2. Run `Raster · Native Compact 80 roads`.
   - Expected: recognizable connected streets centered correctly, no labels/POIs/address text, roughly 10 chunks and at most 60.
3. Reconnect, then run `Raster · Native Detail 200 roads`.
   - Expected: same geometry and center as Compact, with more side streets, roughly 19 chunks and at most 60.
4. Reconnect, then run `Vector · Native 40 roads`.
   - Expected: the same local road structure with 1–40 primitives. Stop if the Band freezes, goes black or reboots.
5. Run `Vector · Native 60 roads` only if the 40-road mode is stable.
   - Expected: 1–60 primitives and more detail. Treat any reboot or black screen as `FAIL-HW`.
6. Export H1 JSON after each terminal run.
   - Expected: the iOS share sheet opens and exports sanitized bytes/chunks/time/ACK metrics.

Return the exported JSON and a clear Band screenshot for Compact and Detail first. Never return AuthKey, Vietmap keys, UUIDs, raw BLE captures, nonces, HMACs, derived keys or signing material.

## Verification evidence

- Local: 169 Swift package tests, 55 RPK tests and 19 protocol-lab tests passed; lint, diff and secret gates passed.
- GitHub iOS checks: 74 simulator tests passed and the unsigned arm64 device app passed artifact inspection.
- GitHub unsigned release workflow built the IPA from the source commit above.

Pan/zoom, routing, navigation instructions and view switching remain out of scope until one raster preset receives owner hardware acceptance.
