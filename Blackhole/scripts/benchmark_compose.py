#!/usr/bin/env python3
import argparse
import json
import os
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import List


@dataclass
class RunResult:
    backend: str
    run_index: int
    warmup: bool
    elapsed_sec: float
    return_code: int
    output_image: str
    stderr_tail: str


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Benchmark Blackhole compose backend speed/latency.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--runs", type=int, default=5, help="Measured runs per backend")
    p.add_argument("--warmup", type=int, default=1, help="Warmup runs per backend (excluded from stats)")
    p.add_argument("--width", type=int, default=1200)
    p.add_argument("--height", type=int, default=1200)
    p.add_argument("--ssaa", type=int, default=1, choices=[1, 2, 4])
    p.add_argument("--mode", type=str, default="fast", choices=["fast", "debug"])
    p.add_argument("--pipeline", type=str, default="./run_pipeline.sh", help="Path to run_pipeline.sh")
    p.add_argument("--out-dir", type=str, default="/tmp/bh_compose_bench")
    p.add_argument("--no-build", action="store_true", help="Pass --no-build to pipeline")
    p.add_argument(
        "--backend",
        type=str,
        default="both",
        choices=["both", "python", "gpu-match", "gpu-native", "gpu-hybrid"],
        help="Which backend(s) to benchmark",
    )
    p.add_argument(
        "--extra-args",
        nargs=argparse.REMAINDER,
        default=[],
        help="Extra args forwarded to run_pipeline.sh",
    )
    args, unknown = p.parse_known_args()
    if unknown:
        args.extra_args = list(args.extra_args) + unknown
    return args


def stats(values: List[float]) -> dict:
    if not values:
        return {"count": 0, "mean": None, "stdev": None, "median": None, "min": None, "max": None}
    return {
        "count": len(values),
        "mean": statistics.mean(values),
        "stdev": (statistics.stdev(values) if len(values) > 1 else 0.0),
        "median": statistics.median(values),
        "min": min(values),
        "max": max(values),
    }


def run_once(cmd: List[str], env: dict, log_path: Path) -> tuple[int, float, str]:
    t0 = time.perf_counter()
    proc = subprocess.run(cmd, capture_output=True, text=True, env=env)
    elapsed = time.perf_counter() - t0
    log_path.write_text(proc.stdout + "\n" + proc.stderr, encoding="utf-8", errors="replace")
    tail = "\n".join((proc.stdout + "\n" + proc.stderr).strip().splitlines()[-12:])
    return proc.returncode, elapsed, tail


def main() -> int:
    args = parse_args()
    if args.runs <= 0:
        print("error: --runs must be > 0", file=sys.stderr)
        return 2
    if args.warmup < 0:
        print("error: --warmup must be >= 0", file=sys.stderr)
        return 2

    pipeline = Path(args.pipeline).resolve()
    if not pipeline.exists():
        print(f"error: pipeline script not found: {pipeline}", file=sys.stderr)
        return 2

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.backend == "both":
        backends = ["python", "gpu-match", "gpu-native"]
    else:
        backends = [args.backend]
    results: List[RunResult] = []

    env = os.environ.copy()
    env["BH_ETA_RELAY"] = "none"

    print("== Compose Benchmark ==")
    print(f"pipeline   : {pipeline}")
    print(f"size       : {args.width}x{args.height} (ssaa={args.ssaa})")
    print(f"runs       : warmup={args.warmup}, measured={args.runs}")
    print(f"mode       : {args.mode}")
    if args.extra_args:
        print(f"extra args : {' '.join(args.extra_args)}")

    for backend in backends:
        print(f"\n-- backend={backend} --")
        total_runs = args.warmup + args.runs
        for i in range(total_runs):
            warmup = i < args.warmup
            tag = f"{backend}_{i+1}"
            image_out = out_dir / f"{tag}.png"
            log_out = out_dir / f"{tag}.log"

            compose_backend = "python" if backend == "python" else "gpu"
            cmd = [
                str(pipeline),
                "--compose",
                compose_backend,
                "--mode",
                args.mode,
                "--width",
                str(args.width),
                "--height",
                str(args.height),
                "--ssaa",
                str(args.ssaa),
                "--image-out",
                str(image_out),
            ]
            if backend == "gpu-native":
                cmd.append("--gpu-native")
            elif backend == "gpu-hybrid":
                cmd.append("--gpu-hybrid")
            elif backend == "gpu-match":
                cmd.append("--match-cpu")
            if args.no_build:
                cmd.append("--no-build")
            if args.extra_args:
                extra = args.extra_args
                if extra and extra[0] == "--":
                    extra = extra[1:]
                cmd.extend(extra)

            rc, elapsed, tail = run_once(cmd, env, log_out)
            results.append(
                RunResult(
                    backend=backend,
                    run_index=i + 1,
                    warmup=warmup,
                    elapsed_sec=elapsed,
                    return_code=rc,
                    output_image=str(image_out),
                    stderr_tail=tail,
                )
            )
            label = "warmup" if warmup else "measure"
            status = "OK" if rc == 0 else f"FAIL({rc})"
            print(f"{label:7s} run {i+1:02d}/{total_runs:02d}  {elapsed:8.3f}s  {status}")
            if rc != 0:
                print("recent output:")
                print(tail)
                break

    summary = {}
    for backend in backends:
        vals = [
            r.elapsed_sec
            for r in results
            if r.backend == backend and (not r.warmup) and r.return_code == 0
        ]
        summary[backend] = stats(vals)

    py_mean = summary.get("python", {}).get("mean")
    for key in ("gpu-match", "gpu-native", "gpu-hybrid"):
        g_mean = summary.get(key, {}).get("mean")
        if py_mean and g_mean and g_mean > 0:
            summary[f"speedup_python_over_{key}"] = py_mean / g_mean

    print("\n== Summary ==")
    for backend in backends:
        s = summary[backend]
        if not s["count"]:
            print(f"{backend:7s}: no successful measured runs")
            continue
        print(
            f"{backend:7s}: mean={s['mean']:.3f}s  stdev={s['stdev']:.3f}s  "
            f"median={s['median']:.3f}s  min={s['min']:.3f}s  max={s['max']:.3f}s  n={s['count']}"
        )
    for key in ("gpu-match", "gpu-native", "gpu-hybrid"):
        s = summary.get(f"speedup_python_over_{key}")
        if s is not None:
            print(f"speedup (python/{key}): {s:.2f}x")

    report = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "config": {
            "pipeline": str(pipeline),
            "width": args.width,
            "height": args.height,
            "ssaa": args.ssaa,
            "mode": args.mode,
            "runs": args.runs,
            "warmup": args.warmup,
            "no_build": args.no_build,
            "backend": args.backend,
            "extra_args": args.extra_args,
        },
        "summary": summary,
        "runs": [asdict(r) for r in results],
    }
    report_path = out_dir / "report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"report: {report_path}")

    # Return non-zero if any backend failed all measured runs.
    for backend in backends:
        measured_ok = any(
            (r.backend == backend and (not r.warmup) and r.return_code == 0) for r in results
        )
        if not measured_ok:
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
