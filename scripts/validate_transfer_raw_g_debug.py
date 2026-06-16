#!/usr/bin/env python3
"""Phase 3 raw g-factor renderer diagnostic.

This validator reads `--realism-debug raw-g` from the renderer's float
HDR32 intermediate instead of judging an 8-bit PNG ramp. It verifies that the
thin-disk transfer path can expose raw physical g-factor values for a no-flow
Schwarzschild fixture and that re-enabling orbital flow changes those raw
values. This is still not a same-tetrad flat-space proof; gravitational
redshift and lens geometry remain active in the rendered scene.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
from pathlib import Path
from typing import Any

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
RUN_PIPELINE = ROOT / "Blackhole" / "run_pipeline.sh"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--width", type=int, default=128)
    p.add_argument("--height", type=int, default=72)
    p.add_argument("--quality", default="preview")
    p.add_argument("--out-dir", default="/private/tmp/bh_transfer_raw_g_debug")
    p.add_argument("--no-build", action="store_true")
    return p.parse_args()


def run(cmd: list[str], env: dict[str, str]) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=str(ROOT), env=env, check=True)


def base_cmd(args: argparse.Namespace, png_out: Path, linear_out: Path, extra: list[str]) -> list[str]:
    cmd = [
        "bash",
        str(RUN_PIPELINE),
        "--source-model",
        "static-transfer-reference-v1",
        "--quality",
        args.quality,
        "--presentation",
        "scientific",
        "--look",
        "linear",
        "--width",
        str(args.width),
        "--height",
        str(args.height),
        "--realism-debug",
        "raw-g",
        "--linear32-intermediate",
        "--linear32-out",
        str(linear_out),
        "--output",
        str(png_out),
    ]
    cmd += extra
    return cmd


def cases() -> dict[str, list[str]]:
    return {
        "static_no_flow": [],
        "orbiting_control": [
            "--disk-orbital-boost",
            "0.80",
            "--disk-orbital-boost-inner",
            "0.80",
            "--disk-orbital-boost-outer",
            "0.80",
        ],
    }


def read_linear32(path: Path, width: int, height: int) -> np.ndarray:
    expected = width * height * 4
    data = np.fromfile(path, dtype="<f4")
    if data.size != expected:
        raise ValueError(f"{path} has {data.size} floats; expected {expected}")
    return data.reshape(height, width, 4)


def raw_g_stats(linear: np.ndarray) -> dict[str, float]:
    alpha = linear[..., 3]
    hit = alpha > 1.0
    rgb = linear[..., :3]
    g = rgb[..., 0][hit]
    channel_spread = np.max(np.abs(rgb[..., 0] - rgb[..., 1])) + np.max(np.abs(rgb[..., 0] - rgb[..., 2]))
    if g.size == 0:
        return {
            "hit_fraction": 0.0,
            "finite_fraction": 0.0,
            "channel_spread_max": float(channel_spread),
            "g_min": 0.0,
            "g_p05": 0.0,
            "g_median": 0.0,
            "g_mean": 0.0,
            "g_p95": 0.0,
            "g_max": 0.0,
            "g_std": 0.0,
        }
    finite = np.isfinite(g)
    gf = g[finite]
    return {
        "hit_fraction": float(np.mean(hit)),
        "finite_fraction": float(np.mean(finite)),
        "channel_spread_max": float(channel_spread),
        "g_min": float(np.min(gf)),
        "g_p05": float(np.percentile(gf, 5)),
        "g_median": float(np.median(gf)),
        "g_mean": float(np.mean(gf)),
        "g_p95": float(np.percentile(gf, 95)),
        "g_max": float(np.max(gf)),
        "g_std": float(np.std(gf)),
    }


def raw_g_rmse(a: np.ndarray, b: np.ndarray) -> float:
    hit = (a[..., 3] > 1.0) & (b[..., 3] > 1.0)
    if not np.any(hit):
        return 0.0
    d = a[..., 0][hit] - b[..., 0][hit]
    return float(np.sqrt(np.mean(d * d)))


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    env = os.environ.copy()
    env.setdefault("BH_DERIVED_DATA_PATH", str(out_dir / "DerivedData"))
    env.setdefault("BH_ETA_HISTORY", str(out_dir / "eta_history.json"))

    rendered: dict[str, dict[str, Path]] = {}
    first = True
    for name, extra in cases().items():
        case_dir = out_dir / name
        case_dir.mkdir(parents=True, exist_ok=True)
        png_out = case_dir / "raw_g_preview.png"
        linear_out = case_dir / "raw_g.linear32f32"
        cmd = base_cmd(args, png_out, linear_out, extra)
        if args.no_build or not first:
            cmd.append("--no-build")
        run(cmd, env)
        first = False
        rendered[name] = {"png": png_out, "linear": linear_out}
        (case_dir / "raw_g_command.json").write_text(json.dumps(cmd, indent=2), encoding="utf-8")

    arrays = {name: read_linear32(paths["linear"], args.width, args.height) for name, paths in rendered.items()}
    stats = {name: raw_g_stats(arr) for name, arr in arrays.items()}
    comparisons = {
        "static_to_orbiting_raw_g_rmse": raw_g_rmse(arrays["static_no_flow"], arrays["orbiting_control"]),
        "orbiting_g_std_over_static": stats["orbiting_control"]["g_std"] / max(stats["static_no_flow"]["g_std"], 1e-8),
    }

    gates = {
        "raw_g_cli_surface": "raw-g" in (ROOT / "Blackhole" / "Sources" / "Params" / "ParamsBuilderVisual.swift").read_text(encoding="utf-8"),
        "raw_g_shader_mode": "analysisMode == 43u" in (ROOT / "Blackhole" / "Metal" / "Compose" / "helpers.metalh").read_text(encoding="utf-8"),
        "static_has_hits": stats["static_no_flow"]["hit_fraction"] > 0.01,
        "orbiting_has_hits": stats["orbiting_control"]["hit_fraction"] > 0.01,
        "static_raw_g_finite": math.isclose(stats["static_no_flow"]["finite_fraction"], 1.0),
        "orbiting_raw_g_finite": math.isclose(stats["orbiting_control"]["finite_fraction"], 1.0),
        "raw_g_monochrome_float": max(s["channel_spread_max"] for s in stats.values()) < 1e-5,
        "static_g_plausible_range": 0.05 < stats["static_no_flow"]["g_p05"] < stats["static_no_flow"]["g_p95"] < 2.5,
        "orbiting_control_changes_raw_g": comparisons["static_to_orbiting_raw_g_rmse"] > 0.02,
    }
    report: dict[str, Any] = {
        "phase": "Phase 3 / L2 raw renderer g-factor diagnostic",
        "cases": stats,
        "comparisons": comparisons,
        "gates": gates,
        "passed": all(gates.values()),
        "outputs": {name: {k: str(v) for k, v in paths.items()} for name, paths in rendered.items()},
        "contract_gaps": [
            "raw-g exposes renderer g-factor values as float diagnostics.",
            "This is not a same-tetrad flat-space g ~= 1 proof because the rendered scene still includes Schwarzschild redshift and lens geometry.",
        ],
    }

    report_path = out_dir / "raw_g_debug_metrics.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    print(f"report={report_path}")
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
