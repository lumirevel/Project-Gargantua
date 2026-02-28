#!/usr/bin/env python3
import argparse
import json
import shlex
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Union

import numpy as np

COLLISION_DTYPE_V6 = np.dtype(
    [
        ("hit", "<u4"),
        ("ct", "<f4"),
        ("T", "<f4"),
        ("_pad0", "V4"),
        ("v_disk", "<f4", (3,)),
        ("_pad1", "V4"),
        ("direct_world", "<f4", (3,)),
        ("_pad2", "V4"),
        ("noise", "<f4"),
        ("emit_r_norm", "<f4"),
        ("emit_phi", "<f4"),
        ("emit_z_norm", "<f4"),
    ]
)


def run_checked(cmd: List[str], cwd: Path) -> None:
    print("+", shlex.join(cmd))
    subprocess.run(cmd, cwd=str(cwd), check=True)


def read_ppm(path: Path) -> np.ndarray:
    with path.open("rb") as f:
        magic = f.readline().strip()
        if magic != b"P6":
            raise ValueError(f"expected P6 PPM, got {magic!r}")
        line = f.readline()
        while line.startswith(b"#"):
            line = f.readline()
        width, height = map(int, line.strip().split())
        maxv = int(f.readline().strip())
        if maxv != 255:
            raise ValueError("expected max value 255")
        raw = f.read()
    expected = width * height * 3
    if len(raw) != expected:
        raise ValueError(f"PPM payload size mismatch: got {len(raw)}, expected {expected}")
    return np.frombuffer(raw, dtype=np.uint8).reshape(height, width, 3)


def write_ppm(path: Path, img: np.ndarray) -> None:
    h, w, c = img.shape
    if c != 3:
        raise ValueError("image must be HxWx3")
    with path.open("wb") as f:
        f.write(f"P6\n{w} {h}\n255\n".encode("ascii"))
        f.write(img.astype(np.uint8, copy=False).tobytes())


def load_meta(path: Path) -> Dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def load_collisions(path: Path, meta_path: Path) -> Tuple[np.memmap, Dict]:
    meta = load_meta(meta_path)
    width = int(meta.get("width", 0))
    height = int(meta.get("height", 0))
    if width <= 0 or height <= 0:
        raise ValueError("collision meta must include positive width/height")

    stride_meta = int(meta.get("collisionStride", COLLISION_DTYPE_V6.itemsize))
    if stride_meta != COLLISION_DTYPE_V6.itemsize:
        raise ValueError(f"unsupported collisionStride={stride_meta} (expected {COLLISION_DTYPE_V6.itemsize})")

    total = width * height
    expected_size = total * COLLISION_DTYPE_V6.itemsize
    raw_size = path.stat().st_size
    if raw_size == expected_size:
        byte_offset = 0
    elif raw_size == expected_size * 2:
        byte_offset = expected_size
    else:
        raise ValueError(f"collision size mismatch: got {raw_size}, expected {expected_size} or {expected_size*2}")

    rec = np.memmap(path, dtype=COLLISION_DTYPE_V6, mode="r", shape=(total,), offset=byte_offset)
    return rec, meta


def compute_global_ssim(x: np.ndarray, y: np.ndarray) -> float:
    x = x.astype(np.float64)
    y = y.astype(np.float64)
    ux = float(x.mean())
    uy = float(y.mean())
    vx = float(np.mean((x - ux) ** 2))
    vy = float(np.mean((y - uy) ** 2))
    cxy = float(np.mean((x - ux) * (y - uy)))
    c1 = (0.01 * 255.0) ** 2
    c2 = (0.03 * 255.0) ** 2
    denom = (ux * ux + uy * uy + c1) * (vx + vy + c2)
    if denom <= 1e-12:
        return 1.0
    num = (2.0 * ux * uy + c1) * (2.0 * cxy + c2)
    return float(num / denom)


def fmt(v: Optional[float], digits: int = 6) -> str:
    if v is None:
        return "n/a"
    return f"{v:.{digits}f}"


def build_pipeline_cmd(
    run_pipeline: Path,
    no_build: bool,
    width: int,
    height: int,
    ssaa: int,
    preset: str,
    metric: str,
    spin: float,
    rcp: float,
    collisions_out: Path,
    image_out: Path,
    extra_tokens: List[str],
    atlas_args: List[str],
) -> List[str]:
    cmd = ["/bin/bash", str(run_pipeline)]
    if no_build:
        cmd.append("--no-build")
    cmd += [
        "--width",
        str(width),
        "--height",
        str(height),
        "--ssaa",
        str(ssaa),
        "--preset",
        preset,
        "--metric",
        metric,
        "--spin",
        str(spin),
        "--rcp",
        str(rcp),
        "--collisions",
        "debug",
        "--collisions-out",
        str(collisions_out),
        "--output",
        str(image_out),
    ]
    cmd += extra_tokens
    cmd += atlas_args
    return cmd


def main() -> None:
    parser = argparse.ArgumentParser(description="Automated stage-3 A/B quality report (no-atlas vs atlas)")
    root = Path(__file__).resolve().parents[1]
    parser.add_argument("--out-dir", default="/tmp/stage3_ab", help="output directory")
    parser.add_argument("--run-pipeline", default=str(root / "Blackhole" / "run_pipeline.sh"))
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=640)
    parser.add_argument("--ssaa", type=int, default=1)
    parser.add_argument("--preset", default="interstellar")
    parser.add_argument("--metric", default="kerr")
    parser.add_argument("--spin", type=float, default=0.92)
    parser.add_argument("--rcp", type=float, default=9.0)
    parser.add_argument("--no-build", action="store_true", help="skip Swift build")
    parser.add_argument("--extra", default="", help="extra run_pipeline args, quoted string")

    parser.add_argument("--atlas-width", type=int, default=1024)
    parser.add_argument("--atlas-height", type=int, default=512)
    parser.add_argument("--atlas-r-min", type=float, default=1.0)
    parser.add_argument("--atlas-r-max", type=float, default=9.0)
    parser.add_argument("--atlas-r-warp", type=float, default=0.65)
    parser.add_argument("--atlas-density-source", choices=["noise", "ones"], default="noise")

    parser.add_argument("--disk-atlas-temp-scale", type=float, default=1.0)
    parser.add_argument("--disk-atlas-density-blend", type=float, default=0.7)
    parser.add_argument("--disk-atlas-vr-scale", type=float, default=0.35)
    parser.add_argument("--disk-atlas-vphi-scale", type=float, default=1.0)
    parser.add_argument("--inner-r-threshold", type=float, default=2.2, help="r/rs threshold for inner-ring stats")
    parser.add_argument("--diff-gain", type=float, default=4.0, help="absolute-difference visualization gain")
    args = parser.parse_args()

    if args.width <= 0 or args.height <= 0:
        raise ValueError("width/height must be positive")
    if args.ssaa not in (1, 2, 4):
        raise ValueError("ssaa must be one of 1, 2, 4")
    if args.atlas_width <= 0 or args.atlas_height <= 0:
        raise ValueError("atlas width/height must be positive")
    if not (args.atlas_r_max > args.atlas_r_min):
        raise ValueError("atlas-r-max must be greater than atlas-r-min")
    if args.atlas_r_warp <= 0:
        raise ValueError("atlas-r-warp must be > 0")

    out_dir = Path(args.out_dir).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    run_pipeline = Path(args.run_pipeline).expanduser().resolve()
    export_bridge = root / "scripts" / "export_stage3_bridge.py"
    build_atlas = root / "scripts" / "build_disk_atlas.py"

    baseline_ppm = out_dir / "baseline_no_atlas.ppm"
    baseline_bin = out_dir / "baseline_no_atlas.bin"
    baseline_meta = Path(str(baseline_bin) + ".json")

    stage3_npz = out_dir / "baseline.stage3.npz"
    atlas_bin = out_dir / "disk_atlas.bin"
    atlas_meta = Path(str(atlas_bin) + ".json")

    atlas_ppm = out_dir / "atlas_stage3.ppm"
    atlas_collisions = out_dir / "atlas_stage3.bin"
    atlas_collisions_meta = Path(str(atlas_collisions) + ".json")

    diff_ppm = out_dir / "diff_abs_xgain.ppm"
    report_json = out_dir / "report.json"
    report_md = out_dir / "report.md"

    extra_tokens = shlex.split(args.extra)
    commands: List[List[str]] = []

    baseline_cmd = build_pipeline_cmd(
        run_pipeline=run_pipeline,
        no_build=args.no_build,
        width=args.width,
        height=args.height,
        ssaa=args.ssaa,
        preset=args.preset,
        metric=args.metric,
        spin=args.spin,
        rcp=args.rcp,
        collisions_out=baseline_bin,
        image_out=baseline_ppm,
        extra_tokens=extra_tokens,
        atlas_args=[],
    )
    commands.append(baseline_cmd)
    run_checked(baseline_cmd, cwd=root)

    bridge_cmd = [
        "python3",
        str(export_bridge),
        "--input",
        str(baseline_bin),
        "--meta",
        str(baseline_meta),
        "--output",
        str(stage3_npz),
    ]
    commands.append(bridge_cmd)
    run_checked(bridge_cmd, cwd=root)

    atlas_build_cmd = [
        "python3",
        str(build_atlas),
        "--input",
        str(stage3_npz),
        "--output",
        str(atlas_bin),
        "--width",
        str(args.atlas_width),
        "--height",
        str(args.atlas_height),
        "--r-min",
        str(args.atlas_r_min),
        "--r-max",
        str(args.atlas_r_max),
        "--r-warp",
        str(args.atlas_r_warp),
        "--density-source",
        args.atlas_density_source,
    ]
    commands.append(atlas_build_cmd)
    run_checked(atlas_build_cmd, cwd=root)

    atlas_render_cmd = build_pipeline_cmd(
        run_pipeline=run_pipeline,
        no_build=True,
        width=args.width,
        height=args.height,
        ssaa=args.ssaa,
        preset=args.preset,
        metric=args.metric,
        spin=args.spin,
        rcp=args.rcp,
        collisions_out=atlas_collisions,
        image_out=atlas_ppm,
        extra_tokens=extra_tokens,
        atlas_args=[
            "--disk-atlas",
            str(atlas_bin),
            "--disk-atlas-temp-scale",
            str(args.disk_atlas_temp_scale),
            "--disk-atlas-density-blend",
            str(args.disk_atlas_density_blend),
            "--disk-atlas-vr-scale",
            str(args.disk_atlas_vr_scale),
            "--disk-atlas-vphi-scale",
            str(args.disk_atlas_vphi_scale),
            "--disk-atlas-r-min",
            str(args.atlas_r_min),
            "--disk-atlas-r-max",
            str(args.atlas_r_max),
            "--disk-atlas-r-warp",
            str(args.atlas_r_warp),
        ],
    )
    commands.append(atlas_render_cmd)
    run_checked(atlas_render_cmd, cwd=root)

    base_img = read_ppm(baseline_ppm)
    atlas_img = read_ppm(atlas_ppm)
    if base_img.shape != atlas_img.shape:
        raise ValueError(f"image shape mismatch: {base_img.shape} vs {atlas_img.shape}")

    d = atlas_img.astype(np.float32) - base_img.astype(np.float32)
    abs_d = np.abs(d)
    mae_rgb = float(abs_d.mean())
    rmse_rgb = float(np.sqrt(np.mean(d * d)))
    psnr_db = None if rmse_rgb <= 1e-12 else float(20.0 * np.log10(255.0 / rmse_rgb))

    w = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    base_y = np.tensordot(base_img.astype(np.float32), w, axes=([2], [0]))
    atlas_y = np.tensordot(atlas_img.astype(np.float32), w, axes=([2], [0]))
    dy = atlas_y - base_y
    abs_dy = np.abs(dy)
    mae_luma = float(abs_dy.mean())
    p95_luma = float(np.percentile(abs_dy, 95.0))
    p99_luma = float(np.percentile(abs_dy, 99.0))
    ssim_global = compute_global_ssim(base_y, atlas_y)

    vis = np.clip(abs_d * float(args.diff_gain), 0.0, 255.0).astype(np.uint8)
    write_ppm(diff_ppm, vis)

    base_rec, base_meta = load_collisions(baseline_bin, baseline_meta)
    atlas_rec, atlas_meta_collision = load_collisions(atlas_collisions, atlas_collisions_meta)
    if base_rec.shape[0] != atlas_rec.shape[0]:
        raise ValueError("collision record count mismatch between baseline and atlas runs")

    hit_base = base_rec["hit"] != 0
    hit_atlas = atlas_rec["hit"] != 0
    hit_common = hit_base & hit_atlas
    hit_union = hit_base | hit_atlas
    hit_union_count = int(np.count_nonzero(hit_union))
    hit_common_count = int(np.count_nonzero(hit_common))

    collision_metrics: Dict[str, Union[Optional[float], int]] = {
        "hit_count_baseline": int(np.count_nonzero(hit_base)),
        "hit_count_atlas": int(np.count_nonzero(hit_atlas)),
        "hit_count_union": hit_union_count,
        "hit_count_common": hit_common_count,
        "hit_common_ratio": float(hit_common_count / max(hit_union_count, 1)),
        "temp_mae_common": None,
        "ct_mae_common": None,
        "noise_mae_common": None,
        "emit_r_norm_mae_common": None,
        "g_factor_mae_common": None,
        "inner_hit_count_common": 0,
        "inner_noise_std_baseline": None,
        "inner_noise_std_atlas": None,
    }

    if hit_common_count > 0:
        t0 = base_rec["T"][hit_common].astype(np.float64)
        t1 = atlas_rec["T"][hit_common].astype(np.float64)
        ct0 = base_rec["ct"][hit_common].astype(np.float64)
        ct1 = atlas_rec["ct"][hit_common].astype(np.float64)
        n0 = base_rec["noise"][hit_common].astype(np.float64)
        n1 = atlas_rec["noise"][hit_common].astype(np.float64)
        r0 = base_rec["emit_r_norm"][hit_common].astype(np.float64)
        r1 = atlas_rec["emit_r_norm"][hit_common].astype(np.float64)

        collision_metrics["temp_mae_common"] = float(np.mean(np.abs(t1 - t0)))
        collision_metrics["ct_mae_common"] = float(np.mean(np.abs(ct1 - ct0)))
        collision_metrics["noise_mae_common"] = float(np.mean(np.abs(n1 - n0)))
        collision_metrics["emit_r_norm_mae_common"] = float(np.mean(np.abs(r1 - r0)))

        if str(base_meta.get("spectralEncoding", "")).lower() == "gfactor_v1":
            g0 = base_rec["v_disk"][hit_common][:, 0].astype(np.float64)
            g1 = atlas_rec["v_disk"][hit_common][:, 0].astype(np.float64)
            collision_metrics["g_factor_mae_common"] = float(np.mean(np.abs(g1 - g0)))

        inner_mask = hit_common & (base_rec["emit_r_norm"] <= float(args.inner_r_threshold))
        inner_count = int(np.count_nonzero(inner_mask))
        collision_metrics["inner_hit_count_common"] = inner_count
        if inner_count > 0:
            n0_inner = base_rec["noise"][inner_mask].astype(np.float64)
            n1_inner = atlas_rec["noise"][inner_mask].astype(np.float64)
            collision_metrics["inner_noise_std_baseline"] = float(np.std(n0_inner))
            collision_metrics["inner_noise_std_atlas"] = float(np.std(n1_inner))

    report = {
        "inputs": {
            "width": args.width,
            "height": args.height,
            "ssaa": args.ssaa,
            "preset": args.preset,
            "metric": args.metric,
            "spin": args.spin,
            "rcp": args.rcp,
            "extra": args.extra,
            "atlas_width": args.atlas_width,
            "atlas_height": args.atlas_height,
            "atlas_r_min": args.atlas_r_min,
            "atlas_r_max": args.atlas_r_max,
            "atlas_r_warp": args.atlas_r_warp,
            "disk_atlas_temp_scale": args.disk_atlas_temp_scale,
            "disk_atlas_density_blend": args.disk_atlas_density_blend,
            "disk_atlas_vr_scale": args.disk_atlas_vr_scale,
            "disk_atlas_vphi_scale": args.disk_atlas_vphi_scale,
            "inner_r_threshold": args.inner_r_threshold,
            "diff_gain": args.diff_gain,
        },
        "paths": {
            "baseline_image": str(baseline_ppm),
            "baseline_collisions": str(baseline_bin),
            "stage3_npz": str(stage3_npz),
            "atlas_bin": str(atlas_bin),
            "atlas_meta": str(atlas_meta),
            "atlas_image": str(atlas_ppm),
            "atlas_collisions": str(atlas_collisions),
            "diff_abs_image": str(diff_ppm),
            "report_md": str(report_md),
        },
        "image_metrics": {
            "mae_rgb_0_255": mae_rgb,
            "rmse_rgb_0_255": rmse_rgb,
            "psnr_db": psnr_db,
            "mae_luma_0_255": mae_luma,
            "p95_abs_luma_0_255": p95_luma,
            "p99_abs_luma_0_255": p99_luma,
            "global_ssim_luma": ssim_global,
        },
        "collision_metrics": collision_metrics,
        "baseline_meta": {
            "version": base_meta.get("version"),
            "diskModel": base_meta.get("diskModel"),
            "spectralEncoding": base_meta.get("spectralEncoding"),
            "diskAtlasEnabled": base_meta.get("diskAtlasEnabled"),
        },
        "atlas_meta": {
            "version": atlas_meta_collision.get("version"),
            "diskModel": atlas_meta_collision.get("diskModel"),
            "spectralEncoding": atlas_meta_collision.get("spectralEncoding"),
            "diskAtlasEnabled": atlas_meta_collision.get("diskAtlasEnabled"),
            "diskAtlasPath": atlas_meta_collision.get("diskAtlasPath"),
            "diskAtlasWidth": atlas_meta_collision.get("diskAtlasWidth"),
            "diskAtlasHeight": atlas_meta_collision.get("diskAtlasHeight"),
            "diskAtlasRNormMin": atlas_meta_collision.get("diskAtlasRNormMin"),
            "diskAtlasRNormMax": atlas_meta_collision.get("diskAtlasRNormMax"),
            "diskAtlasRNormWarp": atlas_meta_collision.get("diskAtlasRNormWarp"),
        },
        "commands": [shlex.join(cmd) for cmd in commands],
    }

    with report_json.open("w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=True, indent=2, sort_keys=True)

    md_lines = [
        "# Stage-3 A/B Report",
        "",
        "## Summary",
        f"- baseline image: `{baseline_ppm}`",
        f"- atlas image: `{atlas_ppm}`",
        f"- diff image (abs x{args.diff_gain:g}): `{diff_ppm}`",
        f"- report json: `{report_json}`",
        "",
        "## Image Metrics",
        f"- MAE RGB (0..255): {fmt(mae_rgb, 4)}",
        f"- RMSE RGB (0..255): {fmt(rmse_rgb, 4)}",
        f"- PSNR (dB): {'inf' if psnr_db is None else fmt(psnr_db, 4)}",
        f"- MAE luma (0..255): {fmt(mae_luma, 4)}",
        f"- P95 |delta luma| (0..255): {fmt(p95_luma, 4)}",
        f"- P99 |delta luma| (0..255): {fmt(p99_luma, 4)}",
        f"- Global SSIM (luma): {fmt(ssim_global, 6)}",
        "",
        "## Collision Metrics",
        f"- hit count baseline: {collision_metrics['hit_count_baseline']}",
        f"- hit count atlas: {collision_metrics['hit_count_atlas']}",
        f"- hit count union: {collision_metrics['hit_count_union']}",
        f"- hit count common: {collision_metrics['hit_count_common']}",
        f"- hit common ratio: {fmt(collision_metrics['hit_common_ratio'], 6)}",
        f"- temp MAE (common hit): {fmt(collision_metrics['temp_mae_common'], 6)}",
        f"- ct MAE (common hit): {fmt(collision_metrics['ct_mae_common'], 6)}",
        f"- noise MAE (common hit): {fmt(collision_metrics['noise_mae_common'], 6)}",
        f"- emit_r_norm MAE (common hit): {fmt(collision_metrics['emit_r_norm_mae_common'], 6)}",
        f"- g_factor MAE (common hit): {fmt(collision_metrics['g_factor_mae_common'], 6)}",
        f"- inner hit count (r/rs <= {args.inner_r_threshold:g}): {collision_metrics['inner_hit_count_common']}",
        f"- inner noise std baseline: {fmt(collision_metrics['inner_noise_std_baseline'], 6)}",
        f"- inner noise std atlas: {fmt(collision_metrics['inner_noise_std_atlas'], 6)}",
        "",
        "## Commands",
    ]
    md_lines += [f"- `{line}`" for line in report["commands"]]
    md_lines.append("")
    report_md.write_text("\n".join(md_lines), encoding="utf-8")

    print(f"report json: {report_json}")
    print(f"report md:   {report_md}")
    print(f"diff image:  {diff_ppm}")


if __name__ == "__main__":
    main()
