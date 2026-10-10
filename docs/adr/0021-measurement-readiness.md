# ADR 0021: Passive native send evidence and complete startup measurement

Status: accepted for measurement candidate; hardware acceptance pending.

## Context

The strict target includes Start to first display as well as moving, turning and
entering uncached coverage. Existing GPS-to-confirmation timing can conceal
startup before the latest GPS fix. Existing send errors cannot distinguish
missing native callbacks from application ACK delay. Instrumentation needs to
capture these distinctions in one install without tuning transport first.

## Decision

Keep Xiaomi framing, crypto, segmentation, command bytes/retries, write ordering,
chunk windows and map scheduling unchanged. Extend only the application diagnostic
envelope with opt-in `diagnostics.get` body `transport:true`. Existing requests
retain their existing response and ACK behavior. Send no periodic diagnostic poll.

The response body contains `request`, `rpk`, `versionName`, and `transport` v1.
Counter fields are `attempted`, `succeeded`, `failed`, `pending`, `peakPending`,
`timeouts204`, `abandoned` (pending callbacks invalidated by a lifecycle change).
Counters saturate at 2147483647 and set `saturated:true`; saturated evidence is
inconclusive. State is plain non-rendered JavaScript storage. The first live-epoch
callback settles a send; duplicates and old connection/epoch callbacks do nothing.
Native error 204 retains transfer state exactly as before. Other errors still lock.

`lastCallbackMs` and `maxCallbackMs` are Band-local callback durations, nullable
when unavailable. Sticky `clockValid:false` nulls both. A pending send is never a
zero-duration success. The snapshot precedes its own reply and ACK; cumulative
counters cover the page lifetime, including previous navigation sessions. Compare
snapshots only within the same page lifetime; they are not per-case throughput.
Neither native success nor image completion proves physical scanout.

Independent literal application vector:
`apps/band/test/fixtures/transport-diagnostics.json` is 451 ASCII bytes, includes
maximum-width counters, 32-character request and a long message ID, and is compared
byte-for-byte with the actual page response. Normal RPK identities are shorter.
Existing Xiaomi and application vectors must remain passing. No raw captures or
keys are introduced. Unsupported peers remain unobservable, never assumed fast.

Trace schema remains 1; measurement contract is 2. Add Start uptime, immutable
case/environment/mode metadata, fixed phase/visible-problem markers, and physical
write/receive-ACK telemetry correlated by session/request. Add separate startup,
readiness and complete-goal gates without reinterpreting the legacy `overall` gate.

## Hardware acceptance cases

1. iOS 27 + unchanged Band firmware: record exact versions, request resource and
   transport diagnostics, verify correlated responses within 512-byte limit.
2. Delayed/no native callback: pending remains observable while independent sends
   continue; compare with video and command ACK timing.
3. Native 204: accepted chunks survive; bounded exact-command retry completes.
4. Disconnect/reconnect or map reset during callbacks: abandoned grows, old
   callbacks cannot unlock/lock or corrupt new measurements; new requests work.
5. Cold/warm Start, cached movement, turn and new coverage: export complete traces
   and video. Confirm startup includes GPS/routing/bootstrap and all deadlines are
   strictly below 1000 ms, or report the measured failure.
6. Phone locked and Band sleep/wake: identify suspension and missing confirmations;
   never infer background support from simulator or deterministic tests.

All hardware cases are pending. CI validates contracts and ownership, not latency
or firmware callback availability. Only the subsequent evidence-driven iteration
may change scheduling/prefetch/rotation, with its own regression evidence.
