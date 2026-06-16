#!/usr/bin/env python3
"""Phase 6 presentation isolation across a source-model matrix.

This wraps validate_blackhole_presentation_invariance.py for multiple source
models so the Phase 6 boundary is not proven only on one canonical source.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SINGLE_SOURCE_VALIDATOR = ROOT / "scripts" / "validate_blackhole_presentation_invariance.py"

DEFAULT_SOURCES = [
    "canonical-visible-disk-v1",
    "thin-disk-visible-reference",
    "cinematic-physical-disk-v1",
    "physics-constrained-cinematic-disk-v1",
]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out-dir", default="/private/tmp/bh_presentation_source_matrix")
    p.add_argument("--source-model", action="append", dest="sources", default=[])
    p.add_argument("--width", type=int, default=96)
    p.add_argument("--height", type=int, default=54)
    p.add_argument("--quality", default="preview", choices=["preview", "hq"])
    p.add_argument("--no-build", action="store_true")
    return p.parse_args()


def run_source(args: argparse.Namespace, source: str, out_dir: Path, first: bool) -> dict[str, Any]:
    source_dir = out_dir / source
    source_dir.mkdir(parents=True, exist_ok=True)
    cmd = [
        sys.executable,
        str(SINGLE_SOURCE_VALIDATOR),
        "--source-model",
        source,
        "--out-dir",
        str(source_dir),
        "--width",
        str(args.width),
        "--height",
        str(args.height),
        "--quality",
        args.quality,
    ]
    if args.no_build or not first:
        cmd.append("--no-build")

    env = os.environ.copy()
    env.setdefault("BH_DERIVED_DATA_PATH", str(out_dir / "DerivedData"))
    env.setdefault("BH_ETA_HISTORY", str(out_dir / "eta_history.json"))
    print("+", " ".join(cmd), flush=True)
    completed = subprocess.run(cmd, cwd=str(ROOT), env=env, text=True, capture_output=True)
    metrics_path = source_dir / "blackhole_presentation_metrics.json"
    row: dict[str, Any] = {
        "source_model": source,
        "command": cmd,
        "returncode": completed.returncode,
        "stdout_tail": completed.stdout.strip().splitlines()[-20:],
        "stderr_tail": completed.stderr.strip().splitlines()[-20:],
        "metrics_path": str(metrics_path),
    }
    if completed.returncode != 0 or not metrics_path.exists():
        row["passed"] = False
        row["failure"] = "single-source presentation validator failed"
        return row
    metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
    row["passed"] = bool(metrics.get("passed", False))
    row["gates"] = metrics.get("gates", {})
    row["comparisons"] = metrics.get("comparisons", {})
    row["contact_sheet"] = metrics.get("contact_sheet", "")
    row["contract_gaps"] = metrics.get("contract_gaps", [])
    return row


def main() -> None:
    args = parse_args()
    sources = args.sources or DEFAULT_SOURCES
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    rows = [run_source(args, source, out_dir, first=(idx == 0)) for idx, source in enumerate(sources)]
    failures = [
        row["source_model"]
        for row in rows
        if not row.get("passed", False)
    ]
    report = {
        "phase": "Phase 6 source-model presentation isolation matrix",
        "passed": not failures,
        "width": args.width,
        "height": args.height,
        "quality": args.quality,
        "sources": sources,
        "source_count": len(sources),
        "failures": failures,
        "rows": rows,
        "contract_gaps": [
            "camera-raw still validates a RAW-like audit route, not a dedicated RAW buffer.",
            "This matrix covers recommended/candidate thin-disk style source models; GRMHD diagnostic data-backed paths remain separate promotion gates.",
        ],
    }
    report_path = out_dir / "presentation_source_matrix_metrics.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "rows"}, indent=2, sort_keys=True))
    print(f"report={report_path}")
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
