#!/usr/bin/env python3
"""Extreme A/B validation for physics-constrained-cinematic-disk-v1.

This script validates source-model functionality, not presentation quality. It
renders physically meaningful extremes and verifies that source diagnostics and
final RGB respond to those controls.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
RUN_PIPELINE = ROOT / "Blackhole" / "run_pipeline.sh"

DIAGNOSTICS = [
    "density",
    "temperature",
    "emissivity-pre-transfer",
    "opacity",
    "optical-depth",
    "transfer-saturation",
    "activity",
    "spiral",
    "clump",
    "hot-crescent",
    "g",
    "beaming",
    "raw-radiance",
    "final-rgb",
]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--width", type=int, default=160)
    p.add_argument("--height", type=int, default=90)
    p.add_argument("--out-dir", default="/private/tmp/bh_pcd_goal_validation")
    p.add_argument("--quality", default="preview")
    p.add_argument("--no-build", action="store_true")
    p.add_argument("--extra", nargs=argparse.REMAINDER, default=[])
    return p.parse_args()


def run(cmd: list[str], env: dict[str, str]) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=str(ROOT), env=env, check=True)


def base_cmd(args: argparse.Namespace, out: Path, preset: str, debug: str | None = None) -> list[str]:
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
    if preset:
        cmd += ["--preset", preset]
    if debug:
        cmd += ["--realism-debug", debug]
    cmd += args.extra
    return cmd


def presets() -> dict[str, dict[str, object]]:
    return {
        "no_structure": {
            "preset": "balanced",
            "args": [
                "--disk-turbulence", "0",
                "--pcd-structure-scale", "0.2",
                "--pcd-spiral-amp", "0",
                "--pcd-clump-contrast", "0",
                "--pcd-hot-crescent", "0",
                "--pcd-opacity-scale", "1",
            ],
        },
        "high_structure": {
            "preset": "balanced",
            "args": [
                "--disk-turbulence", "2.4",
                "--pcd-structure-scale", "2.2",
                "--pcd-spiral-amp", "0.85",
                "--pcd-clump-contrast", "0.85",
                "--pcd-hot-crescent", "0.85",
            ],
        },
        "high_tau": {
            "preset": "balanced",
            "args": ["--pcd-opacity-scale", "4.0"],
        },
        "low_tau": {
            "preset": "balanced",
            "args": ["--pcd-opacity-scale", "0.20"],
        },
        "high_doppler": {
            "preset": "eht",
            "args": [
                "--metric", "kerr",
                "--spin", "0.90",
                "--disk-orbital-boost", "1.28",
                "--pcd-hot-crescent", "0.75",
            ],
        },
    }


def read_rgb(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def luma(rgb: np.ndarray) -> np.ndarray:
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def rmse(a: Path, b: Path) -> float:
    da = read_rgb(a)
    db = read_rgb(b)
    d = da - db
    return float(np.sqrt(np.mean(d * d)))


def mean_luma(path: Path) -> float:
    return float(np.mean(luma(read_rgb(path))))


def active_fraction(path: Path, threshold: float = 0.08) -> float:
    y = luma(read_rgb(path))
    return float(np.mean(y > threshold))


def asymmetry(path: Path) -> float:
    y = luma(read_rgb(path))
    h, w = y.shape
    left = float(np.sum(y[:, : w // 2]))
    right = float(np.sum(y[:, w // 2 :]))
    return abs(left - right) / max(left + right, 1e-8)


def contact_sheet(paths: dict[str, dict[str, Path]], out_path: Path) -> None:
    cols = ["final", "density", "emissivity-pre-transfer", "activity", "optical-depth", "transfer-saturation", "g"]
    cell_w, cell_h = 210, 140
    label_h = 34
    rows = list(paths.keys())
    sheet = Image.new("RGB", (len(cols) * cell_w, len(rows) * (cell_h + label_h)), (0, 0, 0))
    for r, name in enumerate(rows):
        for c, key in enumerate(cols):
            path = paths[name]["final"] if key == "final" else paths[name].get(key)
            canvas = Image.new("RGB", (cell_w, cell_h + label_h), (8, 8, 8))
            if path and path.exists():
                im = Image.open(path).convert("RGB").resize((cell_w, cell_h))
                canvas.paste(im, (0, 0))
            draw = ImageDraw.Draw(canvas)
            draw.text((5, cell_h + 4), f"{name}\n{key}", fill=(235, 235, 235))
            sheet.paste(canvas, (c * cell_w, r * (cell_h + label_h)))
    sheet.save(out_path)


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.setdefault("BH_DERIVED_DATA_PATH", "/private/tmp/ProjectGargantuaPcdGoalDerivedData")
    env.setdefault("BH_ETA_HISTORY", str(out_dir / "eta_history.json"))

    rendered: dict[str, dict[str, Path]] = {}
    first = True
    for name, spec in presets().items():
        preset = str(spec["preset"])
        extra_args = list(spec["args"])
        pdir = out_dir / name
        pdir.mkdir(parents=True, exist_ok=True)
        rendered[name] = {}

        final = pdir / "final.png"
        cmd = base_cmd(args, final, preset)
        cmd += extra_args
        if args.no_build or not first:
            cmd.append("--no-build")
        first = False
        run(cmd, env)
        rendered[name]["final"] = final
        (pdir / "final_command.json").write_text(json.dumps(cmd, indent=2), encoding="utf-8")

        for debug in DIAGNOSTICS:
            path = pdir / f"{debug}.png"
            cmd = base_cmd(args, path, preset, debug)
            cmd += extra_args
            cmd.append("--no-build")
            run(cmd, env)
            rendered[name][debug] = path

    metrics: dict[str, object] = {
        "presets": {},
        "comparisons": {},
        "gates": {},
    }
    for name, paths in rendered.items():
        metrics["presets"][name] = {
            "final_mean_luma": mean_luma(paths["final"]),
            "activity_mean_luma": mean_luma(paths["activity"]),
            "emissivity_mean_luma": mean_luma(paths["emissivity-pre-transfer"]),
            "optical_depth_mean_luma": mean_luma(paths["optical-depth"]),
            "transfer_saturation_mean_luma": mean_luma(paths["transfer-saturation"]),
            "g_asymmetry": asymmetry(paths["g"]),
            "beaming_asymmetry": asymmetry(paths["beaming"]),
            "transfer_saturation_active_fraction": active_fraction(paths["transfer-saturation"], 0.35),
        }

    cmp = metrics["comparisons"]
    cmp["no_vs_high_activity_rmse"] = rmse(rendered["no_structure"]["activity"], rendered["high_structure"]["activity"])
    cmp["no_vs_high_emissivity_rmse"] = rmse(rendered["no_structure"]["emissivity-pre-transfer"], rendered["high_structure"]["emissivity-pre-transfer"])
    cmp["no_vs_high_density_rmse"] = rmse(rendered["no_structure"]["density"], rendered["high_structure"]["density"])
    cmp["no_vs_high_final_rmse"] = rmse(rendered["no_structure"]["final"], rendered["high_structure"]["final"])
    cmp["high_vs_low_tau_optical_depth_rmse"] = rmse(rendered["high_tau"]["optical-depth"], rendered["low_tau"]["optical-depth"])
    cmp["high_vs_low_tau_transfer_saturation_mean_diff"] = abs(
        mean_luma(rendered["high_tau"]["transfer-saturation"]) - mean_luma(rendered["low_tau"]["transfer-saturation"])
    )
    baseline_asym = max(asymmetry(rendered["no_structure"]["g"]), asymmetry(rendered["no_structure"]["beaming"]))
    doppler_asym = max(asymmetry(rendered["high_doppler"]["g"]), asymmetry(rendered["high_doppler"]["beaming"]))
    cmp["baseline_g_or_beaming_asymmetry"] = baseline_asym
    cmp["high_doppler_g_or_beaming_asymmetry"] = doppler_asym
    cmp["high_doppler_asymmetry_ratio"] = doppler_asym / max(baseline_asym, 1e-6)

    gates = {
        "source_activity_or_emissivity_or_density_rmse": max(
            cmp["no_vs_high_activity_rmse"],
            cmp["no_vs_high_emissivity_rmse"],
            cmp["no_vs_high_density_rmse"],
        ) > 0.025,
        "final_rgb_rmse": cmp["no_vs_high_final_rmse"] > 0.012,
        "optical_depth_rmse": cmp["high_vs_low_tau_optical_depth_rmse"] > 0.030,
        "transfer_saturation_mean_diff": cmp["high_vs_low_tau_transfer_saturation_mean_diff"] > 0.050,
        "high_doppler_asymmetry": cmp["high_doppler_asymmetry_ratio"] > 1.15,
    }
    metrics["gates"] = gates
    metrics["passed"] = all(gates.values())

    sheet = out_dir / "ab_sheet.png"
    contact_sheet(rendered, sheet)
    metrics["ab_sheet"] = str(sheet)
    (out_dir / "ab_metrics.json").write_text(json.dumps(metrics, indent=2, sort_keys=True), encoding="utf-8")

    report = [
        "# Physics-constrained cinematic disk A/B validation",
        "",
        f"- passed: `{metrics['passed']}`",
        f"- sheet: `{sheet}`",
        "",
        "## Gates",
    ]
    for key, value in gates.items():
        report.append(f"- {key}: `{value}`")
    report += ["", "## Comparisons"]
    for key, value in cmp.items():
        report.append(f"- {key}: `{value:.6f}`")
    if not metrics["passed"] and not gates["final_rgb_rmse"]:
        report += [
            "",
            "## Transfer suppression note",
            "Source diagnostics changed, but final RGB did not clear the RMSE gate. Inspect raw-radiance, optical-depth, and transfer-saturation before changing presentation.",
        ]
    (out_dir / "ab_report.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    print(json.dumps(metrics, indent=2, sort_keys=True))
    if not metrics["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
