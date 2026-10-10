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

- [x] 1. Reproduce duplicate callbacks, remount and stale ownership; fix Band
  idempotence and verify runtime tests without changing application wire fields.
- [x] 2. Add a bounded replay trajectory/source with actual fresh timestamps,
  no live GPS mixing, fixed demo route and deterministic cancellation tests.
- [x] 3. Integrate automatic preflight, route playback, phases, end diagnostics,
  Stop and export preparation through normal AppModel paths. Test old RPK,
  blocked diagnostics, failure, completion and cancellation/late callback races.
- [x] 4. Expose the automatic test and persistent Stop; make previews passive,
  show observed RPK identity and clarify the metadata-only external Replay
  choice. Verify iOS behavior and keep real navigation available.
- [x] 5. Review, run make test and git diff --check plus iOS CI; package the
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
- RED evidence: Band duplicate completion tests failed before containment;
  iOS run 38070096945 compiled and failed the three AppModel and eight replay
  behavioral tests against the scaffold. Two keyed-phase analyzer regressions
  failed before implementation, then all 15 measurement tests passed.
- Independent review identified terminal-fix cancellation, missing/misattributed
  phases, and late scene publication during arrival. The final implementation
  quiesces scene producers before bounded terminal delivery and records ACK
  separately from display evidence. No remaining Critical/Important findings.
- Source 7526cfc: canonical Linux make test passed in run 38071476124
  (67 Python, 205 portable Swift, 61 Band, 19 protocol-lab tests plus scripts).
  All 118 iOS tests passed in run 38071476123, followed by Release arm64 build
  and unsigned IPA inspection. Both artifacts use this exact source commit.
- Handoff: iOS 0.5.25 (41), RPK 0.6.20 (35). Downloaded archive hashes match
  GitHub artifact digests; local checks verify inner IPA hash, both manifests,
  unsigned app identity, and RPK resources against source. Instructions live in
  docs/testing/automatic-navigation-smoke.md. Hardware acceptance remains open.
- Local Windows make test reaches the existing symlink privilege failure
  (WinError 1314); Linux CI supplies the complete canonical verification.
