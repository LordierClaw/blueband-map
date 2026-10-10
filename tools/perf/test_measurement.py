import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from test_report import record, stamp, trace


def measured(startup=999, session="s1"):
    rows = trace(session, latency=startup)
    rows[0]["metrics"].update(measurementVersion=2, osVersion="27.0", deviceModel="iPhone16,1",
                              testCaseID="walk-01", gpsSource="device", mapMode="automatic", firmware="fixture")
    rows.insert(1, record("navigation.intent", 0, {"sampleUptimeMs": 10000}))
    first = next(r for r in rows if r["event"] == "map.confirmed")
    first["metrics"]["sampleUptimeMs"] = 10000 + startup
    # A recent GPS update cannot erase time spent acquiring GPS/routing/bootstrap.
    rows[2]["monotonicMs"] = startup - 100
    first["metrics"].update(fixToConfirmMs=200, appToConfirmMs=100)
    tail = rows[-2]["monotonicMs"] - 1
    rows[-2:-2] = [record("band.identity", tail, {"rpk": 34, "versionName": "0.6.19", "perfVersion": 1}),
                    record("band.transport", tail, {"v": 1, "clockValid": True, "attempted": 12,
                        "succeeded": 12, "failed": 0, "pending": 0, "peakPending": 2,
                        "timeouts204": 0, "abandoned": 0, "saturated": False, "lastCallbackMs": 10, "maxCallbackMs": 20})]
    return stamp(rows, session)


class MeasurementTest(unittest.TestCase):
    def test_untrusted_startup_or_missing_contract_cannot_be_a_timing_failure(self):
        rows = measured(1200)
        next(r for r in rows if r["event"] == "map.confirmed")["fixId"] = "wrong"
        self.assertEqual(self.analyze(rows)["startupGate"]["status"], "INCONCLUSIVE")
        rows = measured()
        del rows[0]["metrics"]["measurementVersion"]
        self.assertEqual(self.analyze(rows)["startupGate"]["status"], "INCONCLUSIVE")

    def test_saturated_or_inconsistent_native_counters_cannot_be_ready(self):
        for changes in ({"saturated": True}, {"attempted": 99}, {"versionName": "unknown"}):
            rows = measured()
            event = "band.identity" if "versionName" in changes else "band.transport"
            next(r for r in rows if r["event"] == event)["metrics"].update(changes)
            self.assertEqual(self.analyze(rows)["measurementReadiness"]["status"], "INCONCLUSIVE")

    def test_all_phases_can_pass_observed_goal_but_malformed_sidecar_cannot(self):
        rows = measured()
        rows.insert(4, record("measurement.phase", 1200, {"phase": "cached"}))
        index = next(i for i, row in enumerate(rows) if row["event"] == "band.telemetry")
        extra = []
        for seq, phase in ((3, "coverage"), (4, "turn")):
            at = 1999 + (seq - 3) * 500
            extra += [record("measurement.phase", at - 300, {"phase": phase}),
                      record("gps.fix", at - 250, {"gpsInputAgeMs": 50, "accepted": True}, fixId=f"f{seq}"),
                      record("map.confirmed", at, {"fixToConfirmMs": 300, "appToConfirmMs": 250,
                          "frameGapMs": 500, "mode": "corridor", "clockValid": True, "initial": False,
                          "appState": "active"}, fixId=f"f{seq}", scene="a", epoch=1, viewSeq=seq)]
        for row in rows[index:]:
            row["monotonicMs"] += 1000
        rows[index:index] = extra
        rows = stamp(rows)
        self.assertEqual(self.analyze(rows)["subsecondGoal"]["status"], "PASS")
        with tempfile.TemporaryDirectory() as folder:
            run = Path(folder)
            (run / "navigation.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows))
            (run / "run.json").write_text("{")
            result = subprocess.run([sys.executable, str(Path(__file__).with_name("report.py")), folder], capture_output=True)
            self.assertEqual(result.returncode, 0)
            summary = json.loads((run / "summary.json").read_text())
            self.assertEqual(summary["subsecondGoal"]["status"], "INCONCLUSIVE")

    def analyze(self, rows, session=None):
        with tempfile.TemporaryDirectory() as folder:
            run = Path(folder)
            (run / "navigation.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows))
            command = [sys.executable, str(Path(__file__).with_name("report.py")), folder]
            if session:
                command += ["--session", session]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.markdown = (run / "report.md").read_text(encoding="utf-8")
            return json.loads((run / "summary.json").read_text())

    def test_startup_uses_intent_not_newest_gps_and_strict_deadline(self):
        for duration, status in ((999, "PASS"), (1000, "FAIL"), (1200, "FAIL")):
            with self.subTest(duration=duration):
                result = self.analyze(measured(duration))
                self.assertEqual(result["startupGate"]["status"], status)
                self.assertEqual(result["startup"][0]["intentToConfirmMs"], duration)
                self.assertEqual(result["latencyGate"]["status"], "PASS")
                self.assertIn("Start to first confirmation", self.markdown)
                if status == "FAIL":
                    self.assertEqual(result["subsecondGoal"]["status"], "FAIL")

    def test_missing_duplicate_intent_and_incomplete_trace_cannot_pass(self):
        missing = [r for r in measured() if r["event"] != "navigation.intent"]
        duplicate = measured()
        duplicate.insert(2, dict(duplicate[1]))
        unfinished = [r for r in measured() if r["event"] not in ("session.end", "trace.status")]
        for rows in (missing, duplicate, unfinished, trace()):
            with self.subTest(rows=rows):
                result = self.analyze(stamp(rows))
                self.assertEqual(result["startupGate"]["status"], "INCONCLUSIVE")
                self.assertEqual(result["subsecondGoal"]["status"], "INCONCLUSIVE")

    def test_metadata_peer_and_phase_evidence_are_required(self):
        rows = measured()
        result = self.analyze(rows)
        self.assertEqual(result["measurementReadiness"]["status"], "PASS")
        self.assertEqual(result["subsecondGoal"]["status"], "INCONCLUSIVE")
        for key in ("osVersion", "deviceModel", "testCaseID", "gpsSource", "mapMode"):
            unknown = measured()
            unknown[0]["metrics"][key] = "unknown"
            self.assertEqual(self.analyze(unknown)["measurementReadiness"]["status"], "INCONCLUSIVE")
        for event in ("band.identity", "band.transport"):
            self.assertEqual(self.analyze(stamp([r for r in rows if r["event"] != event]))
                             ["measurementReadiness"]["status"], "INCONCLUSIVE")

    def test_visible_freeze_is_preserved_even_when_confirmations_are_fast(self):
        rows = measured()
        rows.insert(-2, record("measurement.observation", rows[-2]["monotonicMs"], {"visibleProblem": True}))
        result = self.analyze(stamp(rows))
        self.assertEqual(result["subsecondGoal"]["status"], "FAIL")
        self.assertEqual(len(result["observations"]), 1)

    def test_commands_join_attempts_by_session_and_request_without_inventing_causality(self):
        rows = []
        for session in ("s1", "s2"):
            events = measured(session=session)
            additions = [record("ble.command", 1, {"topic": "map.cell.begin", "bytes": 90}, requestId="same"),
                         record("ble.write", 2, {"queueWaitMs": 1, "writeMs": 2, "nativeWriteCount": 2,
                             "attemptedBytes": 95, "outcome": "ok"}, requestId="same"),
                         record("ble.write", 3, {"queueWaitMs": 2, "writeMs": 3, "nativeWriteCount": 2,
                             "attemptedBytes": 95, "outcome": "ok"}, requestId="same"),
                         record("ble.ack", 4, {"elapsedMs": 3}, requestId="same")]
            events[2:2] = additions
            rows += stamp(events, session)
        result = self.analyze(rows)
        self.assertEqual(len(result["commands"]), 2)
        self.assertEqual([c["writeAttempts"] for c in result["commands"]], [2, 2])
        self.assertEqual([c["attemptedBytes"] for c in result["commands"]], [190, 190])
        self.assertEqual(result["startupGate"]["status"], "INCONCLUSIVE")
        selected = self.analyze(rows, "s2")
        self.assertEqual(len(selected["commands"]), 1)
        self.assertEqual(selected["startupGate"]["status"], "PASS")

    def test_phase_labels_alone_do_not_prove_full_coverage(self):
        # Coverage labels alone never prove that a case exercised or confirmed that phase.
        rows = measured()
        rows.insert(2, record("measurement.phase", 1, {"phase": "turn"}))
        result = self.analyze(stamp(rows))
        self.assertIn("turn", result["phases"])
        self.assertEqual(result["subsecondGoal"]["status"], "INCONCLUSIVE")
