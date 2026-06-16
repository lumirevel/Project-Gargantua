#!/usr/bin/env python3
"""Optional GRMHD data-backed presentation isolation gate.

This is intentionally separate from the fast Phase 6 source matrix because the
GRMHD snapshot conversion/cache path is much heavier than analytic thin-disk
source renders. When the configured HDF5 snapshot exists, the script runs the
same presentation-isolation validator against a data-backed GRMHD diagnostic
source.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SINGLE_SOURCE_VALIDATOR = ROOT / "scripts" / "validate_blackhole_presentation_invariance.py"
DEFAULT_HDF5 = Path("/private/tmp/bh_real_grmhd_sequence/SANE_a0_torus.out0.05010.h5")
DEFAULT_SUITE_HDF5 = [
    DEFAULT_HDF5,
    Path("/private/tmp/bh-march-grmhd-repro/cache/sample.h5"),
]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--disk-hdf5", default=str(DEFAULT_HDF5))
    p.add_argument("--out-dir", default="/private/tmp/bh_grmhd_presentation_fixture")
    p.add_argument("--source-model", default="grmhd-temperature-flow-diagnostic")
    p.add_argument("--width", type=int, default=64)
    p.add_argument("--height", type=int, default=36)
    p.add_argument("--quality", default="preview", choices=["preview", "hq"])
    p.add_argument("--no-build", action="store_true")
    p.add_argument("--require-data", action="store_true")
    p.add_argument("--suite", action="store_true", help="run a data-backed fixture suite instead of one snapshot")
    p.add_argument("--suite-disk-hdf5", action="append", default=[], help="extra HDF5 snapshot for --suite")
    p.add_argument("--suite-min-count", type=int, default=2)
    return p.parse_args()


def skipped_report(args: argparse.Namespace, snapshot: Path, reason: str) -> dict[str, Any]:
    return {
        "phase": "Phase 6 optional GRMHD data-backed presentation fixture",
        "passed": True,
        "skipped": True,
        "skip_reason": reason,
        "disk_hdf5": str(snapshot),
        "source_model": args.source_model,
        "contract_gaps": [
            "This optional gate is skipped when the local GRMHD HDF5 snapshot is unavailable.",
            "camera-raw still validates a RAW-like audit route, not a dedicated RAW buffer.",
        ],
    }


def safe_label(path: Path) -> str:
    stem = re.sub(r"[^A-Za-z0-9_.-]+", "_", path.name)
    return stem[:96] or "snapshot"


def hdf5_summary(path: Path) -> dict[str, Any]:
    summary: dict[str, Any] = {
        "path": str(path),
        "byte_count": path.stat().st_size if path.exists() else 0,
    }
    try:
        import h5py  # type: ignore

        with h5py.File(path, "r") as h5:
            keys = list(h5.keys())
            summary["top_level_keys"] = keys[:20]
            if "prims" in h5:
                summary["schema_hint"] = "iharm-prims"
                summary["primary_shape"] = list(h5["prims"].shape)
            elif "rho" in h5:
                summary["schema_hint"] = "converted-fm-torus"
                summary["primary_shape"] = list(h5["rho"].shape)
            else:
                summary["schema_hint"] = "unknown"
    except Exception as exc:  # pragma: no cover - optional metadata only
        summary["schema_hint"] = "unreadable"
        summary["summary_error"] = str(exc)
    return summary


def run_snapshot(args: argparse.Namespace, snapshot: Path, out_dir: Path, no_build: bool) -> dict[str, Any]:
    cmd = [
        sys.executable,
        str(SINGLE_SOURCE_VALIDATOR),
        "--source-model",
        args.source_model,
        "--out-dir",
        str(out_dir),
        "--width",
        str(args.width),
        "--height",
        str(args.height),
        "--quality",
        args.quality,
        "--extra",
        "--disk-hdf5",
        str(snapshot),
    ]
    if no_build:
        cmd.append("--no-build")

    env = os.environ.copy()
    env.setdefault("BH_DERIVED_DATA_PATH", str(out_dir.parent / "DerivedData"))
    env.setdefault("BH_ETA_HISTORY", str(out_dir.parent / "eta_history.json"))
    print("+", " ".join(cmd), flush=True)
    completed = subprocess.run(cmd, cwd=str(ROOT), env=env, text=True, capture_output=True)
    metrics_path = out_dir / "blackhole_presentation_metrics.json"
    row: dict[str, Any] = {
        "disk_hdf5": str(snapshot),
        "hdf5_summary": hdf5_summary(snapshot),
        "source_model": args.source_model,
        "command": cmd,
        "returncode": completed.returncode,
        "stdout_tail": completed.stdout.strip().splitlines()[-30:],
        "stderr_tail": completed.stderr.strip().splitlines()[-30:],
        "metrics_path": str(metrics_path),
        "skipped": False,
    }
    if completed.returncode != 0 or not metrics_path.exists():
        row["passed"] = False
        row["failure"] = "GRMHD presentation validator failed"
    else:
        metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
        row["passed"] = bool(metrics.get("passed", False))
        row["gates"] = metrics.get("gates", {})
        row["comparisons"] = metrics.get("comparisons", {})
        row["contact_sheet"] = metrics.get("contact_sheet", "")
        row["contract_gaps"] = [
            "camera-raw sidecar validation is covered by scripts/validate_camera_raw_sidecar.py.",
            "This GRMHD fixture checks presentation isolation, not physical calibration quality of each snapshot.",
        ]
    return row


def unique_existing(paths: list[Path]) -> list[Path]:
    seen: set[str] = set()
    out: list[Path] = []
    for path in paths:
        resolved = str(path.resolve()) if path.exists() else str(path)
        if resolved in seen or not path.exists():
            continue
        seen.add(resolved)
        out.append(path)
    return out


def suite_paths(args: argparse.Namespace) -> list[Path]:
    paths = DEFAULT_SUITE_HDF5 + [Path(p) for p in args.suite_disk_hdf5]
    return unique_existing(paths)


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    report_path = out_dir / "grmhd_presentation_fixture_metrics.json"

    if args.suite:
        snapshots = suite_paths(args)
        if len(snapshots) < args.suite_min_count:
            report = {
                "phase": "Phase 6 GRMHD data-backed presentation fixture suite",
                "passed": not args.require_data,
                "skipped": True,
                "skip_reason": f"need at least {args.suite_min_count} HDF5 snapshots, found {len(snapshots)}",
                "available_snapshots": [str(p) for p in snapshots],
                "contract_gaps": [
                    "The suite gate requires multiple local GRMHD/HDF5 snapshots to prove more than one data-backed path.",
                ],
            }
            report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
            print(json.dumps(report, indent=2, sort_keys=True))
            print(f"report={report_path}")
            if args.require_data:
                raise SystemExit(1)
            return
        rows = [
            run_snapshot(args, snapshot, out_dir / safe_label(snapshot), no_build=(args.no_build or idx > 0))
            for idx, snapshot in enumerate(snapshots)
        ]
        failures = [row["disk_hdf5"] for row in rows if not row.get("passed", False)]
        schema_hints = sorted({row.get("hdf5_summary", {}).get("schema_hint", "unknown") for row in rows})
        report = {
            "phase": "Phase 6 GRMHD data-backed presentation fixture suite",
            "passed": not failures,
            "skipped": False,
            "source_model": args.source_model,
            "width": args.width,
            "height": args.height,
            "quality": args.quality,
            "snapshot_count": len(rows),
            "schema_hints": schema_hints,
            "failures": failures,
            "rows": rows,
            "contract_gaps": [
                "This suite validates presentation isolation across local GRMHD/HDF5 fixtures; named paper-reference calibration remains future validation work.",
            ],
        }
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
        print(json.dumps({k: v for k, v in report.items() if k != "rows"}, indent=2, sort_keys=True))
        print(f"report={report_path}")
        if failures:
            raise SystemExit(1)
        return

    snapshot = Path(args.disk_hdf5)
    if not snapshot.exists():
        report = skipped_report(args, snapshot, "disk HDF5 snapshot not found")
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
        print(json.dumps(report, indent=2, sort_keys=True))
        print(f"report={report_path}")
        if args.require_data:
            raise SystemExit(1)
        return

    row = run_snapshot(args, snapshot, out_dir / args.source_model, no_build=args.no_build)
    row["phase"] = "Phase 6 optional GRMHD data-backed presentation fixture"
    report_path.write_text(json.dumps(row, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(row, indent=2, sort_keys=True))
    print(f"report={report_path}")
    if not row["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
