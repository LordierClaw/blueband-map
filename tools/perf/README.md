# Navigation trace reports

```sh
make perf-report RUN=/absolute/path/to/run
make perf-report RUN=/absolute/path/to/run SESSION=session-id-from-report
make test-perf
```

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
