#!/usr/bin/env python3
"""Run focused science-regime diagnostics for the black-hole renderer.

The goal is not to make a prettier image. The script keeps the main physical
regimes separate and produces comparable outputs:

- visible thin-disk scientific master
- human-eye presentation
- GRMHD-native hot-flow diagnostic
- GRMHD visible-photosphere diagnostic
- GRMHD debug maps for density/temperature/field/emission/transfer
- optional electron-model and frequency sweeps

If a controlled perturbation is requested, it is written as a separate HDF5 file
and reported as a synthetic structure test, not as real evolved GRMHD data.
"""

from __future__ import annotations

import argparse
import json
import shlex
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional


ROOT = Path(__file__).resolve().parents[2]
RUN_PIPELINE = ROOT / "Blackhole" / "run_pipeline.sh"
BUILD_SAMPLE = ROOT / "Blackhole" / "scripts" / "build_sample_hdf5.py"
PERTURB_HDF5 = ROOT / "Blackhole" / "scripts" / "perturb_hdf5_initial_conditions.py"
AUDIT_GRMHD = ROOT / "Blackhole" / "scripts" / "audit_grmhd_snapshot.py"


@dataclass
class CommandResult:
    label: str
    command: List[str]
    returncode: int
    stdout: str
    stderr: str


@dataclass
class DiagnosticReport:
    out_dir: str
    snapshot: str
    controlled_perturbation_snapshot: str = ""
    renders: Dict[str, str] = field(default_factory=dict)
    audits: Dict[str, Any] = field(default_factory=dict)
    image_stats: Dict[str, Any] = field(default_factory=dict)
    image_diffs: Dict[str, Any] = field(default_factory=dict)
    commands: List[Dict[str, Any]] = field(default_factory=list)
    notes: List[str] = field(default_factory=list)


def run_command(label: str, cmd: List[str], cwd: Path, check: bool = True) -> CommandResult:
    print(f"== {label} ==")
    print(" ".join(shlex.quote(x) for x in cmd))
    proc = subprocess.run(cmd, cwd=str(cwd), text=True, capture_output=True)
    if proc.stdout:
        print(proc.stdout, end="")
    if proc.stderr:
        print(proc.stderr, end="", file=sys.stderr)
    result = CommandResult(label, cmd, proc.returncode, proc.stdout, proc.stderr)
    if check and proc.returncode != 0:
        raise SystemExit(f"{label} failed with code {proc.returncode}")
    return result


def load_json_from_command(label: str, cmd: List[str], cwd: Path) -> Any:
    result = run_command(label, cmd, cwd)
    text = result.stdout.strip()
    start = text.find("[")
    if start < 0:
        raise ValueError(f"{label}: JSON array not found in stdout")
    return json.loads(text[start:])


def audit_snapshot(label: str, snapshot: Path, out_dir: Path, report: DiagnosticReport) -> Any:
    json_path = out_dir / f"{label}_audit.json"
    result = run_command(
        f"audit {label} GRMHD snapshot",
        [sys.executable, str(AUDIT_GRMHD), str(snapshot), "--json-out", str(json_path)],
        ROOT,
    )
    report.commands.append({"label": result.label, "returncode": result.returncode, "command": result.command})
    return json.loads(json_path.read_text(encoding="utf-8"))


def image_stats(path: Path) -> Dict[str, Any]:
    try:
        from PIL import Image
    except Exception:
        return {"error": "Pillow is not installed"}

    im = Image.open(path).convert("RGB")
    pixels = list(im.getdata())
    luma = sorted((0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0 for r, g, b in pixels)
    if not luma:
        return {"size": list(im.size)}
    sat = sum(1 for r, g, b in pixels if max(r, g, b) >= 250) / len(pixels)
    return {
        "size": list(im.size),
        "mean": float(sum(luma) / len(luma)),
        "p50": float(luma[int(0.50 * (len(luma) - 1))]),
        "p95": float(luma[int(0.95 * (len(luma) - 1))]),
        "p99": float(luma[int(0.99 * (len(luma) - 1))]),
        "saturationFraction": float(sat),
    }


def image_diff_stats(path_a: Path, path_b: Path) -> Dict[str, Any]:
    try:
        from PIL import Image
    except Exception:
        return {"error": "Pillow is not installed"}

    im_a = Image.open(path_a).convert("RGB")
    im_b = Image.open(path_b).convert("RGB")
    if im_a.size != im_b.size:
        return {"error": f"size mismatch: {im_a.size} != {im_b.size}"}
    diffs = []
    for pa, pb in zip(im_a.getdata(), im_b.getdata()):
        diffs.append(max(abs(float(pa[i]) - float(pb[i])) for i in range(3)) / 255.0)
    if not diffs:
        return {"size": list(im_a.size)}
    diffs.sort()
    return {
        "size": list(im_a.size),
        "meanAbsMaxRGB": float(sum(diffs) / len(diffs)),
        "p95AbsMaxRGB": float(diffs[int(0.95 * (len(diffs) - 1))]),
        "p99AbsMaxRGB": float(diffs[int(0.99 * (len(diffs) - 1))]),
        "maxAbsRGB": float(diffs[-1]),
    }


def make_contact_sheet(paths: Dict[str, str], out_path: Path, thumb: int = 320) -> Optional[Path]:
    try:
        from PIL import Image, ImageDraw
    except Exception:
        return None

    items = [(label, Path(path)) for label, path in paths.items() if Path(path).exists()]
    if not items:
        return None
    canvases = []
    for label, path in items:
        im = Image.open(path).convert("RGB")
        resample = Image.Resampling.LANCZOS if hasattr(Image, "Resampling") else Image.LANCZOS
        im.thumbnail((thumb, thumb), resample)
        canvas = Image.new("RGB", (thumb, thumb + 42), (18, 18, 18))
        canvas.paste(im, ((thumb - im.width) // 2, 42 + (thumb - im.height) // 2))
        draw = ImageDraw.Draw(canvas)
        draw.text((10, 12), label[:44], fill=(235, 235, 235))
        canvases.append(canvas)

    cols = min(3, len(canvases))
    rows = (len(canvases) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * thumb, rows * (thumb + 42)), (18, 18, 18))
    for i, canvas in enumerate(canvases):
        x = (i % cols) * thumb
        y = (i // cols) * (thumb + 42)
        sheet.paste(canvas, (x, y))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path)
    return out_path


def render(
    label: str,
    report: DiagnosticReport,
    out_dir: Path,
    base_args: List[str],
    extra_args: Iterable[str],
    width: int,
    height: int,
) -> None:
    out_path = out_dir / f"{label}.png"
    cmd = [
        str(RUN_PIPELINE),
        "--no-build",
        "--width",
        str(width),
        "--height",
        str(height),
        "--output",
        str(out_path),
        *base_args,
        *list(extra_args),
    ]
    result = run_command(f"render {label}", cmd, ROOT)
    report.commands.append(
        {
            "label": result.label,
            "returncode": result.returncode,
            "command": result.command,
        }
    )
    report.renders[label] = str(out_path)
    if out_path.exists():
        report.image_stats[label] = image_stats(out_path)


def safe_token(value: str) -> str:
    return value.replace(".", "p").replace("+", "").replace("-", "m")


def render_temporal_sweep(
    report: DiagnosticReport,
    out_dir: Path,
    base_args: List[str],
    snapshot_next: Path,
    alphas: List[str],
    debug_maps: List[str],
    width: int,
    height: int,
) -> None:
    if not snapshot_next.is_file():
        raise SystemExit(f"--snapshot-next not found: {snapshot_next}")
    rendered_by_debug: Dict[str, List[tuple[str, Path]]] = {}
    for alpha in alphas:
        token = safe_token(alpha)
        temporal_args = [
            "--disk-hdf5-next",
            str(snapshot_next),
            "--disk-hdf5-time-blend",
            alpha,
        ]
        label = f"temporal_a{token}_final"
        render(
            label,
            report,
            out_dir,
            base_args,
            [*temporal_args, "--science-regime", "grmhd-temperature-flow"],
            width,
            height,
        )
        rendered_by_debug.setdefault("final", []).append((alpha, out_dir / f"{label}.png"))

        for debug in debug_maps:
            safe_debug = debug.replace("-", "_")
            label = f"temporal_a{token}_{safe_debug}"
            render(
                label,
                report,
                out_dir,
                base_args,
                [
                    *temporal_args,
                    "--science-regime",
                    "grmhd-temperature-flow",
                    "--disk-grmhd-debug",
                    debug,
                ],
                width,
                height,
            )
            rendered_by_debug.setdefault(debug, []).append((alpha, out_dir / f"{label}.png"))

    for debug, items in rendered_by_debug.items():
        sheet_paths = {f"a={alpha}": str(path) for alpha, path in items}
        contact = make_contact_sheet(sheet_paths, out_dir / f"temporal_{debug.replace('-', '_')}_contact_sheet.png", thumb=width)
        if contact is not None:
            report.renders[f"temporal_{debug.replace('-', '_')}_contact_sheet"] = str(contact)
        for (alpha_a, path_a), (alpha_b, path_b) in zip(items, items[1:]):
            if path_a.exists() and path_b.exists():
                report.image_diffs[f"temporal_{debug}_{alpha_a}_to_{alpha_b}"] = image_diff_stats(path_a, path_b)
        if len(items) >= 2:
            alpha_a, path_a = items[0]
            alpha_b, path_b = items[-1]
            if path_a.exists() and path_b.exists():
                report.image_diffs[f"temporal_{debug}_{alpha_a}_to_{alpha_b}"] = image_diff_stats(path_a, path_b)


def build_or_resolve_snapshot(args: argparse.Namespace, out_dir: Path, report: DiagnosticReport) -> Path:
    if args.snapshot:
        return Path(args.snapshot).expanduser().resolve()

    sample = out_dir / "fm_torus_sample.h5"
    cmd = [
        sys.executable,
        str(BUILD_SAMPLE),
        "--output",
        str(sample),
        "--nr",
        str(args.sample_nr),
        "--nth",
        str(args.sample_nth),
        "--nphi",
        str(args.sample_nphi),
        "--perturb",
        str(args.sample_perturb),
        "--seed",
        str(args.seed),
    ]
    result = run_command("build sample HDF5", cmd, ROOT)
    report.commands.append({"label": result.label, "returncode": result.returncode, "command": result.command})
    report.notes.append("Using generated Fishbone-Moncrief-style sample HDF5; this is an IC/test dataset, not evolved GRMHD.")
    return sample.resolve()


def maybe_make_controlled_perturbation(
    snapshot: Path,
    args: argparse.Namespace,
    out_dir: Path,
    report: DiagnosticReport,
) -> Path:
    if not (args.structure_test_amp > 0.0):
        return snapshot
    perturbed = out_dir / "controlled_structure_test.h5"
    cmd = [
        sys.executable,
        str(PERTURB_HDF5),
        "--input",
        str(snapshot),
        "--output",
        str(perturbed),
        "--seed",
        str(args.seed),
        "--amp",
        str(args.structure_test_amp),
        "--scale",
        str(args.structure_test_scale),
    ]
    result = run_command("controlled HDF5 structure perturbation", cmd, ROOT)
    report.commands.append({"label": result.label, "returncode": result.returncode, "command": result.command})
    report.controlled_perturbation_snapshot = str(perturbed.resolve())
    report.notes.append(
        "Controlled perturbation is a synthetic structure-sensitivity test only; do not treat it as evolved GRMHD truth."
    )
    return perturbed.resolve()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--snapshot", default="", help="input GRMHD HDF5 snapshot; if omitted, a test sample is generated")
    ap.add_argument("--snapshot-next", default="", help="optional next GRMHD HDF5 snapshot for temporal diagnostics")
    ap.add_argument("--out-dir", default="/tmp/blackhole_science_diagnostics", help="diagnostic output directory")
    ap.add_argument("--width", type=int, default=384)
    ap.add_argument("--height", type=int, default=384)
    ap.add_argument("--preset", default="thin-disk")
    ap.add_argument("--seed", type=int, default=1337)
    ap.add_argument("--sample-nr", type=int, default=64)
    ap.add_argument("--sample-nth", type=int, default=48)
    ap.add_argument("--sample-nphi", type=int, default=96)
    ap.add_argument("--sample-perturb", type=float, default=0.01, help="raw sample generator perturbation")
    ap.add_argument("--structure-test-amp", type=float, default=0.0, help="optional controlled non-axisymmetric perturbation")
    ap.add_argument("--structure-test-scale", type=float, default=12.0)
    ap.add_argument(
        "--debug-map",
        action="append",
        default=[],
        help="GRMHD debug map to render; may be repeated. Defaults cover core photometry diagnostics.",
    )
    ap.add_argument(
        "--freq",
        action="append",
        default=[],
        help="frequency for grmhd hot-flow sweep, Hz; may be repeated",
    )
    ap.add_argument("--skip-frequency-sweep", action="store_true")
    ap.add_argument("--skip-electron-sweep", action="store_true")
    ap.add_argument("--skip-transfer-sweep", action="store_true")
    ap.add_argument("--skip-temporal-sweep", action="store_true")
    ap.add_argument(
        "--time-blend",
        action="append",
        default=[],
        help="temporal blend alpha for --snapshot-next diagnostics; may be repeated. Default: 0, 0.5, 1",
    )
    ap.add_argument(
        "--temporal-debug-map",
        action="append",
        default=[],
        help="debug map for temporal diagnostics; may be repeated. Defaults target flow/transfer contrast.",
    )
    ap.add_argument("--temporal-only", action="store_true", help="run only the temporal GRMHD sweep and report")
    ap.add_argument("--no-thin", action="store_true", help="skip thin-visible/experience renders")
    ap.add_argument("--report-json", default="", help="optional report path; default is out-dir/report.json")
    args = ap.parse_args()

    if args.width <= 0 or args.height <= 0:
        raise SystemExit("--width and --height must be positive")
    if args.structure_test_amp < 0:
        raise SystemExit("--structure-test-amp must be >= 0")

    out_dir = Path(args.out_dir).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    report = DiagnosticReport(out_dir=str(out_dir), snapshot="")
    snapshot = build_or_resolve_snapshot(args, out_dir, report)
    report.snapshot = str(snapshot)

    report.audits["input"] = audit_snapshot("input", snapshot, out_dir, report)
    render_snapshot = maybe_make_controlled_perturbation(snapshot, args, out_dir, report)
    if render_snapshot != snapshot:
        report.audits["controlledPerturbation"] = audit_snapshot("controlled_perturbation", render_snapshot, out_dir, report)

    thin_base = ["--preset", args.preset]
    if args.temporal_only and not args.snapshot_next:
        raise SystemExit("--temporal-only requires --snapshot-next")

    if not args.no_thin and not args.temporal_only:
        render("thin_visible", report, out_dir, thin_base, ["--science-regime", "thin-visible"], args.width, args.height)
        render("experience", report, out_dir, thin_base, ["--science-regime", "experience"], args.width, args.height)

    grmhd_base = ["--preset", args.preset, "--disk-hdf5", str(render_snapshot)]

    if args.snapshot_next and not args.skip_temporal_sweep:
        alphas = args.time_blend or ["0.0", "0.5", "1.0"]
        temporal_debug_maps = args.temporal_debug_map or [
            "rho",
            "thetae",
            "bmag",
            "jthermal",
            "jthermal-cloud",
            "thermal-cloud-ratio",
            "source-thermal",
            "thermal-alpha-post",
            "raw-log",
        ]
        render_temporal_sweep(
            report,
            out_dir,
            grmhd_base,
            Path(args.snapshot_next).expanduser().resolve(),
            alphas,
            temporal_debug_maps,
            args.width,
            args.height,
        )
        report.notes.append(
            "Temporal sweep uses GRMHD temperature-flow with HDF5-state preprocessing blend. "
            "Use the per-debug contact sheets and imageDiffs to see where time-varying structure survives or is smoothed away."
        )

    if not args.temporal_only:
        render(
            "grmhd_structure_flow",
            report,
            out_dir,
            grmhd_base,
            ["--science-regime", "grmhd-structure-flow"],
            args.width,
            args.height,
        )
        # Backward-compatible filename for older reports and comparisons.
        render("grmhd_hot_flow", report, out_dir, grmhd_base, ["--science-regime", "grmhd-hot-flow"], args.width, args.height)
        render(
            "grmhd_photosphere",
            report,
            out_dir,
            grmhd_base,
            ["--science-regime", "grmhd-photosphere"],
            args.width,
            args.height,
        )

        debug_maps = args.debug_map or ["rho", "thetae", "bmag", "jthin", "source", "raw-log", "g", "tau", "samples"]
        for debug in debug_maps:
            render(
                f"debug_{debug.replace('-', '_')}",
                report,
                out_dir,
                grmhd_base,
                ["--science-regime", "grmhd-structure-flow", "--disk-grmhd-debug", debug],
                args.width,
                args.height,
            )

    if not args.skip_frequency_sweep and not args.temporal_only:
        freqs = args.freq or ["4.3e14", "5.5e14", "7.2e14"]
        for freq in freqs:
            safe = freq.replace(".", "p").replace("+", "").replace("-", "m")
            render(
                f"freq_{safe}",
                report,
                out_dir,
                grmhd_base,
                ["--science-regime", "grmhd-structure-flow", "--disk-nu-obs-hz", freq],
                args.width,
                args.height,
            )

    if not args.skip_transfer_sweep and not args.temporal_only:
        # Keep this sweep small: it is meant to catch the two common failure
        # modes for real primitive dumps, synch-only saturation and photosphere
        # over-occlusion, without turning the diagnostic run into a benchmark.
        for scale in ["0.3", "1.0", "3.0"]:
            safe = scale.replace(".", "p")
            render(
                f"synch_scale_{safe}",
                report,
                out_dir,
                grmhd_base,
                ["--science-regime", "grmhd-structure-flow", "--visible-synch-scale", scale],
                args.width,
                args.height,
            )
        for kappa in ["0.01", "0.02", "0.04"]:
            safe = kappa.replace(".", "p")
            render(
                f"photo_kappa_{safe}",
                report,
                out_dir,
                grmhd_base,
                ["--science-regime", "grmhd-photosphere", "--visible-kappa", kappa],
                args.width,
                args.height,
            )

    if not args.skip_electron_sweep and not args.temporal_only:
        for model in ["single-temp", "r-beta"]:
            render(
                f"electron_{model.replace('-', '_')}",
                report,
                out_dir,
                grmhd_base,
                ["--science-regime", "grmhd-hot-flow", "--disk-grmhd-electron-model", model],
                args.width,
                args.height,
            )
        report.notes.append(
            "Electron-model sweep changes the render only when thetae is derived from internal energy; snapshots with a direct thetae field use that field."
        )

    contact = make_contact_sheet(report.renders, out_dir / "contact_sheet.png")
    if contact is not None:
        report.renders["contact_sheet"] = str(contact)

    report_path = Path(args.report_json).expanduser().resolve() if args.report_json else out_dir / "report.json"
    report_path.write_text(
        json.dumps(
            {
                "outDir": report.out_dir,
                "snapshot": report.snapshot,
                "controlledPerturbationSnapshot": report.controlled_perturbation_snapshot,
                "renders": report.renders,
                "audits": report.audits,
                "imageStats": report.image_stats,
                "imageDiffs": report.image_diffs,
                "commands": report.commands,
                "notes": report.notes,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"report: {report_path}")
    if contact is not None:
        print(f"contact_sheet: {contact}")


if __name__ == "__main__":
    main()
