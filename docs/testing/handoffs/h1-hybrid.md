# H1 hybrid renderer — owner hardware handoff

This handoff applies only to the exact artifacts below. CI and live provider checks do not prove Xiaomi Smart Band 10 hardware acceptance; the owner test is the acceptance boundary.

## Artifact identity

- Source commit: `b5329cff1a2329a8ccd9e805ddd4d1498e0272f5`
- IPA: `artifacts/h1-hybrid/BlueBandMap-unsigned.ipa`
- IPA version/build: `0.1.5 (6)`
- IPA bytes / SHA-256: `785236` / `9b0032d00c9b5c338e597c6cc5f7ffd998ba22bd1970ee1d5d84f0cadbec7186`
- RPK: `artifacts/h1-hybrid/dev.lordierclaw.bluebandmap.band.debug.0.2.8.rpk`
- RPK version/code: `0.2.8 (10)`
- RPK bytes / SHA-256: `25019` / `8777472b683d99c9b6d3b823097db78412c8af96914ba29588618f00c4c5af8b`
- Both artifacts changed. Replace IPA `0.1.4 (5)` and fully remove the old RPK before installing `0.2.8 (10)`.

The IPA is unsigned. Keep signing credentials, profiles and private keys outside this repository.

## What was fixed from the latest owner evidence

The owner run proved all three modes now reach `displayed`. It also exposed three correctness/performance problems:

1. Synthetic 40 was intentionally generated as isolated random dashes. It now renders a deterministic connected road grid, so it measures Band line capacity without resembling corrupt geometry.
2. TileMap projected MVT extent units directly as screen pixels and decoded every line layer. The real 2.34 MB tile contains `transportation`, boundaries, waterways and thousands of unrelated features. The iPhone now converts the 4096-unit MVT extent to 256 tile pixels and keeps only road source layers selected by the live Vietmap style.
3. Static Map transferred 21,567 bytes in 120 steps. ACK latency rose from roughly 150 ms to roughly 420 ms after ACK 24 because the Band performed one filesystem write per data chunk. RPK `0.2.8 (10)` allocates one bounded buffer (maximum 64 KiB), ACKs after copy/hash, then writes the complete validated payload once.

The static payload itself remains the exact 212×360 Vietmap PNG in this build. Live API measurements at the POC coordinate were 21,567 bytes for 212×360, 12,376 bytes for 159×270 and 7,091 bytes for 106×180. A half-resolution real-map mode is deferred until the owner confirms whether scaled text and roads remain readable.

Long exports now retain aggregate p50/p95/max metrics and at most 32 ACK samples, keeping the shared JSON valid and below 1,024 bytes. No key, provider URL, raw tile body, UUID or BLE secret is exported.

## H1 contract

- The iPhone selects exactly one renderer before transfer.
- The Band must answer `render.prepare` with `render.ready` before asset chunks are sent.
- Raster uses a 212×360 PNG. Vector uses BBMV v1 with no more than 40 line primitives.
- Vector never silently falls back to raster.
- Transfer remains stop-and-wait and preserves the verified Xiaomi BLE/SPP/auth bytes.
- Success requires an exact semantic result: renderer, format, bytes, primitives and hash prefix.

## Preconditions

- iPhone 13 Pro Max on the intended iOS 26 build.
- Xiaomi Smart Band 10 on the latest firmware; Mi Fitness fully closed during the session.
- AuthKey, Vietmap Service key and Vietmap TileMap key show `SAVED` in Config.
- Old Band package fully uninstalled, then RPK `0.2.8 (10)` installed.
- IPA `0.1.5 (6)` installed and signed through the tester's normal process.
- Test while stationary.

## Test sequence and expected output

Run one mode at a time. After any terminal failure, disconnect and reconnect before the next attempt.

1. Open the Band app.
   - Expected: `BLUEBAND MAP`, a ready/link status and `RPK 0.2.8` appear immediately.
   - Stop if the screen is black, frozen or displays another version.
2. Connect from the compact device picker and complete authentication/trust.
   - Expected iPhone state: `Đã xác thực`.
3. Run `Vector · Synthetic 40 lines`.
   - Expected: `382 / 40`, displayed/success, a connected rectangular road grid and a responsive Band. Isolated diagonal dashes are a failure.
4. Disconnect/reconnect and run `Vector · Vietmap TileMap`.
   - Expected: one tile processed on iPhone, 1–40 primitives, displayed/success and recognizable connected road fragments around the center marker. Boundaries/waterways filling the screen or the old widely scattered dashes are failures.
5. Disconnect/reconnect and run `Raster · Vietmap Static Map`.
   - Expected: 21,567 bytes and about 120 transfer steps for the current provider response, followed by the correct recognizable map.
   - Primary measurement: ACKs after sample 24 should no longer plateau near 420 ms. Total time should improve, but hardware evidence determines the accepted threshold.
6. Tap `Export log H1` after every terminal run and save/share the JSON.
   - Expected: the share sheet appears.
   - Expected file: valid one-line JSON smaller than 1,024 bytes, with a complete 64-character `payloadSHA256` and no secret values.

If a provider mode fails before transfer, return its exact bounded code such as `STYLE_HTTP_###`, `TILE_HTTP_###`, `STYLE_MIME`, `TILE_MIME` or `PROVIDER_DATA`. Do not retry a rate-limited request.

## Evidence to return

For each mode, return:

- terminal status or bounded error code;
- bytes / primitives;
- total time and ACK p95;
- whether the Band remained responsive;
- exported JSON file;
- redacted screenshot of the Band result.

Never return AuthKey, Vietmap keys, CoreBluetooth UUIDs, raw BLE captures, nonces, HMACs, derived keys or signing material.

Use one disposition:

- `PASS-HW`: all six modes display successfully and exports are valid.
- `FAIL-HW`: a reproducible crash, hang, render mismatch or provider failure occurred.
- `BLOCKED-ENV`: artifact, signing, key, device or firmware prerequisites are unavailable.
- `NEEDS-MEASURE`: behavior ran but required metrics/evidence are missing.

H2 pan/zoom, multi-tile viewport, routing, navigation instructions and view switching remain out of scope until H1 receives owner hardware evidence.
