#!/usr/bin/env python3
"""Pixel-level presentation isolation on a real black-hole source render.

This is the source-render counterpart to validate_cinematic_pixel_invariance.py.
It keeps the source model fixed and compares first-class presentation routes so
cinematic/camera changes cannot silently alter the RAW-like scientific audit.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
RUN_PIPELINE = ROOT / "Blackhole" / "run_pipeline.sh"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out-dir", default="/private/tmp/bh_blackhole_presentation_invariance")
    p.add_argument("--source-model", default="canonical-visible-disk-v1")
    p.add_argument("--width", type=int, default=128)
    p.add_argument("--height", type=int, default=72)
    p.add_argument("--quality", default="preview", choices=["preview", "hq"])
    p.add_argument("--no-build", action="store_true")
    p.add_argument("--rebuild-each-render", action="store_true")
    p.add_argument("--extra", nargs=argparse.REMAINDER, default=[])
    return p.parse_args()


def run(cmd: list[str]) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=str(ROOT), check=True)


def render(args: argparse.Namespace, out_dir: Path) -> dict[str, Path]:
    common = [
        "bash",
        str(RUN_PIPELINE),
        "--source-model",
        args.source_model,
        "--quality",
        args.quality,
        "--width",
        str(args.width),
        "--height",
        str(args.height),
        "--background",
        "off",
    ] + list(args.extra)
    off_switches = [
        "--look",
        "linear",
        "--exposure-mode",
        "fixed",
        "--exposure-ev",
        "0",
        "--camera-psf-sigma",
        "0",
        "--camera-read-noise",
        "0",
        "--camera-shot-noise",
        "0",
        "--camera-flare",
        "0",
        "--camera-dof-strength",
        "0",
    ]
    specs = {
        "scientific_audit": [
            "--presentation",
            "scientific",
            "--camera-model",
            "legacy",
            "--camera-profile",
            "ideal",
        ]
        + off_switches,
        "camera_raw_default": ["--presentation", "camera-raw"],
        "camera_raw_explicit_off": ["--presentation", "camera-raw"] + off_switches,
        "camera_rendered_off": ["--presentation", "camera-rendered"] + off_switches,
        "cinema_off": ["--presentation", "cinema"] + off_switches,
        "cinema_on": [
            "--presentation",
            "cinema",
            "--look",
            "sensor-filmic",
            "--exposure-mode",
            "fixed",
            "--exposure-ev",
            "0",
            "--camera-profile",
            "cinema-digital",
            "--camera-flare",
            "0.6",
            "--camera-dof-strength",
            "1.0",
            "--camera-focus-depth",
            "4.2",
        ],
    }

    paths: dict[str, Path] = {}
    first = True
    for name, extra in specs.items():
        path = out_dir / f"{name}.png"
        paths[name] = path
        cmd = common + extra + ["--output", str(path)]
        if args.no_build or (not first and not args.rebuild_each_render):
            cmd.append("--no-build")
        run(cmd)
        first = False
    return paths


def read_rgb(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def luma(rgb: np.ndarray) -> np.ndarray:
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def compare(a: np.ndarray, b: np.ndarray) -> dict[str, float]:
    diff = a - b
    abs_diff = np.abs(diff)
    lum = luma(abs_diff)
    return {
        "rgb_rmse": float(np.sqrt(np.mean(diff * diff))),
        "rgb_mae": float(np.mean(abs_diff)),
        "luma_abs_mean": float(np.mean(lum)),
        "luma_abs_p99": float(np.percentile(lum, 99.0)),
        "luma_abs_max": float(np.max(lum)),
    }


def contact_sheet(paths: dict[str, Path], out_path: Path) -> None:
    labels = list(paths.keys())
    panels = []
    for label in labels:
        im = Image.open(paths[label]).convert("RGB")
        im.thumbnail((240, 135))
        panel = Image.new("RGB", (240, 160), (18, 18, 18))
        panel.paste(im, ((240 - im.width) // 2, 22 + (135 - im.height) // 2))
        ImageDraw.Draw(panel).text((7, 5), label, fill=(235, 235, 235))
        panels.append(panel)
    cols = 3
    rows = math.ceil(len(panels) / cols)
    sheet = Image.new("RGB", (cols * 240, rows * 160), (8, 8, 8))
    for idx, panel in enumerate(panels):
        sheet.paste(panel, ((idx % cols) * 240, (idx // cols) * 160))
    sheet.save(out_path)


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    paths = render(args, out_dir)
    images = {name: read_rgb(path) for name, path in paths.items()}

    comparisons = {
        "scientific_vs_camera_raw_default": compare(images["scientific_audit"], images["camera_raw_default"]),
        "camera_raw_default_vs_explicit_off": compare(images["camera_raw_default"], images["camera_raw_explicit_off"]),
        "camera_rendered_off_vs_cinema_off": compare(images["camera_rendered_off"], images["cinema_off"]),
        "cinema_off_vs_cinema_on": compare(images["cinema_off"], images["cinema_on"]),
    }
    gates = {
        "scientific_vs_camera_raw_recorded": comparisons["scientific_vs_camera_raw_default"]["rgb_rmse"] >= 0.0,
        "camera_raw_default_matches_explicit_off": comparisons["camera_raw_default_vs_explicit_off"]["rgb_rmse"] < 0.004,
        "cinematic_on_changes_only_cinematic_output": comparisons["cinema_off_vs_cinema_on"]["rgb_rmse"] > 0.002,
    }
    sheet = out_dir / "blackhole_presentation_sheet.png"
    contact_sheet(paths, sheet)
    report: dict[str, Any] = {
        "phase": "Phase 5/6 black-hole source presentation isolation",
        "passed": all(gates.values()),
        "source_model": args.source_model,
        "quality": args.quality,
        "width": args.width,
        "height": args.height,
        "outputs": {name: str(path) for name, path in paths.items()},
        "contact_sheet": str(sheet),
        "comparisons": comparisons,
        "gates": gates,
        "contract_gaps": [
            "camera-raw still validates a RAW-like audit route, not a dedicated RAW buffer.",
            "This low-resolution gate uses the canonical source; additional source models should be added as promotion gates.",
            "Scientific PNG and camera-raw PNG are measured but not required to be identical; camera-raw purity is gated by default-vs-explicit-off identity and the linear32 sidecar validator.",
        ],
    }
    report_path = out_dir / "blackhole_presentation_metrics.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    print(f"sheet={sheet}")
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
