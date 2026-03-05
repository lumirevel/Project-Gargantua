#!/usr/bin/env python3
import argparse
import json
import math
import os
import platform
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np

from select_lensed_pixels import load_hit_map, parse_xy, select_pixels


COLLISION_DTYPE = np.dtype(
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
        ("_pad3", "V12"),
    ]
)


@dataclass
class RenderArtifacts:
    collisions: Path
    meta: Path
    image: Optional[Path]
    hits: int


def run(cmd: Sequence[str], cwd: Path, env: Optional[Dict[str, str]] = None) -> None:
    print("+", " ".join(str(c) for c in cmd))
    subprocess.run(cmd, cwd=str(cwd), env=env, check=True)


def build_binary(root: Path, derived_data: Path, force_build: bool) -> Path:
    bin_path = derived_data / "Build" / "Products" / "Release" / "Blackhole"
    if bin_path.exists() and not force_build:
        return bin_path

    cmd = [
        "xcodebuild",
        "-project",
        "Blackhole.xcodeproj",
        "-scheme",
        "Blackhole",
        "-configuration",
        "Release",
        "-derivedDataPath",
        str(derived_data),
        "build",
    ]
    run(cmd, root)
    if not bin_path.exists():
        raise FileNotFoundError(f"binary not found after build: {bin_path}")
    return bin_path


def make_swift_args(args: argparse.Namespace) -> List[str]:
    out: List[str] = []
    if args.cam_x is not None:
        out += ["--camX", str(args.cam_x)]
    if args.cam_y is not None:
        out += ["--camY", str(args.cam_y)]
    if args.cam_z is not None:
        out += ["--camZ", str(args.cam_z)]
    if args.fov is not None:
        out += ["--fov", str(args.fov)]
    if args.roll is not None:
        out += ["--roll", str(args.roll)]
    if args.rcp is not None:
        out += ["--rcp", str(args.rcp)]
    if args.disk_h is not None:
        out += ["--diskH", str(args.disk_h)]
    if args.max_steps is not None:
        out += ["--maxSteps", str(args.max_steps)]
    if args.h is not None:
        out += ["--h", str(args.h)]
    out += ["--kerr-radial-scale", str(args.kerr_radial_scale)]
    out += ["--kerr-azimuth-scale", str(args.kerr_azimuth_scale)]
    out += ["--kerr-impact-scale", str(args.kerr_impact_scale)]
    return out


def count_hits(collisions: Path, width: int, height: int) -> int:
    total = width * height
    mem = np.memmap(str(collisions), dtype=COLLISION_DTYPE, mode="r", shape=(total,))
    return int(np.count_nonzero(mem["hit"] != 0))


def hit_delta_pct(ref_hits: int, other_hits: int) -> float:
    if ref_hits <= 0:
        return 0.0
    return abs(other_hits - ref_hits) * 100.0 / ref_hits


def detect_binary_arch(binary: Path) -> str:
    try:
        out = subprocess.check_output(["/usr/bin/lipo", "-archs", str(binary)], text=True).strip()
    except Exception:
        return ""
    if not out:
        return ""
    archs = out.split()
    host = platform.machine().lower()
    if host in archs:
        return host
    if "arm64" in archs:
        return "arm64"
    if "x86_64" in archs:
        return "x86_64"
    return archs[0]


def apply_arch_prefix(cmd: List[str], force_arch: str) -> List[str]:
    if not force_arch or force_arch == "none":
        return cmd
    return ["/usr/bin/arch", f"-{force_arch}"] + cmd


def render_with_pipeline(
    root: Path,
    run_pipeline: Path,
    derived_data: Path,
    preset: str,
    width: int,
    height: int,
    metric: str,
    spin: float,
    collisions: Path,
    image: Path,
    swift_extra: Sequence[str],
    kerr_substeps: int,
    kerr_tol: float,
    kerr_escape_mult: float,
    force_arch: str,
) -> RenderArtifacts:
    cmd = [
        str(run_pipeline),
        "--no-build",
        "--preset",
        preset,
        "--width",
        str(width),
        "--height",
        str(height),
        "--metric",
        metric,
        "--spin",
        str(spin),
        "--collisions-out",
        str(collisions),
        "--image-out",
        str(image),
        "--look",
        preset,
    ]
    if metric == "kerr":
        cmd += [
            "--kerr-substeps",
            str(kerr_substeps),
            "--kerr-tol",
            str(kerr_tol),
            "--kerr-escape-mult",
            str(kerr_escape_mult),
        ]
    cmd += list(swift_extra)
    env = os.environ.copy()
    env["BH_DERIVED_DATA_PATH"] = str(derived_data)
    if force_arch and force_arch != "none":
        env["BH_FORCE_ARCH"] = force_arch
    run(cmd, root, env=env)
    meta = Path(str(collisions) + ".json")
    hits = count_hits(collisions, width, height)
    return RenderArtifacts(collisions=collisions, meta=meta, image=image, hits=hits)


def render_with_binary(
    root: Path,
    binary: Path,
    preset: str,
    width: int,
    height: int,
    metric: str,
    spin: float,
    collisions: Path,
    swift_extra: Sequence[str],
    kerr_substeps: int,
    kerr_tol: float,
    kerr_escape_mult: float,
    force_arch: str,
) -> int:
    cmd = [
        str(binary),
        "--preset",
        preset,
        "--width",
        str(width),
        "--height",
        str(height),
        "--metric",
        metric,
        "--spin",
        str(spin),
        "--output",
        str(collisions),
    ]
    if metric == "kerr":
        cmd += [
            "--kerr-substeps",
            str(kerr_substeps),
            "--kerr-tol",
            str(kerr_tol),
            "--kerr-escape-mult",
            str(kerr_escape_mult),
        ]
    cmd += list(swift_extra)
    run(apply_arch_prefix(cmd, force_arch), root)
    return count_hits(collisions, width, height)


def run_trace(
    root: Path,
    trace_script: Path,
    label: str,
    pixel: Tuple[int, int],
    args: argparse.Namespace,
    out_dir: Path,
) -> Dict[str, object]:
    pair_csv = out_dir / f"{label}_kerr_pair.csv"
    full_csv = out_dir / f"{label}_kerr_full_state.csv"
    analysis_json = out_dir / f"{label}_kerr_analysis.json"

    cmd = [
        sys.executable,
        str(trace_script),
        "--preset",
        args.preset,
        "--width",
        str(args.width),
        "--height",
        str(args.height),
        "--spin",
        "0.0",
        "--pixel-x",
        str(pixel[0]),
        "--pixel-y",
        str(pixel[1]),
        "--kerr-substeps",
        str(args.kerr_substeps),
        "--kerr-tol",
        str(args.kerr_tol),
        "--kerr-escape-mult",
        str(args.kerr_escape_mult),
        "--kerr-radial-scale",
        str(args.kerr_radial_scale),
        "--kerr-azimuth-scale",
        str(args.kerr_azimuth_scale),
        "--kerr-impact-scale",
        str(args.kerr_impact_scale),
        "--csv",
        str(pair_csv),
        "--full-state-csv",
        str(full_csv),
        "--analysis-json",
        str(analysis_json),
    ]
    if args.cam_x is not None:
        cmd += ["--cam-x", str(args.cam_x)]
    if args.cam_y is not None:
        cmd += ["--cam-y", str(args.cam_y)]
    if args.cam_z is not None:
        cmd += ["--cam-z", str(args.cam_z)]
    if args.fov is not None:
        cmd += ["--fov", str(args.fov)]
    if args.roll is not None:
        cmd += ["--roll", str(args.roll)]
    if args.rcp is not None:
        cmd += ["--rcp", str(args.rcp)]
    if args.disk_h is not None:
        cmd += ["--disk-h", str(args.disk_h)]
    if args.max_steps is not None:
        cmd += ["--max-steps", str(args.max_steps)]
    if args.h is not None:
        cmd += ["--h", str(args.h)]

    run(cmd, root)
    with open(analysis_json, "r", encoding="utf-8") as f:
        analysis = json.load(f)

    return {
        "pair_csv": str(pair_csv),
        "full_state_csv": str(full_csv),
        "analysis_json": str(analysis_json),
        "analysis": analysis,
    }


def _safe_array(field: np.ndarray) -> np.ndarray:
    arr = np.asarray(field)
    if arr.ndim == 0:
        arr = arr.reshape(1)
    return arr


def plot_trajectory(pair_csv: Path, out_png: Path, title: str) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    data = np.genfromtxt(str(pair_csv), delimiter=",", names=True)
    if data.size == 0:
        return
    sx = _safe_array(data["sx"])
    sy = _safe_array(data["sy"])
    sz = _safe_array(data["sz"])
    kx = _safe_array(data["kx"])
    ky = _safe_array(data["ky"])
    kz = _safe_array(data["kz"])

    s_ok = np.isfinite(sx) & np.isfinite(sy) & np.isfinite(sz)
    k_ok = np.isfinite(kx) & np.isfinite(ky) & np.isfinite(kz)
    if not np.any(s_ok) and not np.any(k_ok):
        return

    fig = plt.figure(figsize=(8, 6), dpi=140)
    ax = fig.add_subplot(111, projection="3d")
    if np.any(s_ok):
        ax.plot(sx[s_ok], sy[s_ok], sz[s_ok], color="#1f77b4", lw=1.5, label="Schwarzschild")
    if np.any(k_ok):
        ax.plot(kx[k_ok], ky[k_ok], kz[k_ok], color="#d62728", lw=1.5, label="Kerr")
    ax.set_title(title)
    ax.set_xlabel("x (m)")
    ax.set_ylabel("y (m)")
    ax.set_zlabel("z (m)")
    ax.legend(loc="upper right")
    fig.tight_layout()
    out_png.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(str(out_png))
    plt.close(fig)


def plot_distance(pair_csv: Path, out_png: Path, title: str) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    data = np.genfromtxt(str(pair_csv), delimiter=",", names=True)
    if data.size == 0:
        return
    step = _safe_array(data["step"])
    dist = _safe_array(data["dist"])
    ok = np.isfinite(step) & np.isfinite(dist)
    if not np.any(ok):
        return

    fig = plt.figure(figsize=(8, 4), dpi=140)
    ax = fig.add_subplot(111)
    ax.plot(step[ok], dist[ok], color="#2ca02c", lw=1.2)
    ax.set_title(title)
    ax.set_xlabel("step")
    ax.set_ylabel("distance (m)")
    ax.grid(True, alpha=0.25)
    fig.tight_layout()
    out_png.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(str(out_png))
    plt.close(fig)


def spin_values(start: float, end: float, step: float) -> List[float]:
    vals: List[float] = []
    x = start
    for _ in range(10000):
        if x > end + 1e-12:
            break
        vals.append(round(x, 8))
        x += step
    return vals


def write_report(
    report_path: Path,
    args: argparse.Namespace,
    schwarz: RenderArtifacts,
    kerr_new: RenderArtifacts,
    selected: Dict[str, Dict[str, int]],
    traces: Dict[str, Dict[str, Dict[str, object]]],
    sweep_rows: List[Dict[str, object]],
    max_gap: Dict[str, object],
) -> None:
    lines: List[str] = []
    lines.append("# Kerr(spin=0) Diagnosis Report")
    lines.append("")
    lines.append("## Configuration")
    lines.append(
        f"- preset={args.preset}, width={args.width}, height={args.height}, "
        f"h={args.h if args.h is not None else 0.01}, maxSteps={args.max_steps if args.max_steps is not None else 1600}"
    )
    lines.append(
        f"- kerr: substeps={args.kerr_substeps}, tol={args.kerr_tol}, "
        f"escapeMult={args.kerr_escape_mult}"
    )
    lines.append("")
    lines.append("## Global Hit Metrics")
    lines.append("| metric | value |")
    lines.append("|---|---:|")
    lines.append(f"| schwarzschild hits | {schwarz.hits} |")
    lines.append(f"| kerr(spin=0) hits | {kerr_new.hits} |")
    lines.append(f"| hit delta vs schwarz (%) | {hit_delta_pct(schwarz.hits, kerr_new.hits):.4f} |")
    lines.append("")
    lines.append("## Selected Pixels")
    lines.append(
        f"- top=({selected['top']['x']},{selected['top']['y']}), "
        f"bottom=({selected['bottom']['x']},{selected['bottom']['y']})"
    )
    lines.append("")
    lines.append("## Pixel Hit Match")
    lines.append("| pixel | hit_match | dist_max (m) |")
    lines.append("|---|---:|---:|")
    for label in ("top", "bottom"):
        new_sum = traces[label]["kerr"]["analysis"]["summary"]
        lines.append(
            f"| {label} | {new_sum['hit_match']} | {new_sum.get('dist_max_m', math.nan):.6e} |"
        )
    lines.append("")
    lines.append("## Root Cause Extraction")
    lines.append("| item | value |")
    lines.append("|---|---|")
    lines.append(f"| max difference pixel | {max_gap.get('pixel', 'n/a')} |")
    lines.append(f"| max difference step | {max_gap.get('step', 'n/a')} |")
    lines.append(f"| max difference dist (m) | {max_gap.get('dist_m', float('nan')):.6e} |")
    lines.append(f"| divergence stage | {max_gap.get('divergence_stage', 'unknown')} |")
    lines.append(f"| cause tag | {max_gap.get('cause', 'unclassified')} |")
    lines.append("")
    lines.append("## Spin Continuity Sweep")
    lines.append("| spin | kerr hits | delta from previous (%) |")
    lines.append("|---:|---:|---:|")
    for row in sweep_rows:
        d = row["delta_prev_pct"]
        d_txt = "n/a" if d is None else f"{d:.4f}"
        lines.append(f"| {row['spin']:.1f} | {row['hits']} | {d_txt} |")
    lines.append("")
    lines.append("## Output Paths")
    lines.append(f"- Schwarz collisions: `{schwarz.collisions}`")
    lines.append(f"- Kerr collisions: `{kerr_new.collisions}`")
    lines.append(f"- report: `{report_path}`")

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Run full Kerr vs Schwarzschild diagnosis pipeline.")
    parser.add_argument("--out-dir", type=str, default="/tmp/kerr_diagnosis")
    parser.add_argument("--preset", type=str, default="interstellar")
    parser.add_argument("--width", type=int, default=1200)
    parser.add_argument("--height", type=int, default=1200)
    parser.add_argument("--h", type=float, default=0.01)
    parser.add_argument("--max-steps", type=int, default=1600)

    parser.add_argument("--cam-x", type=float, default=None)
    parser.add_argument("--cam-y", type=float, default=None)
    parser.add_argument("--cam-z", type=float, default=None)
    parser.add_argument("--fov", type=float, default=None)
    parser.add_argument("--roll", type=float, default=None)
    parser.add_argument("--rcp", type=float, default=None)
    parser.add_argument("--disk-h", type=float, default=None)

    parser.add_argument("--kerr-substeps", type=int, default=2)
    parser.add_argument("--kerr-tol", type=float, default=1e-5)
    parser.add_argument("--kerr-escape-mult", type=float, default=3.0)
    parser.add_argument("--kerr-radial-scale", type=float, default=0.67)
    parser.add_argument("--kerr-azimuth-scale", type=float, default=0.92)
    parser.add_argument("--kerr-impact-scale", type=float, default=0.97)
    parser.add_argument("--pixel-top", type=str, default="")
    parser.add_argument("--pixel-bottom", type=str, default="")

    parser.add_argument("--sweep-start", type=float, default=0.0)
    parser.add_argument("--sweep-end", type=float, default=0.9)
    parser.add_argument("--sweep-step", type=float, default=0.1)
    parser.add_argument("--no-sweep", action="store_true")
    parser.add_argument("--clean-out", action="store_true")

    parser.add_argument("--run-pipeline", type=str, default="./run_pipeline.sh")
    parser.add_argument("--derived-data", type=str, default="/tmp/BlackholeDD")
    parser.add_argument("--force-build", action="store_true")
    parser.add_argument("--binary-arch", choices=["auto", "none", "arm64", "x86_64"], default="auto")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    out_dir = Path(args.out_dir).resolve()
    if args.clean_out and out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "plots").mkdir(parents=True, exist_ok=True)
    (out_dir / "renders").mkdir(parents=True, exist_ok=True)
    (out_dir / "traces").mkdir(parents=True, exist_ok=True)
    (out_dir / "sweep").mkdir(parents=True, exist_ok=True)

    run_pipeline = Path(args.run_pipeline)
    if not run_pipeline.is_absolute():
        run_pipeline = (root / run_pipeline).resolve()
    if not run_pipeline.exists():
        raise FileNotFoundError(f"run_pipeline not found: {run_pipeline}")

    trace_script = root / "Blackhole" / "scripts" / "trace_ray_compare.py"
    if not trace_script.exists():
        raise FileNotFoundError(f"trace script not found: {trace_script}")

    if args.sweep_step <= 0:
        raise ValueError("--sweep-step must be > 0")

    derived_data = Path(args.derived_data).resolve()
    bin_path = build_binary(root, derived_data, force_build=args.force_build)
    if args.binary_arch == "auto":
        force_arch = ""
        host_arch = platform.machine().lower()
        bin_arch = detect_binary_arch(bin_path)
        if bin_arch and bin_arch != host_arch:
            force_arch = bin_arch
    elif args.binary_arch == "none":
        force_arch = ""
    else:
        force_arch = args.binary_arch

    swift_extra = make_swift_args(args)

    schwarz = render_with_pipeline(
        root=root,
        run_pipeline=run_pipeline,
        derived_data=derived_data,
        preset=args.preset,
        width=args.width,
        height=args.height,
        metric="schwarzschild",
        spin=0.0,
        collisions=out_dir / "renders" / "collisions_schwarzschild.bin",
        image=out_dir / "renders" / "schwarzschild.png",
        swift_extra=swift_extra,
        kerr_substeps=args.kerr_substeps,
        kerr_tol=args.kerr_tol,
        kerr_escape_mult=args.kerr_escape_mult,
        force_arch=force_arch,
    )
    kerr_new = render_with_pipeline(
        root=root,
        run_pipeline=run_pipeline,
        derived_data=derived_data,
        preset=args.preset,
        width=args.width,
        height=args.height,
        metric="kerr",
        spin=0.0,
        collisions=out_dir / "renders" / "collisions_kerr_spin0.bin",
        image=out_dir / "renders" / "kerr_spin0.png",
        swift_extra=swift_extra,
        kerr_substeps=args.kerr_substeps,
        kerr_tol=args.kerr_tol,
        kerr_escape_mult=args.kerr_escape_mult,
        force_arch=force_arch,
    )

    hit = load_hit_map(str(schwarz.collisions), args.width, args.height)
    auto_picks = select_pixels(hit)
    top_xy = (auto_picks["top"]["x"], auto_picks["top"]["y"])
    bottom_xy = (auto_picks["bottom"]["x"], auto_picks["bottom"]["y"])
    if args.pixel_top:
        top_xy = parse_xy(args.pixel_top)
    if args.pixel_bottom:
        bottom_xy = parse_xy(args.pixel_bottom)
    selected = {
        "top": {"x": int(top_xy[0]), "y": int(top_xy[1])},
        "bottom": {"x": int(bottom_xy[0]), "y": int(bottom_xy[1])},
        "band": auto_picks["band"],
    }
    (out_dir / "selected_pixels.json").write_text(json.dumps(selected, indent=2, sort_keys=True), encoding="utf-8")

    traces: Dict[str, Dict[str, Dict[str, object]]] = {"top": {}, "bottom": {}}
    for label, pixel in (("top", top_xy), ("bottom", bottom_xy)):
        new_trace = run_trace(root, trace_script, label, pixel, args, out_dir / "traces")
        traces[label]["kerr"] = new_trace

        plot_trajectory(
            Path(new_trace["pair_csv"]),
            out_dir / "plots" / f"{label}_kerr_traj3d.png",
            f"{label}: Schwarzschild vs Kerr(spin=0)",
        )
        plot_distance(
            Path(new_trace["pair_csv"]),
            out_dir / "plots" / f"{label}_kerr_dist.png",
            f"{label}: dist(step) Kerr",
        )

    max_gap: Dict[str, object] = {"pixel": "n/a", "step": None, "dist_m": -1.0, "divergence_stage": "unknown", "cause": "unclassified"}
    for label in ("top", "bottom"):
        analysis = traces[label]["kerr"]["analysis"]
        summary = analysis.get("summary", {})
        payload = analysis.get("max_step_payload") or {}
        dist_val = float(payload.get("dist_m", -1.0))
        if dist_val > float(max_gap.get("dist_m", -1.0)):
            cause = "integration_drift"
            stage = str(summary.get("divergence_stage", "unknown"))
            if stage == "initial_mapping":
                cause = "initial_mapping_mismatch"
            elif stage == "early_integration":
                cause = "early_integrator_divergence"
            max_gap = {
                "pixel": label,
                "step": payload.get("step"),
                "dist_m": dist_val,
                "divergence_stage": stage,
                "cause": cause,
            }

    sweep_rows: List[Dict[str, object]] = []
    if not args.no_sweep:
        spins = spin_values(args.sweep_start, args.sweep_end, args.sweep_step)
        prev_hits: Optional[int] = None
        for spin in spins:
            out_bin = out_dir / "sweep" / f"kerr_spin_{spin:.1f}.bin"
            hits = render_with_binary(
                root=root,
                binary=bin_path,
                preset=args.preset,
                width=args.width,
                height=args.height,
                metric="kerr",
                spin=spin,
                collisions=out_bin,
                swift_extra=swift_extra,
                kerr_substeps=args.kerr_substeps,
                kerr_tol=args.kerr_tol,
                kerr_escape_mult=args.kerr_escape_mult,
                force_arch=force_arch,
            )
            delta_prev = None
            if prev_hits is not None and prev_hits > 0:
                delta_prev = abs(hits - prev_hits) * 100.0 / prev_hits
            sweep_rows.append({"spin": spin, "hits": hits, "delta_prev_pct": delta_prev})
            prev_hits = hits

    report_path = out_dir / "report.md"
    write_report(
        report_path=report_path,
        args=args,
        schwarz=schwarz,
        kerr_new=kerr_new,
        selected=selected,
        traces=traces,
        sweep_rows=sweep_rows,
        max_gap=max_gap,
    )

    summary = {
        "paths": {
            "out_dir": str(out_dir),
            "report": str(report_path),
            "selected_pixels": str(out_dir / "selected_pixels.json"),
        },
        "global_hits": {
            "schwarzschild": schwarz.hits,
            "kerr_spin0": kerr_new.hits,
            "delta_pct": hit_delta_pct(schwarz.hits, kerr_new.hits),
        },
        "selected_pixels": selected,
        "max_gap": max_gap,
        "sweep": sweep_rows,
    }
    summary_path = out_dir / "analysis_summary.json"
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True), encoding="utf-8")

    print(f"report: {report_path}")
    print(f"summary: {summary_path}")
    print(
        "hit delta (new vs schwarz): "
        f"{hit_delta_pct(schwarz.hits, kerr_new.hits):.4f}% "
        f"({kerr_new.hits}/{schwarz.hits})"
    )


if __name__ == "__main__":
    main()
