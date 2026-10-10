# Measurement readiness for subsecond navigation

## Intent and scope

The user authorized the direction in `docs/research/2026-10-10-subsecond-map-streaming.md` and asked for thorough measurements that minimize repeat device tests and reinstallations. Target device context is iOS 27 and unchanged Band 10 firmware. Startup, movement, turns and new coverage all have a strict 1000 ms deadline. Hardware timing remains unverified.

This first implementation delivers the measurement build and analyzer needed to choose the next optimization. Transport scheduling, proprietary Xiaomi bytes and production rendering stay unchanged so it can establish a baseline. It adds a selectable full-frame comparison within the same installed build. The later scheduling/prefetch/rotation changes require the baseline; they are not silently bundled into it.

## Evidence to collect in one install

- Versioned measurement contract `measurementVersion:2`, app build, OS version, device model class (no unique device ID), Band firmware and correlated RPK version/perf capability.
- User-supplied bounded test case ID, GPS source (unknown/device/replay), map mode (automatic/full), captured at Start and immutable for the session.
- A monotonic `navigation.intent` marker for the accepted Start action, before navigation work. First valid `map.confirmed` is measured from this anchor. Prerequisite rejection is recorded with a terminal reason if recording is enabled; no fake successful startup.
- Phase markers for startup/cached/coverage/turn/recovery and a single user action to mark a visible problem. Fixed labels only; no arbitrary log text or coordinates added.
- Per-command BLE correlation from application command through physical SPP write and retry: request ID, topic, frame kind, queue depth, native write count and exact attempted byte count. Incoming application dispatch reports time spent sending its ACK without logging content.
- Corridor view requests include fix/epoch/sequence, cache missing count and pixel offset (not GPS). Cell begin/end/prepare/sent events retain cell identity and measured timings. Full-frame pipeline keeps current stage measurements.
- Native Band send counters: attempted/succeeded/failed/pending/peakPending/timeouts204 and latest/max completed callback duration. Completion/failure callbacks count once and must belong to the live connection epoch. On-demand diagnostics use a bounded correlated request and do not add periodic traffic or alter send scheduling.
- Retain existing 32 MiB/session and three-session recorder limits. Export after each Stop, with visible case/session identification and an evidence checklist; do not increase retained memory just to avoid exports. Preserve crash/incomplete evidence.

## Analysis contract

Keep schemaVersion 1 input compatible. Existing `overall` and normal-navigation gates remain interpretable for old exports. Add `startupGate`, `startup` measurements, `measurementReadiness` and `subsecondGoal` gates with explicit scope. The new goal requires normal-navigation gates plus startup and evidence readiness; physical pixel and native memory status remain independent and UNVERIFIED without external evidence.

Startup measures accepted intent to the first trustworthy confirmed frame. >=1000 ms is FAIL, missing/duplicate intent, missing first confirmation, conflicting clocks, corrupted/unfinished trace or missing measurement contract is INCONCLUSIVE. Fast latest GPS after a long route request cannot mask slow startup. Old traces remain analyzable but cannot pass the new complete goal.

Readiness requires known app/OS/model/Band/RPK identities, nonempty case ID, declared GPS source, declared map mode and no integrity loss. A user-marked visible problem is reported as a failure observation, never ignored because callback latency passes. Separate observer/native send availability from timing measurements; no callback means unknown, not zero duration.

Per-command summaries join only within a session and request ID, retaining all retries and failed/cancelled attempts. Show raw stage observations and incomplete joins; do not infer one root cause from the largest uncorrelated percentile. Report phase groups, stream-reset reasons, frame failures and trace completeness with evidence line numbers. Session selection continues to reject an unknown ID; mixed sessions cannot produce a single-case PASS.

## Compatibility and safety

Preserve Xiaomi framing/authentication/encryption/segmentation, chunk sizes/windows, exact-command retries, error-204 recovery, epoch ownership and resource budgets. Native callback telemetry is passive. The optional diagnostics transport body fits 512 bytes; it does not replace normal application ACKs/results. Document independent literal vectors in ADR 0021 and test the actual RPK page. Old peers remain explicitly unobservable for added fields.

No secrets, raw payloads, routes, device UUIDs or arbitrary error strings are added. Case IDs allow only ASCII letters/digits/hyphen/underscore, at most 32 characters. UI remains Vietnamese, with small extracted views to avoid the previous SwiftUI type-checker failure. Comparison mode is locked during navigation and always shown in exports.

## Verification and release

Write behavioral regression tests before implementation and observe RED. Run Python analyzer tests locally through GNU make with a selectable Python executable; pinned Docker and Apple-only tests run through existing CI on the isolated feature branch. Add a CI `make test` gate covering all portable suites. Review the whole change with one fresh reviewer before packaging.

Deliver one matching unsigned IPA/RPK pair, source SHA and SHA256SUMS only after Apple CI, actual RPK build and portable suites pass. Package a short Vietnamese runbook and a manifest/checklist template. A local build limit or missing artifact is a named incomplete step, never a release claim. No merge to main or device installation is implied.

Minimum device packet: one short foreground run containing labeled cached/coverage/turn phases, one locked-phone run, cold and warm Start attempts, and one sleep/wake/recovery run. Run a long-duration test only after short-run evidence is complete. Export each Stop before a fourth session can retire the oldest. Physical observations/video and GPS replay schedule remain distinct from device acknowledgements.
