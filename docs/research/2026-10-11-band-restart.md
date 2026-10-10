# Band reboot during automatic navigation

## Evidence

The user confirmed a Xiaomi boot logo and whole-device restart. The new private
JSONL is retained outside Git, SHA-256
`95b6327c335ed1c23eb11f61948f0d1b467df83f5399fc99d1e3f4b1c2ff83e0`.
Only aggregate measurements are included here; no raw capture or coordinates.

The newest session ran iOS 0.5.25 (41), Band 0.6.20 (35), firmware 3.2.8,
iOS 27.0.1, and the in-app replay. It contains 223 accepted synthetic fixes,
20 full-frame confirmations and no corridor viewport confirmations. Four cell
transfers produced four decode notifications: the previous duplicate callback
storm is absent. Startup confirmation took 5736.9 ms; normal fix-to-confirmation
was approximately 4–6 seconds. Twenty stream resets followed heading/zoom
changes. Every one of 127 viewport replies still lacked 10–18 cells.

The last Band reply was a full-frame result at 225514.7 ms. A stream open,
navigation update and stream close then timed out. The session ended at
230593.9 ms with `stopped`. Existing code uses that same reason for a user Stop
and a disconnect; the trace cannot distinguish them. No rows were dropped,
truncated or lost to a reported write failure.

Only the preflight contains native transport counters (2 pending sends, no
completed callback yet). That early sample is NOT evidence of a callback leak.
Native RAM and firmware reboot cause are absent. Low cell file/node counts do
not measure native memory or account for full-frame images.

## Confirmed software gaps

1. Diagnostics occur only at start and normal finish. A reboot loses the useful
   pre-failure history. An automatic test can continue after command timeouts
   until a disconnect or the 600-second replay deadline.
2. Disconnect records the generic `stopped` reason, hiding the termination source.
3. Full-frame publication waits for the staging image's complete event, then
   assigns the URI to a different visible image node without a complete/error
   handler, removes the decoded staging source and deletes the old fallback.
   The second native load is unobserved. This is an ownership defect; whether
   it caused the device reboot is still unverified.
4. Corridor startup is starved by expensive CPU atlas drawing and camera resets.
   One warm-cache cell preparation took 21.267 seconds; the next same-atlas
   cell took 37.9 ms. Five tile fetches in the entire run took 406–457 ms each.
   Therefore network alone does not explain the slow first cell. Performance
   work must use non-empty geometry fixtures, not only empty tile tests.

## Bounded follow-up within the automatic test design

Preserve the existing Xiaomi framing, crypto, command bodies and retry policy.
Reuse existing resource/native diagnostic requests every 10 seconds while an
automatic run is active. Keep one probe pair in flight and the existing 8-second
deadline. A missing running probe, disconnect or terminal navigation-send failure
must stop local producers and prepare export with its explicit reason, without
waiting for another probe to the failed peer. Late results cannot revive a run.

Publish full frames by promoting the same mounted image that completed decoding.
Keep bounded image ownership through replacement, failure and teardown. Test
delayed and duplicate callbacks separately from native hardware acceptance.

Do not add speculative garbage collection, change firmware, claim OOM/watchdog,
or advertise a subsecond/reboot fix based on deterministic tests. Xiaomi's
[memory guidance](https://iot.mi.com/vela/quickapp/en/guide/best-practice/memory.html)
supports avoiding unnecessary reactive state and image allocations but does not
diagnose this crash. Their [interconnect API](https://iot.mi.com/vela/quickapp/en/features/network/interconnect.html)
documents callbacks, not a native queue/RAM guarantee.

## Separate renderer experiment

Before a CPU optimization, profile a public synthetic MVT fixture with non-empty
roads, polygons, labels and offscreen geometry. Compare 1/2/4 cached tiles, a
second cell from the same atlas, an adjacent atlas and a camera change at zooms
15–17 and headings 0/45/90. In `VietmapCPURenderer`, distinguish tile assembly,
feature projection, Core Graphics strokes, labels, atlas crop/route overlay and
`SnapshotPNGEncoder` quantization. Keep pixel-equivalence and payload limits as
correctness checks; simulator wall time alone is not a regression assertion.
The existing warm-cache fixture has an empty road layer, which cannot explain
the dense-geometry preparation interval seen here. No CPU optimization is being
presented as a fix for Band reboot.

## Verification ledger

- [x] Preserve new raw capture privately and run canonical `make perf-report`.
- [x] Confirm installed pair and actual replay source from trace.
- [ ] Observe failing behavioral tests for automatic health and disconnect reason.
- [ ] Observe failing behavioral tests for full-frame mounted-node ownership.
- [ ] Implement and verify scoped changes; review late callbacks/cancellation.
- [ ] Run `make test`, iOS simulator tests, package verification and `git diff --check`.
- [ ] Hardware acceptance: the same stationary automatic route, periodic samples,
  same-node frame replacements and arrival/export; kernel reboot cause and
  physical pixel latency remain separate unverified observations.
