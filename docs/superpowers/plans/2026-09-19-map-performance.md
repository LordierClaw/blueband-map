# Realtime map measurement implementation

Goal: establish reproducible GPS-to-Band confirmation latency and bounded-resource evidence before replacing the map architecture. The target is strictly below 1,000 ms during normal navigation, including turns/new coverage and a locked iPhone. Startup, disconnected radio and sleeping Band are reported separately. No claim of physical pixel presentation or native RAM measurement follows from an application callback.

## Delivery checklist

- [x] Add a bounded file-backed iPhone trace, typed GPS/frame correlation, monotonic durations, persistent export and explicit data-loss status.
- [x] Observe BLE queue/write, command/ACK/retry, CPU style/tile/cache/encoding and Band write/decode/apply/cleanup boundaries without changing Xiaomi bytes.
- [x] Add optional bounded Band perf v1 replies and a default-off frame label, with independent vectors in ADR 0020.
- [x] Add a standard-library analyzer and `make perf-report RUN=...`; refuse optimistic pass with missing or invalid evidence.
- [x] Extend the existing external GPS playback tool with PREPARE/RUN/FINISHED test sessions, metadata and guaranteed cleanup attempts.
- [x] Supply the step-by-step Vietnamese T01–T07 guide in `docs/manual-tests/2026-09-19-map-performance.md`.
- [ ] Run all Linux checks, iOS simulator/device-build CI and independent review; package the exact test builds.
- [ ] User performs baseline T01–T06, exports traces and selected video; analyze actual bottlenecks.
- [ ] Only after baseline, test bounded cached-image translation/rotation on the real Band; select architecture using latency, coverage, readability and resource evidence.
- [ ] Repeat T01–T07 for the candidate and retain separate automated, release and hardware results.

## Implemented evidence contract

The JSONL journal uses schemaVersion 1, sessionId, eventSeq, monotonicMs, source, event, metrics and optional fixId/scene/epoch/viewSeq/requestId. Journal monotonicMs records admission order on the iPhone. GPS and confirmation sampleUptimeMs records the actual sampling anchor before logger contention; duration validation uses those anchors. GPS input age is measured from CLLocation.timestamp at receipt, never the host GPX schedule. A wall/monotonic disagreement of 100 ms or a future fix invalidates the clock sample. No clock subtraction across devices.

Full-frame confirmations have a unique scene; corridor confirmations also identify epoch/viewSeq. The first confirmation is initial. An ACK is not a displayed frame; the confirmation includes the return path and is not proof of pixel presentation. Legacy map.pipeline prepare/validate aliases are labeled legacy; perf v1 owns the real native callback timings. GPU snapshot internals remain aggregate SDK measurements; CPU provider work has explicit style/tile/cache timing.

The iPhone writer has a maximum of 256 queued records, 32 MiB per session and three retained journals. It syncs once per second and at session end/export. Data loss, file limits and write failures are explicit; a killed process may lose the last flush interval. A trace without a terminal session record is incomplete. File protection permits continued writes after the first unlock. Export concatenates the retained journals and their status records; individual sessions remain distinguishable. T04 exports at every Stop before retention removes old sessions.

Band perf fields are optional and range checked. Partial timings are not silently replaced with zero. Resource counters describe cell files/nodes, including pending replacements; native memory remains unavailable. Extra telemetry fields are shed before exceeding the unchanged 512-byte envelope. No chunk logging or new periodic BLE polling is added.

## Verification and decision gate

Run `make test`, `make lint`, `make test-gps-replay` and `git diff --check`. iOS CI must typecheck and exercise the AppModel integration, export the unsigned arm64 IPA, and remain distinct from hardware acceptance. The release pair is iOS 0.5.23 (39), Band 0.6.18 (33).

The analyzer writes report.md, summary.json and timeline.csv beside the input. Its confirmation-latency gate, coverage gap gate and observed counter gate are separate; native memory and physical pixels remain unverified without additional evidence. No-result, corrupt, dropped or interrupted traces cannot become successful measurements. Fixture hash, route hash, build and test configuration must agree before comparisons; host CSV/GPX remains scheduled evidence.

Do not increase the 30-cell-file/24-cell-node bounds, transmit window or payload size merely to improve benchmark numbers. Start with measured baseline and preserve old error-204, ACK, stale-callback, decode-cycle and starvation regressions. A rendering rewrite and a subsecond hardware claim remain gated by device evidence.

BLE records retain operationStartedUptime (phone monotonic seconds) across retries; an operation begun before the current navigation session cannot write into that session. ble.write reports attempted and outcome; a cancelled/closed operation without a native write has writeMs:null. CPU telemetry registration does not block GPS startup. Mixed-session exports require an explicit SESSION selection for a single-case result.
