# Automatic navigation smoke implementation plan

**Goal:** Repair duplicate Band completion traffic and supply a bounded automatic
GPS-to-Band smoke test with reliable local Stop and prepared export.

**Spec:** ../specs/2026-10-10-automatic-navigation-smoke-design.md

**Execution:** Continue the user's authorized implementation in the existing
isolated worktree. Independent Band callback work and read-only Stop review are
delegated using dispatching-parallel-agents; iOS integration is owned here.

## Global constraints

- Preserve verified Xiaomi bytes; no raw captures or credentials in commits.
- Add failing behavioral tests before implementation changes.
- Canonical commands use make and pinned runtimes, not host-native Node.
- Deterministic tests do not establish hardware support or latency.

## Tasks

- [ ] 1. Reproduce duplicate callbacks, remount and stale ownership; fix Band
  idempotence and verify runtime tests without changing application wire fields.
- [ ] 2. Add a bounded replay trajectory/source with actual fresh timestamps,
  no live GPS mixing, fixed demo route and deterministic cancellation tests.
- [ ] 3. Integrate automatic preflight, route playback, phases, end diagnostics,
  Stop and export preparation through normal AppModel paths. Test old RPK,
  blocked diagnostics, failure, completion and cancellation/late callback races.
- [ ] 4. Expose the automatic test and persistent Stop; make previews passive,
  show observed RPK identity and remove the misleading metadata-only Replay
  choice. Verify iOS behavior and keep real navigation available.
- [ ] 5. Review, run make test and git diff --check plus iOS CI; package the
  matching pair only after verified builds. Document the short one-button run.

## Review focus

- Repeated decode callbacks must not suppress a legitimate remount.
- Cancellation during route/render/probe must not re-enable a stopped run.
- Wrong Band builds must not progress merely because their envelope is valid.
- Timestamp/cadence labels must describe emitted replay, not assumed reception.
- Errors and partial/unfinished sessions remain exportable without a retest.

## Progress

- Investigation: private reports saved outside the repository. Both captured
  sessions used real GPS and RPK31. No stop/end event establishes no successful
  local stop was recorded; it does not establish why the UI action was missed.
- Ruling: existing user authorization covers fixing the measurement workflow
  and implementing the requested automatic test. No new install/test is asked
  of the user before the replacement is concrete and verified.
