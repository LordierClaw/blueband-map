# Latency optimization and automatic installation pair

Execution: direct implementation in the existing worktree, no subagents, as explicitly requested. User approval covers the preceding research and this implementation/handoff. Use executing-plans and behavioral tests; do not ask for another approval of the same work.

Goal: make corridor preparation survive camera cancellation, reduce guidance scheduling delay, and provide one automatic full-flow replay with bounded diagnostics and export, packaged as a matched IPA/RPK pair.

Spec: `docs/research/2026-10-11-latency-followup.md`, sections 5–7. Preserve heading-up and the existing Xiaomi framing/crypto. Native rotation and north-up are alternatives requiring separate device validation, not changes in this batch. Do not claim the hardware latency target has passed.

## Tasks and verification

- [x] Add regressions in `VietmapSnapshotRendererTests.swift` for concurrent/cancelled style preparation and sanitized stage errors; in `AppModelPickerTests.swift` for queued guidance after delayed ACK; in `NavigationReplayTests.swift` for a bounded multi-phase replay. Observe the selected regressions failing once on Apple CI before runtime edits.
- [x] In `VietmapCPURenderer.swift`, share a bounded style task per key/generation, retain successful source data across camera cancellation, explicitly invalidate on navigation/key ownership changes, prewarm through `VietmapSnapshotRenderer`, and record failed as well as completed stages. Keep existing body/cache/redirect limits. Add conservative geometry culling/projection reuse with a nonempty pixel-equivalence fixture; profile work counts rather than assert simulator speed.
- [x] In `AppModel.swift`, start CPU preparation alongside snapshot work and replace ACK-plus-one-second guidance scheduling with a bounded latest-only cadence. Reject stale corridor startup before opening the peer. Preserve cancellation, Stop and arrival ownership.
- [x] In `NavigationReplay.swift` and app controls, offer a roughly five-minute full-flow mode covering cached movement, coverage, turns, zoom, producer drain and automatic Stop/export. Retain route-source mode for focused tests. Use a controllable clock for replay tests, including Stop/restart and late wake.
- [x] In Band diagnostics, report bounded callback classes and oldest outstanding sample age without keeping unbounded IDs or changing transport flow control. Add harness regression before the change. Optional diagnostic fields get independent vectors and an ADR; preserve existing message bytes when diagnostics are not requested.
- [x] Consolidate automatic Linux suite ownership; leave specialized duplicate workflows manual. Add a focused iOS diagnostic mode that does not package a release. Docs-only pushes retain lightweight checks without rebuilding RPK. No repeated full CI runs on unchanged code.
- [x] Self-review cancellation/key switches, probe timing, trace privacy, full-flow termination and image bounds. Bump both versions, run final `make test`, Apple tests/build and `git diff --check`; inspect downloaded IPA/RPK and package hashes plus Vietnamese installation/test/export instructions.

## Risk cases to pin

1. Cancelling one camera must not cancel the shared source fetch needed by its successor.
2. A changed key or Stop must reject old results and stop owned background work.
3. A delayed ACK must not add another unconditional second or let an old scene overwrite arrival.
4. Full-flow completion and Stop must export without waiting forever for Band callbacks.
5. Diagnostics must remain bounded and must not expose provider URLs, credentials or raw coordinates beyond the existing private trace contract.

## Execution ledger

- Initial state: source f274685, docs 9c6582a; only prior research/AGENTS edits present. Windows has no Apple compiler. Ruling: one selected failing-test Apple run, then one final Apple/Linux verification checkpoint; no per-fix full builds. If a real failure requires repair, rerun only affected checks until final artifact validation.
- Ruling: defer native view rotation and HTTP session pooling. First remove cancellation-driven source refetches and measure sanitized stage failures; preserve the established transport security behavior.
- RED evidence: first selected Apple run 38118038698 found a missing test import; corrected in 0f7bb46. Run 38118265568 then compiled and failed all four intended regressions (13 assertions, no unexpected errors, 2.727 seconds test execution). No device package was produced by either focused run.
- Runtime changes prepared directly, with one additional controlled-clock end-to-end Stop/export test, source ownership regression and a rotated nonempty geometry equivalence/work-count fixture. Band runtime: 53 tests passed after final version bump (2.334 seconds).
- Local canonical `make test` attempted: 67 performance-tool tests ran; Windows denied the existing symlink test with WinError 1314. Full Linux verification remains required; this is not recorded as a test pass or suppressed. Final `git diff --check` and matching Linux/Apple artifacts are the next gate.
- Final Apple checkpoint 38119454225 stopped before compilation: macOS Bash 3.2 rejects empty array expansion with nounset in the new test selector. Keep the xcodebuild `test` action in the argument array so full scope is nonempty. Retry only Apple verification/package; reuse the concurrent canonical Linux result and its RPK after confirming Band and shared source trees are unchanged.
- Linux 38119454228 passed 67 performance and 205 Swift tests, but two Band contract regexes still expected the previous version. The RPK itself built and verified successfully, but the failed suite correctly prevented artifact upload. Correct both regexes and the iOS metadata version assertions together; local page-contract and metadata checks now pass. One Linux retry is required for a green canonical run and downloadable RPK; it does not trigger another Apple build.
- Linux retry 38119700756 passed the complete canonical `make test`, lint and secret scan, and uploaded RPK 0.6.22 (37). No further Linux run is needed for the following Apple-only work.
- Apple 38119591506 found an inaccessible memberwise CorridorCell initializer before testing; use the existing public viewport factory instead. Apple 38119729550 then executed all 130 tests: 128 passed, including all four original regressions, rotated geometry/work counts and source-stop ownership. Two export assertions failed: the new fixture read the final trace.status row instead of session.end; an existing rejection test assumed fsync/export completes within two seconds (the actual export completed later with the correct failure reason). Correct assertions only and run those two tests with Release packaging; do not repeat the other 128 passing tests.

- Handoff verified: Apple run 38120150206 passed both corrected export tests (3.335 seconds), then built and inspected the unsigned arm64 IPA. Runtime source is unchanged from the preceding 128 passing Apple tests. Linux run 38119700756 passed canonical make test, lint, secret scan and RPK packaging; exact Band/shared trees match the final source. Local archive verification checked ZIP integrity, manifest/plist versions, arm64 binary, signing state and SHA-256.
- Install pair: E:/code/blueband-map/artifacts/latency-5ee7802. IPA 0.5.27 (43), SHA-256 fbb7be44a7aef9184581d276dffb4defc791f7199427d5e59cc9f93c7e276d5a; RPK 0.6.22 (37), SHA-256 53e55d439976fd0f5d1234eb30e7a8b66e3e5dc4817838cfc8770dbf85766753. Package source SHAs, workflow URLs and hashes are in verification.json beside the pair. Vietnamese full-flow installation/export guide included. No physical Band test performed; sub-second latency and absence of reboot remain unverified.
