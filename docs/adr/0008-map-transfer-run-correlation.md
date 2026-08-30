# ADR 0008: Correlate map transfers by attempt

- Status: Accepted
- Date: 2026-08-30

## Context

M1 map assets are content-addressed, so an explicit retry of identical PNG bytes has the same asset ID. Asset ID alone therefore cannot distinguish a delayed `map.asset.result` from a prior attempt. The iOS owner also needs a bounded value that survives the full application-envelope transfer and Band render result.

## Decision

Every explicit M1 attempt creates a run ID matching `^[a-z0-9-]{1,24}$`. The same `run` string is required in `map.asset.begin`, every `map.asset.chunk`, `map.asset.end`, and the corresponding `map.asset.result`. The Band stores the run with the active transfer and pending render publication, rejects a changed run, and round-trips the triggering run in failure results. iOS accepts a result only when both asset ID and run ID match its current pending attempt.

A terminal Band failure for the active transfer is identified only by an exact validated asset-and-run match. The Band clears the transfer and working UI state, finishes cleanup of the unconfirmed file, and only then sends the error `map.asset.result` followed by the request ACK. A stale or different asset/run rejection never discards the active transfer. This ordering makes a valid semantic `ASSET_*` result proof that Band ownership has been released before iOS offers an explicit retry.

An iOS-local send, ACK, cancellation, invalid-result, or result-timeout failure cannot prove that Band ownership was released. Such a terminal state raises a reconnect-required gate. A retry attempt performs no provider request and reports `TRANSFER_RECONNECT_REQUIRED` until iOS observes a disconnect followed by a new connected event. Provider failures before transfer and valid current-run semantic `ASSET_*` results do not raise the gate. Run tokens continue to prevent a cancelled or stale operation or timeout from mutating a newer attempt.

Chunk sizing reserves the maximum 24-byte run ID even when the current run is shorter. With a 32-byte worst-case escaped envelope ID and a six-digit offset, 210 raw chunk bytes encode to an envelope of exactly 512 bytes; the next Base64 quantum does not fit. Every emitted envelope is independently encoded and checked against the 512-byte application limit.

The independent Swift and Band JavaScript tests use these exact body vectors:

```json
{"asset":"m1-054edec1d0211f62","bytes":4,"height":360,"mime":"image/png","run":"run-0123456789abcdef","sha256":"054edec1d0211f624fed0cbca9d4f9400b0e491c43742af2c5b0abebf0c990d8","width":212}
{"asset":"m1-054edec1d0211f62","data":"AAECAw==","offset":0,"run":"run-0123456789abcdef"}
{"asset":"m1-054edec1d0211f62","run":"run-0123456789abcdef"}
{"asset":"m1-054edec1d0211f62","bytes":4,"run":"run-0123456789abcdef","sha256Prefix":"054edec1","status":"ok"}
```

An `ASSET_RUN_MISMATCH` result carries the rejected message's run, allowing the owner of a newer run to ignore a stale prior message rather than fail the current attempt.

## Consequences

- A stale result for identical asset bytes is deterministic because its prior run ID does not match the current run.
- A run remains locally owned until its fetch or awaited send settles, even if a semantic Band failure has already made the public state terminal.
- The Band-result timeout starts only after the final transfer ACK. It is cancelled by a matching result, disconnect, or a new explicit run.
- Current-run Band failures publish their result and ACK only after unconfirmed-file cleanup completes; stale asset/run failures preserve the active transfer.
- Ambiguous iOS-local transfer failures require a disconnect/reconnect cycle before another provider fetch. The UI disables M1 retry and explains this requirement.
- The application-envelope payload changed, but Xiaomi SPP framing, authentication, encryption, and `ThirdPartyApp` codec bytes are unchanged.
- Automated tests do not establish hardware support; the cases below remain hardware acceptance work.
