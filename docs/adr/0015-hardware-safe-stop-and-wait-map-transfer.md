# ADR 0015: Conservative stop-and-wait map transfer

- Status: Accepted
- Date: 2026-09-04

## Context

iOS 0.5.14 retained a two-message application ACK window and retried one immutable command after a timeout. A new iPhone and Xiaomi Smart Band 10 trace improved from 4/18 to 7/18 acknowledged messages, then still ended after 5,657 ms with `TRANSFER_TIMEOUT`. The route and admitted payload reached transfer, and location diagnostics reported an accepted precise fix with background updates enabled. The app was active; this trace does not establish locked-screen GPS health.

The iPhone serializes complete BLE/SPP frame writes, but a window of two still lets the Band receive the next application message while its preceding asynchronous interconnect ACK send can be pending. The test doubles simulate successful ACK delivery without modeling firmware outbound backpressure. Xiaomi's interconnect send API exposes asynchronous success/failure callbacks; the RPK does not currently wait for the success callback before sending another ACK.

The trace does not distinguish a lost command from a lost ACK or prove that concurrency caused the loss. Stop-and-wait is a conservative mitigation that removes chunk overlap; confirming the device root cause still requires the hardware acceptance below.

## Decision

The production `RouteCardRenderCoordinator` default returns to `transferWindow = 1`. Each map chunk must receive its application ACK before the next chunk starts. Explicit windows 2 and 4 remain available only for controlled tests and future hardware measurement.

Serial application ACKs may increase transfer time. The five-second target must be measured again on hardware; a successful transfer alone does not meet that target.

The bounded identical-command retry from ADR 0014 remains active for one isolated loss. This change does not alter map dimensions, payload limits, chunk encoding, Xiaomi authentication, BLE/SPP framing, encryption, protobuf fields, application-envelope schemas, RPK code, UI, route rendering, or GPS behavior.

## Independent vectors

For the existing 2,048-byte deterministic raster test, block the first `map.asset.chunk` acknowledgement for 25 ms. With the production default, the observed maximum concurrent chunks must be one and zero later chunks may start while the first acknowledgement is pending.

The encoded command vector remains byte-for-byte identical to ADR 0014. Only its application-level schedule changes from:

```text
chunk[0], chunk[1], ACK(any), ...
```

to:

```text
chunk[0], ACK(0), chunk[1], ACK(1), ...
```

## Hardware acceptance

Automated tests do not prove radio delivery. With iOS 0.5.15 (31) and Band RPK 0.6.11 (26):

1. Start navigation and confirm the first map reaches `band.displayed` without `TRANSFER_TIMEOUT`.
2. Exercise at least ten foreground refreshes and ten locked-screen refreshes; none may end as `MAP_PAYLOAD_TOO_LARGE` or `BAND_DISPLAY_FAILED`.
3. Under normal GPS and radio conditions, confirm each meaningful movement reaches the Band within five seconds.
4. Export diagnostics and confirm successful transfers report `window=1` and a complete ACK count.
5. Interrupt Bluetooth once and confirm terminal reconnect handling still occurs only after the bounded retry is exhausted.
