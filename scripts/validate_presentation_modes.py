#!/usr/bin/env python3
"""Validate scientific/eye/cinema presentation separation.

This is a renderer-level regression harness, not a source-model tuner.  It
renders the same source model through the three public presentation modes,
captures canonical branch diagnostics, and measures whether observer/presentation
transforms preserve source morphology.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
RUN_PIPELINE = ROOT / "Blackhole" / "run_pipeline.sh"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out-dir", default="/private/tmp/bh_presentation_validation")
    p.add_argument("--source-model", default="canonical-visible-disk-v1")
    p.add_argument("--width", type=int, default=384)
    p.add_argument("--height", type=int, default=216)
    p.add_argument("--quality", default="preview", choices=["preview", "hq"])
    p.add_argument("--disk-turbulence", type=float, default=2.0)
    p.add_argument("--no-render", action="store_true", help="reuse existing PNGs")
    p.add_argument("--rebuild-each-render", action="store_true", help="do not add --no-build after the first render")
    p.add_argument("--stable-debug-trace", action="store_true",
                   help="force collision-buffer trace for debug maps; useful for slower Kerr sweeps on interactive GPUs")
    p.add_argument("--extra", nargs=argparse.REMAINDER, default=[], help="extra args after --")
    return p.parse_args()


def run(cmd: List[str]) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=str(ROOT), check=True)


def render_set(args: argparse.Namespace, out_dir: Path) -> Dict[str, Path]:
    outputs: Dict[str, Path] = {}
    extra = list(args.extra)
    if args.stable_debug_trace and "--trace-hdr-direct" not in extra:
        extra += ["--trace-hdr-direct", "off"]
    common = [
        "bash", str(RUN_PIPELINE),
        "--source-model", args.source_model,
        "--quality", args.quality,
        "--width", str(args.width),
        "--height", str(args.height),
        "--disk-turbulence", str(args.disk_turbulence),
    ] + extra

    first_render = True

    def maybe_no_build(cmd: List[str]) -> List[str]:
        nonlocal first_render
        if first_render or args.rebuild_each_render:
            first_render = False
            return cmd
        return cmd + ["--no-build"]

    for mode in ("scientific", "eye", "cinema"):
        path = out_dir / f"{mode}.png"
        outputs[mode] = path
        if not args.no_render:
            cmd = common + ["--presentation", mode, "--output", str(path)]
            if mode == "scientific":
                cmd += ["--look", "linear"]
            run(maybe_no_build(cmd))

    for debug in ("photosphere", "skin", "corona", "hdr", "perturbation", "activity"):
        path = out_dir / f"debug_{debug}.png"
        outputs[f"debug_{debug}"] = path
        if not args.no_render:
            cmd = common + [
                "--presentation", "scientific",
                "--look", "linear",
                "--realism-debug", debug,
                "--output", str(path),
            ]
            run(maybe_no_build(cmd))

    return outputs


def load_rgb(path: Path) -> np.ndarray:
    im = Image.open(path).convert("RGB")
    return np.asarray(im, dtype=np.float32) / 255.0


def decode_branch_linear(rgb: np.ndarray) -> np.ndarray:
    """Undo the fixed gamma encode used by absolute canonical branch previews."""
    return np.power(np.clip(rgb, 0.0, 1.0), 2.2)


def luma(rgb: np.ndarray) -> np.ndarray:
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def normalize_luma(y: np.ndarray) -> np.ndarray:
    lo = float(np.percentile(y, 1.0))
    hi = float(np.percentile(y, 99.0))
    if hi <= lo + 1e-8:
        return np.zeros_like(y)
    return np.clip((y - lo) / (hi - lo), 0.0, 1.0)


def safe_share(num: np.ndarray, den: np.ndarray) -> np.ndarray:
    return np.where(den > 1e-8, num / np.maximum(den, 1e-8), 0.0)


def gradient_mag(y: np.ndarray) -> np.ndarray:
    gy, gx = np.gradient(y)
    return np.sqrt(gx * gx + gy * gy)


def corr(a: np.ndarray, b: np.ndarray, mask: np.ndarray | None = None) -> float:
    if mask is not None:
        a = a[mask]
        b = b[mask]
    aa = a.astype(np.float64).reshape(-1)
    bb = b.astype(np.float64).reshape(-1)
    if aa.size < 2:
        return 0.0
    aa -= aa.mean()
    bb -= bb.mean()
    denom = math.sqrt(float(np.dot(aa, aa) * np.dot(bb, bb)))
    if denom <= 1e-12:
        return 0.0
    return float(np.dot(aa, bb) / denom)


def image_stats(rgb: np.ndarray) -> Dict[str, float]:
    y = luma(rgb)
    active = y > max(1e-4, float(np.percentile(y, 70.0)) * 0.1)
    if not np.any(active):
        active = y > 0.0
    g = gradient_mag(normalize_luma(y))
    return {
        "mean_luma": float(y.mean()),
        "p50_luma": float(np.percentile(y, 50.0)),
        "p90_luma": float(np.percentile(y, 90.0)),
        "p99_luma": float(np.percentile(y, 99.0)),
        "active_mean": float(y[active].mean()) if np.any(active) else 0.0,
        "active_fraction": float(active.mean()),
        "sat_fraction": float(np.mean(np.max(rgb, axis=-1) >= 0.995)),
        "local_contrast": float(np.std(y[active]) / max(float(np.mean(y[active])), 1e-8)) if np.any(active) else 0.0,
        "grad_p95": float(np.percentile(g[active], 95.0)) if np.any(active) else 0.0,
    }


def presentation_metrics(images: Dict[str, np.ndarray]) -> Dict[str, Dict[str, float]]:
    sci_y = normalize_luma(luma(images["scientific"]))
    sci_g = gradient_mag(sci_y)
    active = sci_y > max(0.02, float(np.percentile(sci_y, 70.0)) * 0.1)

    out: Dict[str, Dict[str, float]] = {}
    for mode in ("scientific", "eye", "cinema"):
        y = normalize_luma(luma(images[mode]))
        g = gradient_mag(y)
        row = image_stats(images[mode])
        if mode != "scientific":
            row["morphology_luma_corr_vs_scientific"] = corr(sci_y, y, active)
            row["morphology_grad_corr_vs_scientific"] = corr(sci_g, g, active)
            row["normalized_luma_mae_vs_scientific"] = float(np.mean(np.abs(sci_y[active] - y[active]))) if np.any(active) else 0.0
        out[mode] = row
    return out


def branch_metrics(images: Dict[str, np.ndarray]) -> Dict[str, float]:
    ratio = images["debug_perturbation"]
    total_y = luma(images["scientific"])
    abs_total_y = luma(decode_branch_linear(images["debug_hdr"]))
    body_y = luma(decode_branch_linear(images["debug_photosphere"]))
    skin_y = luma(decode_branch_linear(images["debug_skin"]))
    corona_y = luma(decode_branch_linear(images["debug_corona"]))
    activity_y = luma(images["debug_activity"])

    active = total_y > max(1e-4, float(np.percentile(total_y, 70.0)) * 0.1)
    if not np.any(active):
        active = total_y > 0.0
    body = ratio[..., 0]
    skin = ratio[..., 1]
    corona = ratio[..., 2]
    abs_total = body_y + skin_y + corona_y
    body_abs_share = safe_share(body_y, abs_total)
    skin_abs_share = safe_share(skin_y, abs_total)
    corona_abs_share = safe_share(corona_y, abs_total)
    total_residual = normalize_luma(abs_total_y) - normalize_luma(body_y)
    skin_norm = normalize_luma(skin_y)
    activity_norm = normalize_luma(activity_y)
    skin_active = active & (skin_y > max(1e-6, float(np.percentile(skin_y, 75.0)) * 0.15))
    return {
        "body_ratio_mean_active": float(body[active].mean()) if np.any(active) else 0.0,
        "skin_ratio_mean_active": float(skin[active].mean()) if np.any(active) else 0.0,
        "corona_ratio_mean_active": float(corona[active].mean()) if np.any(active) else 0.0,
        "skin_ratio_p90_active": float(np.percentile(skin[active], 90.0)) if np.any(active) else 0.0,
        "corona_ratio_p90_active": float(np.percentile(corona[active], 90.0)) if np.any(active) else 0.0,
        "body_abs_share_mean_active": float(body_abs_share[active].mean()) if np.any(active) else 0.0,
        "skin_abs_share_mean_active": float(skin_abs_share[active].mean()) if np.any(active) else 0.0,
        "corona_abs_share_mean_active": float(corona_abs_share[active].mean()) if np.any(active) else 0.0,
        "skin_abs_share_p90_active": float(np.percentile(skin_abs_share[active], 90.0)) if np.any(active) else 0.0,
        "corona_abs_share_p90_active": float(np.percentile(corona_abs_share[active], 90.0)) if np.any(active) else 0.0,
        "abs_total_vs_scientific_corr_active": corr(normalize_luma(abs_total_y), normalize_luma(total_y), active),
        "ratio_vs_abs_skin_mae_active": float(np.mean(np.abs(skin[active] - skin_abs_share[active]))) if np.any(active) else 0.0,
        "ratio_vs_abs_corona_mae_active": float(np.mean(np.abs(corona[active] - corona_abs_share[active]))) if np.any(active) else 0.0,
        "skin_abs_to_body_abs_mean_active": float(safe_share(skin_y, body_y)[active].mean()) if np.any(active) else 0.0,
        "skin_abs_active_fraction": float(skin_active.mean()),
        "skin_abs_grad_p95_active": float(np.percentile(gradient_mag(skin_norm)[active], 95.0)) if np.any(active) else 0.0,
        "activity_mean_active": float(activity_y[active].mean()) if np.any(active) else 0.0,
        "activity_p90_active": float(np.percentile(activity_y[active], 90.0)) if np.any(active) else 0.0,
        "activity_vs_skin_abs_corr_active": corr(activity_norm, skin_norm, active),
        "activity_vs_total_residual_corr_active": corr(activity_norm, total_residual, active),
        "skin_abs_vs_total_residual_corr_active": corr(skin_norm, total_residual, active),
    }


def make_contact_sheet(paths: Dict[str, Path], out_path: Path) -> None:
    labels = [
        ("scientific", "scientific"),
        ("eye", "eye"),
        ("cinema", "cinema"),
        ("debug_photosphere", "body absolute"),
        ("debug_skin", "skin absolute"),
        ("debug_corona", "corona absolute"),
        ("debug_hdr", "total absolute"),
        ("debug_perturbation", "ratio RGB"),
        ("debug_activity", "activity"),
    ]
    tiles: List[Tuple[str, Image.Image]] = []
    for key, label in labels:
        im = Image.open(paths[key]).convert("RGB")
        tiles.append((label, im))

    tile_w, tile_h = tiles[0][1].size
    label_h = 24
    cols = 4
    rows = math.ceil(len(tiles) / cols)
    sheet = Image.new("RGB", (cols * tile_w, rows * (tile_h + label_h)), (8, 8, 8))
    draw = ImageDraw.Draw(sheet)
    for idx, (label, im) in enumerate(tiles):
        x = (idx % cols) * tile_w
        y = (idx // cols) * (tile_h + label_h)
        draw.rectangle([x, y, x + tile_w, y + label_h], fill=(18, 18, 18))
        draw.text((x + 8, y + 5), label, fill=(230, 230, 230))
        sheet.paste(im, (x, y + label_h))
    sheet.save(out_path)


def write_summary(out_dir: Path, metrics: Dict[str, object], paths: Dict[str, Path]) -> None:
    md = out_dir / "summary.md"
    with md.open("w", encoding="utf-8") as f:
        f.write("# Presentation Validation\n\n")
        f.write("This pass checks observer/presentation transforms against the same source model.\n\n")
        f.write("## Outputs\n\n")
        for key, path in sorted(paths.items()):
            f.write(f"- `{key}`: `{path}`\n")
        f.write("\n## Metrics\n\n")
        f.write("```json\n")
        f.write(json.dumps(metrics, indent=2, sort_keys=True))
        f.write("\n```\n")
        f.write("\nInterpretation: high morphology correlations mean eye/cinema changed display response without inventing new source morphology.\n")


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    outputs = render_set(args, out_dir)
    images = {key: load_rgb(path) for key, path in outputs.items()}

    metrics: Dict[str, object] = {
        "source_model": args.source_model,
        "width": args.width,
        "height": args.height,
        "disk_turbulence": args.disk_turbulence,
        "presentation": presentation_metrics(images),
        "branches": branch_metrics(images),
    }

    metrics_path = out_dir / "metrics.json"
    metrics_path.write_text(json.dumps(metrics, indent=2, sort_keys=True), encoding="utf-8")
    outputs["metrics"] = metrics_path

    sheet_path = out_dir / "presentation_validation_sheet.png"
    make_contact_sheet(outputs, sheet_path)
    outputs["contact_sheet"] = sheet_path

    write_summary(out_dir, metrics, outputs)
    print(json.dumps(metrics, indent=2, sort_keys=True))
    print(f"contact_sheet={sheet_path}")


if __name__ == "__main__":
    main()
