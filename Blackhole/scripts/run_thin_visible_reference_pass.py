#!/usr/bin/env python3
"""Render and score thin visible reference candidates.

This pass intentionally keeps GRMHD out of the primary disk appearance.  It
compares the protected GRMHD/hybrid checkpoints, when present, against a pure
Kerr ray/disk-intersection thin photosphere whose local temperature is the
NT-shaped visible reference profile selected by --teff-model grmhd-hybrid.
"""

from __future__ import annotations

import argparse
import csv
import math
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
RUN_PIPELINE = ROOT / "run_pipeline.sh"


def run(cmd: list[str]) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=ROOT.parent, check=True)


def image_metrics(path: Path) -> dict[str, float | str]:
    im = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
    y = 0.2126 * im[..., 0] + 0.7152 * im[..., 1] + 0.0722 * im[..., 2]
    gy, gx = np.gradient(y)
    grad = np.sqrt(gx * gx + gy * gy)
    active = y[y > 1e-4]
    local_contrast = float(np.std(active) / (np.mean(active) + 1e-9)) if active.size else 0.0
    return {
        "file": str(path),
        "mean_luma": float(np.mean(y)),
        "p50_luma": float(np.percentile(y, 50)),
        "p90_luma": float(np.percentile(y, 90)),
        "p99_luma": float(np.percentile(y, 99)),
        "max_luma": float(np.max(y)),
        "coverage": float(np.mean(y > 1e-4)),
        "local_contrast": local_contrast,
        "grad_p95": float(np.percentile(grad, 95)),
        "sat_frac": float(np.mean(np.max(im, axis=-1) > 0.98)),
    }


def make_sheet(items: list[tuple[str, Path]], out: Path, thumb_w: int = 384) -> None:
    loaded: list[tuple[str, Image.Image]] = []
    for label, path in items:
        if not path.exists():
            continue
        img = Image.open(path).convert("RGB")
        scale = thumb_w / img.width
        thumb = img.resize((thumb_w, max(1, int(img.height * scale))), Image.Resampling.LANCZOS)
        loaded.append((label, thumb))
    if not loaded:
        return
    label_h = 26
    cols = min(3, len(loaded))
    rows = math.ceil(len(loaded) / cols)
    cell_w = max(img.width for _, img in loaded)
    cell_h = max(img.height for _, img in loaded) + label_h
    sheet = Image.new("RGB", (cols * cell_w, rows * cell_h), (10, 10, 10))
    draw = ImageDraw.Draw(sheet)
    for i, (label, img) in enumerate(loaded):
        x = (i % cols) * cell_w
        y = (i // cols) * cell_h
        draw.text((x + 5, y + 5), label, fill=(235, 235, 235))
        sheet.paste(img, (x, y + label_h))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", default="/private/tmp/bh_thin_visible_reference/pass")
    ap.add_argument("--width", type=int, default=384)
    ap.add_argument("--height", type=int, default=216)
    ap.add_argument("--ssaa", type=int, default=2)
    ap.add_argument("--no-build", action="store_true")
    args = ap.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    variants = [
        ("thin_ref_T7000_science", ["--teff-T0", "7000", "--fcol", "1.25", "--exposure-ev", "-52"]),
        ("thin_ref_T9000_science", ["--teff-T0", "9000", "--fcol", "1.25", "--exposure-ev", "-54"]),
        ("thin_ref_T11500_science", ["--teff-T0", "11500", "--fcol", "1.25", "--exposure-ev", "-56"]),
    ]

    rendered: list[tuple[str, Path]] = []
    for i, (name, extra) in enumerate(variants):
        out = out_dir / f"{name}_{args.width}.png"
        cmd = [
            str(RUN_PIPELINE),
            "--science-regime", "thin-disk-visible-reference",
            "--preset", "realistic",
            "--metric", "kerr",
            "--spin", "0.92",
            "--width", str(args.width),
            "--height", str(args.height),
            "--ssaa", str(args.ssaa),
            "--dither", "0",
            "--exposure-mode", "fixed",
            "--output", str(out),
        ]
        if args.no_build or i > 0:
            cmd.insert(1, "--no-build")
        cmd.extend(extra)
        run(cmd)
        rendered.append((name, out))

    # Presentation variants are generated from the selected pure-science reference
    # without changing scene formation or enabling the physical-flow/hybrid shader.
    presentations = [
        ("thin_ref_T7000_eye", ["--presentation-mode", "eye", "--look", "realistic", "--camera-model", "eye"]),
        (
            "thin_ref_T7000_cinema",
            [
                "--presentation-mode", "cinema", "--look", "realistic",
                "--camera-model", "cinematic", "--camera-profile", "cinema-digital",
                "--camera-psf-sigma", "0.24", "--camera-flare", "0.018",
            ],
        ),
    ]
    for name, extra in presentations:
        out = out_dir / f"{name}_{args.width}.png"
        cmd = [
            str(RUN_PIPELINE),
            "--no-build",
            "--science-regime", "thin-disk-visible-reference",
            "--preset", "realistic",
            "--metric", "kerr",
            "--spin", "0.92",
            "--width", str(args.width),
            "--height", str(args.height),
            "--ssaa", str(args.ssaa),
            "--dither", "0",
            "--teff-T0", "7000",
            "--fcol", "1.25",
            "--exposure-mode", "fixed",
            "--exposure-ev", "-52",
            "--output", str(out),
        ] + extra
        run(cmd)
        rendered.append((name, out))

    baselines = [
        ("protected_plasma_body", Path("/private/tmp/bh_hybrid_visible_protected_plasma_body_1536.png")),
        ("failed_hybrid_visible", Path("/private/tmp/bh_hybrid_visible_final_scientific_1536.png")),
    ]
    sheet_items = [(label, path) for label, path in baselines if path.exists()] + rendered
    make_sheet(sheet_items, out_dir / "thin_visible_reference_comparison_sheet.png")

    rows = [image_metrics(path) | {"label": label} for label, path in sheet_items if path.exists()]
    with (out_dir / "thin_visible_reference_metrics.csv").open("w", newline="") as f:
        fieldnames = ["label"] + [k for k in rows[0].keys() if k != "label"]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"comparison_sheet={out_dir / 'thin_visible_reference_comparison_sheet.png'}")
    print(f"metrics={out_dir / 'thin_visible_reference_metrics.csv'}")


if __name__ == "__main__":
    main()
