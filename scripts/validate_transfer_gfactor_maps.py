#!/usr/bin/env python3
"""Phase 3 renderer-produced g-factor and beaming map baseline.

This validates the transfer diagnostic maps produced by the renderer. It is
not a beauty-image test: the gates inspect `--realism-debug g` and
`--realism-debug beaming` from low-Doppler, controlled baseline, and
high-Doppler cases.
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
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
RUN_PIPELINE = ROOT / "Blackhole" / "run_pipeline.sh"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--width", type=int, default=128)
    p.add_argument("--height", type=int, default=72)
    p.add_argument("--quality", default="preview")
    p.add_argument("--out-dir", default="/private/tmp/bh_transfer_gfactor_maps")
    p.add_argument("--no-build", action="store_true")
    return p.parse_args()


def run(cmd: list[str], env: dict[str, str]) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=str(ROOT), env=env, check=True)


def base_cmd(args: argparse.Namespace, out: Path, debug: str | None, extra: list[str]) -> list[str]:
    cmd = [
        "bash",
        str(RUN_PIPELINE),
        "--source-model",
        "physics-constrained-cinematic-disk-v1",
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
        "--output",
        str(out),
    ]
    if debug is not None:
        cmd += ["--realism-debug", debug]
    cmd += extra
    return cmd


def cases() -> dict[str, list[str]]:
    return {
        "low_doppler": [
            "--preset",
            "balanced",
            "--metric",
            "schwarzschild",
            "--spin",
            "0.0",
            "--disk-orbital-boost",
            "0.05",
            "--pcd-hot-crescent",
            "0.0",
        ],
        "baseline": [
            "--preset",
            "balanced",
            "--metric",
            "kerr",
            "--spin",
            "0.30",
            "--disk-orbital-boost",
            "0.65",
            "--pcd-hot-crescent",
            "0.20",
        ],
        "high_doppler": [
            "--preset",
            "eht",
            "--metric",
            "kerr",
            "--spin",
            "0.90",
            "--disk-orbital-boost",
            "1.28",
            "--pcd-hot-crescent",
            "0.75",
        ],
    }


def read_rgb(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def luma(path: Path) -> np.ndarray:
    rgb = read_rgb(path)
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def map_stats(path: Path) -> dict[str, float]:
    y = luma(path)
    h, w = y.shape
    left = float(np.sum(y[:, : w // 2]))
    right = float(np.sum(y[:, w // 2 :]))
    total = max(left + right, 1e-8)
    finite = np.isfinite(y)
    return {
        "mean": float(np.mean(y)),
        "p95": float(np.percentile(y, 95)),
        "active_fraction_02": float(np.mean(y > 0.02)),
        "active_fraction_08": float(np.mean(y > 0.08)),
        "left_luma": left,
        "right_luma": right,
        "signed_asymmetry": (right - left) / total,
        "abs_asymmetry": abs(left - right) / total,
        "finite_fraction": float(np.mean(finite)),
    }


def image_rmse(a: Path, b: Path) -> float:
    da = read_rgb(a)
    db = read_rgb(b)
    d = da - db
    return float(np.sqrt(np.mean(d * d)))


def contact_sheet(rendered: dict[str, dict[str, Path]], out: Path) -> None:
    cols = ["final", "g", "beaming"]
    rows = list(rendered.keys())
    cell_w, cell_h = 224, 126
    label_h = 28
    sheet = Image.new("RGB", (len(cols) * cell_w, len(rows) * (cell_h + label_h)), (0, 0, 0))
    for r, name in enumerate(rows):
        for c, key in enumerate(cols):
            canvas = Image.new("RGB", (cell_w, cell_h + label_h), (8, 8, 8))
            image = Image.open(rendered[name][key]).convert("RGB").resize((cell_w, cell_h))
            canvas.paste(image, (0, 0))
            draw = ImageDraw.Draw(canvas)
            draw.text((6, cell_h + 6), f"{name} / {key}", fill=(235, 235, 235))
            sheet.paste(canvas, (c * cell_w, r * (cell_h + label_h)))
    sheet.save(out)


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
        rendered[name] = {}
        for debug in [None, "g", "beaming"]:
            key = "final" if debug is None else debug
            out = case_dir / f"{key}.png"
            cmd = base_cmd(args, out, debug, extra)
            if args.no_build or not first:
                cmd.append("--no-build")
            run(cmd, env)
            first = False
            rendered[name][key] = out
            (case_dir / f"{key}_command.json").write_text(
                json.dumps(cmd, indent=2), encoding="utf-8"
            )

    report: dict[str, Any] = {
        "phase": "Phase 3 / L2 renderer g-factor map baseline",
        "cases": {},
        "comparisons": {},
        "gates": {},
    }
    for name, paths in rendered.items():
        report["cases"][name] = {
            "g": map_stats(paths["g"]),
            "beaming": map_stats(paths["beaming"]),
            "final": map_stats(paths["final"]),
        }

    low = report["cases"]["low_doppler"]
    baseline = report["cases"]["baseline"]
    high = report["cases"]["high_doppler"]
    low_asym = max(low["g"]["abs_asymmetry"], low["beaming"]["abs_asymmetry"])
    baseline_asym = max(baseline["g"]["abs_asymmetry"], baseline["beaming"]["abs_asymmetry"])
    high_asym = max(high["g"]["abs_asymmetry"], high["beaming"]["abs_asymmetry"])
    report["comparisons"] = {
        "low_to_high_g_rmse": image_rmse(rendered["low_doppler"]["g"], rendered["high_doppler"]["g"]),
        "low_to_high_beaming_rmse": image_rmse(rendered["low_doppler"]["beaming"], rendered["high_doppler"]["beaming"]),
        "g_rmse": image_rmse(rendered["baseline"]["g"], rendered["high_doppler"]["g"]),
        "beaming_rmse": image_rmse(rendered["baseline"]["beaming"], rendered["high_doppler"]["beaming"]),
        "final_rmse": image_rmse(rendered["baseline"]["final"], rendered["high_doppler"]["final"]),
        "low_doppler_g_or_beaming_abs_asymmetry": low_asym,
        "baseline_g_or_beaming_abs_asymmetry": baseline_asym,
        "high_doppler_g_or_beaming_abs_asymmetry": high_asym,
        "high_vs_low_doppler_asymmetry_ratio": high_asym / max(low_asym, 1e-6),
        "high_doppler_asymmetry_ratio": high_asym / max(baseline_asym, 1e-6),
    }

    comparisons = report["comparisons"]
    gates = {
        "finite_debug_maps": all(
            math.isclose(report["cases"][case][debug]["finite_fraction"], 1.0)
            for case in ["low_doppler", "baseline", "high_doppler"]
            for debug in ["g", "beaming"]
        ),
        "active_gfactor_maps": all(
            report["cases"][case]["g"]["active_fraction_02"] > 0.005
            for case in ["low_doppler", "baseline", "high_doppler"]
        ),
        "active_beaming_maps": all(
            report["cases"][case]["beaming"]["active_fraction_02"] > 0.005
            for case in ["low_doppler", "baseline", "high_doppler"]
        ),
        "high_doppler_changes_g_or_beaming": max(
            comparisons["g_rmse"], comparisons["beaming_rmse"]
        )
        > 0.010,
        "high_doppler_has_stronger_asymmetry": (
            comparisons["high_doppler_asymmetry_ratio"] > 1.15
            and comparisons["high_doppler_g_or_beaming_abs_asymmetry"] > 0.03
        ),
        "high_doppler_stronger_than_low_doppler": (
            comparisons["high_vs_low_doppler_asymmetry_ratio"] > 2.0
            and max(comparisons["low_to_high_g_rmse"], comparisons["low_to_high_beaming_rmse"]) > 0.010
        ),
    }
    report["gates"] = gates
    report["passed"] = all(gates.values())
    report["contract_gaps"] = [
        "This renderer gate uses the physics-constrained cinematic disk source only.",
        "The low-Doppler case is a renderer regression fixture, not a true static-emitter/static-observer source model.",
    ]

    sheet = out_dir / "gfactor_map_sheet.png"
    contact_sheet(rendered, sheet)
    report["contact_sheet"] = str(sheet)

    report_path = out_dir / "gfactor_map_metrics.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    print(f"report={report_path}")
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
