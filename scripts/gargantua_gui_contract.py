#!/usr/bin/env python3
"""Shared GUI command-surface contract helpers.

Keep these helpers side-effect free. Validators can import this module to
check the same source/observer/render-intent command surface without copying
argument lists across scripts.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "docs" / "realism" / "gui_option_manifest_v1.json"
LAUNCHER_DIR = ROOT / "tools" / "GargantuaLauncher"

REQUIRED_SOURCE_IDS = [
    "canonical-visible-disk-v1",
    "cinematic-physical-disk-v1",
    "physics-constrained-cinematic-disk-v1",
    "thin-disk-visible-reference",
    "static-transfer-reference-v1",
    "grmhd-surrogate-disk-v1",
    "grmhd-temperature-flow-diagnostic",
    "legacy-perlin",
    "legacy-perlin-classic",
    "legacy-perlin-ec7",
    "legacy-bh-finish-grmhd",
    "legacy-thin-disk-preset-default",
]

REQUIRED_INTENTS = ["raw-like", "rendered", "cinematic"]
VALID_STATUS = {"recommended", "production-candidate", "surrogate", "diagnostic", "legacy"}
COMMAND_MATRIX_MODES = ["eye", "raw-like", "rendered", "cinematic"]

BASE_PREFIX_ARGS = [
    "--metric",
    "kerr",
    "--spin",
    "0.6",
    "--quality",
    "preview",
    "--width",
    "1536",
    "--height",
    "864",
    "--ssaa",
    "1",
]

BASE_SUFFIX_ARGS = [
    "--no-build",
    "--output",
    "/private/tmp/gargantua_gui_render.png",
]

RAW_LIKE_ARGS = [
    "--presentation",
    "camera-raw",
    "--camera-model",
    "legacy",
    "--camera-profile",
    "ideal",
    "--look",
    "linear",
    "--exposure-mode",
    "fixed",
    "--exposure-ev",
    "0",
    "--camera-psf-sigma",
    "0",
    "--camera-read-noise",
    "0",
    "--camera-shot-noise",
    "0",
    "--camera-flare",
    "0",
    "--camera-dof-strength",
    "0",
    "--background",
    "off",
    "--hdr-intermediate",
    "--hdr-out",
    "/private/tmp/gargantua_gui_render.png.raw.linear32f32",
    "--camera-raw-out",
    "/private/tmp/gargantua_gui_render.png.bayer-rggb-f32.raw",
]


def load_manifest() -> dict[str, Any]:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def launcher_sources_text() -> str:
    return "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted(LAUNCHER_DIR.glob("*.swift"))
    )


def has_pair(args: list[str], key: str, value: str) -> bool:
    return any(args[i] == key and i + 1 < len(args) and args[i + 1] == value for i in range(len(args)))


def command_for(source: dict[str, Any], mode: str) -> list[str]:
    args = list(source["args"])
    if source.get("requiresDiskHDF5"):
        args += ["--disk-hdf5", source.get("defaultDiskHDF5", "")]
    args += BASE_PREFIX_ARGS
    if mode == "eye":
        args += [
            "--presentation",
            "eye",
            "--camera-model",
            "eye",
            "--realism-profile",
            "physical",
            "--look",
            "realistic",
        ]
    elif mode == "raw-like":
        args += RAW_LIKE_ARGS
    elif mode == "rendered":
        args += [
            "--presentation",
            "camera-rendered",
            "--camera-model",
            "cinematic",
            "--exposure-mode",
            "photographic",
            "--camera-f-number",
            "4",
            "--camera-shutter",
            "1/60",
            "--camera-iso",
            "100",
            "--photographic-calibration",
            "photometric",
            "--camera-profile",
            "full-frame",
            "--look",
            "linear",
            "--realism-profile",
            "observational",
            "--camera-flare",
            "0",
            "--camera-dof-strength",
            "0",
            "--camera-diffraction",
            "0.02",
            "--camera-psf-sigma",
            "0",
            "--camera-read-noise",
            "0",
            "--camera-shot-noise",
            "0",
            "--camera-photon-noise",
            "auto",
            "--camera-photon-scale",
            "1",
        ]
    elif mode == "cinematic":
        args += [
            "--presentation",
            "cinema",
            "--camera-model",
            "cinematic",
            "--exposure-mode",
            "photographic",
            "--camera-f-number",
            "4",
            "--camera-shutter",
            "1/60",
            "--camera-iso",
            "100",
            "--photographic-calibration",
            "photometric",
            "--camera-profile",
            "cinema-digital",
            "--look",
            "linear",
            "--realism-profile",
            "cinematic",
            "--camera-flare",
            "0",
            "--camera-dof-strength",
            "0",
            "--camera-aperture-blades",
            "7",
            "--camera-diffraction",
            "0.02",
            "--camera-psf-sigma",
            "0",
            "--camera-read-noise",
            "0",
            "--camera-shot-noise",
            "0",
            "--camera-photon-noise",
            "auto",
            "--camera-photon-scale",
            "1",
        ]
    else:
        raise ValueError(mode)
    args += BASE_SUFFIX_ARGS
    return args
