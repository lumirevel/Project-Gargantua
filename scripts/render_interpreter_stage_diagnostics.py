#!/usr/bin/env python3
"""Render stage-named interpreter diagnostics without changing final rendering.

This harness uses existing renderer controls to make the interpreter pipeline
easier to inspect:

- raw_interpreter_input: scientific/linear preview of source radiance entering
  compose.
- tone_mapped_no_bloom: requested presentation with PSF/glare/flare/DOF/noise
  disabled.
- final_rgb: requested presentation using normal defaults.
- bloom_only: positive display-space difference between final_rgb and
  tone_mapped_no_bloom.

The bloom_only image is a diagnostic proxy, not a physically additive buffer:
PSF and glare can redistribute energy, so negative differences are omitted.
"""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path
from typing import Dict, List

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
RUN_PIPELINE = ROOT / "Blackhole" / "run_pipeline.sh"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out-dir", default="/private/tmp/bh_interpreter_stage_diagnostics")
    p.add_argument("--source-model", default="canonical-visible-disk-v1")
    p.add_argument("--compose-hdr-in", default="", help="optional linear32 HDR input for compose-only validation")
    p.add_argument("--width", type=int, default=384)
    p.add_argument("--height", type=int, default=216)
    p.add_argument("--quality", default="preview", choices=["preview", "hq"])
    p.add_argument("--presentation", default="cinema", choices=["scientific", "eye", "cinema"])
    p.add_argument("--look", default="", help="optional look override for tone_mapped_no_bloom and final_rgb")
    p.add_argument("--bloom-scale", type=float, default=4.0, help="display gain for bloom_only proxy")
    p.add_argument("--no-render", action="store_true", help="reuse existing stage PNGs")
    p.add_argument("--rebuild-each-render", action="store_true", help="do not add --no-build after the first render")
    p.add_argument("--extra", nargs=argparse.REMAINDER, default=[], help="extra run_pipeline args after --")
    return p.parse_args()


def run(cmd: List[str]) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=str(ROOT), check=True)


def load_rgb(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def write_rgb(path: Path, rgb: np.ndarray) -> None:
    arr = np.clip(rgb * 255.0 + 0.5, 0.0, 255.0).astype(np.uint8)
    Image.fromarray(arr, mode="RGB").save(path)


def luma(rgb: np.ndarray) -> np.ndarray:
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def make_contact_sheet(paths: Dict[str, Path], out_path: Path) -> None:
    labels = ["raw_interpreter_input", "tone_mapped_no_bloom", "bloom_only", "final_rgb"]
    thumbs = []
    for label in labels:
        im = Image.open(paths[label]).convert("RGB")
        im.thumbnail((320, 180))
        panel = Image.new("RGB", (320, 208), (20, 20, 20))
        panel.paste(im, ((320 - im.width) // 2, 24 + (180 - im.height) // 2))
        draw = ImageDraw.Draw(panel)
        draw.text((8, 6), label, fill=(235, 235, 235))
        thumbs.append(panel)
    sheet = Image.new("RGB", (640, 416), (12, 12, 12))
    for i, panel in enumerate(thumbs):
        sheet.paste(panel, ((i % 2) * 320, (i // 2) * 208))
    sheet.save(out_path)


def stage_commands(args: argparse.Namespace, out_dir: Path) -> Dict[str, List[str]]:
    extra = list(args.extra)
    if args.compose_hdr_in:
        base = [
            "bash", str(RUN_PIPELINE),
            "--compose-hdr-in", args.compose_hdr_in,
            "--width", str(args.width),
            "--height", str(args.height),
        ]
    else:
        base = [
            "bash", str(RUN_PIPELINE),
            "--source-model", args.source_model,
            "--quality", args.quality,
            "--width", str(args.width),
            "--height", str(args.height),
        ]
    base += extra

    raw = base + [
        "--presentation", "scientific",
        "--look", "linear",
        "--output", str(out_dir / "raw_interpreter_input.png"),
    ]
    if not args.compose_hdr_in:
        raw += ["--realism-debug", "hdr"]

    requested = base + ["--presentation", args.presentation]
    if args.look:
        requested += ["--look", args.look]

    no_bloom = requested + [
        "--camera-psf-sigma", "0",
        "--camera-flare", "0",
        "--camera-dof-strength", "0",
        "--camera-read-noise", "0",
        "--camera-shot-noise", "0",
        "--output", str(out_dir / "tone_mapped_no_bloom.png"),
    ]
    final = requested + ["--output", str(out_dir / "final_rgb.png")]
    return {
        "raw_interpreter_input": raw,
        "tone_mapped_no_bloom": no_bloom,
        "final_rgb": final,
    }


def render_stages(args: argparse.Namespace, out_dir: Path) -> Dict[str, Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    commands = stage_commands(args, out_dir)
    paths = {
        "raw_interpreter_input": out_dir / "raw_interpreter_input.png",
        "tone_mapped_no_bloom": out_dir / "tone_mapped_no_bloom.png",
        "final_rgb": out_dir / "final_rgb.png",
        "bloom_only": out_dir / "bloom_only.png",
        "contact_sheet": out_dir / "interpreter_stage_sheet.png",
        "metrics": out_dir / "interpreter_stage_metrics.json",
    }

    first_render = True
    if not args.no_render:
        for label in ("raw_interpreter_input", "tone_mapped_no_bloom", "final_rgb"):
            cmd = list(commands[label])
            if not first_render and not args.rebuild_each_render:
                cmd.append("--no-build")
            run(cmd)
            first_render = False

    no_bloom = load_rgb(paths["tone_mapped_no_bloom"])
    final = load_rgb(paths["final_rgb"])
    bloom_proxy = np.maximum(final - no_bloom, 0.0) * max(args.bloom_scale, 0.0)
    write_rgb(paths["bloom_only"], bloom_proxy)
    make_contact_sheet(paths, paths["contact_sheet"])

    delta = final - no_bloom
    positive = np.maximum(delta, 0.0)
    negative = np.maximum(no_bloom - final, 0.0)
    positive_luma = luma(positive)
    negative_luma = luma(negative)
    positive_mean = float(np.mean(positive_luma))
    negative_mean = float(np.mean(negative_luma))
    metrics = {
        "stages": {k: str(v) for k, v in paths.items()},
        "presentation": args.presentation,
        "source_model": "" if args.compose_hdr_in else args.source_model,
        "compose_hdr_in": args.compose_hdr_in,
        "bloom_only_is_display_space_proxy": True,
        "bloom_scale": args.bloom_scale,
        "mean_abs_delta": float(np.mean(np.abs(delta))),
        "positive_delta_luma_mean": positive_mean,
        "positive_delta_luma_p95": float(np.percentile(positive_luma, 95.0)),
        "positive_delta_luma_p99": float(np.percentile(positive_luma, 99.0)),
        "positive_delta_luma_p999": float(np.percentile(positive_luma, 99.9)),
        "positive_delta_luma_max": float(np.max(positive_luma)),
        "positive_delta_coverage_gt_0_01": float(np.mean(positive_luma > 0.01)),
        "positive_delta_coverage_gt_0_05": float(np.mean(positive_luma > 0.05)),
        "negative_delta_luma_mean": negative_mean,
        "negative_delta_luma_p95": float(np.percentile(negative_luma, 95.0)),
        "negative_delta_luma_p99": float(np.percentile(negative_luma, 99.0)),
        "negative_delta_luma_max": float(np.max(negative_luma)),
        "redistribution_negative_to_positive_luma_mean_ratio": float(
            negative_mean / max(positive_mean, 1e-9)
        ),
        "final_luma_mean": float(np.mean(luma(final))),
        "tone_mapped_no_bloom_luma_mean": float(np.mean(luma(no_bloom))),
    }
    paths["metrics"].write_text(json.dumps(metrics, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(metrics, indent=2, sort_keys=True))
    print(f"sheet={paths['contact_sheet']}")
    return paths


def main() -> None:
    args = parse_args()
    render_stages(args, Path(args.out_dir))


if __name__ == "__main__":
    main()
