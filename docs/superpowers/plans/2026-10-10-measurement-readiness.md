# Measurement Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship one measurement build that captures actionable startup, control/transfer and Band callback evidence without repeated instrumentation installs.

**Architecture:** Extend the bounded schemaVersion 1 trace and existing diagnostics envelopes without changing transport scheduling. Add a separate complete-goal analysis for measurementVersion 2 while preserving legacy gates.

**Tech Stack:** Swift 6.3.3, SwiftUI/CoreBluetooth, Vela API 1, Node 20.19.5, Python standard library, GNU make, public GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-10-measurement-readiness-design.md`

## Global Constraints

- Preserve Xiaomi framing/authentication/encryption/segmentation, chunk sizes/windows, exact-command retries, error-204 recovery, epoch ownership and resource budgets.
- Retain existing 32 MiB/session and three-session recorder limits.
- Case IDs allow only ASCII letters/digits/hyphen/underscore, at most 32 characters.
- Native callback telemetry is passive; diagnostic replies fit 512 bytes.
- Startup, movement, turns and new coverage all have a strict 1000 ms deadline.
- Hardware timing remains unverified until a real device packet is analyzed.

## Review Focus

- A new GPS fix during a slow startup must not hide elapsed time since Start.
- Concurrent retries and late callbacks must not contaminate another request/session/connection.
- Old peers or missing identity/telemetry must stay unknown rather than pass.
- User-visible freeze reports must survive an otherwise fast confirmation trace.
- Full-frame comparison and recording controls must be immutable within the recorded session.

### Task 1: Analyzer readiness and complete-goal gates

**Files:** `tools/perf/report.py`, new `tools/perf/measurement.py`, `tools/perf/test_measurement.py`, `tools/perf/README.md`, `Makefile`.

**Interfaces:** `measurement.analyze_measurement(records, integrity_valid) -> dict`, added result keys `startupGate`, `startup`, `measurementReadiness`, `subsecondGoal`, `commands`, `phases`, `streamResets`, `observations`. Records use existing parsed events with `_line`; no changes to encoded schemaVersion.

- [ ] Add RED CLI tests: startup 999/1000/1200 ms, newer GPS after slow routing, missing/duplicate intent, legacy/mixed/incomplete session, unknown metadata, a visible freeze marker, and request joins across retries/two sessions.
- [ ] Run `make test-perf`; expect behavioral failures for missing complete-goal evidence.
- [ ] Implement pure analysis and integrate reports; keep legacy statistics/exit semantics.
- [ ] Run `make test-perf`; require all old and new cases pass, inspect generated report text.
- [ ] Commit task with recorded RED/GREEN evidence.

### Task 2: Correlated iPhone measurement and controls

**Files:** `PerformanceTrace.swift`, `BandTransport.swift`, `InterconnectSession.swift`, `AppModel.swift`, new `NavigationMeasurement.swift`/`MeasurementControls.swift`, related portable and iOS tests.

**Interfaces:** trace context carries requestID/topic across write tasks; `navigation.intent` uses `sampleUptimeMs`; `measurement.phase` carries one enumerated phase; `measurement.observation` carries `visibleProblem`; `session.start` carries immutable versioned metadata. `AppModel` exposes bounded case/source/mode settings and marker actions.

- [ ] Add RED tests for end-to-end startup marker order, metadata snapshot, unsafe case normalization, immutable mode, full-frame comparison, request/retry write correlation and incoming ACK-wait observation.
- [ ] Publish test-only commit to feature branch and run canonical portable/iOS tests; record intended RED failures before implementation.
- [ ] Implement passive trace and controls; no wire/scheduling changes. Preserve recorder ownership/retention.
- [ ] Run canonical tests in CI; require GREEN and inspect any Apple-only failures.
- [ ] Commit task with recorded RED/GREEN evidence.

### Task 3: Native Band callback diagnostics

**Files:** `apps/band/src/pages/index/index.ux`, `apps/band/test/envelope-page.test.mjs`, `docs/adr/0021-measurement-readiness.md`, iOS diagnostics consumer/tests.

**Interfaces:** `diagnostics.get` accepts optional `transport:true`; reply body has request/rpk/versionName and bounded `transport` numeric summary with callback durations nullable. Existing resource/perf response remains unchanged when absent.

- [ ] Add actual-page RED tests for asynchronous success/failure, 204 preserving state, duplicate callbacks, late connection callbacks, no callback, clock regression and literal max-size vectors.
- [ ] Run `make test-rpk` in CI and verify intended RED results.
- [ ] Implement passive counters and correlated iOS intake/on-demand capture with bounded request lifetime.
- [ ] Run RPK/portable/iOS suites; verify generated firmware-safe bundle and unchanged old vectors.
- [ ] Commit task with recorded RED/GREEN evidence.

### Task 4: Device packet, release and review

**Files:** manual test guide, performance README, version metadata/tests, handoff tooling only if needed, CI full-test gate.

**Interfaces:** one candidate pair identified by source SHA/app version/RPK version and artifact hashes; one folder per case with original export/video/notes and optional GPS sidecar. No output is represented as hardware acceptance.

- [ ] Write a short staged runbook, evidence manifest example and decision table that identifies missing evidence before a long run.
- [ ] Bump matching app/RPK metadata and any contract fixtures; run `make test`, `make lint`, `git diff --check`, Apple CI and RPK packaging.
- [ ] Dispatch one fresh whole-branch review, fix important findings with RED/GREEN tests.
- [ ] Download and inspect exact successful artifacts, create handoff with SHA256SUMS, report what still requires hardware.

## Execution record

User authorized executing the previously proposed direction. Execute inline in `codex/map-diagnostics`; use one independent final reviewer. The original workspace's research remains untouched. Decisions and test outputs are kept in the plan-scoped `.superpowers` ledger. Windows lacks Docker/WSL; do not install a system hypervisor or use host Node to pretend equivalence. CI supplies the canonical Linux/Apple gates.
