import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from test_measurement import measured
from test_report import record, stamp


PACKET = Path(__file__).with_name("packet.py")
SHA = "0947f7b9824eb13b6ea25722b3214673079f57a9"


class PacketTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.manifest = {"schemaVersion": 1, "sourceSHA": SHA,
                         "expected": {"appBuild": "test-1", "rpkVersion": "0.6.19", "rpkBuild": 34},
                         "cases": [{"id": "walk-01", "directory": "walk-01", "mapMode": "automatic",
                                    "requiredPhases": ["cached"]}]}
        self.rows = measured()
        self.rows.insert(1, record("measurement.phase", 0, {"phase": "cached"}))
        self.rows = stamp(self.rows)
        self.write_case(self.rows)

    def write_case(self, rows, name="walk-01", sidecar=None, suffix=""):
        folder = self.root / name
        folder.mkdir(exist_ok=True)
        (folder / "navigation.jsonl").write_text("".join(json.dumps(row) + "\n" for row in rows) + suffix, encoding="utf-8")
        (folder / "run.json").write_text(json.dumps(sidecar or {"caseID": name, "sourceSHA": SHA, "gpsSource": "device"}), encoding="utf-8")

    def invoke(self, expected_code=0):
        (self.root / "packet.json").write_text(json.dumps(self.manifest), encoding="utf-8")
        result = subprocess.run([sys.executable, str(PACKET), str(self.root)], capture_output=True, text=True)
        self.assertEqual(result.returncode, expected_code, result.stdout + result.stderr)
        if expected_code:
            return result
        self.assertTrue((self.root / "packet-summary.json").is_file(), "packet summary must be created")
        return json.loads((self.root / "packet-summary.json").read_text(encoding="utf-8"))

    def test_complete_capture_is_ready_for_analysis_without_claiming_latency_or_hardware_acceptance(self):
        path = self.root / "walk-01/navigation.jsonl"
        original = hashlib.sha256(path.read_bytes()).digest()
        result = self.invoke()
        self.assertEqual(result["status"], "READY_FOR_ANALYSIS")
        self.assertEqual(result["hardwareAcceptance"], "UNVERIFIED")
        self.assertEqual(result["sourceSHAEvidence"], "DECLARED_ONLY")
        case = result["cases"][0]
        self.assertEqual(case["sessionId"], "s1")
        self.assertEqual(case["gates"]["startupGate"]["status"], "PASS")
        self.assertEqual(case["gates"]["subsecondGoal"]["status"], "INCONCLUSIVE")
        self.assertEqual(hashlib.sha256(path.read_bytes()).digest(), original)
        self.assertFalse((path.parent / "summary.json").exists())
        self.assertIn("UNVERIFIED", (self.root / "packet-report.md").read_text(encoding="utf-8"))

    def test_valid_slow_start_is_evidence_to_analyze_not_a_request_to_retake(self):
        rows = measured(1200)
        rows.insert(1, record("measurement.phase", 0, {"phase": "cached"}))
        self.write_case(stamp(rows))
        result = self.invoke()
        self.assertEqual(result["status"], "READY_FOR_ANALYSIS")
        self.assertEqual(result["cases"][0]["gates"]["startupGate"]["status"], "FAIL")
        self.assertEqual(result["observedFailureCases"], ["walk-01"])

    def test_missing_case_does_not_discard_other_captures(self):
        self.manifest["cases"].append({"id": "cold-01", "directory": "cold-01", "mapMode": "automatic"})
        result = self.invoke()
        self.assertEqual(result["status"], "NEEDS_ATTENTION")
        self.assertEqual(result["cases"][0]["status"], "READY_FOR_ANALYSIS")
        self.assertIn("trace_unavailable", result["cases"][1]["issues"])

    def test_unique_matching_case_is_selected_from_three_session_export(self):
        other = measured(session="old")
        other[0]["metrics"]["testCaseID"] = "other-01"
        other[0]["metrics"]["build"] = "old-build"
        self.write_case(other + self.rows)
        result = self.invoke()
        self.assertEqual(result["status"], "READY_FOR_ANALYSIS")
        self.assertEqual(result["cases"][0]["availableSessions"], ["old", "s1"])
        self.assertEqual(result["cases"][0]["sessionId"], "s1")

    def test_repeated_case_id_requires_explicit_session_and_wrong_selection_is_rejected(self):
        self.write_case(self.rows + stamp(json.loads(json.dumps(self.rows)), "s2"))
        result = self.invoke()
        self.assertIn("session_ambiguous", result["cases"][0]["issues"])
        self.manifest["cases"][0]["sessionId"] = "s2"
        self.assertEqual(self.invoke()["status"], "READY_FOR_ANALYSIS")
        self.manifest["cases"][0]["sessionId"] = "missing"
        self.assertIn("session_unknown", self.invoke()["cases"][0]["issues"])

    def test_selected_wrong_case_cannot_pass_just_because_build_matches(self):
        self.rows[0]["metrics"]["testCaseID"] = "other-01"
        self.write_case(self.rows)
        self.manifest["cases"][0]["sessionId"] = "s1"
        self.assertIn("case_id_mismatch", self.invoke()["cases"][0]["issues"])

    def test_build_peer_mode_source_and_gps_mismatch_are_reported(self):
        for change, issue in (("app", "app_build_mismatch"), ("peer", "rpk_mismatch"),
                              ("mode", "map_mode_mismatch"), ("source", "source_sha_mismatch"),
                              ("gps", "gps_source_mismatch")):
            with self.subTest(change=change):
                rows = json.loads(json.dumps(self.rows))
                sidecar = {"caseID": "walk-01", "sourceSHA": SHA, "gpsSource": "device"}
                if change == "app": rows[0]["metrics"]["build"] = "old"
                if change == "peer": next(r for r in rows if r["event"] == "band.identity")["metrics"]["rpk"] = 33
                if change == "mode": rows[0]["metrics"]["mapMode"] = "full"
                if change == "source": sidecar["sourceSHA"] = "0" * 40
                if change == "gps": sidecar["gpsSource"] = "replay"
                self.write_case(rows, sidecar=sidecar)
                result = self.invoke()
                self.assertEqual(result["status"], "NEEDS_ATTENTION")
                self.assertIn(issue, result["cases"][0]["issues"])

    def test_missing_phase_and_background_confirmation_are_not_satisfied_by_labels(self):
        self.manifest["cases"][0]["requiredPhases"] = ["turn"]
        self.manifest["cases"][0]["requiredAppState"] = "background"
        for row in self.rows:
            if row["event"] == "map.confirmed": row["metrics"]["appState"] = "active"
        self.write_case(self.rows)
        issues = self.invoke()["cases"][0]["issues"]
        self.assertIn("phase_unobserved:turn", issues)
        self.assertIn("app_state_unobserved:background", issues)

    def test_partial_trace_or_malformed_sidecar_requires_attention(self):
        self.rows[-1]["metrics"]["droppedEvents"] = 1
        self.write_case(self.rows)
        result = self.invoke()
        self.assertEqual(result["status"], "NEEDS_ATTENTION")
        self.assertIn("trace_integrity", result["cases"][0]["issues"])
        (self.root / "walk-01/run.json").write_text("{", encoding="utf-8")
        self.assertIn("run_metadata_unavailable", self.invoke()["cases"][0]["issues"])

    def test_unassignable_corruption_is_not_hidden_by_automatic_session_selection(self):
        self.write_case(self.rows, suffix="{broken\n")
        self.assertIn("trace_integrity", self.invoke()["cases"][0]["issues"])

    def test_unlisted_captures_are_not_included(self):
        self.write_case([], name="unlisted")
        result = self.invoke()
        self.assertEqual(len(result["cases"]), 1)
        self.assertEqual(result["status"], "READY_FOR_ANALYSIS")

    def test_manifest_rejects_empty_duplicate_and_escaping_cases(self):
        original = json.loads(json.dumps(self.manifest))
        for cases in ([], [original["cases"][0]] * 2,
                      [{"id": "walk-01", "directory": "../outside", "mapMode": "automatic"}],
                      [{"id": "walk-01", "directory": str(self.root), "mapMode": "automatic"}]):
            self.manifest = {**original, "cases": cases}
            result = self.invoke(expected_code=2)
            self.assertIn("perf-packet:", result.stderr)
            self.assertFalse((self.root / "packet-summary.json").exists())

    def test_output_alias_cannot_overwrite_trace(self):
        trace_path = self.root / "walk-01/navigation.jsonl"
        original = trace_path.read_bytes()
        os.link(trace_path, self.root / "packet-summary.json")
        result = self.invoke(expected_code=2)
        self.assertIn("overwrite", result.stderr)
        self.assertEqual(trace_path.read_bytes(), original)

    def test_misspelled_requirements_are_rejected_instead_of_silently_weakened(self):
        self.manifest["cases"][0]["requiredPhase"] = ["turn"]
        result = self.invoke(expected_code=2)
        self.assertIn("Unknown case fields", result.stderr)

    def test_missing_session_list_does_not_break_the_case_table(self):
        self.write_case(self.rows + stamp(json.loads(json.dumps(self.rows)), "s2"))
        self.manifest["cases"].append({"id": "cold-01", "directory": "cold-01", "mapMode": "automatic"})
        self.invoke()
        text = (self.root / "packet-report.md").read_text(encoding="utf-8")
        first = next(i for i, line in enumerate(text.splitlines()) if line.startswith("| `walk-01`"))
        self.assertTrue(text.splitlines()[first + 1].startswith("| `cold-01`"))

    def test_observed_failure_cannot_hide_missing_resource_evidence(self):
        telemetry = next(row for row in self.rows if row["event"] == "band.telemetry")["metrics"]
        telemetry["files"] = 32
        self.write_case(self.rows)
        self.assertEqual(self.invoke()["status"], "READY_FOR_ANALYSIS", "complete resource violations remain useful evidence")
        del telemetry["nodes"]
        self.write_case(self.rows)
        result = self.invoke()
        self.assertEqual(result["cases"][0]["gates"]["resourceGate"]["status"], "FAIL")
        self.assertEqual(result["status"], "NEEDS_ATTENTION", "FAIL must not conceal missing evidence")
        self.assertIn("incomplete:resourceGate", result["cases"][0]["issues"])

    def test_oversized_replay_field_does_not_abort_other_cases(self):
        (self.root / "walk-01/replay.csv").write_text("lat,lon\n" + "1" * 131073 + ",2\n", encoding="utf-8")
        other = json.loads(json.dumps(self.rows))
        other[0]["metrics"]["testCaseID"] = "other-01"
        self.write_case(other, name="other-01")
        self.manifest["cases"].append({"id": "other-01", "directory": "other-01", "mapMode": "automatic"})
        result = self.invoke()
        self.assertEqual(result["status"], "NEEDS_ATTENTION")
        self.assertIn("trace_integrity", result["cases"][0]["issues"])
        self.assertEqual(result["cases"][1]["status"], "READY_FOR_ANALYSIS")


if __name__ == "__main__":
    unittest.main()
