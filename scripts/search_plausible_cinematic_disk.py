#!/usr/bin/env python3
"""Science-gated search for physics-constrained cinematic disk candidates."""

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
MINIMAL_DIAGNOSTICS = ("activity", "emissivity-pre-transfer", "optical-depth", "transfer-saturation")
FULL_DIAGNOSTICS = (
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
)


@dataclass(frozen=True)
class Candidate:
    name: str
    source_model: str
    preset: str
    pcd_density_exp: float
    pcd_emissivity_scale: float
    pcd_opacity_scale: float
    pcd_seed: int
    pcd_structure_scale: float
    pcd_spiral_amp: float
    pcd_spiral_pitch: float
    pcd_clump_contrast: float
    pcd_hot_crescent: float
    temperature_scale: float
    temp_exponent: float
    color_factor: float
    disk_turbulence: float
    disk_time: float
    orbital_boost: float
    photosphere_thickness: float


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--count", type=int, default=12)
    p.add_argument("--top", type=int, default=3)
    p.add_argument("--width", type=int, default=160)
    p.add_argument("--height", type=int, default=90)
    p.add_argument("--quality", default="preview")
    p.add_argument("--out-dir", default="/private/tmp/bh_pcd_goal_search")
    p.add_argument("--seed", type=int, default=1729)
    p.add_argument("--source-model", default="physics-constrained-cinematic-disk-v1")
    p.add_argument("--presentation", default="scientific")
    p.add_argument("--look", default="linear")
    p.add_argument("--no-build", action="store_true")
    p.add_argument("--min-distinct-rmse", type=float, default=0.018)
    p.add_argument("--extra", nargs=argparse.REMAINDER, default=[])
    return p.parse_args()


def run(cmd: list[str], env: dict[str, str]) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=str(ROOT), env=env, check=True)


def frac(x: float) -> float:
    return x - math.floor(x)


def candidate_list(args: argparse.Namespace, count: int) -> list[Candidate]:
    presets = ("balanced", "realistic", "thin-disk", "eht")
    out: list[Candidate] = []
    for i in range(max(count, 1)):
        base = args.seed * 0.001 + i + 1
        h = [frac(base * k) for k in (0.61803398875, 0.41421356237, 0.73205080757, 0.27950849719,
                                      0.16227766017, 0.30277563773, 0.23606797749, 0.12732395447,
                                      0.17320508076, 0.14142135623, 0.57735026919, 0.75487766625)]
        # Keep EHT/high-inclination as a minority; it is useful but should not
        # dominate the search purely through beaming contrast.
        preset = presets[3] if (i % 7 == 3) else presets[int(math.floor(h[0] * 3.0))]
        out.append(Candidate(
            name=f"camd_{i:02d}",
            source_model=args.source_model,
            preset=preset,
            pcd_density_exp=round(0.65 + 1.15 * h[1], 4),
            pcd_emissivity_scale=round(0.78 + 1.25 * h[2], 4),
            pcd_opacity_scale=round(0.35 + 2.25 * h[3], 4),
            pcd_seed=args.seed + 31 * i,
            pcd_structure_scale=round(0.85 + 1.85 * h[4], 4),
            pcd_spiral_amp=round(0.10 + 0.78 * h[5], 4),
            pcd_spiral_pitch=round(2.0 + 10.0 * h[6], 4),
            pcd_clump_contrast=round(0.10 + 0.82 * h[7], 4),
            pcd_hot_crescent=round(0.10 + 0.86 * h[8], 4),
            temperature_scale=round(13500.0 + 8500.0 * h[9], 2),
            temp_exponent=round(0.56 + 0.27 * h[10], 4),
            color_factor=round(1.08 + 0.25 * h[11], 4),
            disk_turbulence=round(0.80 + 1.60 * h[0], 4),
            disk_time=round(32.0 * h[2], 4),
            orbital_boost=round(0.88 + 0.42 * h[6], 4),
            photosphere_thickness=round(0.95 + 0.40 * h[3], 4),
        ))
    return out


def command_for(c: Candidate, path: Path, args: argparse.Namespace, debug: str | None = None, no_build: bool = False) -> list[str]:
    cmd = [
        "bash", str(RUN_PIPELINE),
        "--source-model", c.source_model,
        "--quality", args.quality,
        "--presentation", args.presentation,
        "--look", args.look,
        "--preset", c.preset,
        "--width", str(args.width),
        "--height", str(args.height),
        "--output", str(path),
        "--pcd-density-exp", str(c.pcd_density_exp),
        "--pcd-emissivity-scale", str(c.pcd_emissivity_scale),
        "--pcd-opacity-scale", str(c.pcd_opacity_scale),
        "--pcd-seed", str(c.pcd_seed),
        "--pcd-structure-scale", str(c.pcd_structure_scale),
        "--pcd-spiral-amp", str(c.pcd_spiral_amp),
        "--pcd-spiral-pitch", str(c.pcd_spiral_pitch),
        "--pcd-clump-contrast", str(c.pcd_clump_contrast),
        "--pcd-hot-crescent", str(c.pcd_hot_crescent),
        "--teff-T0", str(c.temperature_scale),
        "--teff-p", str(c.temp_exponent),
        "--fcol", str(c.color_factor),
        "--disk-turbulence", str(c.disk_turbulence),
        "--disk-time", str(c.disk_time),
        "--disk-orbital-boost", str(c.orbital_boost),
        "--thick-scale", str(c.photosphere_thickness),
        *args.extra,
    ]
    if c.preset == "eht":
        cmd += ["--metric", "kerr", "--spin", "0.90"]
    if debug:
        cmd += ["--realism-debug", debug]
    if no_build:
        cmd.append("--no-build")
    return cmd


def no_structure_candidate(args: argparse.Namespace) -> Candidate:
    return Candidate(
        name="no_structure_reference",
        source_model=args.source_model,
        preset="balanced",
        pcd_density_exp=1.15,
        pcd_emissivity_scale=1.0,
        pcd_opacity_scale=1.0,
        pcd_seed=args.seed,
        pcd_structure_scale=0.2,
        pcd_spiral_amp=0.0,
        pcd_spiral_pitch=5.0,
        pcd_clump_contrast=0.0,
        pcd_hot_crescent=0.0,
        temperature_scale=17800.0,
        temp_exponent=0.66,
        color_factor=1.20,
        disk_turbulence=0.0,
        disk_time=0.0,
        orbital_boost=1.12,
        photosphere_thickness=1.12,
    )


def read_rgb(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def luma(rgb: np.ndarray) -> np.ndarray:
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def grad(y: np.ndarray) -> np.ndarray:
    gy, gx = np.gradient(y)
    return np.sqrt(gx * gx + gy * gy)


def image_distance(a: Path, b: Path) -> dict[str, float]:
    ia = read_rgb(a)
    ib = read_rgb(b)
    d = ia - ib
    ya = luma(ia)
    yb = luma(ib)
    ha, _ = np.histogram(ya, bins=32, range=(0, 1), density=True)
    hb, _ = np.histogram(yb, bins=32, range=(0, 1), density=True)
    return {
        "mae": float(np.mean(np.abs(d))),
        "rmse": float(np.sqrt(np.mean(d * d))),
        "luma_hist_l1": float(np.mean(np.abs(ha - hb))),
    }


def entropy(y: np.ndarray) -> float:
    vals = y[y > 0.015]
    if vals.size < 32:
        return 0.0
    hist, _ = np.histogram(vals, bins=48, range=(0.0, 1.0))
    p = hist.astype(np.float64)
    p = p[p > 0] / max(float(np.sum(p)), 1.0)
    return float(-np.sum(p * np.log2(p)) / math.log2(48.0))


def spatial_stats(path: Path) -> dict[str, float]:
    rgb = read_rgb(path)
    y = luma(rgb)
    active = y > max(0.015, float(np.percentile(y, 70)) * 0.20)
    g = grad(y)
    h, w = y.shape
    yy, xx = np.mgrid[0:h, 0:w]
    cx = (w - 1) * 0.5
    cy = (h - 1) * 0.5
    xn = (xx - cx) / max(w, 1)
    yn = (yy - cy) / max(h, 1)
    r = np.sqrt(xn * xn + yn * yn)
    bins = np.linspace(0, float(np.max(r[active])) + 1e-6 if np.any(active) else 1.0, 18)
    means: list[float] = []
    azvars: list[float] = []
    for lo, hi in zip(bins[:-1], bins[1:]):
        m = active & (r >= lo) & (r < hi)
        if np.count_nonzero(m) < 8:
            continue
        mu = float(np.mean(y[m]))
        means.append(mu)
        azvars.append(float(np.var(y[m]) / max(mu * mu, 1e-8)))
    left = active & (xx < cx)
    right = active & (xx >= cx)
    return {
        "mean_luma": float(np.mean(y)),
        "active_mean_luma": float(np.mean(y[active])) if np.any(active) else 0.0,
        "p90_luma": float(np.percentile(y, 90)),
        "p95_luma": float(np.percentile(y, 95)),
        "active_fraction": float(np.mean(active)),
        "luma_entropy": entropy(y),
        "saturated_pixel_ratio": float(np.mean(np.max(rgb, axis=2) > 0.985)),
        "black_background_preservation": float(np.mean(y < 0.006)),
        "high_frequency_texture_energy": float(np.percentile(g[active], 95)) if np.any(active) else 0.0,
        "radial_contrast": (max(means) - min(means)) / max(float(np.mean(means)), 1e-8) if means else 0.0,
        "azimuthal_variance": float(np.mean(azvars)) if azvars else 0.0,
        "crescent_asymmetry": abs(float(np.sum(y[left])) - float(np.sum(y[right]))) / max(float(np.sum(y[active])), 1e-8) if np.any(active) else 0.0,
    }


def render_candidate(c: Candidate, args: argparse.Namespace, out_dir: Path, env: dict[str, str], first: bool) -> tuple[dict, bool]:
    cand_dir = out_dir / c.name
    cand_dir.mkdir(parents=True, exist_ok=True)
    preview = cand_dir / "preview.png"
    cmd = command_for(c, preview, args, no_build=(args.no_build or not first))
    (cand_dir / "params.json").write_text(json.dumps(asdict(c), indent=2, sort_keys=True), encoding="utf-8")
    (cand_dir / "command.json").write_text(json.dumps(cmd, indent=2), encoding="utf-8")
    run(cmd, env)
    diagnostics: dict[str, str] = {}
    for dbg in MINIMAL_DIAGNOSTICS:
        path = cand_dir / f"diagnostic_{dbg}.png"
        run(command_for(c, path, args, debug=dbg, no_build=True), env)
        diagnostics[dbg] = str(path)
    return {
        "candidate": asdict(c),
        "preview": str(preview),
        "diagnostics": diagnostics,
    }, False


def score_item(item: dict, no_structure_path: Path) -> dict:
    preview = Path(item["preview"])
    m = spatial_stats(preview)
    activity = spatial_stats(Path(item["diagnostics"]["activity"]))
    emissivity = spatial_stats(Path(item["diagnostics"]["emissivity-pre-transfer"]))
    tau = spatial_stats(Path(item["diagnostics"]["optical-depth"]))
    sat = spatial_stats(Path(item["diagnostics"]["transfer-saturation"]))
    dist_ref = image_distance(preview, no_structure_path)
    source_structure = max(activity["azimuthal_variance"], emissivity["azimuthal_variance"])
    transfer_saturation_active = sat["active_fraction"]
    science_reasons: list[str] = []
    science_gate = True
    if not (0.50 <= item["candidate"]["temp_exponent"] <= 0.86):
        science_gate = False
        science_reasons.append("temperature exponent outside monotone thin-disk range")
    if not (0.02 <= m["active_fraction"] <= 0.30):
        science_gate = False
        science_reasons.append("emission active fraction outside disk-like range")
    if m["saturated_pixel_ratio"] > 0.025:
        science_gate = False
        science_reasons.append("excess clipping")
    if transfer_saturation_active > 0.42:
        science_gate = False
        science_reasons.append("excess transfer saturation")
    if source_structure < 0.010:
        science_gate = False
        science_reasons.append("source diagnostics too smooth")
    if m["azimuthal_variance"] < 0.018:
        science_gate = False
        science_reasons.append("final disk too azimuthally smooth")

    science = (
        0.20 * min(m["black_background_preservation"] / 0.86, 1.0)
        + 0.18 * min(m["radial_contrast"] / 2.4, 1.0)
        + 0.18 * min(max(source_structure, m["azimuthal_variance"]) / 0.12, 1.0)
        + 0.16 * (1.0 - min(m["saturated_pixel_ratio"] / 0.025, 1.0))
        + 0.14 * (1.0 - min(transfer_saturation_active / 0.42, 1.0))
        + 0.14 * min(dist_ref["rmse"] / 0.055, 1.0)
    )
    aesthetic = (
        0.24 * min(m["luma_entropy"] / 0.80, 1.0)
        + 0.20 * min(m["high_frequency_texture_energy"] / 0.20, 1.0)
        + 0.18 * min(m["active_mean_luma"] / 0.24, 1.0)
        + 0.20 * min(m["radial_contrast"] / 2.6, 1.0)
        + 0.18 * min(m["crescent_asymmetry"] / 0.55, 1.0)
    )
    score = (0.62 * science + 0.38 * aesthetic) if science_gate else 0.28 * science
    caps: list[str] = []
    if m["azimuthal_variance"] < 0.06:
        score = min(score, 0.74)
        caps.append("azimuthal_variance_below_0p06")
    if source_structure > 0.030 and dist_ref["rmse"] < 0.012:
        score = min(score, 0.78)
        caps.append("source_structure_suppressed_in_final")
    if transfer_saturation_active > 0.35:
        score = min(score, 0.80)
        caps.append("transfer_saturation_excess")
    if m["azimuthal_variance"] < 0.025 and m["luma_entropy"] < 0.35:
        score = min(score, 0.90)
        caps.append("smooth_boring_disk_cap")
    item.update({
        "metrics": {
            **m,
            "activity_azimuthal_variance": activity["azimuthal_variance"],
            "emissivity_azimuthal_variance": emissivity["azimuthal_variance"],
            "optical_depth_active_fraction": tau["active_fraction"],
            "transfer_saturation_active_fraction": transfer_saturation_active,
            "rmse_vs_no_structure": dist_ref["rmse"],
            "source_structure_proxy": source_structure,
            "science_gate": science_gate,
            "science_gate_reasons": science_reasons,
            "score_caps": caps,
        },
        "science_score": science,
        "aesthetic_score": aesthetic,
        "score": score,
    })
    return item


def select_top(results: list[dict], top_n: int, min_rmse: float) -> list[dict]:
    pool = [r for r in results if r["metrics"]["science_gate"]]
    selected: list[dict] = []
    for item in sorted(pool, key=lambda x: x["score"], reverse=True):
        if len(selected) >= top_n:
            break
        duplicate = False
        for prev in selected:
            dist = image_distance(Path(item["preview"]), Path(prev["preview"]))
            if dist["rmse"] < min_rmse:
                item["near_duplicate_of"] = prev["candidate"]["name"]
                item["near_duplicate_distance"] = dist
                duplicate = True
                break
        if not duplicate:
            selected.append(item)
    return selected


def render_full_diagnostics(top: list[dict], args: argparse.Namespace, env: dict[str, str]) -> None:
    for item in top:
        c = Candidate(**item["candidate"])
        cand_dir = Path(item["preview"]).parent
        full = dict(item.get("diagnostics", {}))
        for dbg in FULL_DIAGNOSTICS:
            path = cand_dir / f"diagnostic_{dbg}.png"
            if not path.exists():
                run(command_for(c, path, args, debug=dbg, no_build=True), env)
            full[dbg] = str(path)
        item["diagnostics"] = full


def contact_sheet(items: list[dict], out_path: Path) -> None:
    cols = ("preview", "activity", "emissivity-pre-transfer", "optical-depth", "transfer-saturation")
    cell_w, cell_h, label_h = 220, 124, 38
    sheet = Image.new("RGB", (len(cols) * cell_w, max(1, len(items)) * (cell_h + label_h)), (0, 0, 0))
    for r, item in enumerate(items):
        for c, key in enumerate(cols):
            path = Path(item["preview"]) if key == "preview" else Path(item["diagnostics"][key])
            canvas = Image.new("RGB", (cell_w, cell_h + label_h), (8, 8, 8))
            if path.exists():
                canvas.paste(Image.open(path).convert("RGB").resize((cell_w, cell_h)), (0, 0))
            draw = ImageDraw.Draw(canvas)
            draw.text((5, cell_h + 3), f"{item['candidate']['name']} {key}\nscore={item['score']:.3f}", fill=(235, 235, 235))
            sheet.paste(canvas, (c * cell_w, r * (cell_h + label_h)))
    sheet.save(out_path)


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.setdefault("BH_DERIVED_DATA_PATH", "/private/tmp/ProjectGargantuaPcdGoalDerivedData")
    env.setdefault("BH_ETA_HISTORY", str(out_dir / "eta_history.json"))

    # Render a no-structure reference once. It is the scoring guard against
    # smooth, near-canonical disks being ranked as strong candidates.
    no_ref = no_structure_candidate(args)
    ref_item, first = render_candidate(no_ref, args, out_dir, env, first=True)
    no_structure_path = Path(ref_item["preview"])

    target_count = max(args.count, 1)
    results: list[dict] = []
    while True:
        first_render = first
        for c in candidate_list(args, target_count):
            if any(r["candidate"]["name"] == c.name for r in results):
                continue
            item, first_render = render_candidate(c, args, out_dir, env, first=first_render)
            results.append(score_item(item, no_structure_path))
        top = select_top(results, args.top, args.min_distinct_rmse)
        if len(top) >= min(args.top, 3) or target_count >= 24:
            break
        target_count = 24

    top = select_top(results, args.top, args.min_distinct_rmse)
    render_full_diagnostics(top, args, env)
    contact_sheet(top, out_dir / "top_candidates_sheet.png")

    report = {
        "source_model": args.source_model,
        "requested_count": args.count,
        "evaluated_count": len(results),
        "science_pass_count": sum(1 for r in results if r["metrics"]["science_gate"]),
        "near_duplicate_min_rmse": args.min_distinct_rmse,
        "no_structure_reference": ref_item,
        "results": sorted(results, key=lambda x: x["score"], reverse=True),
        "top": top,
        "top_candidates_sheet": str(out_dir / "top_candidates_sheet.png"),
        "passed": len(top) >= min(args.top, 3),
    }
    (out_dir / "search_report.json").write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    (out_dir / "top_candidates.json").write_text(json.dumps(top, indent=2, sort_keys=True), encoding="utf-8")
    if top:
        (out_dir / "best_params.json").write_text(json.dumps(top[0], indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({
        "passed": report["passed"],
        "evaluated_count": report["evaluated_count"],
        "science_pass_count": report["science_pass_count"],
        "top": [
            {
                "name": t["candidate"]["name"],
                "score": t["score"],
                "preview": t["preview"],
                "params": str(Path(t["preview"]).parent / "params.json"),
                "score_json": str(Path(t["preview"]).parent / "score.json"),
            }
            for t in top
        ],
    }, indent=2, sort_keys=True))
    for item in results:
        cand_dir = Path(item["preview"]).parent
        (cand_dir / "score.json").write_text(json.dumps(item, indent=2, sort_keys=True), encoding="utf-8")
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
