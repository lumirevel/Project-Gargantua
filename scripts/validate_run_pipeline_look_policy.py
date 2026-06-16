#!/usr/bin/env python3
"""Validate run_pipeline look defaults across presentation boundaries.

Source-model defaults may choose filmic looks for cinema, but scientific and
RAW-like audit presentations must not inherit those presentation looks, and
camera-raw must reject non-linear user looks.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
RUN_PIPELINE = ROOT / "Blackhole" / "run_pipeline.sh"
OUT_DIR = Path("/private/tmp/bh_run_pipeline_look_policy")


CASES = [
    {
        "name": "camera_raw_default_forces_linear",
        "args": [
            "--source-model",
            "cinematic-physical-disk-v1",
            "--presentation",
            "camera-raw",
        ],
        "expected_look": "linear",
    },
    {
        "name": "camera_raw_user_filmic_look_is_rejected",
        "args": [
            "--source-model",
            "cinematic-physical-disk-v1",
            "--presentation",
            "camera-raw",
            "--look",
            "agx",
        ],
        "expected_returncode": 3,
        "expected_stderr": "camera-raw requires --look linear/none",
    },
    {
        "name": "cinema_default_keeps_source_filmic_look",
        "args": [
            "--source-model",
            "cinematic-physical-disk-v1",
            "--presentation",
            "cinema",
        ],
        "expected_look": "sensor-filmic",
    },
]


def extract_log_item(stdout: str, key: str) -> str | None:
    pattern = re.compile(rf"^\s*{re.escape(key)}\s+(.+?)\s*$", re.MULTILINE)
    match = pattern.search(stdout)
    return match.group(1) if match else None


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.setdefault("BH_DERIVED_DATA_PATH", str(OUT_DIR / "DerivedData"))
    env.setdefault("BH_ETA_HISTORY", str(OUT_DIR / "eta_history.json"))

    rows: list[dict[str, Any]] = []
    failures: list[str] = []
    for idx, case in enumerate(CASES):
        out = OUT_DIR / f"{case['name']}.png"
        cmd = [
            "bash",
            str(RUN_PIPELINE),
            "--quality",
            "preview",
            "--width",
            "32",
            "--height",
            "18",
            "--background",
            "off",
            "--output",
            str(out),
        ] + list(case["args"])
        if idx > 0:
            cmd.append("--no-build")
        completed = subprocess.run(
            cmd,
            cwd=str(ROOT),
            env=env,
            text=True,
            capture_output=True,
        )
        look = extract_log_item(completed.stdout, "look")
        presentation = extract_log_item(completed.stdout, "presentation_mode")
        expected_look = case.get("expected_look")
        row = {
            "name": case["name"],
            "command": cmd,
            "returncode": completed.returncode,
            "presentation_mode": presentation,
            "look": look,
            "expected_look": expected_look,
            "stdout_tail": completed.stdout.strip().splitlines()[-18:],
            "stderr_tail": completed.stderr.strip().splitlines()[-18:],
            "output": str(out),
        }
        expected_returncode = int(case.get("expected_returncode", 0))
        expected_stderr = case.get("expected_stderr")
        row["expected_returncode"] = expected_returncode
        row["expected_stderr"] = expected_stderr
        row["passed"] = completed.returncode == expected_returncode
        if expected_look is not None:
            row["passed"] = row["passed"] and look == expected_look
        if expected_stderr is not None:
            row["passed"] = row["passed"] and expected_stderr in completed.stderr
        rows.append(row)
        if not row["passed"]:
            failures.append(
                f"{case['name']}: expected returncode {expected_returncode}, "
                f"look {expected_look!r}, stderr token {expected_stderr!r}; "
                f"got returncode {completed.returncode}, look {look!r}"
            )

    report = {
        "phase": "Phase 1/5/6 run_pipeline look policy",
        "passed": not failures,
        "failures": failures,
        "rows": rows,
        "contract": [
            "camera-raw defaults to linear.",
            "camera-raw rejects non-linear user --look values.",
            "non-RAW explicit user --look values are preserved by their presentation routes.",
            "cinema may keep source-model filmic defaults.",
        ],
    }
    report_path = OUT_DIR / "look_policy_metrics.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "rows"}, indent=2, sort_keys=True))
    print(f"report={report_path}")
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
