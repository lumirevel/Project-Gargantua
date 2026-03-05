#!/usr/bin/env python3
"""Verify current outputs against captured baseline artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class CaseResult:
    name: str
    passed: bool
    message: str
    wall_sec: float


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def _run_case(run_script: Path, args: list[str], output_path: Path) -> tuple[int, float, str, str]:
    cmd = [str(run_script), *args, "--output", str(output_path)]
    t0 = time.perf_counter()
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    dt = time.perf_counter() - t0
    return proc.returncode, dt, proc.stdout, proc.stderr


def _compare_images(compare_script: Path, reference: Path, candidate: Path, out_json: Path) -> dict[str, Any]:
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


def _find_case(report: dict[str, Any], name: str) -> dict[str, Any]:
    for case in report.get("cases", []):
        if case.get("name") == name:
            return case
    raise KeyError(f"case {name} not found in report")


def main() -> None:
    ap = argparse.ArgumentParser(description="Verify render outputs against baseline report/goldens.")
    ap.add_argument("--manifest", default="tests/baseline/manifest.json")
    ap.add_argument("--baseline-report", default="tests/baseline/reports/baseline_report.json")
    ap.add_argument("--work-dir", default="tests/baseline/reports/verify_runs")
    ap.add_argument("--case", default="all", help="case name or 'all'")
    ap.add_argument("--json-out", default="")
    args = ap.parse_args()

    root = Path(__file__).resolve().parents[2]
    manifest_path = (root / args.manifest).resolve()
    baseline_report_path = (root / args.baseline_report).resolve()
    work_dir = (root / args.work_dir).resolve()
    run_script = (root / "run_pipeline.sh").resolve()
    compare_script = (root / "Blackhole" / "scripts" / "compare_images.py").resolve()

    manifest = _load_json(manifest_path)
    baseline = _load_json(baseline_report_path)
    thresholds = manifest.get("thresholds", {}).get("nondeterministic", {})
    max_abs_limit = float(thresholds.get("max_abs_diff", 2.0))
    min_psnr = float(thresholds.get("min_psnr_db", 60.0))
    max_size_delta_ratio = float(thresholds.get("max_size_delta_ratio", 0.01))

    cases = manifest.get("cases", [])
    if args.case != "all":
        cases = [c for c in cases if c.get("name") == args.case]
        if not cases:
            raise RuntimeError(f"unknown case: {args.case}")

    work_dir.mkdir(parents=True, exist_ok=True)
    results: list[CaseResult] = []
    perf_fail = None
    perf_summary: dict[str, Any] = {}

    for case in cases:
        name = str(case["name"])
        out_ext = case.get("output_ext", "png")
        report_case = _find_case(baseline, name)
        golden = Path(report_case["golden"]).resolve()
        out_path = work_dir / f"{name}.verify.{out_ext}"

        rc, wall, stdout, stderr = _run_case(run_script, list(case["args"]), out_path)
        (work_dir / f"{name}.stdout.log").write_text(stdout, encoding="utf-8")
        (work_dir / f"{name}.stderr.log").write_text(stderr, encoding="utf-8")

        if rc != 0:
            results.append(CaseResult(name=name, passed=False, message=f"render failed rc={rc}", wall_sec=wall))
            continue
        if not out_path.exists():
            results.append(CaseResult(name=name, passed=False, message="output missing", wall_sec=wall))
            continue

        deterministic = bool(report_case.get("deterministic", False))
        base_size = int(report_case["run1"]["size_bytes"])
        cur_size = out_path.stat().st_size

        if deterministic:
            expected = str(report_case["run1"]["sha256"])
            got = _sha256(out_path)
            passed = expected == got
            msg = "hash match" if passed else f"hash mismatch expected={expected[:12]} got={got[:12]}"
            results.append(CaseResult(name=name, passed=passed, message=msg, wall_sec=wall))
        else:
            metric_json = work_dir / f"{name}.metrics.json"
            metrics = _compare_images(compare_script, golden, out_path, metric_json)
            max_abs = float(metrics.get("max_abs", 1e9))
            psnr = metrics.get("psnr_db")
            psnr_ok = (psnr is None) or (float(psnr) >= min_psnr)
            max_abs_ok = max_abs <= max_abs_limit
            size_ratio = abs(cur_size - base_size) / max(base_size, 1)
            size_ok = size_ratio <= max_size_delta_ratio
            passed = max_abs_ok and psnr_ok and size_ok
            msg = (
                f"max_abs={max_abs:.3f} (<= {max_abs_limit:.3f}), "
                f"psnr={'inf' if psnr is None else f'{float(psnr):.3f}'} (>= {min_psnr:.3f}), "
                f"size_delta={size_ratio*100:.3f}% (<= {max_size_delta_ratio*100:.3f}%)"
            )
            results.append(CaseResult(name=name, passed=passed, message=msg, wall_sec=wall))

        # Performance gate: run in manifest order right after the anchor case check.
        # This mirrors baseline_capture ordering and reduces thermal ordering bias.
        if case.get("perf_anchor") and perf_fail is None and not perf_summary:
            anchor = report_case.get("perf_anchor")
            if not anchor:
                perf_fail = f"baseline report missing perf_anchor for case {name}"
            else:
                warmup_runs = int(anchor.get("warmup_runs", case.get("perf_warmup_runs", 1)))
                measured_runs = int(anchor.get("measured_runs", case.get("perf_measured_runs", 5)))
                max_factor = float(anchor.get("max_allowed_factor", case.get("perf_regression_factor", 1.03)))
                baseline_mean = float(anchor["mean_sec"])
                times: list[float] = []
                out_ext = case.get("output_ext", "png")
                for i in range(warmup_runs + measured_runs):
                    perf_out_path = work_dir / f"{name}.perf_verify{i}.{out_ext}"
                    prc, pwall, pstdout, pstderr = _run_case(run_script, list(case["args"]), perf_out_path)
                    (work_dir / f"{name}.perf_verify{i}.stdout.log").write_text(pstdout, encoding="utf-8")
                    (work_dir / f"{name}.perf_verify{i}.stderr.log").write_text(pstderr, encoding="utf-8")
                    if prc != 0:
                        perf_fail = f"perf run failed rc={prc} at iteration {i}"
                        break
                    if i >= warmup_runs:
                        times.append(pwall)
                if perf_fail is None:
                    cur_mean = statistics.mean(times)
                    limit = baseline_mean * max_factor
                    perf_summary = {
                        "case": name,
                        "baseline_mean_sec": baseline_mean,
                        "current_mean_sec": cur_mean,
                        "max_factor": max_factor,
                        "limit_sec": limit,
                        "measured_runs": measured_runs,
                        "times_sec": times,
                    }
                    if cur_mean > limit:
                        perf_fail = f"perf regression: mean={cur_mean:.4f}s > limit={limit:.4f}s"

    all_pass = all(r.passed for r in results) and perf_fail is None

    for r in results:
        status = "PASS" if r.passed else "FAIL"
        print(f"[{status}] {r.name} {r.message} wall={r.wall_sec:.3f}s")
    if perf_summary:
        print(
            "[PERF] "
            f"{perf_summary['case']} baseline={perf_summary['baseline_mean_sec']:.4f}s "
            f"current={perf_summary['current_mean_sec']:.4f}s "
            f"limit={perf_summary['limit_sec']:.4f}s"
        )
    if perf_fail:
        print(f"[FAIL] performance {perf_fail}")

    out_report = {
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "manifest": str(manifest_path),
        "baseline_report": str(baseline_report_path),
        "results": [
            {
                "name": r.name,
                "passed": r.passed,
                "message": r.message,
                "wall_sec": r.wall_sec,
            }
            for r in results
        ],
        "performance": perf_summary,
        "performance_failed": perf_fail,
        "passed": all_pass,
    }
    if args.json_out:
        out_path = (root / args.json_out).resolve()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with out_path.open("w", encoding="utf-8") as f:
            json.dump(out_report, f, ensure_ascii=False, indent=2, sort_keys=True)
        print(f"[verify] wrote {out_path}")

    raise SystemExit(0 if all_pass else 2)


if __name__ == "__main__":
    main()
