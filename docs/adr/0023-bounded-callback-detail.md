# 0023 Optional bounded native callback detail

Status: implemented for hardware investigation, hardware acceptance pending.

Keep Xiaomi BLE/SPP framing, encryption, retransmission and existing envelope bodies unchanged. A `diagnostics.get` message may additionally request `callbacks:true` alongside `transport:true`. Only that request causes an additional `diagnostics.report` before the original transport report and ACK, with the same `request` token. Existing peers and ordinary requests keep their original behavior.

`callbacks.v=1`; `ack` and `message` each contain exactly five cumulative counters: attempted, succeeded, failed, pending, abandoned. Without saturation, attempted equals the sum of the other four. Exactly one completion counts per send. A completion from a retired lifecycle increments `late`, a repeated completion increments `duplicate`. Counters saturate at 2147483647 and set `saturated`.

`sample` contains retained pending timestamps count (0–16), oldest retained sample age in milliseconds (null if no sample or invalid clock; capped at 600000), and cumulative sends omitted when all sixteen sample slots were occupied. It is a finite sample, not the native queue or native RAM. No payloads, coordinates, provider keys or message IDs are retained in this sample. Lifecycle reset abandons pending counts and clears sample timestamps. No serialization, retry or flow-control change is introduced.

Independent literal vectors live in `apps/band/test/fixtures/callback-diagnostics.json` (maximum-width reply) and below (request). The page harness checks exact serialization and the existing 512-byte reply budget; the iOS validator rejects wrong shape, non-finite numbers and unsaturated accounting contradictions.

```json
{"v":1,"id":"probe-callbacks","src":"ios","type":"message","topic":"diagnostics.get","body":{"request":"perf-0123456789ab-t","transport":true,"callbacks":true}}
```

Hardware cases: compare per-class counts against phone-received replies; observe a 10-second producer drain; test Stop/reopen and late callbacks; confirm ten-second diagnostic sampling does not stall map updates. A successful callback is not a display confirmation and a missing callback is not proof that bytes failed to arrive. No host test establishes firmware memory reclamation or a reboot fix.
