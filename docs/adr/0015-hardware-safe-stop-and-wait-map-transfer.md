# ADR 0015: Hardware-safe stop-and-wait map transfer

- Status: Accepted
- Date: 2026-09-04

## Context

iOS 0.5.14 retained a two-message application ACK window and retried one immutable command after a timeout. A new iPhone and Xiaomi Smart Band 10 trace improved from 4/18 to 7/18 acknowledged messages, then still ended after 5,657 ms with `TRANSFER_TIMEOUT`. Route generation, the admitted map payload, GPS, and background location were healthy.

The iPhone serializes complete BLE/SPP frame writes, but a window of two still lets the Band receive the next application message while its preceding asynchronous interconnect ACK send can be pending. The iOS test double returned those ACKs synchronously and therefore did not model this hardware boundary. Xiaomi's interconnect send API exposes asynchronous success/failure callbacks; the RPK does not currently wait for the success callback before sending another ACK.

## Decision

The production `RouteCardRenderCoordinator` default returns to `transferWindow = 1`. Each map chunk must receive its application ACK before the next chunk starts. Explicit windows 2 and 4 remain available only for controlled tests and future hardware measurement.

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
