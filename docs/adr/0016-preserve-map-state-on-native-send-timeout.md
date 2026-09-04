# ADR 0016: Preserve map state on native send timeout

- Status: Accepted; device acceptance pending
- Date: 2026-09-04
- Follows: ADR 0014 and ADR 0015

## Evidence

The supplied iOS 0.5.15 (31) trace still ends in `TRANSFER_TIMEOUT`, ACK `3/18`, `transferMs=4875`, `maxAckMs=478`, `window=1`. Sequential transmission did not resolve this device's failure. There is no `band.displayed` or finite display latency. The trace does not include the native Band send error, so it cannot establish which packet or callback failed.

A separate reproducible defect exists in the RPK: every native `send.fail` previously called `lock`, discarding `activeTransfer`, accepted bytes and duplicate-command recovery state. Injecting error 204 after accepting a chunk reproduces that data loss. Xiaomi documents 204 as connection timeout and 1006 as disconnected, not interchangeable outcomes ([official interconnect API](https://iot.mi.com/vela/quickapp/en/features/network/interconnect.html)). This is a proven recovery defect, **not proof that 204 caused the supplied hardware trace**.

iOS CI [33827826566](https://github.com/LordierClaw/blueband-map/actions/runs/33827826566) also reproduces a second defect: a new GPS fix triggers a second snapshot after the transfer has already become reconnect-required. The new test expected one render and observed two.

## Decision

1. Preserve accepted map state on native send timeout 204. Reuse the existing exact-command retry and duplicate ACK behavior. Genuine disconnect, unknown failure, close and error callbacks retain cleanup. Old-connection callbacks remain epoch-guarded. Do not extend timeouts or add a retry loop.
2. Reject publication before rendering when the coordinator requires reconnect. GPS processing continues; the unusable session does not fetch/encode another snapshot.
3. After a terminal connected transfer failure, request one bounded diagnostic exchange using the existing reliable application sender. No polling on success, GPS updates, cancellation or disconnect. Only a correlated, range-checked report updates the diagnostic summary. A missing reply is `peer=unavailable`, never inferred success.

No Xiaomi authentication, encryption, SPP framing, protobuf bytes, chunk size, image payload limit, map renderer, camera, route/marker styling or GPS permission policy changes. The two new topics use the existing application-envelope v1 extension point. Older RPKs may acknowledge an unknown request without a report; they remain explicitly unobservable.

## Application vectors

Request, with a lowercase alphanumeric/hyphen nonce of 1–32 characters:

```json
{"v":1,"id":"i-probe","src":"ios","type":"message","topic":"diagnostics.get","body":{"request":"probe-1"}}
```

Report from RPK build 27 after receiving the first 4-byte chunk:

```json
{"v":1,"id":"b-probe","src":"band","type":"message","topic":"diagnostics.report","body":{"request":"probe-1","rpk":27,"phase":"chunk","offset":0,"received":4,"sendCode":0}}
```

`phase` is one of `none/prepare/begin/chunk/end`; `offset` is -1...8192, `received` is 0...8192, `sendCode` is -1...65535 (-1 unknown, 0 no send failure observed), and `rpk` is 1...9999. Reports contain no raw payload, coordinates, key, device identifier or arbitrary native error text. The RPK source test independently checks the literal report and a serialized size below 512 bytes; the iOS test checks correlation, numeric rejection and lifecycle ownership.

## Automated and hardware gates

The RPK regression first fails against the old implementation and passes with the fix. The full-size replay drives the actual RPK page source through 100 consecutive 8192-byte maps, asynchronous native/file callbacks, one lost ACK plus error 204 per map, identical command retries, hashing, publication and bounded file retirement. Decoder completion and native callbacks are modeled; this does not execute Xiaomi firmware or prove radio timing.

Hardware acceptance must still demonstrate initial map display, at least ten movement refreshes with the iPhone locked, finite GPS-to-display latency below five seconds, and recovery after one intentional disconnect. On the first failure, stop repeating Start and export the enriched log. A report with `err204` narrows the native-send path; `got` distinguishes accepted bytes from the phone's ACK count. An unavailable report means the failing boundary is still unobserved. It must not trigger speculative Xiaomi wire or renderer changes.
