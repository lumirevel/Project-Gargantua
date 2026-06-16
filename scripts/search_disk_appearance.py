#!/usr/bin/env python3
"""Search physically constrained accretion-disk appearance parameters.

This harness explores the canonical thin/intermediate disk source family. It
does not tune eye/cinema post-processing and it writes generated renders outside
the repository by default.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
RUN_PIPELINE = ROOT / "Blackhole" / "run_pipeline.sh"


@dataclass(frozen=True)
class Candidate:
    name: str
    source_model: str
    disk_turbulence: float
    disk_turbulence_inner: float
    disk_turbulence_outer: float
    teff_t0: float
    teff_p: float
    fcol: float
    disk_time: float
    orbital_boost: float


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out-dir", default="/private/tmp/bh_disk_appearance_search")
    p.add_argument("--count", type=int, default=10)
    p.add_argument("--top", type=int, default=3)
    p.add_argument("--width", type=int, default=160)
    p.add_argument("--height", type=int, default=90)
    p.add_argument("--quality", default="preview")
    p.add_argument("--source-model", default="cinematic-physical-disk-v1",
                   choices=["canonical-visible-disk-v1", "cinematic-physical-disk-v1", "grmhd-surrogate-disk-v1"])
    p.add_argument("--no-build", action="store_true")
    p.add_argument("--rebuild-each-render", action="store_true")
    p.add_argument("--extra", nargs=argparse.REMAINDER, default=[])
    return p.parse_args()


def run(cmd: list[str], env: dict[str, str]) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=str(ROOT), env=env, check=True)


def deterministic_candidates(source_model: str, count: int) -> list[Candidate]:
    candidates: list[Candidate] = []
    for i in range(max(count, 1)):
        u = i / max(count - 1, 1)
        # Low-discrepancy-ish deterministic coverage; no random seed needed for
        # reproducibility. These are physical source controls, not post looks.
        v = (i * 0.61803398875) % 1.0
        w = (i * 0.41421356237) % 1.0
        turb = 1.45 + 0.95 * v
        inner = min(2.4, turb + 0.18 + 0.18 * w)
        outer = max(0.80, turb * (0.46 + 0.22 * (1.0 - u)))
        t0 = 13200.0 + 7600.0 * ((i * 0.73205080757) % 1.0)
        p = 0.58 + 0.24 * ((i * 0.27950849719 + 0.17) % 1.0)
        fcol = 1.12 + 0.24 * ((i * 0.16227766017 + 0.31) % 1.0)
        time = 0.35 + 18.0 * ((i * 0.30277563773 + 0.09) % 1.0)
        boost = 0.92 + 0.28 * ((i * 0.23606797749 + 0.21) % 1.0)
        if source_model == "grmhd-surrogate-disk-v1":
            turb = min(2.4, turb + 0.22)
            inner = min(2.4, inner + 0.15)
            outer = max(0.90, outer * 0.92)
        candidates.append(Candidate(
            name=f"cand_{i:02d}",
            source_model=source_model,
            disk_turbulence=round(turb, 4),
            disk_turbulence_inner=round(inner, 4),
            disk_turbulence_outer=round(outer, 4),
            teff_t0=round(t0, 2),
            teff_p=round(p, 4),
            fcol=round(fcol, 4),
            disk_time=round(time, 4),
            orbital_boost=round(boost, 4),
        ))
    return candidates[:count]


def render_candidate(c: Candidate, out_path: Path, width: int, height: int, quality: str,
                     no_build: bool, extra: list[str], env: dict[str, str]) -> None:
    cmd = [
        "bash", str(RUN_PIPELINE),
        "--source-model", c.source_model,
        "--presentation", "scientific",
        "--look", "linear",
        "--quality", quality,
        "--width", str(width),
        "--height", str(height),
        "--output", str(out_path),
        "--disk-turbulence", str(c.disk_turbulence),
        "--disk-turbulence-inner", str(c.disk_turbulence_inner),
        "--disk-turbulence-outer", str(c.disk_turbulence_outer),
        "--teff-T0", str(c.teff_t0),
        "--teff-p", str(c.teff_p),
        "--fcol", str(c.fcol),
        "--disk-time", str(c.disk_time),
        "--disk-orbital-boost", str(c.orbital_boost),
        *extra,
    ]
    if no_build:
        cmd.append("--no-build")
    run(cmd, env)


def render_debug(c: Candidate, out_dir: Path, width: int, height: int, quality: str,
                 env: dict[str, str], extra: list[str]) -> dict[str, str]:
    paths: dict[str, str] = {}
    for dbg in ("photosphere", "skin", "corona", "activity", "perturbation", "hdr"):
        path = out_dir / f"{c.name}_{dbg}.png"
        cmd = [
            "bash", str(RUN_PIPELINE),
            "--source-model", c.source_model,
            "--presentation", "scientific",
            "--look", "linear",
            "--quality", quality,
            "--width", str(width),
            "--height", str(height),
            "--output", str(path),
            "--realism-debug", dbg,
            "--disk-turbulence", str(c.disk_turbulence),
            "--disk-turbulence-inner", str(c.disk_turbulence_inner),
            "--disk-turbulence-outer", str(c.disk_turbulence_outer),
            "--teff-T0", str(c.teff_t0),
            "--teff-p", str(c.teff_p),
            "--fcol", str(c.fcol),
            "--disk-time", str(c.disk_time),
            "--disk-orbital-boost", str(c.orbital_boost),
            "--no-build",
            *extra,
        ]
        run(cmd, env)
        paths[dbg] = str(path)
    return paths


def rgb(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def luma(im: np.ndarray) -> np.ndarray:
    return im[..., 0] * 0.2126 + im[..., 1] * 0.7152 + im[..., 2] * 0.0722


def entropy01(y: np.ndarray) -> float:
    vals = y[y > 0.015]
    if vals.size < 16:
        return 0.0
    hist, _ = np.histogram(np.clip(vals, 0.0, 1.0), bins=48, range=(0.0, 1.0))
    p = hist.astype(np.float64)
    p = p[p > 0] / max(float(np.sum(p)), 1.0)
    return float(-np.sum(p * np.log2(p)) / math.log2(48.0))


def gradient(y: np.ndarray) -> np.ndarray:
    gy, gx = np.gradient(y)
    return np.sqrt(gx * gx + gy * gy)


def radial_azimuth_metrics(y: np.ndarray) -> tuple[float, float, float, float]:
    h, w = y.shape
    yy, xx = np.mgrid[0:h, 0:w]
    cx = 0.5 * (w - 1)
    cy = 0.5 * (h - 1)
    xn = (xx - cx) / max(w, 1)
    yn = (yy - cy) / max(h, 1)
    r = np.sqrt(xn * xn + yn * yn)
    phi = np.arctan2(yn, xn)
    active = y > max(0.018, float(np.percentile(y, 70.0)) * 0.25)
    if np.count_nonzero(active) < 32:
        return 0.0, 0.0, 0.0, 0.0
    bins = np.linspace(0.0, float(np.max(r[active]) + 1e-6), 18)
    radial_means = []
    az_vars = []
    ring_edges = []
    for lo, hi in zip(bins[:-1], bins[1:]):
        m = active & (r >= lo) & (r < hi)
        if np.count_nonzero(m) < 8:
            continue
        radial_means.append(float(np.mean(y[m])))
        az_vars.append(float(np.var(y[m]) / max(float(np.mean(y[m])) ** 2, 1e-8)))
        ring_edges.append(float(np.mean(gradient(y)[m])))
    radial_contrast = (max(radial_means) - min(radial_means)) / max(np.mean(radial_means), 1e-8) if radial_means else 0.0
    azimuthal_variance = float(np.mean(az_vars)) if az_vars else 0.0
    ring_sharpness = float(np.percentile(ring_edges, 90.0)) if ring_edges else 0.0
    left = active & (xx < cx)
    right = active & (xx >= cx)
    crescent = abs(float(np.sum(y[left])) - float(np.sum(y[right]))) / max(float(np.sum(y[active])), 1e-8)
    _ = phi  # kept for future angular-bin metrics
    return radial_contrast, azimuthal_variance, crescent, ring_sharpness


def image_metrics(path: Path) -> dict[str, float]:
    im = rgb(path)
    y = luma(im)
    active = y > 0.015
    g = gradient(y)
    radial_contrast, az_var, crescent, ring_sharp = radial_azimuth_metrics(y)
    high_freq = float(np.percentile(g[active], 95.0)) if np.any(active) else 0.0
    sat = float(np.mean(np.max(im, axis=2) > 0.985))
    bg = float(np.mean(y < 0.006))
    return {
        "mean_luma": float(np.mean(y)),
        "active_mean_luma": float(np.mean(y[active])) if np.any(active) else 0.0,
        "p90_luma": float(np.percentile(y, 90.0)),
        "luma_entropy": entropy01(y),
        "radial_contrast": radial_contrast,
        "azimuthal_variance": az_var,
        "crescent_asymmetry": crescent,
        "saturated_pixel_ratio": sat,
        "black_background_preservation": bg,
        "high_frequency_texture_energy": high_freq,
        "ring_sharpness_proxy": ring_sharp,
    }


def score(m: dict[str, float]) -> dict[str, float]:
    physics = (
        0.23 * min(m["radial_contrast"] / 2.2, 1.0)
        + 0.22 * min(m["azimuthal_variance"] / 0.85, 1.0)
        + 0.18 * min(m["crescent_asymmetry"] / 0.55, 1.0)
        + 0.16 * min(m["ring_sharpness_proxy"] / 0.10, 1.0)
        + 0.21 * min(m["black_background_preservation"] / 0.82, 1.0)
    )
    cinematic = (
        0.24 * min(m["luma_entropy"] / 0.78, 1.0)
        + 0.22 * min(m["high_frequency_texture_energy"] / 0.055, 1.0)
        + 0.22 * min(m["active_mean_luma"] / 0.22, 1.0)
        + 0.18 * min(m["crescent_asymmetry"] / 0.50, 1.0)
        + 0.14 * (1.0 - min(m["saturated_pixel_ratio"] / 0.025, 1.0))
    )
    total = 0.58 * physics + 0.42 * cinematic
    return {"physics_score": physics, "cinematic_score": cinematic, "score": total}


def make_contact_sheet(rows: list[tuple[str, Path]], out_path: Path) -> None:
    thumbs = []
    for label, path in rows:
        im = Image.open(path).convert("RGB").resize((240, 135))
        canvas = Image.new("RGB", (240, 160), (12, 12, 12))
        canvas.paste(im, (0, 0))
        draw = ImageDraw.Draw(canvas)
        draw.text((6, 140), label[:34], fill=(235, 235, 235))
        thumbs.append(canvas)
    if not thumbs:
        return
    cols = min(3, len(thumbs))
    rows_n = int(math.ceil(len(thumbs) / cols))
    sheet = Image.new("RGB", (cols * 240, rows_n * 160), (0, 0, 0))
    for i, im in enumerate(thumbs):
        sheet.paste(im, ((i % cols) * 240, (i // cols) * 160))
    sheet.save(out_path)


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.setdefault("BH_DERIVED_DATA_PATH", "/private/tmp/ProjectGargantuaDiskSearchDerivedData")
    env.setdefault("BH_ETA_HISTORY", str(out_dir / "eta_history.json"))
    candidates = deterministic_candidates(args.source_model, args.count)
    results = []
    first = True
    for c in candidates:
        path = out_dir / f"{c.name}.png"
        no_build = args.no_build or (not first and not args.rebuild_each_render)
        render_candidate(c, path, args.width, args.height, args.quality, no_build, args.extra, env)
        first = False
        m = image_metrics(path)
        s = score(m)
        results.append({
            "candidate": asdict(c),
            "path": str(path),
            "metrics": m,
            **s,
        })

    results.sort(key=lambda item: item["score"], reverse=True)
    top = results[: max(1, args.top)]
    for item in top:
        c = Candidate(**item["candidate"])
        item["debug_outputs"] = render_debug(c, out_dir, args.width, args.height, args.quality, env, args.extra)

    best = top[0]
    (out_dir / "metrics.json").write_text(json.dumps({"results": results}, indent=2, sort_keys=True), encoding="utf-8")
    (out_dir / "best_params.json").write_text(json.dumps(best, indent=2, sort_keys=True), encoding="utf-8")
    make_contact_sheet([(r["candidate"]["name"], Path(r["path"])) for r in top], out_dir / "top_candidates_contact.png")
    print(json.dumps({"best": best, "top": top}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
