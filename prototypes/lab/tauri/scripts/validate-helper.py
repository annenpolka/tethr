#!/usr/bin/env python3
"""Opt-in real helper adapter check. No GUI is launched or activated."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def bundle_binary_path(base: Path):
    """Optional metadata only: this headless check never executes a GUI bundle."""
    candidates = [
        base / "src-tauri/target/release/bundle/macos/Tethr Tauri Lab.app/Contents/MacOS/tethr-lab-tauri",
        base / "dist/Tethr Tauri Lab.app/Contents/MacOS/tethr-lab-tauri",
    ]
    return next((path for path in candidates if path.is_file()), None)


root = Path(__file__).resolve().parent.parent
config_path = Path(os.environ["TETHR_LAB_CONFIG"]).resolve()
config = json.loads(config_path.read_text())
probe = root / "src-tauri/target/release/examples/helper_probe"
bundle_binary = bundle_binary_path(root)
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
report = {
    "scope": "Real Rust subprocess adapter to real shared helper; bypasses Web UI and Tauri IPC. No GUI/focus/IME acceptance.",
    "configPath": str(config_path),
    "configSHA256": digest(config_path),
    "probeSHA256": digest(probe),
    "bundledAppBinaryPath": str(bundle_binary) if bundle_binary else None,
    "bundledAppBinarySHA256": digest(bundle_binary) if bundle_binary else None,
    "bundledAppMetadataStatus": "present-not-executed" if bundle_binary else "not-present-headless-only",
    "attempts": [],
    "verdict": "INCONCLUSIVE",
}

def invoke(action):
    started = time.monotonic_ns()
    result = subprocess.run([str(probe), action], capture_output=True, text=True, timeout=40)
    report["attempts"].append({"action": action, "startedMonotonicNS": started, "endedMonotonicNS": time.monotonic_ns(), "exitCode": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
    if result.returncode != 0:
        raise AssertionError(f"{action}: probe exited {result.returncode}")
    reply = json.loads(result.stdout)
    if reply.get("protocolVersion") != 1 or reply.get("status") != "ok":
        raise AssertionError(f"{action}: invalid or unsuccessful reply")
    return reply

try:
    catalog = invoke("catalog")
    ids = [item["id"] for item in catalog["items"]]
    assert "terminal.step" in ids and "command.git-status" in ids
    first = invoke("terminal.step")["data"]
    second = invoke("terminal.step")["data"]
    for field in ["shellNonce", "shellPID", "cwd"]:
        assert first[field] == second[field], f"persistent shell {field} changed"
    assert first["shellNonce"] and first["shellPID"] > 0
    # Other UIs can legitimately increment the shared counter between these calls.
    assert second["counter"] > first["counter"], "counter did not advance"
    assert Path(first["cwd"]).resolve() == Path(config["cwd"]).resolve()
    command = invoke("command.git-status")["data"]
    assert command["exitCode"] == 0
    assert isinstance(command["stdout"], str) and isinstance(command["stderr"], str)
    assert Path(command["cwd"]).resolve() == Path(config["cwd"]).resolve()
    report["verdict"] = "PASS"
    report["verified"] = {"sameShellPID": first["shellPID"], "sameShellNonce": first["shellNonce"], "counters": [first["counter"], second["counter"]], "cwd": first["cwd"], "gitExitCode": command["exitCode"]}
except (AssertionError, KeyError, ValueError) as error:
    report["verdict"] = "FAIL"
    report["reason"] = str(error)
except (OSError, subprocess.TimeoutExpired) as error:
    report["verdict"] = "INCONCLUSIVE"
    report["reason"] = str(error)
finally:
    out = root / "evidence/real-helper.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"verdict": report["verdict"], "evidence": str(out), "verified": report.get("verified"), "reason": report.get("reason")}, ensure_ascii=False))

raise SystemExit(0 if report["verdict"] == "PASS" else 1)
