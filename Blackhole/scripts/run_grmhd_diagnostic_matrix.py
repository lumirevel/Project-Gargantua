#!/usr/bin/env python3
"""Run a compact GRMHD appearance diagnostic matrix.

This script is intentionally an orchestration tool, not a renderer. It renders
one fixed frame through the existing pipeline and saves comparable final outputs
and physics/debug maps so we can identify whether structure is lost in plasma
state, radiative transfer, or display presentation.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional


@dataclass(frozen=True)
class RenderCase:
    name: str
    regime: str
    debug: Optional[str] = None
    note: str = ""


FINAL_CASES: List[RenderCase] = [
    RenderCase(
        "final_scientific",
        "grmhd-temperature-flow-scientific",
        None,
        "Physical/scientific presentation: no eye adaptation or cinema layer.",
    ),
    RenderCase(
        "final_eye_hot",
        "grmhd-temperature-flow",
        None,
        "Human-eye presentation using the hot GRMHD temperature calibration.",
    ),
    RenderCase(
        "final_eye_human_visible",
        "grmhd-temperature-flow-human-visible",
        None,
        "Human-eye presentation with the human-visible calibration.",
    ),
]

DEBUG_VIEWS: List[str] = [
    "raw-log",
    "post-exposure",
    "post-tonemap",
    "rho",
    "thetae",
    "bmag",
    "alpha",
    "tau",
    "source",
    "jthermal",
    "jthermal-cloud",
    "thermal-cloud-ratio",
    "flow-residual",
    "g",
    "beaming",
    "emission-radius",
    "samples",
    "invalid",
]

def run_case(
    case: RenderCase,
    *,
    run_pipeline: Path,
    hdf5: Path,
    out_dir: Path,
    width: int,
    height: int,
    ssaa: int,
    preset: str,
    metric: str,
    spin: float,
    no_build: bool,
) -> dict:
    out_png = out_dir / f"{case.name}.png"
    log_path = out_dir / f"{case.name}.log"
    cmd: List[str] = [
        str(run_pipeline),
        "--science-regime",
        case.regime,
        "--preset",
        preset,
        "--metric",
        metric,
        "--spin",
        str(spin),
        "--disk-hdf5",
        str(hdf5),
        "--width",
        str(width),
        "--height",
        str(height),
        "--ssaa",
        str(ssaa),
        "--output",
        str(out_png),
    ]
    if no_build:
        cmd.insert(1, "--no-build")
    if case.debug:
        cmd.extend(["--disk-grmhd-debug", case.debug])

    with log_path.open("w", encoding="utf-8") as log:
        log.write("$ " + " ".join(cmd) + "\n\n")
        proc = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, text=True)

    return {
        "name": case.name,
        "regime": case.regime,
        "debug": case.debug,
        "note": case.note,
        "output": str(out_png),
        "log": str(log_path),
        "returncode": proc.returncode,
        "command": cmd,
    }


def make_contact_sheet(results: Iterable[dict], out_path: Path, width: int, height: int) -> bool:
    try:
        from PIL import Image, ImageDraw, ImageFont
    except Exception:
        return False

    items = [r for r in results if r.get("returncode") == 0 and Path(r["output"]).exists()]
    if not items:
        return False

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

    for i, item in enumerate(items):
        x = (i % cols) * thumb_w
        y = (i // cols) * (thumb_h + label_h)
        img = Image.open(item["output"]).convert("RGB")
        img.thumbnail((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        px = x + (thumb_w - img.width) // 2
        py = y + label_h + (thumb_h - img.height) // 2
        sheet.paste(img, (px, py))
        label = item["name"]
        if item.get("debug"):
            label += f"  [{item['debug']}]"
        draw.rectangle((x, y, x + thumb_w, y + label_h), fill=(24, 24, 24))
        draw.text((x + 8, y + 9), label, fill=(230, 230, 230), font=font)

    sheet.save(out_path)
    return True


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--hdf5", required=True, type=Path, help="GRMHD HDF5 snapshot to render.")
    p.add_argument("--out-dir", type=Path, default=Path("/tmp/bh_grmhd_diagnostic_matrix"))
    p.add_argument("--run-pipeline", type=Path, default=Path("Blackhole/run_pipeline.sh"))
    p.add_argument("--width", type=int, default=512)
    p.add_argument("--height", type=int, default=288)
    p.add_argument("--ssaa", type=int, default=1)
    p.add_argument("--preset", default="realistic")
    p.add_argument("--metric", default="kerr")
    p.add_argument("--spin", type=float, default=0.92)
    p.add_argument("--build", action="store_true", help="Allow run_pipeline.sh to build before rendering.")
    p.add_argument("--only-final", action="store_true", help="Render only final presentation comparisons.")
    p.add_argument("--only-debug", action="store_true", help="Render only debug views.")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    hdf5 = args.hdf5.expanduser().resolve()
    run_pipeline = args.run_pipeline.expanduser()
    if not run_pipeline.is_absolute():
        run_pipeline = (Path.cwd() / run_pipeline).resolve()

    if not hdf5.exists():
        print(f"error: HDF5 snapshot not found: {hdf5}", file=sys.stderr)
        return 2
    if not run_pipeline.exists():
        print(f"error: run_pipeline.sh not found: {run_pipeline}", file=sys.stderr)
        return 2

    out_dir = args.out_dir.expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    cases: List[RenderCase] = []
    if not args.only_debug:
        cases.extend(FINAL_CASES)
    if not args.only_final:
        cases.extend(
            RenderCase(
                f"debug_{view.replace('-', '_')}",
                "grmhd-temperature-flow-scientific",
                view,
                "Scientific presentation debug map; compare against raw/final outputs.",
            )
            for view in DEBUG_VIEWS
        )

    results: List[dict] = []
    for idx, case in enumerate(cases, start=1):
        print(f"[{idx:02d}/{len(cases):02d}] render {case.name}")
        result = run_case(
            case,
            run_pipeline=run_pipeline,
            hdf5=hdf5,
            out_dir=out_dir,
            width=args.width,
            height=args.height,
            ssaa=args.ssaa,
            preset=args.preset,
            metric=args.metric,
            spin=args.spin,
            no_build=not args.build,
        )
        results.append(result)
        if result["returncode"] != 0:
            print(f"  failed: see {result['log']}", file=sys.stderr)

    manifest = {
        "hdf5": str(hdf5),
        "width": args.width,
        "height": args.height,
        "ssaa": args.ssaa,
        "preset": args.preset,
        "metric": args.metric,
        "spin": args.spin,
        "results": results,
    }
    manifest_path = out_dir / "matrix_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    sheet_path = out_dir / "matrix_contact.png"
    made_sheet = make_contact_sheet(results, sheet_path, args.width, args.height)
    print(f"manifest: {manifest_path}")
    if made_sheet:
        print(f"contact sheet: {sheet_path}")
    failures = [r for r in results if r["returncode"] != 0]
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
