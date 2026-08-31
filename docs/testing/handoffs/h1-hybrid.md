# H1 hybrid renderer — owner hardware handoff

This handoff applies only to the exact artifacts below. CI and live provider checks do not prove Xiaomi Smart Band 10 hardware acceptance; the owner test is the acceptance boundary.

## Artifact identity

- Source commit: `5a1c7397ae100593e1dc93e9d13565c9351cb2e8`
- IPA: `artifacts/h1-hybrid/BlueBandMap-unsigned.ipa`
- IPA version/build: `0.1.4 (5)`
- IPA bytes / SHA-256: `782211` / `8744e887b99ef0de2a79ae02076dc16c4972fe856bb349f51193d12bfd276c18`
- RPK: `artifacts/h1-hybrid/dev.lordierclaw.bluebandmap.band.debug.0.2.7.rpk`
- RPK version/code: `0.2.7 (9)`
- RPK bytes / SHA-256: `24979` / `74352b31fed618189a3a80370adb3aeb9c2621c163386cb159c2a2a8e956b12e`
- This fix changes only the RPK. If IPA `0.1.4 (5)` is already installed, do not reinstall it. Fully remove the previous RPK before installing `0.2.7 (9)` so Vela cannot reuse a cached package.

The IPA is unsigned. Keep signing credentials, profiles and private keys outside this repository.

## What was fixed

The `0.2.6 (8)` owner run transferred and validated Synthetic 8 successfully, and the iPhone received a successful `render.result`, but the Band screen then went black and the Band rebooted. That ordering proves transfer, Base64, SHA-256 and BBMV decoding completed; the failure occurred when Vela painted the reactive vector elements after the success response. The vector renderer supplied `transform:rotate(...)` inside a dynamically assembled CSS string. [AIoT Toolkit 2.0 migration guidance](https://iot.mi.com/vela/quickapp/en/tools/toolkit/update.html) requires dynamic transforms to use a bound style object whose `transform` value is `JSON.stringify({ rotate: "...deg" })`; incorrect syntax can affect startup/runtime behavior.

RPK `0.2.7 (9)` changes only that render boundary: each line now uses the documented Toolkit 2 style object and rotates around a precomputed segment midpoint, avoiding dynamic `transform-origin`. Protocol, transfer, Base64, SHA-256 and the eight-line payload are unchanged.

The latest three owner logs all reached asset validation and transfer start, then failed on the first chunk with `ASSET_BASE64_INVALID` for real raster, real vector and synthetic vector payloads. The shared failure was the Band page's use of `@system.crypto`: [Xiaomi's official compatibility table](https://iot.mi.com/vela/quickapp/en/features/security/crypto.html) marks that module unsupported on Xiaomi Smart Band 10. The Node harness mocked `crypto.atob` and `crypto.hashDigest`, which falsely made the old implementation pass locally.

RPK `0.2.6 (8)` previously:

1. Removes the unsupported `system.crypto` feature/import completely.
2. Decodes Base64 directly into `Uint8Array`, following Xiaomi's documented pure-JavaScript approach.
3. Verifies SHA-256 incrementally while each file chunk is accepted, using only a fixed 64-byte block buffer instead of rereading or retaining the whole payload.
4. Removes crypto injection and fake crypto implementations from the RPK test harness. The regression test now transfers binary bytes without any crypto module and verifies the actual stored bytes and digest.

Earlier supplied logs also proved three independent failures that remain fixed:

1. Raster and Synthetic 8 reached a Band `status=ok`, but the returned byte count did not match the transferred payload. The RPK success function had six parameters and depended on optional JavaScript arguments. It now has four parameters and returns the already validated publication metadata directly.
2. The exported JSON was truncated at exactly 1,025 bytes. Export is now compact, sorted JSON below 1,024 bytes while internal run records remain detailed.
3. Vietmap vector tiles are transformed before protobuf parsing. The iPhone now applies the transform used by Vietmap GL JS, then decodes the correct MVT 2.1 layer fields and bounded buffer coordinates observed in a real tile.

Vietmap's current `vlc-20260824` tile encoding did not decode with the transform published in Vietmap GL JS 6.x. H1 therefore discovers the compatible legacy style at `/mt/tm/style.json`, clamps the POC request to zoom 14, downloads one tile, decodes it on the iPhone, and sends at most 40 compact BBMV line primitives to the Band. The multi-megabyte provider tile is never transferred to the Band.

Fresh live checks with the saved keys returned:

- Static Map: HTTP 200, `image/png`, 212×360, 21,896 bytes.
- Current TileMap style: HTTP 200, `application/json`, 113,407 bytes.
- Compatible legacy tile used during diagnosis: HTTP 200, 2,339,760 bytes; production Swift decoding produced a non-empty road scene for the fixed POC coordinate.

No key, provider URL, raw tile body, UUID or BLE secret is included in an H1 export.

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
- Old Band package fully uninstalled, then RPK `0.2.7 (9)` installed.
- IPA `0.1.4 (5)` installed and signed through the tester's normal process.
- Test while stationary.

## Test sequence and expected output

Run one mode at a time. After any terminal failure, disconnect and reconnect before the next attempt.

1. Open the Band app.
   - Expected: `BLUEBAND MAP`, a ready/link status and `RPK 0.2.7` appear immediately.
   - Stop if the screen is black, frozen or displays another version.
2. Connect from the compact device picker and complete authentication/trust.
   - Expected iPhone state: `Đã xác thực`.
3. Run `Vector · Synthetic 8 lines` first.
   - Expected metrics: `94 / 8`.
   - Expected terminal state: displayed/success, not `RESULT_BYTES_MISMATCH` or `ASSET_RESULT_INVALID`.
   - Expected Band output: eight visible line primitives and a responsive UI.
4. Disconnect/reconnect and run `Raster · Indexed PNG`.
   - Expected: zero provider calls, a visible four-colour raster and displayed/success.
5. Disconnect/reconnect and run `Raster · Vietmap Static Map`.
   - Expected: one provider call, a roughly 20–25 KiB payload, a recognizable map and displayed/success.
6. Disconnect/reconnect for each of `Synthetic 20` and `Synthetic 40`.
   - Expected primitive counts: 20 and 40. Record responsiveness and ACK p95; 40 is the H1 ceiling test.
7. Disconnect/reconnect and run `Vector · Vietmap TileMap` last.
   - Expected: legacy style discovery, one zoom-14 tile processed on iPhone, a non-zero primitive count no greater than 40, visible roads and displayed/success.
   - The provider tile is about 2.3 MB, so preparation can take several seconds. Only the compact BBMV scene is transferred to the Band.
8. Tap `Export log H1` after every terminal run and save/share the JSON.
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
