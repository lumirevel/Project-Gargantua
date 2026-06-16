#!/usr/bin/env python3
"""Validate public/topic CLI help boundaries for run_pipeline.sh."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUN_PIPELINE = ROOT / "Blackhole" / "run_pipeline.sh"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--run-pipeline", default=str(RUN_PIPELINE))
    return p.parse_args()


def run_help(run_pipeline: str, *topic: str) -> str:
    cmd = ["bash", run_pipeline, "--help", *topic]
    return subprocess.run(cmd, cwd=str(ROOT), check=True, text=True, capture_output=True).stdout


def assert_contains(label: str, text: str, tokens: list[str]) -> list[str]:
    return [f"{label}: missing {tok}" for tok in tokens if tok not in text]


def assert_not_contains(label: str, text: str, tokens: list[str]) -> list[str]:
    return [f"{label}: should not expose {tok}" for tok in tokens if tok in text]


def main() -> None:
    args = parse_args()
    public = run_help(args.run_pipeline)
    source = run_help(args.run_pipeline, "source-models")
    camera = run_help(args.run_pipeline, "camera")
    grmhd = run_help(args.run_pipeline, "grmhd")
    legacy = run_help(args.run_pipeline, "legacy")
    advanced = run_help(args.run_pipeline, "advanced")

    failures: list[str] = []
    failures += assert_contains("public help", public, [
        "--source-model",
        "--quality",
        "--width",
        "--height",
        "--output",
        "--presentation",
        "--look",
        "--exposure-mode",
        "--camera-f-number",
        "--camera-shutter",
        "--camera-iso",
        "--disk-grmhd-debug",
        "--help legacy",
    ])
    failures += assert_not_contains("public help", public, [
        "--disk-model perlin",
        "--disk-source",
        "--science-regime",
        "perlin-classic",
        "perlin-ec7",
        "dngr-volume",
        "--disk-precision-texture",
        "--disk-volume-hdf5",
    ])
    failures += assert_contains("source-models help", source, [
        "canonical-visible-disk-v1",
        "cinematic-physical-disk-v1",
        "physics-constrained-cinematic-disk-v1",
        "grmhd-surrogate-disk-v1",
        "thin-disk-visible-reference",
        "static-transfer-reference-v1",
        "grmhd-hot-flow-diagnostic",
        "grmhd-temperature-flow-diagnostic",
        "--disk-model is a low-level",
    ])
    failures += assert_contains("camera help", camera, [
        "--presentation",
        "--look",
        "--exposure-mode",
        "--camera-f-number",
        "--camera-shutter",
        "--camera-iso",
        "--camera-focus-depth",
        "tone_mapped_no_bloom",
    ])
    failures += assert_contains("grmhd help", grmhd, [
        "--disk-mode grmhd",
        "--disk-grmhd-debug optical_depth",
        "--disk-grmhd-debug transfer-saturation",
        "--disk-grmhd-debug emissivity-pre-transfer",
        "--disk-grmhd-debug radiance-post-transfer",
        "--visible-emission-model",
    ])
    failures += assert_contains("legacy help", legacy, [
        "--disk-model flow",
        "--disk-model perlin",
        "--disk-model perlin-classic",
        "--disk-model perlin-ec7",
        "--disk-model noise",
        "--science-regime",
        "dngr-volume",
        "perlin-f552",
        "perlin-legacy",
    ])
    failures += assert_contains("advanced help", advanced, [
        "--disk-precision-texture",
        "--disk-volume-hdf5",
        "--compose-hdr-in",
        "--collisions-out",
    ])

    # Parser acceptance smoke: these commands should stop after help or ABI
    # validation, not render images.
    parser_smoke = [
        ["bash", args.run_pipeline, "--help", "legacy"],
        ["bash", args.run_pipeline, "--help", "source-models"],
        ["bash", args.run_pipeline, "--help", "camera"],
        ["bash", args.run_pipeline, "--help", "grmhd"],
    ]
    for cmd in parser_smoke:
        subprocess.run(cmd, cwd=str(ROOT), check=True, stdout=subprocess.DEVNULL)

    if failures:
        print("\n".join(failures))
        raise SystemExit(1)
    print("cli surface validation passed")


if __name__ == "__main__":
    main()
