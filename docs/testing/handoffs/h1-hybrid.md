# H1 owner hardware test handoff — hybrid renderer

This document is the H1 hardware acceptance procedure. It is not evidence that a Xiaomi Smart Band 10 has accepted or rendered the payload until the owner completes the steps with the exact IPA and RPK artifacts listed in the final bundle.

## Artifact identity

These values were checked against the downloaded CI artifact; never infer them from source metadata:

- Source commit: `068a3473bc96fb46a55559ab3b1b116bb9ee73d0`
- IPA: `artifacts/h1-hybrid/BlueBandMap-unsigned.ipa`
- IPA bytes / SHA-256: `777511` / `953d17cd6f6a01656d5642d59f07011504ec591253317406a40f6d360ae6084d`
- RPK: `artifacts/h1-hybrid/dev.lordierclaw.bluebandmap.band.debug.0.2.4.rpk`
- RPK bytes / SHA-256: `23235` / `e01d656062a033dc5ebe2338aa3125970ce78f25f22b6c0d432fd9a77ce13d95`
- iOS version/build: `0.1.3 (4)`
- RPK version/code: `0.2.4 (6)`
- Files to update on the test devices: **both IPA and RPK**. RPK `0.2.4` sends explicit success metadata and must not be paired with an older IPA/RPK.

An unsigned IPA needs a valid tester signing/sideload process. Do not put Apple credentials, profiles or signing keys in this repository.

## What H1 proves

The iPhone selects exactly one renderer before transfer. The Band acknowledges `render.prepare` with `render.ready` or `render.reject`; only `render.ready` allows the existing `map.asset.*` stop-and-wait transfer. A matching semantic response may race the transport ACK and is buffered. A vector failure never falls back to raster.

All H1 payloads are bounded to 212×360, 64 KiB, and at most 40 vector line primitives. The fixed-record vector payload is `BBMV` v1. Xiaomi BLE, SPP, authentication, encryption and transport-ACK bytes are unchanged.

Owner exports showed that both a real raster (`21567 / 0`) and Synthetic 8 (`94 / 8`) reached a Band `status=ok` response but ended as `RESULT_METADATA_INVALID`. RPK `0.2.4` now passes `bytes` and the eight-character SHA prefix explicitly at both raster and vector success call sites instead of relying on omitted JavaScript arguments in the Vela runtime. The iOS app keeps exact validation and now reports the mismatched field as `RESULT_RENDERER_MISMATCH`, `RESULT_FORMAT_MISMATCH`, `RESULT_BYTES_MISMATCH`, `RESULT_PRIMITIVES_MISMATCH`, or `RESULT_HASH_MISMATCH`; it does not convert a mismatch into success. Deterministic tests and CI cover the call contract, but only this owner run can confirm the Vela hardware behavior.

The developer live-smoked Vietmap Static Map with the saved Service key: HTTP 200, `image/png`, 212×360, 21,567 bytes. The saved TileMap key was also used for one bounded diagnosis: style HTTP 200 `application/json` (113,407 bytes), then tile z15/26093/15398 HTTP 200 (340,726 bytes) with no `Content-Type` header. The app now permits a missing tile MIME only for an HTTPS `maps.vietmap.vn` `.pbf` URL without userinfo and still requires bounded MVT decoding to succeed; a present but unsupported MIME remains rejected. Style and tile MIME failures are separated as `STYLE_MIME` and `TILE_MIME`. No URL, body, or key is exported.

The two metadata-failure JSON files received from the prior IPA were truncated at exactly 1,025 bytes. IPA `0.1.3` exports the existing sanitized JSON through a file transfer representation rather than sharing its URL value. A valid exported run must parse as JSON and contain the complete 64-character `payloadSHA256` field.

## Mode matrix

| Mode | iPhone source | Expected Band renderer | Provider call | Purpose |
|---|---|---|---:|---|
| Raster · Vietmap Static Map | Vietmap Static Map PNG | native PNG | 1 | real provider baseline |
| Raster · Indexed PNG | local four-color rasterization | native PNG | 0 | smaller raster comparison |
| Vector · Synthetic 8 lines | deterministic scene | native BBMV lines | 0 | first vector proof |
| Vector · Synthetic 20 lines | deterministic scene | native BBMV lines | 0 | moderate primitive load |
| Vector · Synthetic 40 lines | deterministic scene | native BBMV lines | 0 | H1 primitive ceiling |
| Vector · Vietmap TileMap | style/TileJSON + one MVT tile | native BBMV lines | 1 style/tile flow | real vector provider proof |

The UI has one button per mode. Run one button at a time and wait for a terminal state before starting another. The TileMap key is required only by the final vector mode; the Service key is required only by the Static Map mode.

## Preconditions

- iPhone 13 Pro Max with the exact iOS 26.x version recorded.
- Xiaomi Smart Band 10 with the exact current firmware recorded.
- Mi Fitness fully closed while BlueBandMap owns the session.
- AuthKey, Vietmap Service key and Vietmap TileMap key saved through Config; record only `SAVED`, `MISSING` or `UNREADABLE`, never values.
- Test stationary. Do not operate the phone or Band while riding.
- Fully uninstall the previous `dev.lordierclaw.bluebandmap.band` package first and confirm its icon disappears; this prevents a cached old RPK from being mistaken for `0.2.4`.
- Install the RPK and IPA whose hashes are recorded above.

## Test sequence

1. Verify the IPA/RPK hashes and versions against the bundle. If any identity is missing, return `BLOCKED-ENV`.
2. Open Config, close it, reopen it, and confirm saved-key health persists without displaying values.
3. Open the RPK. The entry page must immediately show `BLUEBAND MAP`, `PAGE READY` or `IOS LINK OPEN`, `CHECK CONNECTION`, and `RPK 0.2.4`; it must not be black or unresponsive. If it is black, stop and record the artifact hash before retrying.
4. Open the compact Band picker, select the intended Band, complete device proof and RPK trust, and reach `Đã xác thực`.
5. Run `Raster · Vietmap Static Map` once. Expect one provider call, a prepare/ready exchange, serialized transfer, a recognizable PNG, and terminal state `displayed` rather than `ASSET_RESULT_INVALID`. Record the displayed eight-character hash prefix and H1 metrics.
6. Disconnect and reconnect, then run `Raster · Indexed PNG` once. Expect zero additional provider calls, a visible four-color map, and terminal state `displayed`.
7. For each of Synthetic 8, 20, and 40 lines: disconnect/reconnect, run exactly one mode, then record bytes, primitive count, total time, ACK p95, terminal state, and whether the Band stayed responsive. The expected primitive counts are 8, 20, and 40; the 40-line run is a ceiling test, not an assumption of support.
8. Disconnect/reconnect and run `Vector · Vietmap TileMap` once. Expect style discovery and one bounded MVT tile, then a vector result with a non-zero road primitive count. If it fails before transfer, record the exact safe code—especially `STYLE_HTTP_###`, `TILE_HTTP_###`, `STYLE_MIME`, or `TILE_MIME`—and do not retry after a rate-limit response.
9. Use `Export log H1` after each terminal run. Save the file, confirm it is larger than 1,025 bytes when the run contains the full metric set, parse it as JSON, and confirm `payloadSHA256` has 64 characters. Keep only sanitized JSON and redacted screenshots.

## Recovery checks

Run these only after the positive sequence and only while stationary:

- Disconnect during prepare or transfer. The current run must terminate, partial Band ownership must be cleaned, retry must be blocked until a full reconnect, and no automatic provider request may occur.
- Deliver a stale result from a different run or scene. It must be ignored and must not change the current state.
- Deliver a result before the final transport ACK. The iPhone must display only after the exact final ACK is confirmed.
- Withhold the final result until timeout. The app must report `ASSET_RESULT_TIMEOUT`, preserve the sanitized run record, and make no automatic retry.
- If vector preparation or rendering fails, the app must report the vector error and must not invoke raster fallback.

## Stop conditions and response

Stop immediately on a crash, hang, unresponsive Band, corrupt/truncated/mismatched payload, provider rate limit, secret/UUID leakage, or unsafe interaction. Return exactly one disposition:

- `PASS-HW`: all required positive and recovery checks pass on the recorded artifacts and hardware.
- `FAIL-HW`: a reproducible hardware failure occurred; include the first step and bounded code.
- `BLOCKED-ENV`: artifacts, signing, keys, device, firmware, or safe test conditions are unavailable.
- `NEEDS-MEASURE`: behavior ran but a required count, timing, hash or screenshot evidence is missing.

Report only the disposition, artifact identities, exact iOS/firmware versions, key health labels, provider-call counts, bounded error codes, hash prefixes, metrics and redacted screenshot IDs. Do not report AuthKey, Vietmap keys, CoreBluetooth UUIDs, raw captures, nonces, HMACs, derived keys or signing material.

H2 work such as map pan/zoom, multi-tile viewport, routing, navigation instructions and view switching remains intentionally blocked until H1 hardware evidence is returned.
