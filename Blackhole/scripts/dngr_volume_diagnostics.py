#!/usr/bin/env python3
"""Run focused diagnostics for the DNGR/Interstellar 3D volume bridge.

This is a rendering-debug harness, not a new physical model. It renders the
same camera/frame with fixed exposure plus transfer/state debug maps so source
function flattening, optical-depth closure, and presentation clipping can be
checked side-by-side.
"""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
RUN_PIPELINE = ROOT / "Blackhole" / "run_pipeline.sh"


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out-dir", default="/tmp/bh_dngr_volume_diagnostics")
    ap.add_argument("--width", type=int, default=384)
    ap.add_argument("--height", type=int, default=240)
    ap.add_argument("--preset", default="interstellar")
    ap.add_argument("--metric", default="kerr")
    ap.add_argument("--spin", default="0.92")
    ap.add_argument("--samples", default="1")
    ap.add_argument("--build", action="store_true", help="allow run_pipeline.sh to rebuild before rendering")
    ap.add_argument("--debug", action="append", default=[], help="extra --disk-grmhd-debug view to render")
    ap.add_argument("--ev", action="append", default=[], help="extra fixed exposure EV to render")
    return ap.parse_args()


def run_render(label: str, out_path: Path, base: List[str], extra: Iterable[str], no_build: bool) -> None:
    cmd = [str(RUN_PIPELINE)]
    if no_build:
        cmd.append("--no-build")
    cmd += base
    cmd += list(extra)
    cmd += ["--output", str(out_path)]
    result = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True)
    if result.returncode != 0:
        log = out_path.with_suffix(".log")
        log.write_text(result.stdout + "\n" + result.stderr, encoding="utf-8")
        raise RuntimeError(f"{label} failed rc={result.returncode}; log={log}")


def image_stats(path: Path) -> Dict[str, float]:
    arr = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
    luma = arr @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    mask = luma > 0.02
    if not np.any(mask):
        return {"mean": 0.0, "std": 0.0, "cv": 0.0, "p05": 0.0, "p95": 0.0}
    v = luma[mask]
    return {
        "mean": float(np.mean(v)),
        "std": float(np.std(v)),
        "cv": float(np.std(v) / max(float(np.mean(v)), 1.0e-9)),
        "p05": float(np.percentile(v, 5.0)),
        "p95": float(np.percentile(v, 95.0)),
    }


def make_contact(items: List[Tuple[str, Path]], out_path: Path) -> None:
    thumbs: List[Tuple[str, Image.Image]] = []
    for label, path in items:
        stats = image_stats(path)
        img = Image.open(path).convert("RGB")
        thumbs.append((f"{label} cv={stats['cv']:.3f}", img))
    if not thumbs:
        return
    w, h = thumbs[0][1].size
    cols = 3
    label_h = 24
    rows = (len(thumbs) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * w, rows * (h + label_h)), (18, 18, 18))
    draw = ImageDraw.Draw(sheet)
    for i, (label, img) in enumerate(thumbs):
        x = (i % cols) * w
        y = (i // cols) * (h + label_h)
        draw.rectangle([x, y, x + w, y + label_h], fill=(28, 28, 28))
        draw.text((x + 8, y + 5), label, fill=(235, 235, 235))
        sheet.paste(img, (x, y + label_h))
    sheet.save(out_path)


def main() -> int:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    base = [
        "--science-regime", "dngr-volume",
        "--preset", args.preset,
        "--metric", args.metric,
        "--spin", args.spin,
        "--width", str(args.width),
        "--height", str(args.height),
        "--samples", args.samples,
    ]
    no_build = not args.build
    evs = args.ev or ["-20", "-19", "-18", "-17", "-16"]
    debugs = args.debug or [
        "teff",
        "tau",
        "alpha",
        "samples",
        "source",
        "jthermal",
        "source-thermal",
        "thermal-alpha-post",
        "thin-weight",
        "raw-log",
        "post-exposure",
        "post-tonemap",
    ]

    renders: List[Tuple[str, Path]] = []
    report: Dict[str, object] = {"renders": {}, "stats": {}}

    for ev in evs:
        label = f"final_ev_{ev.replace('-', 'm')}"
        path = out_dir / f"{label}.png"
        run_render(label, path, base, ["--exposure-mode", "fixed", "--exposure-ev", ev], no_build)
        renders.append((label, path))

    for debug in debugs:
        label = f"debug_{debug.replace('-', '_')}"
        path = out_dir / f"{label}.png"
        run_render(label, path, base, ["--disk-grmhd-debug", debug], no_build)
        renders.append((label, path))

    for label, path in renders:
        report["renders"][label] = str(path)
        report["stats"][label] = image_stats(path)

    contact = out_dir / "contact.png"
    make_contact(renders, contact)
    report["renders"]["contact"] = str(contact)
    (out_dir / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(f"contact: {contact}")
    print(f"report: {out_dir / 'report.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
