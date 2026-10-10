# Navigation trace reports

```sh
make perf-report RUN=/absolute/path/to/run
make perf-report RUN=/absolute/path/to/run SESSION=session-id-from-report
make test-perf
```

## Checking a collection before leaving the test site

Copy `tools/perf/packet.example.json` to `packet.json` in the parent of the case
folders, then run `make perf-packet PACKET=/absolute/path/to/collection`. Each
declared direct child folder holds `navigation.jsonl` and `run.json` from the
measurement runbook. The example targets measurement candidate `0947f7b`, iOS
0.5.24 (40), RPK 0.6.19 (34); change expected identities deliberately for another
candidate. Unknown manifest fields are rejected to catch misspelled requirements.

Only listed cases are read. The tool selects a session only when its trace case
ID matches uniquely. For repeated case IDs, add `"sessionId": "exact-export-id"`
to that case in `packet.json`; available IDs are listed in the report. Never
rename an actual case or alter evidence just to satisfy the checker.

Outputs are `packet-report.md` and `packet-summary.json` in the collection root.
Source captures and existing per-case reports are preserved. `READY_FOR_ANALYSIS`
means the declared capture checks have enough evidence, including valid slow or
failed observations; it does **not** mean latency passed. `NEEDS_ATTENTION` lists
missing/ambiguous data, version/source/mode/GPS mismatches, incomplete telemetry,
or required phases/app states without confirmed observations. Correct file/session
selection and metadata first; this status does not automatically require a retest.
Each case retains the original analyzer gates, including observed failures.

Hardware acceptance stays UNVERIFIED. Source SHA is only a sidecar declaration;
the trace does not attest to the binary hash. Cold/warm conditions, actual turns,
video and native RAM still need human review. The report checks only declared
cases, not every possible scenario. Exit 0 means analysis completed (including
NEEDS_ATTENTION); malformed configuration, unsafe output aliases or I/O failure
return 2. Windows uses the same `PYTHON=...` override as other perf targets.

Python standard library only. The analyzer reads `navigation.jsonl` and writes
`report.md`, `summary.json`, and `timeline.csv` in the run folder. Those three
names are reserved outputs and replaced on subsequent runs. Input aliases and
output symlinks are rejected. Exit code 0 means analysis completed, including
FAIL/INCONCLUSIVE results; unreadable input, unknown session selectors, or
unwritable outputs return 2.

The app may export its last three retained sessions. The first command lists
them in the report; use `SESSION=...` (CLI `--session ID`) to analyze the
session matching the intended test case. Without selection, multiple sessions
are marked mixed and cannot yield a clean single-case PASS. With selection,
statistics and timeline use that session, while `availableSessions` preserves
the original session list and `selectedSession` identifies the scope.
Unassignable malformed lines still prevent a clean pass. Output filenames are
reused, so preserve a report before analyzing a different session if needed.

Optional `run.json` and `*.run.json` metadata are preserved in the summary.
`replay.csv` and `replay.gpx` point counts describe scheduled positions only.
Notes and videos are listed for separate human review; their contents are not
interpreted or treated as verified physical display evidence.

## Trace contract

Every JSONL object has `schemaVersion: 1`, a nonempty `sessionId`, contiguous
integer `eventSeq` starting at 0, nonnegative `monotonicMs`, `source` (`ios` or
`band`), `event`, and a `metrics` object containing numbers, strings, booleans,
or null. Optional correlation fields are `fixId`, `scene`, `epoch`, `viewSeq`,
and `requestId`. Record `monotonicMs` always uses the iPhone session clock,
including events received from Band. Band-local durations stay inside metrics.
Concatenated sessions reset their own sequence and clock independently.

Required evidence for a complete session:

- `session.start`: `metrics.build`, `metrics.wallUTC`.
- `gps.fix`: unique `fixId`, boolean `accepted`, numeric `gpsInputAgeMs`.
  `accuracyM`, `speedMps`, and other fields are retained in the timeline.
- `map.confirmed`: an accepted `fixId`, `scene`, numeric `fixToConfirmMs` and
  `appToConfirmMs`, boolean `clockValid`, boolean `initial`, `appState`, and
  `mode` (`full` or `corridor`). Corridor also needs `epoch` and integer
  `viewSeq` increasing within that scene/epoch. The active corridor scene must
  have a preceding full-frame confirmation or matching `map.stream.open`.
  Full frames use distinct scenes.
  First `frameGapMs` may be null; subsequent frames need a numeric gap.
- `session.end`: `metrics.completed: true` and `metrics.reason`.
- Final `trace.status`: `droppedEvents: 0`, `truncated: false`,
  `writeFailed: false`. Live exports remain inconclusive until session end.

The analyzer checks confirmation intervals against captured iPhone
`metrics.sampleUptimeMs` when both records provide it, otherwise the event
clock, and GPS input age with 5 ms tolerance for logging/rounding. A disagreement makes
the evidence inconclusive rather than asserting a slow frame. The producer's
`clockValid: false` also prevents a clean pass.

`band.telemetry` records may contain partial metrics. The resource gate needs
valid `files`, `nodes`, and `pendingDeletes` observations in every session.
Limits cover corridor cells: 30 steady files, 31 with identified
in-flight/retiring activity, and 24 mounted cell nodes. Pending deletes are
reported without a cap because reset may retire multiple cells/full frames.
Cell size is checked against 8192 bytes when
`cellBytes` is present, or `encodedBytes` in a `map.cell.*` event. Missing cell
size measurements are shown as unknown. A resource PASS covers observed
counters only; it does not infer continuous bounds between samples.
`nativeMemory: null` or an absent numeric sample leaves native RAM UNVERIFIED.

## Interpreting results

Measurement contract 2 adds three gates without changing legacy `overall`:

- `startupGate`: `navigation.intent.metrics.sampleUptimeMs` to the first
  confirmed frame on the same iPhone monotonic clock, strictly below 1000 ms.
  GPS acquisition, routing, rendering and transfer are all included.
  The uptime interval is cross-checked against recorder elapsed time plus
  `intentAdmissionDelayMs` (Start capture before recorder admission), with 5 ms
  tolerance. Missing/conflicting anchors or incomplete/mixed sessions are
  inconclusive even if the provisional startup value is slow.
- `measurementReadiness`: known app/OS/model/firmware, case ID, declared GPS
  source (`device`/`replay`), map mode (`automatic`/`full`), RPK identity and
  native callback diagnostics. Missing/old capabilities remain inconclusive.
- `subsecondGoal`: startup, normal navigation/resource gates and confirmations
  in marked `cached`, `coverage`, `turn` phases. A visible-problem marker fails
  this gate and requires video review even if software confirmations are fast.

Phase labels are operator annotations; they do not independently prove that a
physical turn occurred. A PASS covers this session's observations, not all cases.
Confirmations inherit the phase of their accepted GPS fix, so an old in-flight
frame cannot satisfy a newly selected turn or coverage phase.
Use the [measurement runbook](../../docs/testing/measurement-runbook.md) to
collect cold/warm, locked-phone and recovery cases in the same installation.

`summary.json.commands` joins `ble.command`, `ble.write`, retries and ACKs by
session/request, retaining events and line numbers. `attemptedBytes` counts
physical write calls attempted, including calls that fail, not radio delivery.
`nativeWriteCount` is the number of link calls; `queueDepth` counts frames ahead
when enqueued. Uncorrelated SPP ACKs retain wire sequence and frame kind in the
timeline. `ble.receive.transport` is SPP-ACK wait; `ble.receive` is application
ACK wait before dispatch. Neither is remote receive latency.

Band callback counters are cumulative over a page lifetime and sampled before
the probe's own reply/ACK. `pending` is outstanding, `abandoned` means lifecycle
invalidated the callback, and `saturated` invalidates exact counter arithmetic.
Callbacks do not establish peer ACK or display completion. No callback is
unknown duration. Compare counters only across snapshots of the same page.

On Windows with a Python executable available, use
`make test-perf PYTHON=C:/Python313/python.exe`. The symlink protection regression
requires symlink permission; canonical Linux CI runs the entire suite unchanged.

Timing statistics use exact nearest-rank p50/p95/p99/max and count samples
greater than or equal to 1000 ms. The normal-navigation latency target is
strictly below 1000 ms. Initial startup is reported separately and does not
fail that gate. Initial, subsequent, full, corridor, and app-state groups are
reported separately; all-sample statistics still retain startup values.
Accepted fixes stay in the denominator when pending, superseded, or coalesced.
The CSV associates a confirmed-frame failure with upstream rows sharing its
session/fix identity, while preserving every input line and its diagnostics.

A valid observed breach is FAIL, even when other evidence is incomplete.
Missing confirmations, malformed/unsupported records, sequence gaps, dropped
events, stale correlations, incomplete sessions, or malformed supplied
sidecars prevent a clean PASS. `.invalid` evidence events are inconclusive;
ordinary rejected GPS fixes remain recorded outside the accepted denominator.
Frame cadence alone does not fail the gate: 1 Hz GPS input with 100 ms
responses passes even when successive confirmation gaps are 1000 ms.
A long confirmation gap fails only when an accepted, not-already-confirmed
fix has actually exceeded its source-timestamp deadline (input age plus
time to the later confirmation is at least 1000 ms). Intervals without
timely GPS input and uncovered tails are INCONCLUSIVE.

`summary.json` includes all numeric per-event metrics as stage statistics,
resource observations, failures, diagnostics, run metadata, and per-fix state.
The report never equates app-received frame confirmation with physical pixels,
or file/node counts with RAM. Hardware/video acceptance remains independent.
