#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import math
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np

try:
    from PIL import Image, ImageDraw, ImageFont
except Exception as exc:  # pragma: no cover
    raise SystemExit(f"Pillow is required: {exc}")


COLLISION_DTYPE = np.dtype([
    ("hit", "<u4"),
    ("ct", "<f4"),
    ("T", "<f4"),
    ("_pad0", "<f4"),
    ("v_disk", "<f4", (4,)),
    ("direct_world", "<f4", (4,)),
    ("noise", "<f4"),
    ("emit_r_norm", "<f4"),
    ("emit_phi", "<f4"),
    ("emit_z_norm", "<f4"),
])

FIXED_DISPLAY_ARGS = [
    "--presentation-mode", "scientific",
    "--exposure-mode", "fixed",
    "--exposure-ev", "0",
]


@dataclass(frozen=True)
class VariantCase:
    name: str
    extra_args: list[str]
    note: str


@dataclass(frozen=True)
class ScalarCase:
    name: str
    debug: str
    scale: str = "linear"


VARIANTS: list[VariantCase] = [
    VariantCase("baseline_constant", ["--grmhd-smooth-weight", "constant"], "Current constant smooth continuum floor."),
    VariantCase(
        "state_weighted",
        ["--grmhd-smooth-weight", "state"],
        "Smooth continuum weighted by thermalization/residual/magnetization/disk-likeness gates.",
    ),
    VariantCase(
        "state_body_b0p45_s1p18",
        ["--grmhd-smooth-weight", "state-body", "--grmhd-smooth-emission-scale", "0.45", "--grmhd-cloud-emission-scale", "1.18"],
        "State+body candidate: body scale 0.45, skin scale 1.18.",
    ),
    VariantCase(
        "state_body_b0p48_s1p22",
        ["--grmhd-smooth-weight", "state-body", "--grmhd-smooth-emission-scale", "0.48", "--grmhd-cloud-emission-scale", "1.22"],
        "Protected checkpoint: state+body candidate, body scale 0.48, skin scale 1.22.",
    ),
    VariantCase(
        "plasma_body_b0p48_s1p22",
        ["--grmhd-smooth-weight", "plasma-body", "--grmhd-smooth-emission-scale", "0.48", "--grmhd-cloud-emission-scale", "1.22"],
        "Plasma body+skin candidate with reduced old continuum and emissive skin support.",
    ),
    VariantCase(
        "plasma_body_b0p46_s1p30",
        ["--grmhd-smooth-weight", "plasma-body", "--grmhd-smooth-emission-scale", "0.46", "--grmhd-cloud-emission-scale", "1.30"],
        "Plasma candidate with checkpoint-like body budget and stronger hot-skin emission.",
    ),
    VariantCase(
        "plasma_body_b0p44_s1p36",
        ["--grmhd-smooth-weight", "plasma-body", "--grmhd-smooth-emission-scale", "0.44", "--grmhd-cloud-emission-scale", "1.36"],
        "Plasma candidate biased toward structured skin while preserving explicit body.",
    ),
    VariantCase(
        "hybrid_visible_body_only_b0p70",
        [
            "--grmhd-smooth-weight", "hybrid-visible-disk",
            "--grmhd-smooth-emission-scale", "0.70",
            "--grmhd-cloud-emission-scale", "0.0",
            "--teff-T0", "8400",
            "--teff-p", "0.68",
        ],
        "Hybrid visible disk control: analytic photospheric body only, GRMHD skin disabled.",
    ),
    VariantCase(
        "hybrid_visible_b0p70_s1p00",
        [
            "--grmhd-smooth-weight", "hybrid-visible-disk",
            "--grmhd-smooth-emission-scale", "0.70",
            "--grmhd-cloud-emission-scale", "1.00",
            "--teff-T0", "8400",
            "--teff-p", "0.68",
        ],
        "Hybrid visible disk: analytic thermal body plus moderate GRMHD hot skin.",
    ),
    VariantCase(
        "hybrid_visible_shallow_b0p72_s0p95",
        [
            "--grmhd-smooth-weight", "hybrid-visible-disk-shallow",
            "--grmhd-smooth-emission-scale", "0.72",
            "--grmhd-cloud-emission-scale", "0.95",
            "--teff-T0", "8200",
            "--teff-p", "0.60",
        ],
        "Hybrid visible disk with shallower radial temperature slope and restrained skin.",
    ),
    VariantCase(
        "hybrid_visible_structured_b0p66_s1p20",
        [
            "--grmhd-smooth-weight", "hybrid-visible-disk-structured",
            "--grmhd-smooth-emission-scale", "0.66",
            "--grmhd-cloud-emission-scale", "1.20",
            "--teff-T0", "8800",
            "--teff-p", "0.72",
        ],
        "Hybrid visible disk with stronger magnetic/thetae skin sensitivity.",
    ),
    VariantCase(
        "hybrid_visible_corona_b0p68_s1p08",
        [
            "--grmhd-smooth-weight", "hybrid-visible-disk-corona",
            "--grmhd-smooth-emission-scale", "0.68",
            "--grmhd-cloud-emission-scale", "1.08",
            "--teff-T0", "8600",
            "--teff-p", "0.70",
        ],
        "Hybrid visible disk with weak optically-thin inner corona accent.",
    ),
    VariantCase(
        "hybrid_visible_tuned_b2p00_s0p70",
        [
            "--grmhd-smooth-weight", "hybrid-visible-disk",
            "--grmhd-smooth-emission-scale", "2.00",
            "--grmhd-cloud-emission-scale", "0.70",
            "--teff-T0", "8400",
            "--teff-p", "0.68",
        ],
        "Hybrid visible disk local sweep: stronger analytic body, restrained hot skin.",
    ),
    VariantCase(
        "hybrid_visible_tuned_b2p40_s0p60",
        [
            "--grmhd-smooth-weight", "hybrid-visible-disk",
            "--grmhd-smooth-emission-scale", "2.40",
            "--grmhd-cloud-emission-scale", "0.60",
            "--teff-T0", "8300",
            "--teff-p", "0.66",
        ],
        "Hybrid visible disk local sweep: body-biased photosphere control.",
    ),
    VariantCase(
        "hybrid_visible_structured_tuned_b2p10_s0p78",
        [
            "--grmhd-smooth-weight", "hybrid-visible-disk-structured",
            "--grmhd-smooth-emission-scale", "2.10",
            "--grmhd-cloud-emission-scale", "0.78",
            "--teff-T0", "8600",
            "--teff-p", "0.70",
        ],
        "Hybrid visible disk local sweep: balanced body with stronger GRMHD skin selectivity.",
    ),
    VariantCase(
        "hybrid_visible_corona_tuned_b2p10_s0p68",
        [
            "--grmhd-smooth-weight", "hybrid-visible-disk-corona",
            "--grmhd-smooth-emission-scale", "2.10",
            "--grmhd-cloud-emission-scale", "0.68",
            "--teff-T0", "8500",
            "--teff-p", "0.68",
        ],
        "Hybrid visible disk local sweep: balanced body/skin plus weak corona.",
    ),
    VariantCase(
        "hybrid_visible_bodyrich_b4p80_s0p45",
        [
            "--grmhd-smooth-weight", "hybrid-visible-disk",
            "--grmhd-smooth-emission-scale", "4.80",
            "--grmhd-cloud-emission-scale", "0.45",
            "--teff-T0", "8400",
            "--teff-p", "0.66",
        ],
        "Hybrid visible disk correction: body-rich photosphere, reduced skin dominance.",
    ),
    VariantCase(
        "hybrid_visible_bodyrich_b6p00_s0p35",
        [
            "--grmhd-smooth-weight", "hybrid-visible-disk",
            "--grmhd-smooth-emission-scale", "6.00",
            "--grmhd-cloud-emission-scale", "0.35",
            "--teff-T0", "8200",
            "--teff-p", "0.64",
        ],
        "Hybrid visible disk correction: upper body support guard against hollow skin.",
    ),
    VariantCase(
        "hybrid_visible_structured_bodyrich_b4p60_s0p55",
        [
            "--grmhd-smooth-weight", "hybrid-visible-disk-structured",
            "--grmhd-smooth-emission-scale", "4.60",
            "--grmhd-cloud-emission-scale", "0.55",
            "--teff-T0", "8600",
            "--teff-p", "0.68",
        ],
        "Hybrid visible disk correction: body-rich with structured hot-skin selectivity.",
    ),
    VariantCase(
        "hybrid_visible_corona_bodyrich_b4p80_s0p45",
        [
            "--grmhd-smooth-weight", "hybrid-visible-disk-corona",
            "--grmhd-smooth-emission-scale", "4.80",
            "--grmhd-cloud-emission-scale", "0.45",
            "--teff-T0", "8500",
            "--teff-p", "0.66",
        ],
        "Hybrid visible disk correction: body-rich photosphere plus weak corona.",
    ),
    VariantCase(
        "hybrid_visible_hotbody_b3p20_s0p55",
        [
            "--grmhd-smooth-weight", "hybrid-visible-disk",
            "--grmhd-smooth-emission-scale", "3.20",
            "--grmhd-cloud-emission-scale", "0.55",
            "--teff-T0", "12000",
            "--teff-p", "0.66",
        ],
        "Hybrid visible disk correction: hotter visible photosphere with restrained skin.",
    ),
    VariantCase(
        "hybrid_visible_structured_hotbody_b3p00_s0p65",
        [
            "--grmhd-smooth-weight", "hybrid-visible-disk-structured",
            "--grmhd-smooth-emission-scale", "3.00",
            "--grmhd-cloud-emission-scale", "0.65",
            "--teff-T0", "11500",
            "--teff-p", "0.68",
        ],
        "Hybrid visible disk correction: hotter photosphere plus selective structured skin.",
    ),
    VariantCase(
        "hybrid_visible_corona_hotbody_b3p20_s0p55",
        [
            "--grmhd-smooth-weight", "hybrid-visible-disk-corona",
            "--grmhd-smooth-emission-scale", "3.20",
            "--grmhd-cloud-emission-scale", "0.55",
            "--teff-T0", "12000",
            "--teff-p", "0.66",
        ],
        "Hybrid visible disk correction: hotter photosphere with weak corona.",
    ),
    VariantCase(
        "positive_plasma_b0p44_s1p36",
        ["--grmhd-smooth-weight", "positive-plasma", "--grmhd-smooth-emission-scale", "0.44", "--grmhd-cloud-emission-scale", "1.36"],
        "Positive-only emissive skin with branch spectral separation and weak corona.",
    ),
    VariantCase(
        "positive_plasma_b0p48_s1p34",
        ["--grmhd-smooth-weight", "positive-plasma", "--grmhd-smooth-emission-scale", "0.48", "--grmhd-cloud-emission-scale", "1.34"],
        "Positive-skin candidate with more body support.",
    ),
    VariantCase(
        "positive_plasma_b0p42_s1p46",
        ["--grmhd-smooth-weight", "positive-plasma", "--grmhd-smooth-emission-scale", "0.42", "--grmhd-cloud-emission-scale", "1.46"],
        "Positive-skin candidate biased toward hotter skin emission.",
    ),
    VariantCase(
        "positive_plasma_b0p40_s1p58",
        ["--grmhd-smooth-weight", "positive-plasma", "--grmhd-smooth-emission-scale", "0.40", "--grmhd-cloud-emission-scale", "1.58"],
        "Positive-skin v2 candidate: lower body, stronger positive skin, weak corona.",
    ),
    VariantCase(
        "positive_plasma_b0p38_s1p72",
        ["--grmhd-smooth-weight", "positive-plasma", "--grmhd-smooth-emission-scale", "0.38", "--grmhd-cloud-emission-scale", "1.72"],
        "Positive-skin v2 candidate biased toward hot skin with body retained.",
    ),
    VariantCase(
        "hot_skin_moderate_b0p44_s1p40",
        ["--grmhd-smooth-weight", "hot-skin", "--grmhd-smooth-emission-scale", "0.44", "--grmhd-cloud-emission-scale", "1.40"],
        "Independent optically-thin hot-skin emissivity: moderate B/thetae exponents.",
    ),
    VariantCase(
        "hot_skin_strong_b_b0p44_s1p46",
        ["--grmhd-smooth-weight", "hot-skin-b", "--grmhd-smooth-emission-scale", "0.44", "--grmhd-cloud-emission-scale", "1.46"],
        "Independent hot skin with stronger magnetic dependence.",
    ),
    VariantCase(
        "hot_skin_strong_theta_b0p44_s1p50",
        ["--grmhd-smooth-weight", "hot-skin-theta", "--grmhd-smooth-emission-scale", "0.44", "--grmhd-cloud-emission-scale", "1.50"],
        "Independent hot skin with stronger thetae dependence.",
    ),
    VariantCase(
        "hot_skin_corona_b0p44_s1p42",
        ["--grmhd-smooth-weight", "hot-skin-corona", "--grmhd-smooth-emission-scale", "0.44", "--grmhd-cloud-emission-scale", "1.42"],
        "Independent hot skin with weak optically-thin inner corona accent.",
    ),
    VariantCase(
        "hot_skin_tuned_b0p44_s1p60",
        ["--grmhd-smooth-weight", "hot-skin", "--grmhd-smooth-emission-scale", "0.44", "--grmhd-cloud-emission-scale", "1.60"],
        "Tuned hot-skin emissivity after rejecting over-bright first pass.",
    ),
    VariantCase(
        "hot_skin_tuned_b0p46_s1p80",
        ["--grmhd-smooth-weight", "hot-skin", "--grmhd-smooth-emission-scale", "0.46", "--grmhd-cloud-emission-scale", "1.80"],
        "Tuned hot-skin with more body and skin gain.",
    ),
    VariantCase(
        "hot_skin_tuned_theta_b0p46_s1p85",
        ["--grmhd-smooth-weight", "hot-skin-theta", "--grmhd-smooth-emission-scale", "0.46", "--grmhd-cloud-emission-scale", "1.85"],
        "Tuned theta-sensitive hot skin.",
    ),
    VariantCase(
        "visible_ref_body_b2p40_s0p00_T9000",
        [
            "--grmhd-smooth-weight", "visible-reference-skin",
            "--grmhd-smooth-emission-scale", "2.40",
            "--grmhd-cloud-emission-scale", "0.00",
            "--teff-T0", "9000",
            "--teff-p", "0.70",
        ],
        "Visible reference source control: analytic photospheric body only; GRMHD skin disabled.",
    ),
    VariantCase(
        "visible_ref_skin_b2p20_s0p70_T9000",
        [
            "--grmhd-smooth-weight", "visible-reference-skin",
            "--grmhd-smooth-emission-scale", "2.20",
            "--grmhd-cloud-emission-scale", "0.70",
            "--teff-T0", "9000",
            "--teff-p", "0.70",
        ],
        "Visible reference source: analytic body plus positive GRMHD hot-skin emission.",
    ),
    VariantCase(
        "visible_ref_skin_b2p80_s0p70_T9500",
        [
            "--grmhd-smooth-weight", "visible-reference-skin",
            "--grmhd-smooth-emission-scale", "2.80",
            "--grmhd-cloud-emission-scale", "0.70",
            "--teff-T0", "9500",
            "--teff-p", "0.68",
        ],
        "Visible reference source: stronger luminous body with restrained GRMHD hot-skin emission.",
    ),
    VariantCase(
        "visible_ref_skin_b2p50_s0p95_T9500",
        [
            "--grmhd-smooth-weight", "visible-reference-skin",
            "--grmhd-smooth-emission-scale", "2.50",
            "--grmhd-cloud-emission-scale", "0.95",
            "--teff-T0", "9500",
            "--teff-p", "0.68",
        ],
        "Visible reference source: stronger positive GRMHD hot-skin contribution.",
    ),
    VariantCase(
        "visible_ref_corona_b2p50_s0p85_T9500",
        [
            "--grmhd-smooth-weight", "visible-reference-skin-corona",
            "--grmhd-smooth-emission-scale", "2.50",
            "--grmhd-cloud-emission-scale", "0.85",
            "--teff-T0", "9500",
            "--teff-p", "0.68",
            "--corona-layer", "on",
            "--corona-h-over-r", "0.18",
        ],
        "Visible reference source: analytic body plus GRMHD hot skin and weak optically-thin corona.",
    ),
    VariantCase(
        "plasma_body_b0p52_s1p18",
        ["--grmhd-smooth-weight", "plasma-body", "--grmhd-smooth-emission-scale", "0.52", "--grmhd-cloud-emission-scale", "1.18"],
        "Plasma candidate with slightly stronger body and softer skin.",
    ),
    VariantCase(
        "plasma_body_b0p56_s1p14",
        ["--grmhd-smooth-weight", "plasma-body", "--grmhd-smooth-emission-scale", "0.56", "--grmhd-cloud-emission-scale", "1.14"],
        "Plasma candidate with stronger photospheric body and restrained skin.",
    ),
]

SCALAR_CASES: list[ScalarCase] = [
    ScalarCase("samples", "samples", "linear"),
    ScalarCase("ithermal_total", "ithermal", "log"),
    ScalarCase("ithermal_body", "ithermal-body", "log"),
    ScalarCase("ithermal_skin", "ithermal-cloud", "log"),
    ScalarCase("ithermal_corona", "ithermal-corona", "log"),
    ScalarCase("emission_radius", "emission-radius", "linear"),
    ScalarCase("emission_layer", "emission-layer", "linear"),
    ScalarCase("body_proxy", "body-proxy", "ratio"),
]

BRANCH_FINALS: list[tuple[str, str]] = [
    ("smooth_only_fixed_scientific", "smooth"),
    ("body_only_fixed_scientific", "body"),
    ("skin_only_fixed_scientific", "skin"),
    ("corona_only_fixed_scientific", "corona"),
]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="State-dependent GRMHD smooth-continuum causal pass.")
    p.add_argument("--hdf5", required=True, type=Path)
    p.add_argument("--out-dir", type=Path, default=Path("/tmp/bh_grmhd_causal_pass"))
    p.add_argument("--run-pipeline", type=Path, default=Path("Blackhole/run_pipeline.sh"))
    p.add_argument("--width", type=int, default=512)
    p.add_argument("--height", type=int, default=288)
    p.add_argument("--ssaa", type=int, default=1)
    p.add_argument("--preset", default="realistic")
    p.add_argument("--metric", default="kerr")
    p.add_argument("--spin", type=float, default=0.92)
    p.add_argument("--build", action="store_true")
    p.add_argument("--variants", default="", help="Comma-separated variant names to render; empty renders all.")
    return p.parse_args()


def run_command(cmd: list[str], log_path: Path) -> int:
    with log_path.open("w", encoding="utf-8") as log:
        log.write("$ " + " ".join(cmd) + "\n\n")
        proc = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, text=True)
    return proc.returncode


def render_output(
    name: str,
    *,
    variant_args: list[str],
    extra_args: list[str],
    args: argparse.Namespace,
    out_dir: Path,
) -> dict:
    out_png = out_dir / f"{name}.png"
    log_path = out_dir / f"{name}.log"
    cmd = [
        str(args.run_pipeline),
        "--science-regime", "grmhd-temperature-flow-scientific",
        "--preset", args.preset,
        "--metric", args.metric,
        "--spin", str(args.spin),
        "--disk-hdf5", str(args.hdf5),
        "--width", str(args.width),
        "--height", str(args.height),
        "--ssaa", str(args.ssaa),
        *FIXED_DISPLAY_ARGS,
        "--output", str(out_png),
        *variant_args,
        *extra_args,
    ]
    if not args.build:
        cmd.insert(1, "--no-build")
    rc = run_command(cmd, log_path)
    return {"name": name, "output": str(out_png), "log": str(log_path), "returncode": rc, "command": cmd}


def render_scalar(
    variant_name: str,
    case: ScalarCase,
    *,
    variant_args: list[str],
    args: argparse.Namespace,
    out_dir: Path,
) -> dict:
    out_png = out_dir / f"{variant_name}_{case.name}_debug.png"
    bin_path = out_dir / f"{variant_name}_{case.name}.collisions.bin"
    log_path = out_dir / f"{variant_name}_{case.name}.log"
    cmd = [
        str(args.run_pipeline),
        "--science-regime", "grmhd-temperature-flow-scientific",
        "--preset", args.preset,
        "--metric", args.metric,
        "--spin", str(args.spin),
        "--disk-hdf5", str(args.hdf5),
        "--width", str(args.width),
        "--height", str(args.height),
        "--ssaa", str(args.ssaa),
        *FIXED_DISPLAY_ARGS,
        "--disk-grmhd-debug", case.debug,
        "--collisions-out", str(bin_path),
        "--output", str(out_png),
        *variant_args,
    ]
    if not args.build:
        cmd.insert(1, "--no-build")
    rc = run_command(cmd, log_path)
    return {
        "variant": variant_name,
        "name": case.name,
        "debug": case.debug,
        "output": str(out_png),
        "collisions": str(bin_path),
        "log": str(log_path),
        "returncode": rc,
        "command": cmd,
        "scale": case.scale,
    }


def load_collision_scalar(path: Path, width: int, height: int) -> np.ndarray:
    raw = np.fromfile(path, dtype=COLLISION_DTYPE)
    expected = width * height
    if raw.size != expected:
        raise RuntimeError(f"collision count mismatch for {path}: {raw.size} != {expected}")
    return raw["noise"].reshape((height, width)).astype(np.float32)


def srgb_to_linear(img: np.ndarray) -> np.ndarray:
    return np.power(np.clip(img, 0.0, 1.0), 2.2)


def luminance_from_png(path: Path) -> np.ndarray:
    img = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
    lin = srgb_to_linear(img)
    return lin @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)


def box_blur(img: np.ndarray, radius: int) -> np.ndarray:
    if radius <= 0:
        return img.copy()
    kernel = 2 * radius + 1
    padded = np.pad(img, ((radius, radius), (radius, radius)), mode="edge")
    integral = np.pad(
        np.cumsum(np.cumsum(padded, axis=0, dtype=np.float64), axis=1, dtype=np.float64),
        ((1, 0), (1, 0)),
        mode="constant",
    )
    out = (
        integral[kernel:, kernel:]
        - integral[:-kernel, kernel:]
        - integral[kernel:, :-kernel]
        + integral[:-kernel, :-kernel]
    ) / float(kernel * kernel)
    return out.astype(np.float32)


def gradient_stats(img: np.ndarray, mask: np.ndarray) -> tuple[float, float]:
    dx = np.zeros_like(img)
    dy = np.zeros_like(img)
    dx[:, 1:-1] = 0.5 * (img[:, 2:] - img[:, :-2])
    dy[1:-1, :] = 0.5 * (img[2:, :] - img[:-2, :])
    grad = np.sqrt(dx * dx + dy * dy)
    vals = grad[mask]
    if vals.size == 0:
        return 0.0, 0.0
    return float(vals.mean()), float(np.percentile(vals, 95))


def pearson(a: np.ndarray, b: np.ndarray, mask: np.ndarray) -> float:
    av = a[mask].astype(np.float64)
    bv = b[mask].astype(np.float64)
    if av.size < 8:
        return float("nan")
    av -= av.mean()
    bv -= bv.mean()
    denom = math.sqrt(float((av * av).sum()) * float((bv * bv).sum()))
    if denom <= 1e-30:
        return float("nan")
    return float((av * bv).sum() / denom)


def mae(a: np.ndarray, b: np.ndarray, mask: np.ndarray) -> float:
    vals = np.abs(a[mask] - b[mask])
    if vals.size == 0:
        return 0.0
    return float(vals.mean())


def local_contrast(img: np.ndarray, mask: np.ndarray) -> float:
    blur = box_blur(img, 3)
    detail = img - blur
    vals = detail[mask]
    mean = float(img[mask].mean()) if mask.any() else 0.0
    if vals.size == 0 or mean <= 1e-12:
        return 0.0
    return float(vals.std() / mean)


def normalize_for_png(arr: np.ndarray, scale: str, mask: np.ndarray) -> np.ndarray:
    valid = np.isfinite(arr) & mask
    out = np.zeros_like(arr, dtype=np.float32)
    if not valid.any():
        return out
    vals = arr[valid]
    if scale == "ratio":
        return np.clip(arr, 0.0, 1.0).astype(np.float32)
    if scale == "dominant":
        return np.where(mask, arr, 0.0).astype(np.float32)
    if scale == "linear":
        lo = float(np.percentile(vals, 1.0))
        hi = float(np.percentile(vals, 99.0))
        mapped = (arr - lo) / max(hi - lo, 1e-6)
        return np.clip(mapped, 0.0, 1.0).astype(np.float32)
    vals = np.log10(np.maximum(vals, 1e-30))
    lo = float(np.percentile(vals, 1.0))
    hi = float(np.percentile(vals, 99.0))
    mapped = (np.log10(np.maximum(arr, 1e-30)) - lo) / max(hi - lo, 1e-6)
    return np.clip(mapped, 0.0, 1.0).astype(np.float32)


def save_gray_png(arr: np.ndarray, path: Path) -> None:
    img = np.clip(arr * 255.0 + 0.5, 0.0, 255.0).astype(np.uint8)
    Image.fromarray(img, mode="L").save(path)


def make_contact_sheet(items: list[tuple[str, Path]], out_path: Path, width: int, height: int) -> None:
    thumb_w = min(360, max(220, width // 2))
    thumb_h = max(1, int(round(thumb_w * height / max(width, 1))))
    label_h = 34
    cols = 3
    rows = (len(items) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * thumb_w, rows * (thumb_h + label_h)), (12, 12, 12))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 15)
    except Exception:
        font = ImageFont.load_default()
    for idx, (label, path) in enumerate(items):
        x = (idx % cols) * thumb_w
        y = (idx // cols) * (thumb_h + label_h)
        img = Image.open(path).convert("RGB")
        img.thumbnail((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        px = x + (thumb_w - img.width) // 2
        py = y + label_h + (thumb_h - img.height) // 2
        sheet.paste(img, (px, py))
        draw.rectangle((x, y, x + thumb_w, y + label_h), fill=(24, 24, 24))
        draw.text((x + 8, y + 9), label, fill=(230, 230, 230), font=font)
    sheet.save(out_path)


def save_variant_diagnostics(
    variant_dir: Path,
    *,
    scalar_arrays: dict[str, np.ndarray],
    mask: np.ndarray,
) -> dict[str, str]:
    total = np.maximum(scalar_arrays["ithermal_total"], 1.0e-30)
    body = np.clip(scalar_arrays["ithermal_body"] / total, 0.0, 1.0)
    skin = np.clip(scalar_arrays["ithermal_skin"] / total, 0.0, 1.0)
    corona = np.clip(scalar_arrays["ithermal_corona"] / total, 0.0, 1.0)
    stacked = np.stack([body, skin, corona], axis=0)
    dominant_idx = np.argmax(stacked, axis=0).astype(np.float32)
    dominant = np.where(mask, dominant_idx / 2.0, 0.0)

    derived = {
        "body_ratio": body,
        "skin_ratio": skin,
        "corona_ratio": corona,
        "dominant_branch": dominant,
        "emission_radius": scalar_arrays["emission_radius"],
        "emission_layer": scalar_arrays["emission_layer"],
        "body_proxy": np.clip(scalar_arrays["body_proxy"], 0.0, 1.0),
    }
    outputs: dict[str, str] = {}
    for name, arr in derived.items():
        scale = "dominant" if name == "dominant_branch" else ("ratio" if "ratio" in name or name == "body_proxy" else "linear")
        out_png = variant_dir / f"{name}.png"
        save_gray_png(normalize_for_png(arr, scale, mask), out_png)
        outputs[name] = str(out_png)
    return outputs


def save_luma_map(total_png: Path, out_png: Path) -> str:
    total_lum = luminance_from_png(total_png)
    mask = np.isfinite(total_lum) & (total_lum > 0.0)
    save_gray_png(normalize_for_png(total_lum, "log", mask), out_png)
    return str(out_png)


def bright_inner_mask(total_lum: np.ndarray, emission_radius: np.ndarray, mask: np.ndarray) -> np.ndarray:
    active = mask & np.isfinite(total_lum) & np.isfinite(emission_radius)
    if active.sum() < 16:
        return active
    bright_thresh = float(np.percentile(total_lum[active], 92.0))
    inner_thresh = float(np.percentile(emission_radius[active], 35.0))
    bright_inner = active & (total_lum >= bright_thresh) & (emission_radius <= inner_thresh)
    if bright_inner.sum() >= 16:
        return bright_inner
    bright_inner = active & (total_lum >= float(np.percentile(total_lum[active], 96.0)))
    return bright_inner


def ratio_stats(arr: np.ndarray, mask: np.ndarray) -> dict[str, float]:
    vals = arr[mask]
    if vals.size == 0:
        return {
            "mean": 0.0,
            "p50": 0.0,
            "p90": 0.0,
            "p95": 0.0,
            "cloud_dominant_fraction": 0.0,
            "pixel_count": 0.0,
        }
    return {
        "mean": float(vals.mean()),
        "p50": float(np.percentile(vals, 50.0)),
        "p90": float(np.percentile(vals, 90.0)),
        "p95": float(np.percentile(vals, 95.0)),
        "pixel_count": float(vals.size),
    }


def main() -> int:
    args = parse_args()
    args.hdf5 = args.hdf5.expanduser().resolve()
    args.run_pipeline = (Path.cwd() / args.run_pipeline).resolve() if not args.run_pipeline.is_absolute() else args.run_pipeline
    out_dir = args.out_dir.expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    manifests: dict[str, dict] = {}
    total_sheet_items: list[tuple[str, Path]] = []
    smooth_sheet_items: list[tuple[str, Path]] = []
    diagnostic_sheet_items: list[tuple[str, Path]] = []
    branch_final_sheet_items: list[tuple[str, Path]] = []
    luma_sheet_items: list[tuple[str, Path]] = []

    baseline_total_lum: np.ndarray | None = None
    metrics: list[dict[str, float | str]] = []

    requested_variants = {v.strip() for v in args.variants.split(",") if v.strip()}
    selected_variants = [v for v in VARIANTS if not requested_variants or v.name in requested_variants]
    if requested_variants and len(selected_variants) != len(requested_variants):
        known = ", ".join(v.name for v in VARIANTS)
        raise SystemExit(f"unknown --variants entry. known variants: {known}")

    for variant in selected_variants:
        variant_dir = out_dir / variant.name
        variant_dir.mkdir(parents=True, exist_ok=True)

        total_result = render_output(
            "total_fixed_scientific",
            variant_args=variant.extra_args,
            extra_args=[],
            args=args,
            out_dir=variant_dir,
        )
        # Build once per causal pass. The shader/binary is identical for all
        # branch-isolated and scalar-debug renders that follow.
        if args.build:
            args.build = False
        branch_results = []
        for name, branch in BRANCH_FINALS:
            branch_results.append(
                render_output(
                    name,
                    variant_args=variant.extra_args,
                    extra_args=["--grmhd-branch-isolation", branch],
                    args=args,
                    out_dir=variant_dir,
                )
            )
        smooth_result = next(r for r in branch_results if r["name"] == "smooth_only_fixed_scientific")
        results = [total_result, *branch_results]
        scalar_results = [
            render_scalar(variant.name, case, variant_args=variant.extra_args, args=args, out_dir=variant_dir)
            for case in SCALAR_CASES
        ]
        failures = [r for r in results + scalar_results if r["returncode"] != 0]
        if failures:
            print(json.dumps(failures, indent=2))
            return 1

        scalar_arrays: dict[str, np.ndarray] = {}
        samples = load_collision_scalar(variant_dir / f"{variant.name}_samples.collisions.bin", args.width, args.height)
        mask = np.isfinite(samples) & (samples > 0.0)
        for case in SCALAR_CASES:
            scalar_arrays[case.name] = load_collision_scalar(variant_dir / f"{variant.name}_{case.name}.collisions.bin", args.width, args.height)

        diag_outputs = save_variant_diagnostics(variant_dir, scalar_arrays=scalar_arrays, mask=mask)
        luma_map_path = save_luma_map(Path(total_result["output"]), variant_dir / "total_luma_map.png")

        total_lum = luminance_from_png(Path(total_result["output"]))
        smooth_lum = luminance_from_png(Path(smooth_result["output"]))
        active = mask & np.isfinite(total_lum) & np.isfinite(smooth_lum)
        grad_mean, grad_p95 = gradient_stats(total_lum, active)
        if baseline_total_lum is None:
            baseline_total_lum = total_lum.copy()
        bright_mask = bright_inner_mask(total_lum, scalar_arrays["emission_radius"], active)
        body_ratio = np.clip(scalar_arrays["ithermal_body"] / np.maximum(scalar_arrays["ithermal_total"], 1.0e-30), 0.0, 1.0)
        skin_ratio = np.clip(scalar_arrays["ithermal_skin"] / np.maximum(scalar_arrays["ithermal_total"], 1.0e-30), 0.0, 1.0)
        corona_ratio = np.clip(scalar_arrays["ithermal_corona"] / np.maximum(scalar_arrays["ithermal_total"], 1.0e-30), 0.0, 1.0)
        body_proxy = np.clip(scalar_arrays["body_proxy"], 0.0, 1.0)
        body_stats = ratio_stats(body_ratio, bright_mask)
        skin_stats = ratio_stats(skin_ratio, bright_mask)
        corona_stats = ratio_stats(corona_ratio, bright_mask)
        proxy_stats = ratio_stats(body_proxy, bright_mask)
        active_body = body_ratio[active]
        active_skin = skin_ratio[active]
        active_corona = corona_ratio[active]
        global_body_dominant_fraction = float(((active_body >= active_skin) & (active_body >= active_corona)).mean()) if active.any() else 0.0
        global_skin_dominant_fraction = float(((active_skin > active_body) & (active_skin >= active_corona)).mean()) if active.any() else 0.0
        global_corona_dominant_fraction = float(((active_corona > active_body) & (active_corona > active_skin)).mean()) if active.any() else 0.0
        bright_luma = total_lum[bright_mask] if bright_mask.any() else np.array([0.0], dtype=np.float32)

        entry: dict[str, float | str] = {
            "variant": variant.name,
            "local_contrast": local_contrast(total_lum, active),
            "gradient_mean": grad_mean,
            "gradient_p95": grad_p95,
            "spatial_variance": float(total_lum[active].var()) if active.any() else 0.0,
            "corr_vs_baseline": pearson(total_lum, baseline_total_lum, active),
            "corr_vs_smooth_only": pearson(total_lum, smooth_lum, active),
            "mae_vs_smooth_only": mae(total_lum, smooth_lum, active),
            "bright_inner_body_ratio_mean": body_stats["mean"],
            "bright_inner_body_ratio_p50": body_stats["p50"],
            "bright_inner_body_ratio_p90": body_stats["p90"],
            "bright_inner_body_ratio_p95": body_stats["p95"],
            "bright_inner_skin_ratio_mean": skin_stats["mean"],
            "bright_inner_skin_ratio_p50": skin_stats["p50"],
            "bright_inner_skin_ratio_p90": skin_stats["p90"],
            "bright_inner_skin_ratio_p95": skin_stats["p95"],
            "bright_inner_corona_ratio_mean": corona_stats["mean"],
            "bright_inner_corona_ratio_p50": corona_stats["p50"],
            "bright_inner_corona_ratio_p90": corona_stats["p90"],
            "bright_inner_corona_ratio_p95": corona_stats["p95"],
            "global_body_dominant_fraction": global_body_dominant_fraction,
            "global_skin_dominant_fraction": global_skin_dominant_fraction,
            "global_corona_dominant_fraction": global_corona_dominant_fraction,
            "bright_inner_luma_mean": float(bright_luma.mean()),
            "bright_inner_luma_p50": float(np.percentile(bright_luma, 50.0)),
            "bright_inner_luma_p90": float(np.percentile(bright_luma, 90.0)),
            "bright_inner_body_proxy_mean": proxy_stats["mean"],
            "bright_inner_body_proxy_p50": proxy_stats["p50"],
            "bright_inner_body_proxy_p90": proxy_stats["p90"],
            "bright_inner_body_proxy_p95": proxy_stats["p95"],
            "bright_inner_pixel_count": body_stats["pixel_count"],
        }
        metrics.append(entry)

        manifests[variant.name] = {
            "note": variant.note,
            "variant_args": variant.extra_args,
            "display_args": FIXED_DISPLAY_ARGS,
            "total_output": total_result,
            "smooth_output": smooth_result,
            "branch_outputs": branch_results,
            "scalar_outputs": scalar_results,
            "diagnostic_outputs": diag_outputs,
            "luma_map": luma_map_path,
            "metrics": entry,
        }

        total_sheet_items.append((variant.name, Path(total_result["output"])))
        smooth_sheet_items.append((f"{variant.name} smooth", Path(smooth_result["output"])))
        for branch_result in branch_results:
            if branch_result["name"] == "smooth_only_fixed_scientific":
                continue
            label = branch_result["name"].replace("_fixed_scientific", "").replace("_", " ")
            branch_final_sheet_items.append((f"{variant.name} {label}", Path(branch_result["output"])))
        diagnostic_sheet_items.append((f"{variant.name} body/total", Path(diag_outputs["body_ratio"])))
        diagnostic_sheet_items.append((f"{variant.name} skin/total", Path(diag_outputs["skin_ratio"])))
        diagnostic_sheet_items.append((f"{variant.name} corona/total", Path(diag_outputs["corona_ratio"])))
        diagnostic_sheet_items.append((f"{variant.name} dominant", Path(diag_outputs["dominant_branch"])))
        diagnostic_sheet_items.append((f"{variant.name} body-proxy", Path(diag_outputs["body_proxy"])))
        luma_sheet_items.append((f"{variant.name} luma", Path(luma_map_path)))

    state_entry = next((m for m in metrics if m["variant"] == "state_weighted"), None)
    if state_entry is not None:
        state_luma = float(state_entry["bright_inner_luma_mean"])
        for entry in metrics:
            body_mean = float(entry["bright_inner_body_ratio_mean"])
            skin_mean = float(entry["bright_inner_skin_ratio_mean"])
            entry["body_target_penalty"] = max(0.35 - body_mean, 0.0) + max(body_mean - 0.60, 0.0)
            entry["skin_target_penalty"] = max(0.30 - skin_mean, 0.0) + max(skin_mean - 0.55, 0.0)
            entry["brightness_gain_vs_state"] = float(entry["bright_inner_luma_mean"]) / max(state_luma, 1.0e-12)

    metrics_path = out_dir / "causal_metrics.json"
    metrics_path.write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    csv_path = out_dir / "causal_metrics.csv"
    headers = list(metrics[0].keys())
    with csv_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=headers)
        writer.writeheader()
        writer.writerows(metrics)

    manifest = {
        "hdf5": str(args.hdf5),
        "fixed_display_args": FIXED_DISPLAY_ARGS,
        "variants": manifests,
    }
    (out_dir / "causal_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    final_sheet = out_dir / "variant_totals_contact.png"
    make_contact_sheet(total_sheet_items, final_sheet, args.width, args.height)
    smooth_sheet = out_dir / "variant_smooth_contact.png"
    make_contact_sheet(smooth_sheet_items, smooth_sheet, args.width, args.height)
    branch_finals_sheet = out_dir / "variant_branch_finals_contact.png"
    make_contact_sheet(branch_final_sheet_items, branch_finals_sheet, args.width, args.height)
    diagnostic_sheet = out_dir / "variant_branch_diagnostics_contact.png"
    make_contact_sheet(diagnostic_sheet_items, diagnostic_sheet, args.width, args.height)
    luma_sheet = out_dir / "variant_luma_contact.png"
    make_contact_sheet(luma_sheet_items, luma_sheet, args.width, args.height)

    print(f"metrics: {metrics_path}")
    print(f"totals contact: {final_sheet}")
    print(f"smooth contact: {smooth_sheet}")
    print(f"branch finals contact: {branch_finals_sheet}")
    print(f"branch diagnostics contact: {diagnostic_sheet}")
    print(f"luma contact: {luma_sheet}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
