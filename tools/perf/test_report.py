import csv
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPORT = Path(__file__).with_name("report.py")


def record(event, at, metrics=None, **correlation):
    return dict(event=event, monotonicMs=at, metrics=metrics or {}, **correlation)


def trace(session="s1", latency=350, followup_latency=300):
    records = [
        record("session.start", 0, {"build": "test-1", "wallUTC": "2026-09-19T00:00:00Z"}),
        record("gps.fix", 100, {"gpsInputAgeMs": 100, "accuracyM": 5, "accepted": True, "speedMps": 4}, fixId="f1"),
        record("map.confirmed", latency, {"fixToConfirmMs": latency, "appToConfirmMs": latency - 100,
               "frameGapMs": 0, "mode": "full", "clockValid": True, "initial": True, "appState": "active"},
               fixId="f1", scene="a", epoch=1, viewSeq=1),
        record("gps.fix", latency + 250, {"gpsInputAgeMs": 50, "accuracyM": 6, "accepted": True, "speedMps": 4}, fixId="f2"),
        record("map.confirmed", latency + 500, {"fixToConfirmMs": 300, "appToConfirmMs": 250,
               "frameGapMs": 500, "mode": "corridor", "clockValid": True, "initial": False, "appState": "background"},
               fixId="f2", scene="a", epoch=1, viewSeq=2),
        record("band.telemetry", latency + 510, {"writeMs": 12, "decodeMs": 5, "applyMs": 3,
               "cleanupMs": 2, "files": 20, "nodes": 20, "pendingDeletes": 0, "nativeMemory": None, "cellBytes": 6000}),
        record("session.end", latency + 600, {"reason": "test complete", "completed": True}),
        record("trace.status", latency + 601, {"droppedEvents": 0, "truncated": False, "writeFailed": False}),
    ]
    for item in records[4:]:
        item["monotonicMs"] += followup_latency - 300
    records[4]["metrics"].update(fixToConfirmMs=followup_latency, appToConfirmMs=followup_latency - 50,
                                 frameGapMs=followup_latency + 200)
    return stamp(records, session)


def stamp(records, session="s1"):
    for seq, item in enumerate(records):
        item.update(schemaVersion=1, sessionId=session, eventSeq=seq, source="band" if item["event"] == "band.telemetry" else "ios")
    return records


class ReportTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.run = Path(self.temp.name)

    def analyze(self, records, suffix="", session=None):
        self.run.joinpath("navigation.jsonl").write_text(
            "".join(json.dumps(item) + "\n" for item in records) + suffix, encoding="utf-8")
        command = [sys.executable, str(REPORT), str(self.run)]
        if session is not None:
            command.extend(["--session", session])
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(self.run.joinpath("report.md").is_file())
        with self.run.joinpath("timeline.csv").open(newline="", encoding="utf-8") as source:
            self.timeline = list(csv.DictReader(source))
        return json.loads(self.run.joinpath("summary.json").read_text())

    def test_complete_trace_has_exact_statistics_and_separate_evidence(self):
        summary = self.analyze(trace())
        self.assertEqual(summary["latencyGate"]["status"], "PASS")
        self.assertEqual(summary["resourceGate"]["status"], "PASS")
        self.assertEqual(summary["frameGapGate"]["status"], "PASS")
        self.assertEqual(summary["physicalPixelLatency"], "UNVERIFIED")
        self.assertEqual(summary["nativeMemoryEvidence"], "UNVERIFIED")
        self.assertEqual(summary["metrics"]["fixToConfirmMs"],
                         {"count": 2, "p50": 300, "p95": 350, "p99": 350, "max": 350, "atLeast1000": 0})
        self.assertEqual(summary["groups"]["initial"]["metrics"]["fixToConfirmMs"]["count"], 1)
        self.assertEqual(summary["groups"]["corridor"]["metrics"]["fixToConfirmMs"]["max"], 300)
        self.assertIn("appState:background", summary["groups"])
        self.assertEqual(len(self.timeline), 8)

    def test_threshold_is_strict_and_failures_keep_frame_correlation(self):
        self.assertEqual(self.analyze(trace(followup_latency=999))["latencyGate"]["status"], "PASS")
        summary = self.analyze(trace(followup_latency=1000))
        self.assertEqual(summary["latencyGate"]["status"], "FAIL")
        self.assertEqual(summary["metrics"]["fixToConfirmMs"]["atLeast1000"], 1)
        self.assertEqual(summary["failures"][0]["fixId"], "f2")
        self.assertEqual(summary["failures"][0]["scene"], "a")
        self.assertTrue(any(row["failureIds"] for row in self.timeline))

    def test_pending_fix_end_missing_or_trace_loss_cannot_pass(self):
        missing = trace()
        del missing[4]
        cases = [stamp(missing), stamp([r for r in trace() if r["event"] != "session.end"])]
        lost = trace()
        lost[-1]["metrics"]["droppedEvents"] = 2
        cases.append(lost)
        for records in cases:
            with self.subTest(records=records):
                summary = self.analyze(records)
                self.assertEqual(summary["latencyGate"]["status"], "INCONCLUSIVE")
        summary = self.analyze(stamp(missing))
        self.assertEqual(summary["fixes"][1]["status"], "pending")

    def test_superseded_fix_remains_in_denominator(self):
        records = trace()
        records[4] = record("map.superseded", records[4]["monotonicMs"], {}, fixId="f2")
        summary = self.analyze(stamp(records))
        self.assertEqual(summary["latencyGate"]["status"], "INCONCLUSIVE")
        self.assertEqual(summary["fixes"][1]["status"], "superseded")

    def test_malformed_and_unsupported_records_are_diagnostics(self):
        summary = self.analyze(trace(), '{"broken":')
        self.assertEqual(summary["latencyGate"]["status"], "INCONCLUSIVE")
        self.assertIn("malformed", " ".join(d["code"] for d in summary["diagnostics"]))
        records = trace()
        records[3]["schemaVersion"] = 2
        summary = self.analyze(records)
        self.assertEqual(summary["latencyGate"]["status"], "INCONCLUSIVE")
        self.assertIn("unsupported_schema", [d["code"] for d in summary["diagnostics"]])

    def test_invalid_correlation_objects_are_reported_without_crashing(self):
        records = trace()
        records[3]["sessionId"] = {"invalid": True}
        records[3]["fixId"] = [1, 2]
        summary = self.analyze(records)
        self.assertEqual(summary["latencyGate"]["status"], "INCONCLUSIVE")
        self.assertIn("invalid_record", [d["code"] for d in summary["diagnostics"]])

    def test_sessions_reset_sequence_and_clock_independently(self):
        summary = self.analyze(trace("s1") + trace("s2", latency=450))
        self.assertEqual(summary["overall"]["status"], "INCONCLUSIVE")
        self.assertEqual(summary["availableSessions"], ["s1", "s2"])
        self.assertTrue(summary["mixedSessions"])
        self.assertEqual(len(summary["sessions"]), 2)
        self.assertEqual(len(summary["fixes"]), 4)
        self.assertEqual(summary["metrics"]["fixToConfirmMs"]["max"], 450)

    def test_session_selection_filters_observations_and_keeps_export_provenance(self):
        summary = self.analyze(trace("s1", followup_latency=1200) + trace("s2", latency=450), session="s2")
        self.assertEqual(summary["overall"]["status"], "PASS")
        self.assertEqual(summary["availableSessions"], ["s1", "s2"])
        self.assertEqual(summary["selectedSession"], "s2")
        self.assertFalse(summary["mixedSessions"])
        self.assertEqual([item["sessionId"] for item in summary["sessions"]], ["s2"])
        self.assertEqual(len(summary["fixes"]), 2)
        self.assertEqual(summary["metrics"]["fixToConfirmMs"]["max"], 450)
        self.assertEqual({row["sessionId"] for row in self.timeline}, {"s2"})
        report = self.run.joinpath("report.md").read_text()
        self.assertIn("Selected session: `s2`", report)
        self.assertIn("Export sessions: `s1`, `s2`", report)

    def test_session_selection_does_not_hide_unassignable_malformed_lines(self):
        summary = self.analyze(trace("s1") + trace("s2"), '{"incomplete":', session="s2")
        self.assertEqual(summary["overall"]["status"], "INCONCLUSIVE")
        records = trace("s1") + trace("s2")
        invalid = {**records[0], "sessionId": {"unknown": True}}
        summary = self.analyze(records + [invalid], session="s2")
        self.assertEqual(summary["overall"]["status"], "INCONCLUSIVE")

    def test_unknown_session_is_a_cli_error_without_outputs(self):
        self.run.joinpath("navigation.jsonl").write_text("".join(json.dumps(item) + "\n" for item in trace()))
        result = subprocess.run([sys.executable, str(REPORT), str(self.run), "--session", "missing"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("Unknown session", result.stderr)
        self.assertFalse(self.run.joinpath("summary.json").exists())

    def test_duplicate_sequence_clock_jump_and_invalid_clock_block_pass(self):
        cases = []
        for key, value in (("eventSeq", 0), ("monotonicMs", 90)):
            records = trace()
            records[2][key] = value
            cases.append(records)
        records = trace()
        records[2]["metrics"]["clockValid"] = False
        cases.append(records)
        records = trace()
        records[2]["metrics"]["fixToConfirmMs"] = 1
        cases.append(records)
        for records in cases:
            with self.subTest(records=records):
                summary = self.analyze(records)
                self.assertEqual(summary["latencyGate"]["status"], "INCONCLUSIVE")

    def test_band_clock_failure_cannot_pass_resource_evidence(self):
        records = trace()
        records[5]["metrics"]["clockValid"] = False
        summary = self.analyze(records)
        self.assertEqual(summary["resourceGate"]["status"], "INCONCLUSIVE")

    def test_capture_uptime_avoids_false_clock_mismatch_from_log_serialization(self):
        records = trace()
        for item in records[1:5]:
            item["metrics"]["sampleUptimeMs"] = 100000 + item["monotonicMs"]
        records[1]["monotonicMs"] += 20
        records[4]["monotonicMs"] += 8
        summary = self.analyze(records)
        self.assertEqual(summary["latencyGate"]["status"], "PASS")
        self.assertEqual(summary["frameGapGate"]["status"], "PASS")

    def test_stale_correlation_does_not_count_as_fresh_confirmed_sample(self):
        records = trace()
        records.insert(5, {**records[4], "monotonicMs": 855})
        summary = self.analyze(stamp(records))
        self.assertEqual(summary["latencyGate"]["status"], "INCONCLUSIVE")
        self.assertEqual(summary["metrics"]["fixToConfirmMs"]["count"], 2)

    def test_full_frame_uses_scene_only_and_initial_gap_is_null(self):
        records = trace()
        del records[2]["epoch"]
        del records[2]["viewSeq"]
        records[2]["metrics"]["frameGapMs"] = None
        summary = self.analyze(records)
        self.assertEqual(summary["latencyGate"]["status"], "PASS")
        self.assertEqual(summary["metrics"]["frameGapMs"]["count"], 1)

    def test_unknown_corridor_scene_cannot_pass(self):
        records = trace()
        records[4]["scene"] = "not-bootstrapped"
        summary = self.analyze(records)
        self.assertEqual(summary["latencyGate"]["status"], "INCONCLUSIVE")

    def test_explicit_stream_open_can_bootstrap_initial_corridor_frame(self):
        records = trace()
        records[2]["metrics"]["mode"] = "corridor"
        records.insert(1, record("map.stream.open", 50, {}, scene="a", epoch=1))
        summary = self.analyze(stamp(records))
        self.assertEqual(summary["latencyGate"]["status"], "PASS")

    def test_duration_only_telemetry_does_not_require_counters_in_same_event(self):
        records = trace()
        records.insert(6, record("band.telemetry", 875, {"decodeMs": 4}))
        summary = self.analyze(stamp(records))
        self.assertEqual(summary["resourceGate"]["status"], "PASS")

    def test_explicit_stale_confirmation_blocks_a_pass(self):
        records = trace()
        records.insert(5, record("map.stale", 855, {"reason": "old epoch"}, fixId="f1", scene="a", epoch=0))
        summary = self.analyze(stamp(records))
        self.assertEqual(summary["latencyGate"]["status"], "INCONCLUSIVE")

    def test_invalid_telemetry_is_uncertain_but_rejected_gps_is_retained(self):
        records = trace()
        records.insert(6, record("gps.fix", 900, {"accepted": False, "gpsInputAgeMs": 2000,
                                                  "reason": "invalidOrOld"}, fixId="rejected"))
        summary = self.analyze(stamp(records))
        self.assertEqual(summary["latencyGate"]["status"], "PASS")
        self.assertEqual(summary["fixes"][-1]["status"], "rejected")
        records.insert(7, record("band.telemetry.invalid", 910, {"reason": "wrong schema"}))
        summary = self.analyze(stamp(records))
        self.assertEqual(summary["resourceGate"]["status"], "INCONCLUSIVE")
        self.assertEqual(summary["overall"]["status"], "INCONCLUSIVE")

    def test_duplicate_gps_identifier_cannot_hide_replacement_fix(self):
        records = trace()
        records.insert(2, record("gps.fix", 120, {"accepted": True, "gpsInputAgeMs": 100}, fixId="f1"))
        summary = self.analyze(stamp(records))
        self.assertEqual(summary["latencyGate"]["status"], "INCONCLUSIVE")
        self.assertIn("invalid_fix_id", [item["code"] for item in summary["diagnostics"]])

    def test_trace_status_must_be_after_a_completed_session_end(self):
        records = trace()
        records.insert(6, record("trace.status", 900, {"droppedEvents": 0, "truncated": False, "writeFailed": False}))
        summary = self.analyze(stamp(records))
        self.assertEqual(summary["latencyGate"]["status"], "INCONCLUSIVE")

    def test_gps_gap_is_distinguished_from_waiting_for_a_frame(self):
        records = trace()
        for item in records[3:]:
            item["monotonicMs"] += 1500
        records[4]["metrics"]["frameGapMs"] = 2000
        summary = self.analyze(records)
        self.assertEqual(summary["frameGapGate"]["status"], "INCONCLUSIVE")
        self.assertEqual(summary["frameGaps"][0]["classification"], "gps_gap")

    def test_unobserved_tail_does_not_hide_a_long_gap(self):
        records = trace()
        records[-2]["monotonicMs"] += 2000
        records[-1]["monotonicMs"] += 2000
        summary = self.analyze(records)
        self.assertEqual(summary["frameGapGate"]["status"], "INCONCLUSIVE")
        self.assertEqual(summary["frameGaps"][-1]["classification"], "unobserved_tail")

    def test_numeric_resource_counters_cannot_be_fractional(self):
        records = trace()
        records[5]["metrics"]["nodes"] = 0.5
        summary = self.analyze(records)
        self.assertEqual(summary["resourceGate"]["status"], "INCONCLUSIVE")

    def test_failure_is_correlated_to_upstream_fix_row(self):
        summary = self.analyze(trace(followup_latency=1200))
        self.assertEqual(summary["latencyGate"]["status"], "FAIL")
        gps_row = next(row for row in self.timeline if row["event"] == "gps.fix" and row["fixId"] == "f2")
        self.assertIn("1", gps_row["failureIds"].split(";"))

    def test_one_hertz_input_with_fast_responses_is_not_a_cadence_failure(self):
        records = trace()
        records[1]["metrics"]["gpsInputAgeMs"] = 0
        records[2].update(monotonicMs=200)
        records[2]["metrics"].update(fixToConfirmMs=100, appToConfirmMs=100)
        records[3].update(monotonicMs=1100)
        records[3]["metrics"]["gpsInputAgeMs"] = 0
        records[4].update(monotonicMs=1200)
        records[4]["metrics"].update(fixToConfirmMs=100, appToConfirmMs=100, frameGapMs=1000)
        for index, item in enumerate(records[5:]):
            item["monotonicMs"] = 1210 + index
        summary = self.analyze(records)
        self.assertEqual(summary["overall"]["status"], "PASS")
        self.assertEqual(summary["frameGapGate"]["status"], "PASS")
        self.assertEqual(summary["frameGaps"][0]["classification"], "input_cadence")
        self.assertEqual(summary["metrics"]["frameGapMs"]["max"], 1000)

    def test_slow_initial_frame_is_reported_outside_normal_navigation_gate(self):
        summary = self.analyze(trace(latency=5000))
        self.assertEqual(summary["overall"]["status"], "PASS")
        self.assertEqual(summary["latencyGate"]["status"], "PASS")
        self.assertEqual(summary["groups"]["initial"]["metrics"]["fixToConfirmMs"]["max"], 5000)
        self.assertEqual(summary["groups"]["subsequent"]["metrics"]["fixToConfirmMs"]["max"], 300)

    def test_resource_limits_and_missing_telemetry(self):
        summary = self.analyze(stamp([r for r in trace() if r["event"] != "band.telemetry"]))
        self.assertEqual(summary["resourceGate"]["status"], "INCONCLUSIVE")
        for field, value in (("files", 32), ("nodes", 25), ("cellBytes", 8193)):
            records = trace()
            records[5]["metrics"][field] = value
            with self.subTest(field=field):
                self.assertEqual(self.analyze(records)["resourceGate"]["status"], "FAIL")

    def test_cleanup_can_retire_multiple_files_within_retained_file_cap(self):
        records = trace()
        records[5]["metrics"].update(files=31, pendingDeletes=4)
        summary = self.analyze(records)
        self.assertEqual(summary["resourceGate"]["status"], "PASS")
        self.assertEqual(summary["resourceObservations"]["pendingDeletes"]["max"], 4)

    def test_encoded_cell_stage_checks_the_same_resource_limit(self):
        records = trace()
        records.insert(5, record("map.cell.ready", 855, {"encodedBytes": 8193, "prepareMs": 50}))
        summary = self.analyze(stamp(records))
        self.assertEqual(summary["resourceGate"]["status"], "FAIL")
        self.assertEqual(summary["resourceObservations"]["cellBytes"]["max"], 8193)

    def test_report_shows_observed_resources_and_stage_durations(self):
        self.analyze(trace())
        report = self.run.joinpath("report.md").read_text()
        self.assertIn("| nodes | 1 | 20 | 24 |", report)
        self.assertIn("band.telemetry.decodeMs", report)

    def test_optional_sidecar_is_scheduled_evidence_only(self):
        sidecar = {"schemaVersion": 1, "caseId": "C2", "runId": "replay-1",
                   "coordinateEvidence": "scheduled-not-device-ack"}
        self.run.joinpath("replay.run.json").write_text(json.dumps(sidecar))
        self.run.joinpath("replay.csv").write_text("scheduledUtc,latitude,longitude\n2026-09-19T00:00:00Z,1,2\n")
        summary = self.analyze(trace())
        self.assertEqual(summary["runMetadata"]["replay.run.json"], sidecar)
        self.assertEqual(summary["replay"]["scheduledPoints"], 1)
        self.assertEqual(summary["replay"]["deviceAcknowledgement"], "UNVERIFIED")

    def test_present_but_malformed_sidecar_prevents_a_pass(self):
        self.run.joinpath("run.json").write_text('{"schemaVersion":')
        summary = self.analyze(trace())
        self.assertEqual(summary["overall"]["status"], "INCONCLUSIVE")
        self.assertEqual(summary["latencyGate"]["status"], "INCONCLUSIVE")

    def test_unreadable_input_and_output_alias_fail_without_modifying_input(self):
        result = subprocess.run([sys.executable, str(REPORT), str(self.run)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.run.joinpath("navigation.jsonl").write_text("input remains\n")
        self.run.joinpath("summary.json").symlink_to(self.run / "navigation.jsonl")
        result = subprocess.run([sys.executable, str(REPORT), str(self.run)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.run.joinpath("navigation.jsonl").read_text(), "input remains\n")


if __name__ == "__main__":
    unittest.main()
