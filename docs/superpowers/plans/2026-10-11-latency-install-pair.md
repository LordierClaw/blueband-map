# Latency optimization and automatic installation pair

Execution: direct implementation in the existing worktree, no subagents, as explicitly requested. User approval covers the preceding research and this implementation/handoff. Use executing-plans and behavioral tests; do not ask for another approval of the same work.

Goal: make corridor preparation survive camera cancellation, reduce guidance scheduling delay, and provide one automatic full-flow replay with bounded diagnostics and export, packaged as a matched IPA/RPK pair.

Spec: `docs/research/2026-10-11-latency-followup.md`, sections 5–7. Preserve heading-up and the existing Xiaomi framing/crypto. Native rotation and north-up are alternatives requiring separate device validation, not changes in this batch. Do not claim the hardware latency target has passed.

## Tasks and verification

- [ ] Add regressions in `VietmapSnapshotRendererTests.swift` for concurrent/cancelled style preparation and sanitized stage errors; in `AppModelPickerTests.swift` for queued guidance after delayed ACK; in `NavigationReplayTests.swift` for a bounded multi-phase replay. Observe the selected regressions failing once on Apple CI before runtime edits.
- [ ] In `VietmapCPURenderer.swift`, share a bounded style task per key/generation, retain successful source data across camera cancellation, explicitly invalidate on navigation/key ownership changes, prewarm through `VietmapSnapshotRenderer`, and record failed as well as completed stages. Keep existing body/cache/redirect limits. Add conservative geometry culling/projection reuse with a nonempty pixel-equivalence fixture; profile work counts rather than assert simulator speed.
- [ ] In `AppModel.swift`, start CPU preparation alongside snapshot work and replace ACK-plus-one-second guidance scheduling with a bounded latest-only cadence. Reject stale corridor startup before opening the peer. Preserve cancellation, Stop and arrival ownership.
- [ ] In `NavigationReplay.swift` and app controls, offer a roughly five-minute full-flow mode covering cached movement, coverage, turns, zoom, producer drain and automatic Stop/export. Retain route-source mode for focused tests. Use a controllable clock for replay tests, including Stop/restart and late wake.
- [ ] In Band diagnostics, report bounded callback classes and oldest outstanding sample age without keeping unbounded IDs or changing transport flow control. Add harness regression before the change. Optional diagnostic fields get independent vectors and an ADR; preserve existing message bytes when diagnostics are not requested.
- [ ] Consolidate automatic Linux suite ownership; leave specialized duplicate workflows manual. Add a focused iOS diagnostic mode that does not package a release. Docs-only pushes retain lightweight checks without rebuilding RPK. No repeated full CI runs on unchanged code.
- [ ] Self-review cancellation/key switches, probe timing, trace privacy, full-flow termination and image bounds. Bump both versions, run final `make test`, Apple tests/build and `git diff --check`; inspect downloaded IPA/RPK and package hashes plus Vietnamese installation/test/export instructions.

## Risk cases to pin

1. Cancelling one camera must not cancel the shared source fetch needed by its successor.
2. A changed key or Stop must reject old results and stop owned background work.
3. A delayed ACK must not add another unconditional second or let an old scene overwrite arrival.
4. Full-flow completion and Stop must export without waiting forever for Band callbacks.
5. Diagnostics must remain bounded and must not expose provider URLs, credentials or raw coordinates beyond the existing private trace contract.

## Execution ledger

- Initial state: source f274685, docs 9c6582a; only prior research/AGENTS edits present. Windows has no Apple compiler. Ruling: one selected failing-test Apple run, then one final Apple/Linux verification checkpoint; no per-fix full builds. If a real failure requires repair, rerun only affected checks until final artifact validation.
- Ruling: defer native view rotation and HTTP session pooling. First remove cancellation-driven source refetches and measure sanitized stage failures; preserve the established transport security behavior.
