# ADR 0008: Correlate map transfers by attempt

- Status: Accepted
- Date: 2026-08-30

## Context

M1 map assets are content-addressed, so an explicit retry of identical PNG bytes has the same asset ID. Asset ID alone therefore cannot distinguish a delayed `map.asset.result` from a prior attempt. The iOS owner also needs a bounded value that survives the full application-envelope transfer and Band render result.

## Decision

Every explicit M1 attempt creates a run ID matching `^[a-z0-9-]{1,24}$`. The same `run` string is required in `map.asset.begin`, every `map.asset.chunk`, `map.asset.end`, and the corresponding `map.asset.result`. The Band stores the run with the active transfer and pending render publication, rejects a changed run, and round-trips the triggering run in failure results. iOS accepts a result only when both asset ID and run ID match its current pending attempt.

Chunk sizing reserves the maximum 24-byte run ID even when the current run is shorter. With a 32-byte worst-case escaped envelope ID and a six-digit offset, 210 raw chunk bytes encode to an envelope of exactly 512 bytes; the next Base64 quantum does not fit. Every emitted envelope is independently encoded and checked against the 512-byte application limit.

The independent Swift and Band JavaScript tests use these exact body vectors:

```json
{"asset":"m1-0123456789abcdef","bytes":4,"height":360,"mime":"image/png","run":"run-0123456789abcdef","sha256":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","width":212}
{"asset":"m1-0123456789abcdef","data":"AAECAw==","offset":0,"run":"run-0123456789abcdef"}
{"asset":"m1-0123456789abcdef","run":"run-0123456789abcdef"}
{"asset":"m1-0123456789abcdef","bytes":4,"run":"run-0123456789abcdef","sha256Prefix":"01234567","status":"ok"}
```

An `ASSET_RUN_MISMATCH` result carries the rejected message's run, allowing the owner of a newer run to ignore a stale prior message rather than fail the current attempt.

## Consequences

- A stale result for identical asset bytes is deterministic because its prior run ID does not match the current run.
- A run remains locally owned until its fetch or awaited send settles, even if a semantic Band failure has already made the public state terminal.
- The Band-result timeout starts only after the final transfer ACK. It is cancelled by a matching result, disconnect, or a new explicit run.
- The application-envelope payload changed, but Xiaomi SPP framing, authentication, encryption, and `ThirdPartyApp` codec bytes are unchanged.
- Automated tests do not establish hardware support; the cases below remain hardware acceptance work.
