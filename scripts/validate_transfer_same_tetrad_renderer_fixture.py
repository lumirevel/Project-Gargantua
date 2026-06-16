#!/usr/bin/env python3
"""Phase 3 same-tetrad renderer diagnostic fixture.

This validator exercises `--realism-debug same-tetrad-g` through the renderer's
float32 output path. It is not a beauty image and not a physical scene override:
the analysis mode exposes the local reference case u_emit == u_obs, where
g = (k_mu u_obs^mu) / (k_mu u_emit^mu) must be exactly 1.
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
    p.add_argument("--width", type=int, default=96)
    p.add_argument("--height", type=int, default=54)
    p.add_argument("--quality", default="preview")
    p.add_argument("--out-dir", default="/private/tmp/bh_transfer_same_tetrad_renderer_fixture")
    p.add_argument("--no-build", action="store_true")
    return p.parse_args()


def read_linear32(path: Path, width: int, height: int) -> np.ndarray:
    expected = width * height * 4
    data = np.fromfile(path, dtype="<f4")
    if data.size != expected:
        raise ValueError(f"{path} has {data.size} floats; expected {expected}")
    return data.reshape(height, width, 4)


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    png_out = out_dir / "same_tetrad_g_preview.png"
    linear_out = out_dir / "same_tetrad_g.linear32f32"
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
        "same-tetrad-g",
        "--linear32-intermediate",
        "--linear32-out",
        str(linear_out),
        "--output",
        str(png_out),
    ]
    if args.no_build:
        cmd.append("--no-build")

    env = os.environ.copy()
    env.setdefault("BH_DERIVED_DATA_PATH", str(out_dir / "DerivedData"))
    env.setdefault("BH_ETA_HISTORY", str(out_dir / "eta_history.json"))

    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=str(ROOT), env=env, check=True)

    linear = read_linear32(linear_out, args.width, args.height)
    hit = linear[..., 3] > 1.0
    rgb = linear[..., :3]
    hit_rgb = rgb[hit]
    finite = np.isfinite(hit_rgb)
    max_abs_error = float(np.max(np.abs(hit_rgb - 1.0))) if hit_rgb.size else math.inf
    channel_spread = float(
        max(
            np.max(np.abs(rgb[..., 0] - rgb[..., 1])),
            np.max(np.abs(rgb[..., 0] - rgb[..., 2])),
        )
    )

    gates = {
        "same_tetrad_cli_surface": "same-tetrad-g" in (ROOT / "Blackhole" / "Sources" / "Params" / "ParamsBuilderVisual.swift").read_text(encoding="utf-8"),
        "same_tetrad_shader_mode": "analysisMode == 44u" in (ROOT / "Blackhole" / "Metal" / "Compose" / "helpers.metalh").read_text(encoding="utf-8"),
        "same_tetrad_linear_direct_safe": "config.composeAnalysisMode <= 44" in (ROOT / "Blackhole" / "Sources" / "Render" / "Core" / "RenderResourcePolicy.swift").read_text(encoding="utf-8"),
        "has_renderer_hits": float(np.mean(hit)) > 0.01,
        "same_tetrad_g_finite": bool(hit_rgb.size and np.all(finite)),
        "same_tetrad_g_is_one": max_abs_error <= 1e-6,
        "same_tetrad_rgb_channels_match": channel_spread <= 1e-6,
    }
    report: dict[str, Any] = {
        "phase": "Phase 3 / L2 same-tetrad renderer fixture",
        "passed": all(gates.values()),
        "gates": gates,
        "stats": {
            "hit_fraction": float(np.mean(hit)),
            "max_abs_error_from_one": max_abs_error,
            "channel_spread_max": channel_spread,
        },
        "command": cmd,
        "outputs": {
            "png": str(png_out),
            "linear32": str(linear_out),
        },
        "contract_notes": [
            "The physical scene g-factor remains available through --realism-debug raw-g.",
            "same-tetrad-g is an isolated analysis fixture for u_emit == u_obs and does not affect radiance, camera, or cinematic output.",
        ],
        "contract_gaps": [],
    }

    report_path = out_dir / "same_tetrad_renderer_fixture_metrics.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    print(f"report={report_path}")
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
