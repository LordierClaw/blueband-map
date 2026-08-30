# Hardware acceptance: Xiaomi Smart Band 10

Automated tests do not constitute hardware acceptance. Record only versions, artifact hashes, pass/fail stages, and sanitized error categories—never AuthKeys or device identifiers.

Status: **not yet executed for this new foundation**.

| Stage | Expected result | Result |
|---|---|---|
| Verify IPA/RPK SHA-256 | Matches workflow `SHA256SUMS` | Not run |
| Install unsigned iOS app | Launches under free Apple ID provisioning | Not run |
| Clean-install RPK | Shows `RPK 0.1.0` | Not run |
| Foreground scan | Band 10 is selectable | Not run |
| FE95/5E/5F discovery | SPP configuration succeeds | Not run |
| Auth and proof | Model, firmware, battery populated | Not run |
| RPK handshake | State becomes `applicationReady` | Not run |
| iOS → band echo | Band renders once and ACKs | Not run |
| Band → iOS echo | iOS renders once and ACKs | Not run |
| Duplicate delivery | ACK twice, render once | Not run |
| Disconnect | Offline status/cleanup; BLE closes | Not run |
| Changed fingerprint | Rejected until deliberate reset | Not run |
| Resume Mi Fitness | Normal ownership resumes after disconnect | Not run |

Test with the supported matrix only: one iPhone running iOS 17 or later, one Xiaomi Smart Band 10 on the documented firmware, the exact IPA/RPK hashes, and Mi Fitness closed during the direct session.

## Map/navigation POC acceptance protocol

The target acceptance device for the map/navigation POCs is:

- iPhone 13 Pro Max.
- iOS 26.
- Xiaomi Smart Band 10.
- The Band firmware installed at test time, recorded in the result rather than treated as a fixed design dependency.
- Motorcycle routing until the U2 vertical slice passes.

The detailed phase gates are defined in the [approved risk-first POC design](../superpowers/specs/2026-08-29-blueband-map-poc-roadmap-design.md). Do not append a later POC result to the foundation table above; each POC receives a separate result file so evidence remains attributable to one artifact pair and one script.

### Required test packet

The developer supplies:

1. Phase/build ID and git commit.
2. IPA and RPK version plus SHA-256 values.
3. Relevant change summary.
4. Clean-install or upgrade steps.
5. Required masked configuration-health state.
6. Numbered five-to-ten-minute test procedure.
7. Expected visible result at every step.
8. Maximum permitted Vietmap API calls for the procedure.
9. Stop conditions and previous known-good recovery path.

The tester returns one status:

- `PASS-HW`: every gate condition was observed on the target hardware.
- `FAIL-HW`: a repeatable device failure occurred.
- `BLOCKED-ENV`: provisioning, quota, installation or another environment condition prevented the behavior from being exercised.
- `NEEDS-MEASURE`: functional behavior passed but the required timing/readability/stability measurement is incomplete.

The result includes the first failing step, local timestamp, firmware version, safe screenshot/video when useful, subjective readability/smoothness notes requested by the gate, and a redacted diagnostic export.

### Result file template

Store completed records under `docs/testing/results/` with the name `YYYY-MM-DD-<phase>-<build-id>.md`.

```markdown
# Hardware result: <phase> <build-id>

- Result: PASS-HW | FAIL-HW | BLOCKED-ENV | NEEDS-MEASURE
- Git commit: <full commit used to build>
- IPA version and SHA-256: <version and digest>
- RPK version and SHA-256: <version and digest>
- iPhone: iPhone 13 Pro Max
- iOS: 26.x observed during test
- Band: Xiaomi Smart Band 10
- Band firmware: <observed version>
- Test start: <local ISO-8601 time with offset>
- Vietmap call budget: <maximum declared by test packet>
- Vietmap calls observed: <non-secret count>

## Steps

| Step | Expected | Observed | Result |
|---|---|---|---|
| 1 | <copied from test packet> | <tester observation> | PASS/FAIL |

## Measurements

| Metric | Value | Unit/context |
|---|---:|---|
| <gate metric> | <observed value> | <unit> |

## Failure or feedback

<First failure, readability/smoothness feedback, or "None".>

## Attachments

<Safe screenshot/video names and redacted diagnostic export, or "None".>
```

Angle-bracket fields belong only to this copyable result template. A committed result must replace all of them with observed values or the explicit word `None`.

### Diagnostic safety

Allowed fields include build, phase, device class, OS version, user-recorded firmware, stage, bounded asset identity, short content-hash prefix, byte/count/timing values, provider-call count and stable error code.

Never export AuthKey, Vietmap keys, full CoreBluetooth peripheral identifiers, nonces, HMACs, derived keys, raw encrypted payloads, private signing material or unredacted captures.

### M1 run ownership and HTTPS acceptance cases

Run these with a controlled fixture build and redacted diagnostics. Do not use a real key or live Vietmap request for redirect injection.

| Case | Procedure | Expected result | Result |
|---|---|---|---|
| Stale prior result, same asset | Complete attempt A terminally, explicitly start attempt B with identical PNG bytes, then deliver A's delayed `map.asset.result` before B's current result. | The asset IDs may match, but A's run ID is ignored. B remains transferring or waiting until its own run result arrives, then reaches only B's terminal state. | Not run |
| Current-run failure cleanup and retry | During a controlled current run, force one Band file-write failure, then wait for its semantic result and ACK before explicitly retrying with a fresh run. | Band removes the partial file and clears working state before publishing `ASSET_WRITE_FAILED` and ACK. The fresh run begins without `ASSET_BUSY` and makes exactly one new provider call. | Not run |
| Stale failure preserves current run | Keep run B active, then inject a controlled chunk from run A with the same asset ID. Continue B after the rejection. | Band returns `ASSET_RUN_MISMATCH` for A without deleting or clearing B; B continues and reaches only B's terminal result. | Not run |
| Ambiguous transfer failure recovery | Force an iOS-local send/ACK failure after Band may own the transfer, then press M1 before and after a full disconnect/reconnect cycle. | The first retry reports `TRANSFER_RECONNECT_REQUIRED`, remains disabled in UI, and makes zero provider calls. After reconnect, one explicit press makes exactly one provider call. | Not run |
| Result timeout and recovery | ACK every transfer step but withhold the Band render result through the bounded wait; press M1, then complete a disconnect/reconnect cycle and press again. | The run becomes `ASSET_RESULT_TIMEOUT`; no automatic retry occurs. The pre-reconnect press reports `TRANSFER_RECONNECT_REQUIRED` with zero provider calls. The post-reconnect press owns a new run and makes exactly one provider call. | Not run |
| Redirect rejection and call budget | Point the controlled provider fixture at one HTTPS redirect response and press M1 once. | The iOS transport does not follow the redirect, buffers no oversized response, reports a bounded provider failure, and observes exactly one provider request with no retry. | Not run |

### Road-test safety

The tester must not operate the phone or Band while controlling a motorcycle. Use a passenger for live observations or stop safely before reading, capturing or exporting diagnostics. A stationary route replay must pass before the live road test begins.
