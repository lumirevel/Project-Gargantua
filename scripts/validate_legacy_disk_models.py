#!/usr/bin/env python3
"""Render and compare legacy disk model families.

The test intentionally uses the legacy thin disk path. Modern source-model
presets remain the recommended public interface, but explicit --disk-model
values must still preserve distinct historical procedural models.
Generated outputs are written outside the repository by default.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
from itertools import combinations
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
RUN_PIPELINE = ROOT / "Blackhole" / "run_pipeline.sh"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out-dir", default="/private/tmp/bh_legacy_disk_model_validation")
    p.add_argument("--width", type=int, default=80)
    p.add_argument("--height", type=int, default=45)
    p.add_argument("--quality", default="preview")
    p.add_argument("--min-rmse-distinct", type=float, default=0.003)
    p.add_argument("--min-mae-distinct", type=float, default=0.0015)
    p.add_argument("--no-build", action="store_true")
    return p.parse_args()


def run(cmd: list[str], env: dict[str, str]) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=str(ROOT), env=env, check=True)


def read_rgb(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def luma(rgb: np.ndarray) -> np.ndarray:
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def render_model(model: str, out_path: Path, no_build: bool, env: dict[str, str], width: int, height: int) -> None:
    cmd = [
        "bash", str(RUN_PIPELINE),
        "--disk-mode", "thin",
        "--disk-model", model,
        "--presentation", "scientific",
        "--look", "linear",
        "--background", "off",
        "--width", str(width),
        "--height", str(height),
        "--quality", "preview",
        "--output", str(out_path),
    ]
    if no_build:
        cmd.append("--no-build")
    run(cmd, env)


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.setdefault("BH_DERIVED_DATA_PATH", "/private/tmp/ProjectGargantuaLegacyDiskModelsDerivedData")
    env.setdefault("BH_ETA_HISTORY", str(out_dir / "eta_history.json"))

    models = ["flow", "procedural", "noise", "perlin", "perlin-classic", "perlin-ec7"]
    intended_aliases = {
        frozenset(("flow", "procedural")),
        frozenset(("flow", "noise")),
        frozenset(("procedural", "noise")),
    }
    paths: dict[str, Path] = {}
    images: dict[str, np.ndarray] = {}
    first = True
    for model in models:
        path = out_dir / f"{model}.png"
        render_model(
            model=model,
            out_path=path,
            no_build=(args.no_build or not first),
            env=env,
            width=args.width,
            height=args.height,
        )
        first = False
        paths[model] = path
        images[model] = read_rgb(path)

    model_stats = {}
    for model, img in images.items():
        y = luma(img)
        model_stats[model] = {
            "path": str(paths[model]),
            "sha256": sha256(paths[model]),
            "mean_luma": float(np.mean(y)),
            "p90_luma": float(np.percentile(y, 90.0)),
        }

    pair_stats = {}
    failures: list[str] = []
    for a, b in combinations(models, 2):
        diff = images[a] - images[b]
        mae = float(np.mean(np.abs(diff)))
        rmse = float(np.sqrt(np.mean(diff * diff)))
        same_hash = model_stats[a]["sha256"] == model_stats[b]["sha256"]
        key = f"{a}__{b}"
        alias_pair = frozenset((a, b)) in intended_aliases
        pair_stats[key] = {
            "mae": mae,
            "rmse": rmse,
            "same_hash": same_hash,
            "intended_alias": alias_pair,
        }
        if alias_pair:
            if not same_hash and rmse > args.min_rmse_distinct:
                failures.append(f"intended alias pair differs unexpectedly: {a} vs {b} rmse={rmse:.6f}")
        else:
            if same_hash or rmse < args.min_rmse_distinct or mae < args.min_mae_distinct:
                failures.append(f"distinct models collapsed: {a} vs {b} rmse={rmse:.6f} mae={mae:.6f}")

    result = {
        "passed": not failures,
        "models": model_stats,
        "pairs": pair_stats,
        "failures": failures,
        "thresholds": {
            "min_rmse_distinct": args.min_rmse_distinct,
            "min_mae_distinct": args.min_mae_distinct,
        },
    }
    (out_dir / "metrics.json").write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
