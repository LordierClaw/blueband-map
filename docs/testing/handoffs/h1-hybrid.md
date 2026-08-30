# H1 owner hardware test handoff — hybrid renderer

This document is the H1 hardware acceptance procedure. It is not evidence that a Xiaomi Smart Band 10 has accepted or rendered the payload until the owner completes the steps with the exact IPA and RPK artifacts listed in the final bundle.

## Artifact identity

These values were checked against the downloaded CI artifact; never infer them from source metadata:

- Source commit: `4392d87b70bf6f93524d197d765ef5309904403e`
- IPA: `artifacts/h1-hybrid/4392d87/BlueBandMap-unsigned.ipa`
- IPA SHA-256: `1398839176c77cca72254613f67e6f5c32e98be076f3abe2e96a13c496601eab`
- RPK: `artifacts/h1-hybrid/4392d87/dev.lordierclaw.bluebandmap.band.debug.0.2.2.rpk`
- RPK SHA-256: `04b05323057357825fbd36313fc672c6a36786499b06c6295167f391d5bf531a`
- iOS version/build: `0.1.0 (1)` unless read differently from the installed artifact
- RPK version/code: `0.2.2 (4)` unless read differently from the installed artifact

An unsigned IPA needs a valid tester signing/sideload process. Do not put Apple credentials, profiles or signing keys in this repository.

## What H1 proves

The iPhone selects exactly one renderer before transfer. The Band acknowledges `render.prepare` with `render.ready` or `render.reject`; only `render.ready` allows the existing `map.asset.*` stop-and-wait transfer. A matching semantic response may race the transport ACK and is buffered. A vector failure never falls back to raster.

All H1 payloads are bounded to 212×360, 64 KiB, and at most 40 vector line primitives. The fixed-record vector payload is `BBMV` v1. Xiaomi BLE, SPP, authentication, encryption and transport-ACK bytes are unchanged.

The `0.2.2` RPK contains the page-load regression fix and the H1 raster hotfix: the entry page imports only the three Xiaomi system modules, keeps the render helpers page-local in firmware-safe ES5, and publishes raster through one native `<image>` instance with a separate render token. This removes the one-item template loop from the raster path and forces a new package version so an older cached RPK cannot be mistaken for the fix. These properties are verified in the compiled bundle; hardware acceptance remains pending.

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
- Fully uninstall the previous `dev.lordierclaw.bluebandmap.band` package first and confirm its icon disappears; this prevents a cached old RPK from being mistaken for `0.2.2`.
- Install the RPK and IPA whose hashes are recorded above.

## Test sequence

1. Verify the IPA/RPK hashes and versions against the bundle. If any identity is missing, return `BLOCKED-ENV`.
2. Open Config, close it, reopen it, and confirm saved-key health persists without displaying values.
3. Open the RPK. The entry page must immediately show `BLUEBAND MAP`, `PAGE READY` or `IOS LINK OPEN`, `CHECK CONNECTION`, and `RPK 0.2.2`; it must not be black or unresponsive. If it is black, stop and record the artifact hash before retrying.
4. Open the compact Band picker, select the intended Band, complete device proof and RPK trust, and reach `Đã xác thực`.
5. Run `Raster · Vietmap Static Map` once. Expect one provider call, a prepare/ready exchange, serialized transfer, and a recognizable PNG. Record the displayed eight-character hash prefix and the H1 terminal metrics.
6. Run `Raster · Indexed PNG` once. Expect zero additional provider calls and a raster result.
7. Run Synthetic 8, then 20, then 40 lines. After each run record bytes, primitive count, total time, ACK p95, and whether the Band stayed responsive. The 40-line run is the ceiling test, not an assumption of support.
8. Run `Vector · Vietmap TileMap` once. Expect the style/TileJSON discovery and one bounded MVT tile flow, then a vector result with a non-zero road primitive count. A provider authorization, schema, MIME or quota failure is recorded as a provider failure; do not retry after a rate limit.
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
