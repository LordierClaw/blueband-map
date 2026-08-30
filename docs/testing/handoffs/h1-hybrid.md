# H1 owner hardware test handoff — hybrid renderer

This document is the H1 hardware acceptance procedure. It is not evidence that a Xiaomi Smart Band 10 has accepted or rendered the payload until the owner completes the steps with the exact IPA and RPK artifacts listed in the final bundle.

## Artifact identity

These values were checked against the downloaded CI artifact; never infer them from source metadata:

- Source commit: `57db1895fc92e1c3ebbf3a492c5d026079e7d21b`
- IPA: `artifacts/h1-hybrid/BlueBandMap-unsigned.ipa`
- IPA bytes / SHA-256: `767817` / `f2a35b09150464fc987f66b446464dd45b59e694a53034e4866e27963f699c65`
- RPK: `artifacts/h1-hybrid/dev.lordierclaw.bluebandmap.band.debug.0.2.3.rpk`
- RPK bytes / SHA-256: `23224` / `df5d18a6603e1b20113fd6e07b0ab9de70d8cb6931c87d7bd06809700fb541bd`
- iOS version/build: `0.1.1 (2)`
- RPK version/code: `0.2.3 (5)`
- Files to update on the test devices: **both IPA and RPK**. They share a changed H1 application-envelope contract and must not be mixed with an older counterpart.

An unsigned IPA needs a valid tester signing/sideload process. Do not put Apple credentials, profiles or signing keys in this repository.

## What H1 proves

The iPhone selects exactly one renderer before transfer. The Band acknowledges `render.prepare` with `render.ready` or `render.reject`; only `render.ready` allows the existing `map.asset.*` stop-and-wait transfer. A matching semantic response may race the transport ACK and is buffered. A vector failure never falls back to raster.

All H1 payloads are bounded to 212×360, 64 KiB, and at most 40 vector line primitives. The fixed-record vector payload is `BBMV` v1. Xiaomi BLE, SPP, authentication, encryption and transport-ACK bytes are unchanged.

The `0.2.3` RPK retains the page-load and raster-publication fixes from `0.2.2`, and changes the aggregate H1 result from JSON Boolean `success` to the bounded string `status: "ok" | "error"`. The `0.1.1` IPA accepts only that exact result schema. This targets the common failure visible in owner evidence: Static Map transferred `21567 / 0` and Synthetic 8 transferred `94 / 8` before both ended as `ASSET_RESULT_INVALID`. The schema change is covered by exact Swift/RPK vectors and iOS simulator tests, but only this owner run can confirm the native Vela bridge diagnosis on Band hardware.

The developer live-smoked Vietmap Static Map once with the saved Service key: HTTP 200, `image/png`, 212×360, 21,567 bytes. The documented TileMap style URL was independently checked against current Vietmap documentation, but no live TileMap call was made from the build machine because `local/vietmap-tilemap-key` is absent. The IPA now preserves safe three-digit statuses such as `PROVIDER_HTTP_401` or `PROVIDER_HTTP_403`; it never exports the URL, response body, or key.

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
- Fully uninstall the previous `dev.lordierclaw.bluebandmap.band` package first and confirm its icon disappears; this prevents a cached old RPK from being mistaken for `0.2.3`.
- Install the RPK and IPA whose hashes are recorded above.

## Test sequence

1. Verify the IPA/RPK hashes and versions against the bundle. If any identity is missing, return `BLOCKED-ENV`.
2. Open Config, close it, reopen it, and confirm saved-key health persists without displaying values.
3. Open the RPK. The entry page must immediately show `BLUEBAND MAP`, `PAGE READY` or `IOS LINK OPEN`, `CHECK CONNECTION`, and `RPK 0.2.3`; it must not be black or unresponsive. If it is black, stop and record the artifact hash before retrying.
4. Open the compact Band picker, select the intended Band, complete device proof and RPK trust, and reach `Đã xác thực`.
5. Run `Raster · Vietmap Static Map` once. Expect one provider call, a prepare/ready exchange, serialized transfer, a recognizable PNG, and terminal state `displayed` rather than `ASSET_RESULT_INVALID`. Record the displayed eight-character hash prefix and H1 metrics.
6. Disconnect and reconnect, then run `Raster · Indexed PNG` once. Expect zero additional provider calls, a visible four-color map, and terminal state `displayed`.
7. For each of Synthetic 8, 20, and 40 lines: disconnect/reconnect, run exactly one mode, then record bytes, primitive count, total time, ACK p95, terminal state, and whether the Band stayed responsive. The expected primitive counts are 8, 20, and 40; the 40-line run is a ceiling test, not an assumption of support.
8. Disconnect/reconnect and run `Vector · Vietmap TileMap` once. Expect style/TileJSON discovery and one bounded MVT tile flow, then a vector result with a non-zero road primitive count. If it fails before transfer, record the exact safe code—especially `PROVIDER_HTTP_###`—and do not retry after a rate-limit response.
9. Use `Export log H1` after each terminal run. Keep only the sanitized JSON and redacted screenshots; the app stores run files under its Application Support `BlueBandMap/test-runs` directory.

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
