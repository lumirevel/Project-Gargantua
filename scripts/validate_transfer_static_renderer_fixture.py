#!/usr/bin/env python3
"""Phase 3 static-transfer renderer fixture.

This is a renderer-produced no-flow transfer check. It uses
`static-transfer-reference-v1`, which disables source orbital, radial, and
turbulent motion in a Schwarzschild thin-disk scene. Gravitational redshift and
lensing geometry still remain, so this is deliberately not treated as the full
same-tetrad static-emitter/static-observer `g ~= 1` proof.
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
    p.add_argument("--out-dir", default="/private/tmp/bh_transfer_static_renderer_fixture")
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
        "--output",
        str(out),
    ]
    if debug is not None:
        cmd += ["--realism-debug", debug]
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
        "phase": "Phase 3 / L2 static-transfer renderer fixture",
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

    static = report["cases"]["static_no_flow"]
    orbiting = report["cases"]["orbiting_control"]
    static_asym = max(static["g"]["abs_asymmetry"], static["beaming"]["abs_asymmetry"])
    orbiting_asym = max(orbiting["g"]["abs_asymmetry"], orbiting["beaming"]["abs_asymmetry"])
    comparisons = {
        "static_to_orbiting_g_rmse": image_rmse(rendered["static_no_flow"]["g"], rendered["orbiting_control"]["g"]),
        "static_to_orbiting_beaming_rmse": image_rmse(
            rendered["static_no_flow"]["beaming"], rendered["orbiting_control"]["beaming"]
        ),
        "static_to_orbiting_final_rmse": image_rmse(
            rendered["static_no_flow"]["final"], rendered["orbiting_control"]["final"]
        ),
        "static_g_or_beaming_abs_asymmetry": static_asym,
        "orbiting_g_or_beaming_abs_asymmetry": orbiting_asym,
        "orbiting_vs_static_asymmetry_ratio": orbiting_asym / max(static_asym, 1e-6),
    }
    report["comparisons"] = comparisons

    gates = {
        "source_model_surface": "static-transfer-reference-v1" in (ROOT / "Blackhole" / "run_pipeline.sh").read_text(encoding="utf-8"),
        "zero_orbital_boost_allowed": "max(0.0, doubleArg(\"--disk-orbital-boost\"" in (ROOT / "Blackhole" / "Sources" / "Params" / "ParamsBuilder.swift").read_text(encoding="utf-8"),
        "finite_debug_maps": all(
            math.isclose(report["cases"][case][debug]["finite_fraction"], 1.0)
            for case in ["static_no_flow", "orbiting_control"]
            for debug in ["g", "beaming"]
        ),
        "active_static_beaming_map": static["beaming"]["active_fraction_02"] > 0.005,
        "active_orbiting_beaming_map": orbiting["beaming"]["active_fraction_02"] > 0.005,
        "orbiting_control_changes_transfer_maps": max(
            comparisons["static_to_orbiting_g_rmse"],
            comparisons["static_to_orbiting_beaming_rmse"],
        )
        > 0.004,
        "final_radiance_changes_with_orbital_control": comparisons["static_to_orbiting_final_rmse"] > 0.004,
    }
    report["gates"] = gates
    report["passed"] = all(gates.values())
    report["contract_gaps"] = [
        "This fixture disables source flow but leaves Schwarzschild gravitational redshift and lens geometry active.",
        "It is therefore not the final same-tetrad static-emitter/static-observer g ~= 1 renderer proof.",
        "The gate intentionally does not require lower left/right asymmetry in the no-flow image, because lensing and projection asymmetry remain active.",
    ]

    sheet = out_dir / "static_transfer_fixture_sheet.png"
    contact_sheet(rendered, sheet)
    report["contact_sheet"] = str(sheet)

    report_path = out_dir / "static_transfer_fixture_metrics.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    print(f"report={report_path}")
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
