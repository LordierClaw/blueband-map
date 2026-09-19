#!/usr/bin/env python3
"""Analyze exported navigation traces using only the Python standard library."""

import argparse
from collections import defaultdict
import csv
import io
import json
import math
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


THRESHOLD_MS = 1000
CORRELATION = ("sessionId", "fixId", "scene", "epoch", "viewSeq", "requestId")
OUTPUTS = ("report.md", "summary.json", "timeline.csv")


def number(value):
    return type(value) is int or (type(value) is float and math.isfinite(value))


def stats(values):
    values = sorted(values)
    return {"count": len(values), **{
        name: values[(len(values) * percentile + 99) // 100 - 1] if values else None
        for name, percentile in (("p50", 50), ("p95", 95), ("p99", 99), ("max", 100))
    }, "atLeast1000": sum(value >= THRESHOLD_MS for value in values)}


def gate(failed, reasons):
    return {"status": "FAIL" if failed else "INCONCLUSIVE" if reasons else "PASS",
            "reasons": sorted(set(reasons))}


def interval(later, earlier):
    end = later.get("metrics", later).get("sampleUptimeMs")
    start = earlier.get("metrics", earlier).get("sampleUptimeMs")
    if number(end) and number(start) and min(end, start) >= 0:
        return end - start
    return later["monotonicMs"] - earlier["monotonicMs"]


def analyze(path, selected_session=None):
    diagnostics, records, timeline = [], [], []

    def diagnostic(code, message, record=None, line=None):
        item = {"code": code, "message": message}
        if record:
            item.update({key: record[key] for key in CORRELATION if key in record})
            item["eventSeq"] = record["eventSeq"]
            line = record["_line"]
        if line is not None:
            item["line"] = line
        diagnostics.append(item)

    # Reading bytes lets one corrupt/truncated UTF-8 line produce a diagnostic,
    # while still analyzing the remaining exported evidence.
    raw_lines = path.read_bytes().splitlines()
    for line, raw in enumerate(raw_lines, 1):
        row = {"line": line}
        timeline.append(row)
        try:
            item = json.loads(raw.decode("utf-8"))
            if not isinstance(item, dict):
                raise ValueError("record must be an object")
        except (ValueError, UnicodeError) as error:
            diagnostic("malformed", str(error), line=line)
            row["event"] = "<malformed>"
            continue
        row.update({key: value if value is None or isinstance(value, (str, int, float, bool)) else json.dumps(value)
                    for key in (*CORRELATION, "event", "source", "eventSeq", "monotonicMs")
                    for value in [item.get(key, "")]})
        row["metrics"] = json.dumps(item.get("metrics"), ensure_ascii=False, sort_keys=True)
        if type(item.get("schemaVersion")) is not int or item["schemaVersion"] != 1:
            diagnostic("unsupported_schema", "Expected schemaVersion 1", line=line)
            continue
        metrics = item.get("metrics")
        valid = (isinstance(item.get("sessionId"), str) and bool(item["sessionId"])
                 and type(item.get("eventSeq")) is int and item["eventSeq"] >= 0
                 and number(item.get("monotonicMs")) and item["monotonicMs"] >= 0
                 and item.get("source") in ("ios", "band")
                 and isinstance(item.get("event"), str) and bool(item["event"])
                 and isinstance(metrics, dict)
                 and all(value is None or isinstance(value, (str, bool)) or number(value) for value in metrics.values())
                 and all(key not in item or (type(item[key]) in (str, int) and item[key] != "")
                         for key in CORRELATION[1:]))
        if not valid:
            diagnostic("invalid_record", "Invalid required fields, correlation or metric values", line=line)
            continue
        item["_line"] = line
        records.append(item)

    sessions = defaultdict(list)
    for item in records:
        sessions[item["sessionId"]].append(item)
    available_sessions = list(sessions)
    mixed_sessions = selected_session is None and len(sessions) > 1
    if selected_session is not None:
        if selected_session not in sessions:
            raise ValueError(f"Unknown session {selected_session!r}; available: {', '.join(available_sessions)}")
        line_sessions = {row["line"]: row.get("sessionId") for row in timeline}
        diagnostics = [item for item in diagnostics if line_sessions.get(item.get("line")) not in available_sessions
                       or line_sessions.get(item.get("line")) == selected_session]
        timeline = [row for row in timeline if row.get("sessionId") not in available_sessions or row.get("sessionId") == selected_session]
        sessions = {selected_session: sessions[selected_session]}
    elif mixed_sessions:
        diagnostic("mixed_sessions", "Multiple sessions may represent different test conditions; select one with --session ID")

    samples, groups, stage_metrics = defaultdict(list), defaultdict(lambda: defaultdict(list)), defaultdict(lambda: defaultdict(list))
    fixes, failures, frame_gaps, session_summaries = [], [], [], []
    telemetry, memory_samples = [], []
    resource_values = defaultdict(list)
    resource_reasons, latency_reasons, gap_reasons = [], [], []

    def failure(kind, record, message):
        failures.append({"id": len(failures) + 1, "kind": kind, "message": message,
                         "line": record["_line"], "eventSeq": record["eventSeq"],
                         **{key: record[key] for key in CORRELATION if key in record},
                         "metrics": record["metrics"]})

    for session_id, events in sessions.items():
        session_fixes, last_views, full_scenes = {}, {}, set()
        opened_streams = set()
        active_scene, active_epoch = None, None
        starts, ends, statuses = [], [], []
        previous_time, previous_sample, expected_seq, previous_frame = -1, -1, 0, None
        session_telemetry = 0
        resource_fields = set()
        for item in events:
            event, at, metrics = item["event"], item["monotonicMs"], item["metrics"]
            trusted = True
            if item["eventSeq"] != expected_seq:
                diagnostic("sequence_gap_or_duplicate", f"Expected eventSeq {expected_seq}", item)
                trusted = False
            expected_seq = item["eventSeq"] + 1
            if at < previous_time:
                diagnostic("clock_regression", "iPhone monotonic clock moved backwards", item)
                trusted = False
            previous_time = max(previous_time, at)
            if "sampleUptimeMs" in metrics:
                sample = metrics["sampleUptimeMs"]
                if not number(sample) or sample < 0 or sample < previous_sample:
                    diagnostic("sample_clock_invalid", "Captured iPhone uptime is invalid or regressed", item)
                    trusted = False
                else:
                    previous_sample = sample
            if ends and event != "trace.status":
                diagnostic("event_after_end", "Session event follows session.end", item)
                trusted = False
            if metrics.get("clockValid") is False:
                diagnostic("invalid_clock", "Producer reported invalid clock evidence", item)
                trusted = False
            for key, value in metrics.items():
                if number(value):
                    stage_metrics[event][key].append(value)
            cell_bytes = metrics.get("cellBytes", metrics.get("encodedBytes") if event.startswith("map.cell.") else None)
            if number(cell_bytes) and cell_bytes >= 0:
                resource_values["cellBytes"].append(cell_bytes)
                if cell_bytes > 8192:
                    failure("resource", item, f"cellBytes {cell_bytes} exceeds 8192")
            if event == "session.start":
                starts.append(item)
                if item["eventSeq"] != 0 or not metrics.get("build") or not metrics.get("wallUTC"):
                    diagnostic("invalid_start", "Start requires eventSeq 0, build and wallUTC", item)
            elif event == "session.end":
                ends.append(item)
                if metrics.get("completed") is not True or not metrics.get("reason"):
                    diagnostic("incomplete_end", "Session did not report completed:true and reason", item)
            elif event == "trace.status":
                statuses.append(item)
                if not ends:
                    diagnostic("status_before_end", "Export snapshot precedes session completion", item)
                if (type(metrics.get("droppedEvents")) is not int or metrics["droppedEvents"] != 0
                        or metrics.get("truncated") is not False or metrics.get("writeFailed") is not False):
                    diagnostic("trace_loss", "Dropped, truncated, failed or unknown trace export", item)
            elif event in ("map.stream.open", "stream.open"):
                if "scene" not in item or "epoch" not in item:
                    diagnostic("invalid_stream_open", "Stream bootstrap needs scene and epoch", item)
                else:
                    opened_streams.add((item["scene"], item["epoch"]))
                    active_scene, active_epoch = item["scene"], item["epoch"]
            elif event == "gps.fix":
                fix_id = item.get("fixId")
                if fix_id is None or fix_id in session_fixes:
                    diagnostic("invalid_fix_id", "GPS fix needs a unique fixId", item)
                    continue
                accepted = metrics.get("accepted")
                if (type(accepted) is not bool or not number(metrics.get("gpsInputAgeMs"))
                        or metrics["gpsInputAgeMs"] < 0):
                    diagnostic("invalid_gps", "GPS requires accepted and nonnegative gpsInputAgeMs", item)
                fix = {"sessionId": session_id, "fixId": fix_id, "line": item["_line"],
                       "monotonicMs": at, "gpsInputAgeMs": metrics.get("gpsInputAgeMs"),
                       "sampleUptimeMs": metrics.get("sampleUptimeMs"),
                       "accepted": accepted, "status": "pending" if accepted is True else "rejected",
                       "confirmationLines": []}
                fixes.append(fix)
                session_fixes[fix_id] = fix
                if number(metrics.get("gpsInputAgeMs")):
                    samples["gpsInputAgeMs"].append(metrics["gpsInputAgeMs"])
            elif event == "map.confirmed":
                fix = session_fixes.get(item.get("fixId"))
                required = ("fixToConfirmMs", "appToConfirmMs")
                if (not fix or fix["accepted"] is not True or "scene" not in item or metrics.get("clockValid") is not True
                        or metrics.get("mode") not in ("full", "corridor")
                        or type(metrics.get("initial")) is not bool or not isinstance(metrics.get("appState"), str)
                        or (metrics.get("mode") == "corridor" and ("epoch" not in item or "viewSeq" not in item))
                        or (not metrics.get("initial") and (not number(metrics.get("frameGapMs")) or metrics["frameGapMs"] < 0))
                        or any(not number(metrics.get(key)) or metrics[key] < 0 for key in required)):
                    diagnostic("invalid_confirmation", "Missing GPS/correlation or invalid confirmation clock/metrics", item)
                    continue
                if metrics["mode"] == "corridor":
                    identity = (item["scene"], item["epoch"])
                    if ((item["scene"] not in full_scenes and identity not in opened_streams)
                            or item["scene"] != active_scene
                            or (active_epoch is not None and item["epoch"] != active_epoch)):
                        diagnostic("stale_correlation", "Corridor scene/epoch lacks an active bootstrap", item)
                        continue
                    view = item["viewSeq"]
                    if type(view) is not int or view <= last_views.get(identity, -1):
                        diagnostic("stale_correlation", "Repeated or regressing frame viewSeq", item)
                        continue
                    last_views[identity] = view
                else:
                    if item["scene"] in full_scenes:
                        diagnostic("stale_correlation", "Repeated full-frame scene confirmation", item)
                        continue
                    full_scenes.add(item["scene"])
                age = fix["gpsInputAgeMs"]
                elapsed = interval(item, fix)
                if (not number(age) or elapsed < 0
                        or abs(metrics["appToConfirmMs"] - elapsed) > 5
                        or abs(metrics["fixToConfirmMs"] - elapsed - age) > 5):
                    diagnostic("clock_inconsistent", "Latencies disagree with GPS receipt and iPhone monotonic clock (>5ms)", item)
                    continue
                if previous_frame:
                    measured_gap = interval(item, previous_frame)
                    if metrics["initial"] or abs(metrics["frameGapMs"] - measured_gap) > 5:
                        diagnostic("frame_gap_inconsistent", "Frame gap or initial flag disagrees with previous confirmation", item)
                        trusted = False
                elif not metrics["initial"]:
                    diagnostic("missing_initial_frame", "First observed confirmation is not initial", item)
                    trusted = False
                if not trusted:
                    continue
                active_scene = item["scene"]
                active_epoch = item.get("epoch") if metrics["mode"] == "corridor" else None
                first_confirmation = not fix["confirmationLines"]
                fix["status"] = "confirmed"
                fix["confirmationLines"].append(item["_line"])
                fix["fixToConfirmMs"] = metrics["fixToConfirmMs"]
                labels = [metrics["mode"], "appState:" + metrics["appState"], "initial" if metrics["initial"] else "subsequent"]
                for key in (*required, "frameGapMs"):
                    if key == "frameGapMs" and not previous_frame:
                        continue
                    samples[key].append(metrics[key])
                    for label in labels:
                        groups[label][key].append(metrics[key])
                if not metrics["initial"] and metrics["fixToConfirmMs"] >= THRESHOLD_MS:
                    failure("latency", item, "Normal-navigation GPS fix to app-received frame confirmation >=1000ms")
                if previous_frame and metrics["frameGapMs"] >= THRESHOLD_MS:
                    pending = [f for f in session_fixes.values() if f["accepted"] is True
                               and (not f["confirmationLines"] or (f is fix and first_confirmation))]
                    overdue = [f for f in pending if number(f["gpsInputAgeMs"]) and f["gpsInputAgeMs"] >= 0
                               and interval(item, f) >= 0
                               and f["gpsInputAgeMs"] + interval(item, f) >= THRESHOLD_MS]
                    timely_input = any(0 < interval(f, previous_frame) <= THRESHOLD_MS for f in pending)
                    classification = "display_wait" if overdue else "input_cadence" if timely_input else "gps_gap"
                    frame_gaps.append({"sessionId": session_id, "fromLine": previous_frame["_line"],
                                       "toLine": item["_line"], "gapMs": metrics["frameGapMs"],
                                       "classification": classification, "overdueFixIds": [f["fixId"] for f in overdue]})
                    if overdue:
                        failure("frame_gap", item, "Unconfirmed GPS input exceeded its source-timestamp 1000ms deadline")
                        failures[-1]["overdueFixIds"] = [f["fixId"] for f in overdue]
                    elif not timely_input:
                        gap_reasons.append("Long confirmation interval without timely accepted GPS input")
                previous_frame = item
            elif "superseded" in event or "coalesced" in event:
                fix = session_fixes.get(item.get("fixId"))
                if fix and fix["status"] != "confirmed":
                    fix["status"] = "superseded" if "superseded" in event else "coalesced"
                diagnostic("coalesced_or_superseded", "A fix/frame was superseded or coalesced", item)
            elif "stale" in event:
                diagnostic("stale_correlation", "Producer reported stale data/correlation", item)
            elif "invalid" in event.split("."):
                diagnostic("invalid_evidence", "Producer rejected malformed measurement evidence", item)
            elif event == "band.telemetry":
                telemetry.append(item)
                session_telemetry += 1
                for key in ("files", "nodes", "pendingDeletes"):
                    if key not in metrics:
                        continue
                    if not number(metrics[key]) or metrics[key] < 0 or metrics[key] % 1:
                        resource_reasons.append(f"Missing/invalid band.telemetry {key}")
                    else:
                        resource_fields.add(key)
                        resource_values[key].append(metrics[key])
                limits = {"files": 31, "nodes": 24}
                for key, limit in limits.items():
                    if number(metrics.get(key)) and metrics[key] > limit:
                        failure("resource", item, f"{key} {metrics[key]} exceeds {limit}")
                if number(metrics.get("files")) and metrics["files"] > 30:
                    if not ((number(metrics.get("pendingDeletes")) and metrics["pendingDeletes"] > 0)
                            or metrics.get("inFlight") in (1, True)):
                        resource_reasons.append("31 retained files without in-flight/retiring activity identified")
                if number(metrics.get("nativeMemory")) and metrics["nativeMemory"] >= 0:
                    memory_samples.append(metrics["nativeMemory"])
            elif any(word in event.lower() for word in ("error", "failed", "failure")):
                failure("pipeline", item, "Producer reported a pipeline error; inspect event metrics")
                latency_reasons.append("Pipeline errors present")

        if len(starts) != 1 or events[0]["event"] != "session.start":
            diagnostic("missing_or_duplicate_start", f"Session {session_id} needs exactly one initial start")
        if len(ends) != 1:
            diagnostic("missing_or_duplicate_end", f"Session {session_id} needs exactly one completed end")
        if not statuses or events[-1]["event"] != "trace.status":
            diagnostic("missing_trace_status", f"Session {session_id} needs a final trace.status snapshot")
        pending = [f for f in session_fixes.values() if f["accepted"] is True and f["status"] != "confirmed"]
        if pending:
            latency_reasons.append(f"{session_id}: {len(pending)} accepted fixes have no valid confirmation")
            gap_reasons.append(f"{session_id}: missing confirmations prevent complete frame coverage")
        if previous_frame is None:
            latency_reasons.append(f"{session_id}: no valid confirmed frames")
            gap_reasons.append(f"{session_id}: no valid confirmed frames")
        if not session_telemetry:
            resource_reasons.append(f"{session_id}: no band telemetry")
        if resource_fields != {"files", "nodes", "pendingDeletes"}:
            resource_reasons.append(f"{session_id}: resource counter coverage incomplete")
        if previous_frame and ends and ends[-1]["monotonicMs"] - previous_frame["monotonicMs"] >= THRESHOLD_MS:
            frame_gaps.append({"sessionId": session_id, "fromLine": previous_frame["_line"],
                               "toLine": ends[-1]["_line"],
                               "gapMs": ends[-1]["monotonicMs"] - previous_frame["monotonicMs"],
                               "classification": "unobserved_tail"})
            gap_reasons.append(f"{session_id}: final confirmation to session end has incomplete frame coverage")
        session_summaries.append({"sessionId": session_id, "eventCount": len(events),
                                  "acceptedFixes": sum(f["accepted"] is True for f in session_fixes.values()),
                                  "confirmedFixes": sum(f["status"] == "confirmed" for f in session_fixes.values()),
                                  "unconfirmedFixes": len(pending), "start": starts[0]["metrics"] if starts else None,
                                  "end": ends[-1]["metrics"] if ends else None})

    if not records:
        diagnostic("empty_trace", "No supported valid records")
    common = ["Trace integrity diagnostics prevent a complete measurement claim"] if diagnostics else []
    if not samples["fixToConfirmMs"]:
        latency_reasons.append("No valid GPS-to-confirmation latency samples")
    if not telemetry:
        resource_reasons.append("No resource telemetry")
    latency = gate(any(f["kind"] == "latency" for f in failures), common + latency_reasons)
    gap = gate(any(f["kind"] == "frame_gap" for f in failures), common + gap_reasons)
    resource = gate(any(f["kind"] == "resource" for f in failures), common + resource_reasons)
    by_line, failures_by_line, failures_by_fix = defaultdict(list), defaultdict(set), defaultdict(set)
    fixes_by_id = {(fix["sessionId"], fix["fixId"]): fix for fix in fixes}
    for item in diagnostics:
        by_line[item.get("line")].append(item["code"])
    for item in failures:
        failures_by_line[item["line"]].add(item["id"])
        if "fixId" in item:
            failures_by_fix[(item["sessionId"], item["fixId"])].add(item["id"])
        for fix_id in item.get("overdueFixIds", []):
            failures_by_fix[(item["sessionId"], fix_id)].add(item["id"])
    for row in timeline:
        identity = (row.get("sessionId"), row.get("fixId"))
        row["diagnostics"] = "; ".join(by_line[row["line"]])
        row["failureIds"] = ";".join(str(value) for value in sorted(failures_by_line[row["line"]] | failures_by_fix[identity]))
        row["fixStatus"] = fixes_by_id.get(identity, {}).get("status", "")
    return {"schemaVersion": 1, "thresholdMs": THRESHOLD_MS,
            "availableSessions": available_sessions, "selectedSession": selected_session, "mixedSessions": mixed_sessions,
            "overall": gate(any(g["status"] == "FAIL" for g in (latency, gap, resource)),
                            ["One or more evidence gates are inconclusive"] if any(g["status"] == "INCONCLUSIVE" for g in (latency, gap, resource)) else []),
            "latencyGate": latency, "frameGapGate": gap, "resourceGate": resource,
            "physicalPixelLatency": "UNVERIFIED", "nativeMemoryEvidence": "OBSERVED" if memory_samples else "UNVERIFIED",
            "nativeMemory": stats(memory_samples), "sessions": session_summaries,
            "metrics": {key: stats(values) for key, values in samples.items()},
            "groups": {group: {"metrics": {key: stats(values) for key, values in metrics.items()}}
                       for group, metrics in groups.items()},
            "stages": {event: {key: stats(values) for key, values in metrics.items()}
                       for event, metrics in stage_metrics.items()},
            "resourceLimits": {"steadyFiles": 30, "transientFiles": 31, "nodes": 24, "pendingDeletes": None, "cellBytes": 8192},
            "resourceObservations": {key: stats(values) for key, values in resource_values.items()},
            "fixes": fixes, "frameGaps": frame_gaps, "failures": failures, "diagnostics": diagnostics}, timeline


def context(run, summary):
    previous_diagnostics = len(summary["diagnostics"])
    summary["runMetadata"] = {}
    summary["attachments"] = [p.name for p in sorted(run.iterdir()) if p.name not in OUTPUTS and p.is_file()]
    for path in sorted(set(run.glob("*.run.json")) | {run / "run.json"}):
        if not path.exists():
            continue
        try:
            metadata = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(metadata, dict):
                raise ValueError("metadata must be an object")
            summary["runMetadata"][path.name] = metadata
        except (OSError, ValueError, UnicodeError) as error:
            summary["diagnostics"].append({"code": "sidecar_unreadable", "message": f"{path.name}: {error}"})
    replay = {"deviceAcknowledgement": "UNVERIFIED", "scheduledPoints": None, "gpxPoints": None}
    try:
        if (run / "replay.csv").exists():
            with (run / "replay.csv").open(newline="", encoding="utf-8") as source:
                replay["scheduledPoints"] = sum(1 for _ in csv.DictReader(source))
        if (run / "replay.gpx").exists():
            root = ET.parse(run / "replay.gpx").getroot()
            replay["gpxPoints"] = sum(1 for node in root.iter() if node.tag.split("}")[-1] in ("trkpt", "rtept"))
    except (OSError, ValueError, UnicodeError, ET.ParseError) as error:
        summary["diagnostics"].append({"code": "replay_unreadable", "message": str(error)})
    summary["replay"] = replay
    if len(summary["diagnostics"]) > previous_diagnostics:
        for name in ("overall", "latencyGate", "frameGapGate", "resourceGate"):
            if summary[name]["status"] == "PASS":
                summary[name]["status"] = "INCONCLUSIVE"
            summary[name]["reasons"].append("Provided run metadata/replay evidence is malformed or unreadable")


def markdown(summary):
    lines = ["# Navigation performance report", "", f"**Observed evidence: {summary['overall']['status']}**", "",
             "Export sessions: " + ", ".join(f"`{session}`" for session in summary["availableSessions"]),
             "Selected session: " + (f"`{summary['selectedSession']}`" if summary["selectedSession"] else "all exported sessions"),
             "**Mixed sessions: select one session before making a single-case result claim.**" if summary["mixedSessions"] else "", "",
             "This report measures GPS receipt through app-received Band frame confirmation. Physical pixel latency is UNVERIFIED; video needs separate review.",
             "Native RAM is " + summary["nativeMemoryEvidence"] + ". File/node counts are not RAM measurements.", "",
             "| Gate | Result | Limits / scope |", "| --- | --- | --- |",
             f"| Fix to confirmation | {summary['latencyGate']['status']} | Normal navigation strictly <1000 ms; initial startup reported separately |",
             f"| Confirmation coverage | {summary['frameGapGate']['status']} | Accepted GPS input must meet its source-timestamp deadline; frame cadence alone is not a failure |",
             f"| Observed resources | {summary['resourceGate']['status']} | Cell files ≤30 (+1 identified transient), cell nodes ≤24, cell ≤8192 bytes |", "",
             "Percentiles use exact nearest rank. A FAIL is an observed breach; INCONCLUSIVE means evidence is insufficient. A PASS applies only to the exported observations, never unseen hardware behavior.", "",
             "## Timing statistics", "", "These totals include startup. The initial and subsequent groups below separate startup from the normal-navigation gate.", "",
             "| Metric (ms) | n | p50 | p95 | p99 | max | ≥1000 |",
             "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for key, value in summary["metrics"].items():
        lines.append(f"| {key} | " + " | ".join(str(value[name]) if value[name] is not None else "—"
                                               for name in ("count", "p50", "p95", "p99", "max", "atLeast1000")) + " |")
    lines.extend(["", "## Frame groups", "", "| Group | n | fix-to-confirm p95 (ms) | max (ms) | ≥1000 |", "| --- | ---: | ---: | ---: | ---: |"])
    for name, group in summary["groups"].items():
        value = group["metrics"].get("fixToConfirmMs", stats([]))
        lines.append(f"| {name} | {value['count']} | {value['p95']} | {value['max']} | {value['atLeast1000']} |")
    lines.extend(["", "## Observed resources", "", "| Counter | n | max | Cap |", "| --- | ---: | ---: | ---: |"])
    for key, cap in (("files", "30 (+1 transient)"), ("nodes", 24), ("pendingDeletes", "observed only"), ("cellBytes", 8192)):
        value = summary["resourceObservations"].get(key, stats([]))
        lines.append(f"| {key} | {value['count']} | {value['max'] if value['max'] is not None else 'unknown'} | {cap} |")
    lines.extend(["", "File/node caps cover corridor cells. Pending deletes may include full frames or multiple cells during reset; their observed count is not a one-file cap."])
    lines.extend(["", "## Stage durations", "", "Band durations stay on the Band clock; they are not subtracted from iPhone timestamps.", "",
                  "| Event.metric (ms) | n | p50 | p95 | p99 | max | ≥1000 |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"])
    for event, metrics in summary["stages"].items():
        if event in ("gps.fix", "map.confirmed"):
            continue
        for key, value in metrics.items():
            if key.endswith("Ms"):
                lines.append(f"| {event}.{key} | " + " | ".join(str(value[name]) for name in ("count", "p50", "p95", "p99", "max", "atLeast1000")) + " |")
    lines.extend(["", "## Sessions and coverage", ""])
    for session in summary["sessions"]:
        start = session.get("start") or {}
        lines.append(f"- {session['sessionId']} (UTC {start.get('wallUTC', 'unknown')}, build {start.get('build', 'unknown')}): {session['acceptedFixes']} accepted fixes, {session['confirmedFixes']} confirmed, {session['unconfirmedFixes']} unconfirmed.")
    for name in ("latencyGate", "frameGapGate", "resourceGate"):
        lines.extend(f"- {name}: {reason}" for reason in summary[name]["reasons"])
    lines.extend(["", "## Failures and diagnostics", ""])
    for failure in summary["failures"]:
        lines.append(f"- Failure {failure['id']}, line {failure['line']}, session {failure.get('sessionId')}, fix {failure.get('fixId')}, scene {failure.get('scene')}: {failure['message']}.")
    for item in summary["diagnostics"]:
        lines.append(f"- {item['code']} (line {item.get('line', 'session')}): {item['message']}")
    if not summary["failures"] and not summary["diagnostics"]:
        lines.append("No recorded failures or trace-integrity diagnostics.")
    lines.extend(["", "## Evidence files", "", "Replay CSV/GPX describe scheduled coordinates, not device acknowledgements. Notes and videos are listed for independent review.", ""])
    lines.extend(f"- `{name}`" for name in summary["attachments"])
    lines.extend(["", "`summary.json` includes per-stage metrics, resource counters, run metadata and each GPS fix. `timeline.csv` preserves all input lines with correlation, diagnostics and failure IDs.", ""])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path, help="Folder containing navigation.jsonl; outputs written alongside it")
    parser.add_argument("--session", help="Analyze one session ID while preserving the original export session list")
    args = parser.parse_args()
    try:
        run = args.run.resolve(strict=True)
        inputs = [path for path in run.iterdir() if path.name not in OUTPUTS and path.is_file()]
        targets = [run / name for name in OUTPUTS]
        for target in targets:
            if target.is_symlink() or (target.exists() and any(target.samefile(source) for source in inputs)):
                raise OSError(f"Refusing to overwrite an input through {target.name}")
        summary, rows = analyze(run / "navigation.jsonl", args.session)
        context(run, summary)
        csv_output = io.StringIO(newline="")
        writer = csv.DictWriter(csv_output, fieldnames=("line", *CORRELATION, "eventSeq", "monotonicMs", "source", "event", "metrics", "fixStatus", "diagnostics", "failureIds"))
        writer.writeheader()
        writer.writerows(rows)
        # Replace output entries rather than following links to an input inode.
        for target, content in zip(targets, (markdown(summary), json.dumps(summary, ensure_ascii=False, indent=2) + "\n", csv_output.getvalue())):
            temporary = target.with_name(target.name + ".tmp")
            with temporary.open("x", encoding="utf-8", newline="") as destination:
                destination.write(content)
            temporary.replace(target)
        print(f"{summary['overall']['status']}: {run / 'report.md'}")
        return 0
    except (OSError, ValueError) as error:
        print(f"perf-report: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
