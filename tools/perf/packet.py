#!/usr/bin/env python3
"""Check a declared collection of exported cases without changing its evidence."""

import argparse
import json
from pathlib import Path
import re
import sys

from report import analyze, context


OUTPUTS = ("packet-report.md", "packet-summary.json")
GATES = ("startupGate", "measurementReadiness", "latencyGate", "frameGapGate", "resourceGate", "subsecondGoal")
PHASES = ("cached", "coverage", "turn", "recovery")


def read_object(path):
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path.name} must contain an object")
    return value


def load_manifest(root):
    manifest = read_object(root / "packet.json")
    if set(manifest) - {"schemaVersion", "sourceSHA", "expected", "cases"}:
        raise ValueError("Unknown packet fields")
    if type(manifest.get("schemaVersion")) is not int or manifest["schemaVersion"] != 1:
        raise ValueError("packet schemaVersion must be 1")
    if not isinstance(manifest.get("sourceSHA"), str) or not re.fullmatch(r"[0-9a-f]{40}", manifest["sourceSHA"]):
        raise ValueError("packet sourceSHA must be a full lowercase Git SHA")
    expected = manifest.get("expected")
    if (not isinstance(expected, dict) or
            not all(isinstance(expected.get(k), str) and expected[k].strip() for k in ("appBuild", "rpkVersion")) or
            type(expected.get("rpkBuild")) is not int or expected["rpkBuild"] < 0):
        raise ValueError("expected appBuild, rpkVersion and integer rpkBuild are required")
    if set(expected) - {"appBuild", "rpkVersion", "rpkBuild"}:
        raise ValueError("Unknown expected-version fields")
    cases = manifest.get("cases")
    if not isinstance(cases, list) or not 1 <= len(cases) <= 64:
        raise ValueError("packet must declare 1 to 64 cases")
    ids, folders = set(), set()
    for case in cases:
        if not isinstance(case, dict):
            raise ValueError("each case must be an object")
        if set(case) - {"id", "directory", "mapMode", "requiredPhases", "requiredAppState", "sessionId"}:
            raise ValueError("Unknown case fields")
        if (not isinstance(case.get("id"), str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,32}", case["id"]) or
                not isinstance(case.get("directory"), str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", case["directory"])):
            raise ValueError("case id/directory must be safe names of direct child folders")
        folder = (root / case["directory"]).resolve()
        if folder.parent != root or case["id"] in ids or folder in folders:
            raise ValueError("case ids/folders must be unique and stay inside the packet")
        ids.add(case["id"]); folders.add(folder)
        if case.get("mapMode") not in ("automatic", "full"):
            raise ValueError("each case must declare mapMode automatic/full")
        phases = case.get("requiredPhases", [])
        if not isinstance(phases, list) or any(not isinstance(p, str) or p not in PHASES for p in phases):
            raise ValueError("requiredPhases must use cached/coverage/turn/recovery")
        if "sessionId" in case and (not isinstance(case["sessionId"], str) or not case["sessionId"]):
            raise ValueError("omit sessionId or supply a nonempty string")
        if "requiredAppState" in case and case["requiredAppState"] not in ("active", "inactive", "background"):
            raise ValueError("requiredAppState must use active/inactive/background")
    return manifest


def check_case(root, case, manifest):
    result = {"id": case["id"], "directory": case["directory"], "status": "NEEDS_ATTENTION",
              "sessionId": None, "availableSessions": [], "issues": [], "gates": {}}
    issues = result["issues"]
    folder = root / case["directory"]
    path = folder / "navigation.jsonl"
    try:
        # Only the declared folder is inspected. Do not follow evidence links elsewhere.
        if any(p.is_symlink() for p in [path, folder / "run.json", folder / "replay.csv", folder / "replay.gpx",
                                       *folder.glob("*.run.json")]):
            issues.append("linked_evidence"); return result
        initial, _ = analyze(path)
    except (OSError, ValueError):
        issues.append("trace_unavailable"); return result
    result["availableSessions"] = initial["availableSessions"]
    selected = case.get("sessionId")
    if selected is None:
        matches = [s["sessionId"] for s in initial["sessions"] if (s.get("start") or {}).get("testCaseID") == case["id"]]
        if len(matches) != 1:
            issues.append("session_ambiguous" if len(matches) > 1 else "case_id_mismatch")
            return result
        selected = matches[0]
    if selected not in result["availableSessions"]:
        issues.append("session_unknown"); return result
    result["sessionId"] = selected
    summary, timeline = analyze(path, selected)
    context(folder, summary)
    result["gates"] = {key: summary[key] for key in GATES}
    result["startup"] = summary["startup"]
    result["phases"] = summary["phases"]
    result["diagnostics"] = summary["diagnostics"]
    start = summary["sessions"][0].get("start") or {}
    result["environment"] = {key: start.get(key) for key in ("build", "osVersion", "deviceModel", "firmware", "gpsSource", "mapMode")}
    if start.get("testCaseID") != case["id"]:
        issues.append("case_id_mismatch")
    if start.get("build") != manifest["expected"]["appBuild"]:
        issues.append("app_build_mismatch")
    if start.get("mapMode") != case["mapMode"]:
        issues.append("map_mode_mismatch")
    identities = [json.loads(row["metrics"]) for row in timeline if row.get("event") == "band.identity"]
    if not identities or any(not isinstance(m, dict) or m.get("versionName") != manifest["expected"]["rpkVersion"]
                             or m.get("rpk") != manifest["expected"]["rpkBuild"] for m in identities):
        issues.append("rpk_mismatch")
    try:
        sidecar = read_object(folder / "run.json")
        if sidecar.get("caseID") != case["id"]:
            issues.append("run_case_id_mismatch")
        if sidecar.get("sourceSHA") != manifest["sourceSHA"]:
            issues.append("source_sha_mismatch")
        if sidecar.get("gpsSource") not in ("device", "replay") or sidecar.get("gpsSource") != start.get("gpsSource"):
            issues.append("gps_source_mismatch")
    except (OSError, ValueError, UnicodeError):
        issues.append("run_metadata_unavailable")
    if summary["diagnostics"]:
        issues.append("trace_integrity")
    for key in GATES[:-1]:
        if summary[key]["status"] == "INCONCLUSIVE":
            issues.append("incomplete:" + key)
    for phase in case.get("requiredPhases", []):
        if not summary["phases"].get(phase, {}).get("confirmations"):
            issues.append("phase_unobserved:" + phase)
    state = case.get("requiredAppState")
    if state and not summary["groups"].get("appState:" + state, {}).get("metrics", {}).get("fixToConfirmMs", {}).get("count"):
        issues.append("app_state_unobserved:" + state)
    if not issues:
        result["status"] = "READY_FOR_ANALYSIS"
    return result


def markdown(packet):
    def code(value):
        return "`" + str(value).replace("`", "&#96;").replace("|", "&#124;").replace("\n", " ") + "`"

    lines = ["# Kiểm tra bộ trace", "", "**" + packet["status"] + "**", "",
             "Đây là kiểm tra dữ liệu đã thu, không phải nghiệm thu độ trễ. Hardware acceptance: UNVERIFIED.",
             "Source SHA chỉ do hồ sơ khai báo (DECLARED_ONLY); trace không chứa hash binary đã cài.", "",
             "READY_FOR_ANALYSIS nghĩa là đủ các kiểm tra đã khai báo để phân tích, kể cả khi độ trễ FAIL.",
             "NEEDS_ATTENTION: kiểm tra hồ sơ/session/file trước; không mặc định phải chạy lại hoặc cài lại.", "",
             "Cold/warm, thao tác thực tế, video và RAM native cần đánh giá riêng. Pha là nhãn người thử.", "",
             "| Ca | Phiên | Dữ liệu | Startup | Việc cần kiểm tra |", "| --- | --- | --- | --- | --- |"]
    for case in packet["cases"]:
        startup = case["gates"].get("startupGate", {}).get("status", "UNKNOWN")
        lines.append("| " + " | ".join(code(v) for v in (case["id"], case["sessionId"] or "chưa chọn", case["status"], startup,
                                                            ", ".join(case["issues"]) or "Không thiếu mục đã kiểm tra")) + " |")
    for case in packet["cases"]:
        if case["issues"] and case["availableSessions"]:
            lines.append("")
            lines.append("Các phiên có trong " + code(case["id"]) + ": " + ", ".join(code(s) for s in case["availableSessions"]) + ".")
            lines.append("")
    lines += ["", "Ca có vi phạm quan sát được: " + (", ".join(code(s) for s in packet["observedFailureCases"]) or "chưa ghi nhận"), "",
              "Giữ nguyên trace chậm/lỗi. Xem gates, diagnostics, environment và startup trong packet-summary.json;",
              "dùng make perf-report RUN=... SESSION=... để xem timeline và chi tiết từng ca.", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("packet", type=Path, help="Folder containing packet.json and declared case folders")
    args = parser.parse_args()
    try:
        root = args.packet.resolve(strict=True)
        manifest = load_manifest(root)
        inputs = [root / "packet.json"]
        for case in manifest["cases"]:
            folder = root / case["directory"]
            if folder.is_dir():
                inputs.extend(p for p in folder.iterdir() if p.is_file())
        for name in OUTPUTS:
            target = root / name
            if target.is_symlink() or (target.exists() and any(target.samefile(p) for p in inputs)):
                raise OSError(f"Refusing to overwrite an input through {name}")
        cases = [check_case(root, case, manifest) for case in manifest["cases"]]
        packet = {"schemaVersion": 1, "sourceSHA": manifest["sourceSHA"], "sourceSHAEvidence": "DECLARED_ONLY",
                  "status": "READY_FOR_ANALYSIS" if all(c["status"] == "READY_FOR_ANALYSIS" for c in cases) else "NEEDS_ATTENTION",
                  "hardwareAcceptance": "UNVERIFIED", "cases": cases,
                  "observedFailureCases": [c["id"] for c in cases if any(g["status"] == "FAIL" for g in c["gates"].values())]}
        for name, text in zip(OUTPUTS, (markdown(packet), json.dumps(packet, ensure_ascii=False, indent=2) + "\n")):
            target = root / name
            temporary = target.with_name(name + ".tmp")
            with temporary.open("x", encoding="utf-8", newline="") as output:
                output.write(text)
            temporary.replace(target)
        print(f"{packet['status']}: {root / OUTPUTS[0]}")
        return 0
    except (OSError, ValueError) as error:
        print(f"perf-packet: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
