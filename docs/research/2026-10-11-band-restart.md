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

Checked Xiaomi's diagnostic documentation on 2026-10-11: the
[heap snapshot workflow](https://iot.mi.com/vela/quickapp/en/tools/debug/memory.html)
requires suitable firmware for a device that uses low-level capabilities. The
[real-device debugging guide](https://iot.mi.com/vela/quickapp/zh/tools/devicedebug/start.html)
currently lists Watch S4 and designated partner firmware; it does not establish
Band 10 support for retrieving heap/kernel logs. Consequently periodic app
diagnostics improve the pre-failure history but must not be advertised as a
firmware crash dump or native RAM measurement. This handoff does not require a
firmware change or additional device-debug setup.

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
- [x] Observe failing behavioral tests for automatic health and disconnect reason:
  iOS run 38074647212 at d9bba385d1b681da4bed1f77c35be6bc8cb0efa7 ran 120 tests;
  the two new tests produced four expected failures. The other 118 passed.
- [x] Observe failing behavioral tests for full-frame mounted-node ownership:
  50 passed / 4 failed before the fix; independent review exposed one additional
  old-page deletion race (54 passed / 1 failed), then all 56 runtime tests passed.
  The page now retains the decoded image node across publication. Retirement
  waits for DOM removal; a destroyed page cannot delete a successor's reused URI.
- [x] Implement and verify scoped changes; review late callbacks/cancellation.
  Run 38076003917 at f974fe3 reproduced rejected arrival/movement remaining
  active with the wrong terminal state before the delivery fix. The final
  handler excludes stale owners and cancellation and exports the exact failure
  reason. Independent review found no remaining Critical/Important issues.
- [x] Run `make test`, iOS simulator tests, package verification and `git diff --check`.
  Final code: `f274685b094a04a8b10f30327e67da7627040d34`.
  [Canonical Linux run](https://github.com/LordierClaw/blueband-map/actions/runs/38076651028)
  passed 67 Python, 205 portable Swift, 67 Band and 19 protocol-lab tests, plus
  the repository's shell/metadata/runtime checks and package verification.
  [iOS run](https://github.com/LordierClaw/blueband-map/actions/runs/38076651043)
  passed all 122 simulator tests and built/verified the unsigned arm64 IPA.
  Downloaded ZIP digests matched GitHub; local `make` artifact inspection
  confirmed iOS 0.5.26 (42) and RPK 0.6.21 (36).
  Local Windows `make test` hits the existing symlink privilege limitation;
  the complete test result above comes from canonical Linux CI.
- [ ] Explain intermittent simulator export failures: run 38076003917 also had
  missing prepared exports in four other tests. Final run passed these with
  unchanged deadlines and recorder implementation. Extra failure-only test
  diagnostics are retained; this is not a claimed storage fix. Existing Swift
  6 delegate-isolation warnings also remain outside this change.
- [ ] Hardware acceptance: the same stationary automatic route, periodic samples,
  same-node frame replacements and arrival/export; kernel reboot cause and
  physical pixel latency remain separate unverified observations.
