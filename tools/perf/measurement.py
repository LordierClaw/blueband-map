"""Versioned measurement evidence. Durations never cross device clocks."""
from collections import defaultdict
import math
import re


def numeric(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def gate(failed=False, reasons=()):
    return {"status": "FAIL" if failed else "INCONCLUSIVE" if reasons else "PASS",
            "reasons": sorted(set(reasons))}


def transport_ready(m):
    counters = ("attempted", "succeeded", "failed", "pending", "peakPending", "timeouts204", "abandoned")
    return (m.get("v") == 1 and m.get("clockValid") is True and m.get("saturated") is False
            and all(type(m.get(k)) in (int, float) and numeric(m[k]) and m[k] % 1 == 0 and m[k] <= 2147483647 for k in counters)
            and m["attempted"] == m["succeeded"] + m["failed"] + m["pending"] + m["abandoned"]
            and m["succeeded"] + m["failed"] > 0 and m["peakPending"] >= m["pending"]
            and m["timeouts204"] <= m["failed"])


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
            startup_reasons.append("Missing measurementVersion 2")
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
        if not any(numeric(m.get("rpk")) and isinstance(m.get("versionName"), str) and re.fullmatch(r"\d+\.\d+\.\d+", m["versionName"])
                   and m.get("perfVersion") == 1 for m in identity):
            reasons.append("Band identity/performance capability unverified")
        transports = [r["metrics"] for r in rows if r["event"] == "band.transport"]
        if not any(transport_ready(m) for m in transports):
            reasons.append("Band native send callback evidence unavailable")
        intents = [r for r in rows if r["event"] == "navigation.intent"]
        firsts = [r for r in rows if r["event"] == "map.confirmed" and r["metrics"].get("initial") is True
                  and r.get("_trustedConfirmation") is True]
        elapsed = None
        if len(intents) == 1 and len(firsts) == 1:
            start = intents[0]["metrics"].get("sampleUptimeMs")
            end = firsts[0]["metrics"].get("sampleUptimeMs")
            admission_delay = intents[0]["metrics"].get("intentAdmissionDelayMs")
            recorded = firsts[0]["monotonicMs"] - intents[0]["monotonicMs"]
            if (numeric(start) and numeric(end) and end >= start and
                    numeric(admission_delay) and abs(end - start - recorded - admission_delay) <= 5 and
                    intents[0]["eventSeq"] < firsts[0]["eventSeq"] and firsts[0]["metrics"].get("clockValid") is True):
                elapsed = end - start
        if elapsed is None:
            startup_reasons.append("Requires one intent and first confirmation with consistent uptime/admission delay (5 ms tolerance)")
        startup.append({"sessionId": session, "intentToConfirmMs": elapsed,
                        "intentLine": intents[0]["_line"] if len(intents) == 1 else None,
                        "confirmationLine": firsts[0]["_line"] if len(firsts) == 1 else None})
        phase = None
        fix_phases = {}
        for row in rows:
            event, m = row["event"], row["metrics"]
            reference = {k: row[k] for k in ("sessionId", "eventSeq", "fixId", "requestId", "scene", "epoch", "viewSeq") if k in row}
            reference.update(line=row["_line"], metrics=m)
            if event == "measurement.phase":
                phase = m.get("phase") if m.get("phase") in ("startup", "cached", "coverage", "turn", "recovery") else None
                if phase:
                    phases[phase]["markers"] += 1
            if event == "gps.fix" and m.get("accepted") is True:
                fix_phases[row.get("fixId")] = phase
            origin_phase = fix_phases.get(row.get("fixId"))
            if event == "map.confirmed" and row.get("_trustedConfirmation") is True and origin_phase and m.get("initial") is False and numeric(m.get("fixToConfirmMs")):
                phases[origin_phase]["confirmations"] += 1
                phases[origin_phase]["maxFixToConfirmMs"] = max(phases[origin_phase]["maxFixToConfirmMs"] or 0, m["fixToConfirmMs"])
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
    startup_gate = gate(not startup_reasons and any(numeric(s["intentToConfirmMs"]) and s["intentToConfirmMs"] >= 1000 for s in startup), startup_reasons)
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
