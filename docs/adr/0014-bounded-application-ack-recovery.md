# ADR 0014: Bounded application ACK recovery

- Status: Accepted
- Date: 2026-09-03
- Amended by: ADR 0015

## Context

An iPhone 0.5.13 hardware trace reached only 4 of 18 application acknowledgements during the first map transfer. The largest successful ACK latency was 421 ms, then the transfer ended after 5,486 ms with `TRANSFER_TIMEOUT`; the following refresh correctly reported `TRANSFER_RECONNECT_REQUIRED`. GPS, route generation, payload admission, and background location remained healthy. The trace cannot distinguish a dropped outbound command from a dropped Band ACK, and reducing payload size or the transfer window cannot recover either case.

The Band already retains successful message IDs and ACKs an exact duplicate without applying its body again.

## Decision

`sendAwaitingAcknowledgement` retransmits the same immutable `BandCommand`, including the same application-envelope ID and bytes, once when no ACK arrives within one second. The retry has a final three-second ACK window. It does not allocate a new ID, re-encode a body, change chunk order, or emit a second logical `sent` event. A matching ACK received while the retry is transmitting completes the delivery immediately and cancels that retry. A duplicate that reaches the Band after the first copy succeeded receives another ACK and has no second side effect. A duplicate received while the first copy is still in flight remains inert; the first copy's eventual ACK can still complete the delivery.

The non-awaited `send` API retains its existing five-second timeout and never retries. A failed retry remains terminal for a map transfer and requires reconnect cleanup.

This changes only the bounded application delivery sequence. Xiaomi authentication, BLE/SPP framing, encryption, protobuf fields, application-envelope schema, payload limits, and encoded command bytes are unchanged.

## Independent vectors

Portable Swift uses this fixed logical envelope:

```json
{"body":{"text":"PING"},"id":"i-test","src":"ios","topic":"system.echo","type":"message","v":1}
```

With no ACK in the first one-second window, the command recorder must contain two equal `BandCommand` values whose `encode()` bytes are identical. This ACK then completes the original waiter:

```json
{"id":"i-test","src":"band","type":"ack","v":1}
```

The independent Band test receives the following chunk twice with ID `chunk-retry`:

```json
{"body":{"asset":"nav-054edec1d0211f62","data":"AAECAw==","offset":0,"run":"run-0123456789abcdef","scene":"scene-0123456789"},"id":"chunk-retry","src":"ios","topic":"map.asset.chunk","type":"message","v":1}
```

Expected: one four-byte file write containing `00 01 02 03`, two ACKs with ID `chunk-retry`, and no transfer reset.

## Hardware acceptance

Automated tests do not prove radio delivery. On an iPhone and Xiaomi Smart Band 10:

1. Install iOS 0.5.14 (30) with Band RPK 0.6.11 (26), connect once, and start navigation.
2. Confirm the initial map reaches `band.displayed`; lock the iPhone and walk or replay GPS for at least five minutes.
3. Confirm map and guidance refresh within five seconds under normal signal and neither `MAP_PAYLOAD_TOO_LARGE` nor `BAND_DISPLAY_FAILED` occurs.
4. Exercise at least ten map refreshes. If one ACK is lost, confirm the same transfer continues instead of immediately ending in `TRANSFER_TIMEOUT`.
5. Interrupt Bluetooth long enough to exhaust both ACK windows and confirm the transfer fails once, requests reconnect, and succeeds only after a clean reconnect.
