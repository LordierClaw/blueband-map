"""Versioned measurement evidence. Durations never cross device clocks."""
from collections import defaultdict
import math
import re


def numeric(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def gate(failed=False, reasons=()):
    return {"status": "FAIL" if failed else "INCONCLUSIVE" if reasons else "PASS",
            "reasons": sorted(set(reasons))}


def analyze_measurement(records, integrity_valid):
    startup, observations, resets, commands = [], [], [], {}
    phases = defaultdict(lambda: {"markers": 0, "confirmations": 0, "maxFixToConfirmMs": None})
    reasons = [] if integrity_valid else ["Trace integrity/completion is insufficient"]
    startup_reasons = list(reasons)
    sessions = defaultdict(list)
    for row in records:
        sessions[row["sessionId"]].append(row)
    if len(sessions) != 1:
        reasons.append("Select exactly one session")
        startup_reasons.append("Select exactly one session")
    for session, rows in sessions.items():
        starts = [r for r in rows if r["event"] == "session.start"]
        metadata = starts[0]["metrics"] if len(starts) == 1 else {}
        if metadata.get("measurementVersion") != 2:
            reasons.append("Missing measurementVersion 2")
        for key in ("build", "osVersion", "deviceModel", "firmware"):
            if not isinstance(metadata.get(key), str) or metadata[key].lower() in ("", "unknown", "unavailable"):
                reasons.append("Missing environment: " + key)
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,32}", str(metadata.get("testCaseID", ""))) or metadata.get("testCaseID") == "unknown":
            reasons.append("Missing safe testCaseID")
        if metadata.get("gpsSource") not in ("device", "replay"):
            reasons.append("GPS source is unknown")
        if metadata.get("mapMode") not in ("automatic", "full"):
            reasons.append("Map mode is unknown")
        identity = [r["metrics"] for r in rows if r["event"] == "band.identity"]
        if not any(numeric(m.get("rpk")) and isinstance(m.get("versionName"), str)
                   and m.get("perfVersion") == 1 for m in identity):
            reasons.append("Band identity/performance capability unverified")
        transports = [r["metrics"] for r in rows if r["event"] == "band.transport"]
        if not any(m.get("v") == 1 and m.get("clockValid") is True and all(numeric(m.get(k)) for k in
                   ("attempted", "succeeded", "failed", "pending", "peakPending", "timeouts204")) for m in transports):
            reasons.append("Band native send callback evidence unavailable")
        intents = [r for r in rows if r["event"] == "navigation.intent"]
        firsts = [r for r in rows if r["event"] == "map.confirmed" and r["metrics"].get("initial") is True]
        elapsed = None
        if len(intents) == 1 and len(firsts) == 1:
            start = intents[0]["metrics"].get("sampleUptimeMs")
            end = firsts[0]["metrics"].get("sampleUptimeMs")
            if (numeric(start) and numeric(end) and end >= start and
                    intents[0]["eventSeq"] < firsts[0]["eventSeq"] and firsts[0]["metrics"].get("clockValid") is True):
                elapsed = end - start
        if elapsed is None:
            startup_reasons.append("Requires one intent and first confirmation on the iPhone monotonic clock")
        startup.append({"sessionId": session, "intentToConfirmMs": elapsed,
                        "intentLine": intents[0]["_line"] if len(intents) == 1 else None,
                        "confirmationLine": firsts[0]["_line"] if len(firsts) == 1 else None})
        phase = None
        for row in rows:
            event, m = row["event"], row["metrics"]
            reference = {k: row[k] for k in ("sessionId", "eventSeq", "fixId", "requestId", "scene", "epoch", "viewSeq") if k in row}
            reference.update(line=row["_line"], metrics=m)
            if event == "measurement.phase":
                phase = m.get("phase") if m.get("phase") in ("startup", "cached", "coverage", "turn", "recovery") else None
                if phase:
                    phases[phase]["markers"] += 1
            if event == "map.confirmed" and phase and m.get("initial") is False and numeric(m.get("fixToConfirmMs")):
                phases[phase]["confirmations"] += 1
                phases[phase]["maxFixToConfirmMs"] = max(phases[phase]["maxFixToConfirmMs"] or 0, m["fixToConfirmMs"])
            if event == "measurement.observation":
                observations.append(reference)
            if event == "map.stream.reset":
                resets.append(reference)
            request = row.get("requestId", m.get("requestId"))
            if event.startswith("ble.") and request:
                command = commands.setdefault((session, request), {"sessionId": session, "requestId": request,
                    "topic": None, "writeAttempts": 0, "nativeWriteCount": 0, "attemptedBytes": 0, "events": []})
                command["events"].append({"event": event, **reference})
                if event == "ble.command":
                    command["topic"] = m.get("topic")
                if event == "ble.write":
                    command["writeAttempts"] += 1
                    for key in ("nativeWriteCount", "attemptedBytes"):
                        if numeric(m.get(key)):
                            command[key] += m[key]
    startup_gate = gate(any(numeric(s["intentToConfirmMs"]) and s["intentToConfirmMs"] >= 1000 for s in startup), startup_reasons)
    readiness = gate(reasons=reasons)
    goal_reasons = ["Startup evidence incomplete"] if startup_gate["status"] == "INCONCLUSIVE" else []
    if readiness["status"] != "PASS":
        goal_reasons += reasons
    for phase in ("cached", "coverage", "turn"):
        if not phases.get(phase, {}).get("confirmations"):
            goal_reasons.append("No confirmed observations in phase: " + phase)
    visible = any(o["metrics"].get("visibleProblem") is True for o in observations)
    if visible:
        goal_reasons.append("User recorded a visible display problem; review video")
    return {"startup": startup, "startupGate": startup_gate, "measurementReadiness": readiness,
            "subsecondGoal": gate(startup_gate["status"] == "FAIL" or visible, goal_reasons),
            "commands": list(commands.values()), "phases": dict(phases), "streamResets": resets,
            "observations": observations}
