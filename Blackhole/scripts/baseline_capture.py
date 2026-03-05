#!/usr/bin/env python3
"""Capture reproducible baseline artifacts for refactor regression checks."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


@dataclass
class RunResult:
    output_path: Path
    stdout_path: Path
    stderr_path: Path
    returncode: int
    wall_sec: float
    size_bytes: int
    sha256: str


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def _write_json(path: Path, obj: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2, sort_keys=True)


def _run_case(
    run_script: Path,
    args: list[str],
    output_path: Path,
    stdout_path: Path,
    stderr_path: Path,
) -> RunResult:
    cmd = [str(run_script), *args, "--output", str(output_path)]
    t0 = time.perf_counter()
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    dt = time.perf_counter() - t0

    stdout_path.parent.mkdir(parents=True, exist_ok=True)
    stderr_path.parent.mkdir(parents=True, exist_ok=True)
    stdout_path.write_text(proc.stdout, encoding="utf-8")
    stderr_path.write_text(proc.stderr, encoding="utf-8")

    if proc.returncode != 0:
        raise RuntimeError(f"command failed ({proc.returncode}): {' '.join(cmd)}")
    if not output_path.exists():
        raise RuntimeError(f"expected output missing: {output_path}")

    size = output_path.stat().st_size
    digest = _sha256(output_path)
    return RunResult(
        output_path=output_path,
        stdout_path=stdout_path,
        stderr_path=stderr_path,
        returncode=proc.returncode,
        wall_sec=dt,
        size_bytes=size,
        sha256=digest,
    )


def _image_metrics(compare_script: Path, reference: Path, candidate: Path, out_json: Path) -> dict[str, Any]:
    cmd = [
        sys.executable,
        str(compare_script),
        "--reference",
        str(reference),
        "--candidate",
        str(candidate),
        "--output-json",
        str(out_json),
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            "compare_images failed\n"
            f"cmd: {' '.join(cmd)}\n"
            f"stdout:\n{proc.stdout}\n"
            f"stderr:\n{proc.stderr}"
        )
    return _load_json(out_json)


def _ensure_binary(run_script: Path, root: Path) -> None:
    # Build once so later --no-build cases can run reliably.
    out = root / "tests" / "baseline" / "reports" / "_build_probe.png"
    cmd = [
        str(run_script),
        "--pipeline",
        "gpu-only",
        "--width",
        "64",
        "--height",
        "64",
        "--ssaa",
        "1",
        "--disk-mode",
        "thin",
        "--disk-model",
        "perlin",
        "--dither",
        "0",
        "--output",
        str(out),
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            "initial build probe failed\n"
            f"cmd: {' '.join(cmd)}\n"
            f"stdout:\n{proc.stdout}\n"
            f"stderr:\n{proc.stderr}"
        )
    if out.exists():
        out.unlink()


def main() -> None:
    ap = argparse.ArgumentParser(description="Capture baseline outputs and metadata for regression checks.")
    ap.add_argument("--manifest", default="tests/baseline/manifest.json")
    ap.add_argument("--report", default="tests/baseline/reports/baseline_report.json")
    ap.add_argument("--golden-dir", default="tests/baseline/golden")
    ap.add_argument("--work-dir", default="tests/baseline/reports/runs")
    ap.add_argument("--skip-build-probe", action="store_true")
    args = ap.parse_args()

    root = Path(__file__).resolve().parents[2]
    manifest_path = (root / args.manifest).resolve()
    report_path = (root / args.report).resolve()
    golden_dir = (root / args.golden_dir).resolve()
    work_dir = (root / args.work_dir).resolve()
    run_script = (root / "run_pipeline.sh").resolve()
    compare_script = (root / "Blackhole" / "scripts" / "compare_images.py").resolve()

    manifest = _load_json(manifest_path)
    cases: list[dict[str, Any]] = manifest.get("cases", [])
    if not cases:
        raise RuntimeError("manifest has no cases")

    if not args.skip_build_probe:
        _ensure_binary(run_script, root)

    golden_dir.mkdir(parents=True, exist_ok=True)
    work_dir.mkdir(parents=True, exist_ok=True)

    report_cases: list[dict[str, Any]] = []
    for case in cases:
        name = case["name"]
        out_ext = case.get("output_ext", "png")
        out1 = work_dir / f"{name}.run1.{out_ext}"
        out2 = work_dir / f"{name}.run2.{out_ext}"

        print(f"[capture] {name}: run #1")
        run1 = _run_case(
            run_script=run_script,
            args=list(case["args"]),
            output_path=out1,
            stdout_path=work_dir / f"{name}.run1.stdout.log",
            stderr_path=work_dir / f"{name}.run1.stderr.log",
        )

        print(f"[capture] {name}: run #2 (determinism probe)")
        run2 = _run_case(
            run_script=run_script,
            args=list(case["args"]),
            output_path=out2,
            stdout_path=work_dir / f"{name}.run2.stdout.log",
            stderr_path=work_dir / f"{name}.run2.stderr.log",
        )

        deterministic = run1.sha256 == run2.sha256
        metrics: dict[str, Any] | None = None
        metric_json = work_dir / f"{name}.run_diff_metrics.json"
        if not deterministic:
            metrics = _image_metrics(compare_script, run1.output_path, run2.output_path, metric_json)

        golden_path = golden_dir / f"{name}.{out_ext}"
        shutil.copy2(run1.output_path, golden_path)

        case_report: dict[str, Any] = {
            "name": name,
            "args": list(case["args"]),
            "output_ext": out_ext,
            "golden": str(golden_path),
            "deterministic": deterministic,
            "run1": {
                "stdout": str(run1.stdout_path),
                "stderr": str(run1.stderr_path),
                "wall_sec": run1.wall_sec,
                "size_bytes": run1.size_bytes,
                "sha256": run1.sha256,
            },
            "run2": {
                "stdout": str(run2.stdout_path),
                "stderr": str(run2.stderr_path),
                "wall_sec": run2.wall_sec,
                "size_bytes": run2.size_bytes,
                "sha256": run2.sha256,
            },
        }
        if metrics is not None:
            case_report["run12_metrics"] = {
                "report": str(metric_json),
                "max_abs": metrics.get("max_abs"),
                "rmse": metrics.get("rmse"),
                "psnr_db": metrics.get("psnr_db"),
            }

        if case.get("perf_anchor"):
            warmup_runs = int(case.get("perf_warmup_runs", 1))
            measured_runs = int(case.get("perf_measured_runs", 5))
            print(f"[capture] {name}: performance anchor warmup={warmup_runs} measured={measured_runs}")
            perf_times: list[float] = []
            for idx in range(warmup_runs + measured_runs):
                out_perf = work_dir / f"{name}.perf{idx}.{out_ext}"
                perf = _run_case(
                    run_script=run_script,
                    args=list(case["args"]),
                    output_path=out_perf,
                    stdout_path=work_dir / f"{name}.perf{idx}.stdout.log",
                    stderr_path=work_dir / f"{name}.perf{idx}.stderr.log",
                )
                if idx >= warmup_runs:
                    perf_times.append(perf.wall_sec)
            mean_t = statistics.mean(perf_times)
            std_t = statistics.pstdev(perf_times) if len(perf_times) > 1 else 0.0
            case_report["perf_anchor"] = {
                "warmup_runs": warmup_runs,
                "measured_runs": measured_runs,
                "times_sec": perf_times,
                "mean_sec": mean_t,
                "std_sec": std_t,
                "max_allowed_factor": float(case.get("perf_regression_factor", 1.03)),
            }

        report_cases.append(case_report)

    out: dict[str, Any] = {
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "repo_root": str(root),
        "manifest": str(manifest_path),
        "cases": report_cases,
        "thresholds": manifest.get("thresholds", {}),
    }
    _write_json(report_path, out)
    print(f"[capture] wrote {report_path}")


if __name__ == "__main__":
    main()
