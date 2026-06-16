#!/usr/bin/env python3
"""Validate the GUI source/observer/render-intent command matrix.

The SwiftUI launcher is a thin CLI command generator. This script keeps the
matrix contract explicit without launching the app: source options come from the
GUI manifest, observer/render intents are checked against the presentation
contract, and RAW-like audit commands must explicitly disable camera effects.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from gargantua_gui_contract import (
    COMMAND_MATRIX_MODES,
    RAW_LIKE_ARGS,
    command_for,
    has_pair,
    launcher_sources_text,
    load_manifest,
)

ROOT = Path(__file__).resolve().parents[1]
OUT = Path("/private/tmp/bh_gui_command_matrix.json")


def main() -> None:
    manifest = load_manifest()
    launcher = launcher_sources_text()
    failures: list[str] = []
    rows: list[dict[str, Any]] = []

    source_models = manifest["sourceModels"]
    modes = COMMAND_MATRIX_MODES
    for source in source_models:
        for mode in modes:
            args = command_for(source, mode)
            row = {"source": source["id"], "status": source["status"], "mode": mode, "args": args}
            rows.append(row)

            if source["status"] == "legacy":
                if "--source-model" in args:
                    failures.append(f"{source['id']} {mode}: legacy source must not use --source-model")
                if "--disk-model" not in args and "--science-regime" not in args:
                    failures.append(f"{source['id']} {mode}: legacy source must use --disk-model or --science-regime")
                if "--science-regime" in args and not has_pair(args, "--science-regime", source["id"]):
                    failures.append(f"{source['id']} {mode}: legacy science-regime source must pass its id")
            else:
                if not has_pair(args, "--source-model", source["id"]):
                    failures.append(f"{source['id']} {mode}: public source must use --source-model <id>")

            if source.get("requiresDiskHDF5"):
                default_hdf5 = source.get("defaultDiskHDF5", "")
                if not default_hdf5:
                    failures.append(f"{source['id']} {mode}: data-backed source must define defaultDiskHDF5")
                if not has_pair(args, "--disk-hdf5", default_hdf5):
                    failures.append(f"{source['id']} {mode}: data-backed source must include --disk-hdf5")

            if mode == "eye":
                if not has_pair(args, "--presentation", "eye") or not has_pair(args, "--camera-model", "eye"):
                    failures.append(f"{source['id']} eye: missing eye presentation/model")
                if "--camera-flare" in args or "--camera-dof-strength" in args:
                    failures.append(f"{source['id']} eye: must not expose camera effects")
            elif mode == "raw-like":
                for key, value in [
                    ("--presentation", "camera-raw"),
                    ("--camera-model", "legacy"),
                    ("--camera-profile", "ideal"),
                    ("--look", "linear"),
                    ("--exposure-mode", "fixed"),
                    ("--camera-psf-sigma", "0"),
                    ("--camera-read-noise", "0"),
                    ("--camera-shot-noise", "0"),
                    ("--camera-flare", "0"),
                    ("--camera-dof-strength", "0"),
                    ("--background", "off"),
                    ("--hdr-out", "/private/tmp/gargantua_gui_render.png.raw.linear32f32"),
                    ("--camera-raw-out", "/private/tmp/gargantua_gui_render.png.bayer-rggb-f32.raw"),
                ]:
                    if not has_pair(args, key, value):
                        failures.append(f"{source['id']} raw-like: missing {key} {value}")
                if "--hdr-intermediate" not in args:
                    failures.append(f"{source['id']} raw-like: missing --hdr-intermediate")
            elif mode == "rendered":
                if not has_pair(args, "--presentation", "camera-rendered"):
                    failures.append(f"{source['id']} rendered: missing camera-rendered presentation")
                if has_pair(args, "--realism-profile", "cinematic"):
                    failures.append(f"{source['id']} rendered: must not use cinematic realism profile")
                for key, value in [
                    ("--exposure-mode", "photographic"),
                    ("--camera-f-number", "4"),
                    ("--camera-shutter", "1/60"),
                    ("--camera-iso", "100"),
                    ("--photographic-calibration", "photometric"),
                    ("--camera-diffraction", "0.02"),
                    ("--camera-photon-noise", "auto"),
                ]:
                    if not has_pair(args, key, value):
                        failures.append(f"{source['id']} rendered: missing {key} {value}")
            elif mode == "cinematic":
                if not has_pair(args, "--presentation", "cinema"):
                    failures.append(f"{source['id']} cinematic: missing cinema presentation")
                if not has_pair(args, "--realism-profile", "cinematic"):
                    failures.append(f"{source['id']} cinematic: missing cinematic realism profile")
                for key, value in [
                    ("--exposure-mode", "photographic"),
                    ("--camera-profile", "cinema-digital"),
                    ("--camera-aperture-blades", "7"),
                    ("--camera-diffraction", "0.02"),
                    ("--camera-photon-noise", "auto"),
                ]:
                    if not has_pair(args, key, value):
                        failures.append(f"{source['id']} cinematic: missing {key} {value}")

    for token in RAW_LIKE_ARGS:
        if token in [
            "/private/tmp/gargantua_gui_render.png.raw.linear32f32",
            "/private/tmp/gargantua_gui_render.png.bayer-rggb-f32.raw",
        ]:
            continue
        if token not in launcher:
            failures.append(f"GargantuaLauncher.swift raw-like path missing token {token}")

    for token in [
        "requiresDiskHDF5",
        "defaultDiskHDF5",
        "--disk-hdf5",
        "chooseDiskHDF5",
        "rawBufferPath",
        ".raw.linear32f32",
        "sensorRawBufferPath",
        ".bayer-rggb-f32.raw",
        "--ssaa",
        "--ray-bundle",
        "--camX",
        "--fov",
        "CameraExposureProgram",
        "--eye-nd",
        "--camera-diffraction",
        "--camera-photon-noise",
        "PreviewPanel",
        "ProgressView",
    ]:
        if token not in launcher:
            failures.append(f"GargantuaLauncher.swift data-backed source path missing token {token}")

    report = {
        "passed": not failures,
        "source_count": len(source_models),
        "mode_count": len(modes),
        "matrix_rows": len(rows),
        "modes": modes,
        "failures": failures,
        "rows": rows,
    }
    OUT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "rows"}, indent=2, sort_keys=True))
    print(f"report={OUT}")
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
