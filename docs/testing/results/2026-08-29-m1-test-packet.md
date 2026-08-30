# M1 owner hardware test packet — 2026-08-29

## Procedure status

This document is a hardware acceptance procedure, not a hardware result. It does not establish Xiaomi Smart Band 10 map support, record a completed run or imply `PASS-HW`. Complete it only with the actual signed Apple build and RPK release artifacts. Never invent or copy artifact identifiers from source metadata.

Run the procedure while stationary. Do not operate the iPhone or Band while riding a motorcycle. Mi Fitness must remain fully closed while BlueBandMap owns the Xiaomi connection.

## Required artifact identity

The source tree currently declares iOS version `0.1.0` with build `1`, and RPK version `0.2.0` with version code `2`. These are source versions, not proof of the artifacts installed for the test.

Fill every field below from the actual release artifacts after the Apple build exists and before hardware execution:

- Git commit used for both artifacts, full SHA: `REQUIRED AFTER BUILD`
- Apple build/archive ID: `REQUIRED AFTER BUILD`
- IPA version and build read from the built artifact: `REQUIRED AFTER BUILD`
- IPA SHA-256 computed from the installed release artifact: `REQUIRED AFTER BUILD`
- RPK version and version code read from the built artifact: `REQUIRED AFTER BUILD`
- RPK SHA-256 computed from the installed release artifact: `REQUIRED AFTER BUILD`

If any field is unavailable or cannot be tied to the installed artifact, return `BLOCKED-ENV`; do not run or report `PASS-HW`.

## Target and configuration record

- iPhone: iPhone 13 Pro Max
- Observed iOS version: `26.x — record exact version at test time`
- Band: Xiaomi Smart Band 10
- Observed Band firmware: `record exact firmware at test time`
- Mi Fitness: closed and not holding the Band connection
- Test posture: stationary, with no phone or Band operation while riding

Record configuration health as `SAVED`, `MISSING` or `UNREADABLE`; never record values, Keychain contents or CoreBluetooth UUIDs:

| Configuration | Health | Acceptance note |
|---|---|---|
| Xiaomi AuthKey | `record` | Must be `SAVED` before connection. |
| Vietmap Service key | `record` | Must be `SAVED`; M1 consumes this key. |
| Vietmap TileMap key | `record` | Optional for M1. It may be saved, but M1 must not load or consume it. |

## Stop conditions

Stop immediately and do not press M1 again after any of the following:

- HTTP 429, `PROVIDER_RATE_LIMITED` or another provider rate-limit indication;
- corrupt, truncated, mismatched or unexpected map content;
- any secret, key, private peripheral identifier or unredacted sensitive diagnostic appearing in UI, logs, screenshots or exports;
- iOS or RPK crash, hang or unsafe device interaction;
- any need to operate the phone or Band while riding.

Preserve only redacted evidence. Return to the previous signed known-good IPA/RPK pair whose versions and SHA-256 values were recorded, perform a clean reinstall, and re-establish the connection from a stationary position. Do not retry the live provider after a 429 during this test window.

## Main M1 procedure

Use a provider-call counter that reveals only counts and stable status codes. The positive procedure allows at most five provider calls: one for each explicit M1 press. RPK reload checks allow zero additional provider calls.

1. Verify that all required artifact identity fields above were filled from the actual IPA and RPK artifacts. Record the exact observed iOS and Band firmware versions. Confirm the test is stationary and Mi Fitness is closed.
2. Remove the previous RPK and clean-install RPK `0.2.0` from the recorded artifact. Confirm the displayed RPK version before continuing.
3. Install the recorded iOS release build on the iPhone 13 Pro Max and launch it. Do not infer the IPA version or hash from the source tree.
4. Open Config. Confirm AuthKey and Vietmap Service key are still saved. Record the optional TileMap key health without revealing any value. Close and reopen Config once to confirm persistence. M1 must use only the Service key.
5. Open the compact Connect picker, select the intended remembered or discovered Band without recording its UUID, and complete device proof plus the RPK handshake. Confirm the iOS app reports the application session ready.
6. Press M1 exactly once for transfer 1. Make no second press while busy. Wait until the Band displays `M1 MAP READY`. Validate recognizable image content, matching eight-character hash prefixes on iOS and Band, no corruption and no crash. Record cumulative provider calls; maximum: `1`.
7. Press M1 exactly once for transfer 2. Wait for `M1 MAP READY`, then validate image content, matching eight-character hash prefixes, no corruption and no crash. Record cumulative provider calls; maximum: `2`.
8. Press M1 exactly once for transfer 3. Wait for `M1 MAP READY`, then validate image content, matching eight-character hash prefixes, no corruption and no crash. Record cumulative provider calls; maximum: `3`.
9. Press M1 exactly once for transfer 4. Wait for `M1 MAP READY`, then validate image content, matching eight-character hash prefixes, no corruption and no crash. Record cumulative provider calls; maximum: `4`.
10. Press M1 exactly once for transfer 5. Wait for `M1 MAP READY`, then validate image content, matching eight-character hash prefixes, no corruption and no crash. Record cumulative provider calls; maximum: `5`.
11. Confirm the five explicit transfers made no more than five provider calls total. Any automatic request, retry or sixth call fails the call-budget check.
12. Without pressing M1, close and reopen the RPK ten times. After each reopen, confirm the last verified map returns or the RPK reaches its expected safe state without corruption or crash. Record the provider counter for reloads 1 through 10. Every reload delta must be `0`, and the cumulative provider count must remain unchanged from step 11.

### Positive-run evidence table

| Check | Result | Redacted evidence |
|---|---|---|
| M1 press 1: ready/image/hash/no crash | `record` | short hash prefix and screenshot ID only |
| M1 press 2: ready/image/hash/no crash | `record` | short hash prefix and screenshot ID only |
| M1 press 3: ready/image/hash/no crash | `record` | short hash prefix and screenshot ID only |
| M1 press 4: ready/image/hash/no crash | `record` | short hash prefix and screenshot ID only |
| M1 press 5: ready/image/hash/no crash | `record` | short hash prefix and screenshot ID only |
| Provider calls for five presses | `record; must be ≤5` | count only |
| Provider calls for ten reloads | `record; must be 0` | per-reload deltas and total delta only |

## Controlled recovery and negative checks

Run these with a controlled fixture or instrumented test build. Keep their provider counts separate from the five-press positive budget. Do not perform live redirect injection with a real Vietmap key.

1. **Semantic Band failure cleanup:** Force a current-run Band write failure. Verify the Band removes the partial file and clears working ownership before sending `ASSET_WRITE_FAILED` and the ACK. Record the provider counter when the semantic result arrives and verify it does not change automatically. After the iOS operation settles, make one explicit retry. It must begin without `ASSET_BUSY`, increment the provider counter by exactly one and complete normally; no automatic provider call or retry is allowed.
2. **Ambiguous ACK/send failure:** Force a local ACK/send failure after Band ownership may have started. Verify iOS shows `TRANSFER_RECONNECT_REQUIRED`, disables or rejects retry, and makes zero provider calls for presses before a full disconnect/reconnect. After disconnect and a new connected event, one explicit press must make exactly one provider call.
3. **Result timeout:** Record the provider counter after the initiating explicit press, then withhold the Band render result after the final ACK until `ASSET_RESULT_TIMEOUT`. Verify there is no automatic retry and no additional provider call either before or after the timeout. Every pressed retry while reconnect-gated must make zero provider calls and report reconnect-required. Disconnect and reconnect, then make one explicit retry; it must increment the provider counter by exactly one. A stale timeout from the old run must not mutate the new run.
4. **Stale same-asset result:** Start a new run using the same asset bytes as a terminal prior run, then inject the prior run's delayed `map.asset.result`. Verify the old run ID is ignored and the current run alone determines the state.
5. **Stale different-run preservation:** While run B is actively transferring, inject a stale chunk from run A carrying the same asset ID but run A's different run ID. Verify the Band returns `ASSET_RUN_MISMATCH` correlated to run A, preserves run B as the current active transfer, and run B proceeds through verification and reaches `M1 MAP READY` normally.
6. **Redirect rejection and response bound:** Using a controlled URLProtocol/provider fixture and a dummy test credential, return one HTTPS redirect with an oversized declared or streamed response body. Verify the transport rejects the redirect without following it, does not buffer more than `MapAsset.maximumPNGBytes`, reports the bounded app-facing code `PROVIDER_REQUEST`, and makes exactly one provider request. Do not require or attempt live redirect injection with a real key.

## Evidence and disposition

Return exactly one status:

- `PASS-HW`: all required artifact identities are real and recorded; the positive procedure and required recovery checks pass on the target hardware.
- `FAIL-HW`: a reproducible hardware behavior violates the packet. Record the failed numbered step and stable error code.
- `BLOCKED-ENV`: required artifacts, signing, device/firmware access, controlled fixtures or safe test conditions are unavailable.
- `NEEDS-MEASURE`: functional checks completed, but a required count, timing, hash-prefix comparison or other measurement is missing or inconclusive.

Attach only redacted evidence:

- disposition and failed/blocked step, if any;
- full source commit and build/archive ID;
- IPA/RPK versions and SHA-256 values from actual artifacts;
- exact iOS and Band firmware versions;
- configuration health labels only;
- provider-call counts for each press, all ten reload deltas and controlled negative checks;
- stable bounded error codes, eight-character content-hash prefixes and redacted screenshot identifiers;
- confirmation that Mi Fitness remained closed and testing remained stationary.

Do not include AuthKey, Vietmap key values, CoreBluetooth peripheral UUIDs, nonces, HMACs, derived keys, raw captures, signing material or unredacted screenshots.
