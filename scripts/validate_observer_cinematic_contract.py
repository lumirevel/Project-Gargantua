#!/usr/bin/env python3
"""Phase 5/6 observer and cinematic off-switch contract check.

This fast check verifies the command/control surface for RAW-like scientific
audit routing and cinematic effect isolation. It does not render images; future
Phase 6 work must add pixel-level same-radiance comparisons.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
RUN_PIPELINE = ROOT / "Blackhole" / "run_pipeline.sh"


RAW_LIKE_AUDIT = [
    "bash",
    str(RUN_PIPELINE),
    "--source-model",
    "canonical-visible-disk-v1",
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
]

CINEMATIC_ON = [
    "bash",
    str(RUN_PIPELINE),
    "--source-model",
    "cinematic-physical-disk-v1",
    "--presentation",
    "camera-rendered",
    "--camera-model",
    "cinematic",
    "--camera-profile",
    "cinema-digital",
    "--look",
    "cinematic",
    "--realism-profile",
    "cinematic",
    "--camera-flare",
    "0.20",
    "--camera-dof-strength",
    "1.0",
]


def help_text(topic: str) -> str:
    return subprocess.run(
        ["bash", str(RUN_PIPELINE), "--help", topic],
        cwd=str(ROOT),
        check=True,
        text=True,
        capture_output=True,
    ).stdout


def token_check(path: Path, tokens: list[str]) -> dict[str, bool]:
    text = path.read_text(encoding="utf-8")
    return {token: token in text for token in tokens}


def command_has_pair(cmd: list[str], flag: str, value: str) -> bool:
    for i, item in enumerate(cmd[:-1]):
        if item == flag and cmd[i + 1] == value:
            return True
    return False


def main() -> None:
    camera_help = help_text("camera")
    general_help = subprocess.run(
        ["bash", str(RUN_PIPELINE), "--help"],
        cwd=str(ROOT),
        check=True,
        text=True,
        capture_output=True,
    ).stdout
    advanced_help = help_text("advanced")
    legacy_help = help_text("legacy")
    combined_help = "\n".join([general_help, camera_help, advanced_help, legacy_help])

    help_tokens = {
        "camera": {
            token: token in combined_help
            for token in [
                "--presentation",
                "--camera-profile",
                "--camera-psf-sigma",
                "--camera-read-noise",
                "--camera-shot-noise",
                "--camera-flare",
                "--camera-dof-strength",
                "--compose-hdr-in",
            ]
        },
        "modes": {
            token: token in combined_help
            for token in ["scientific", "eye", "cinema", "legacy"]
            + ["camera-raw", "camera-rendered"]
        },
    }

    policy_tokens = token_check(
        ROOT / "Blackhole" / "Sources" / "Params" / "ParamsBuilderPolicy.swift",
        [
            "composeAnalysisMode == 0",
            "cameraPsfSigmaArg : 0.0",
            "cameraReadNoiseArg : 0.0",
            "cameraShotNoiseArg : 0.0",
            "cameraFlareStrengthArg : 0.0",
        ],
    )
    visual_tokens = token_check(
        ROOT / "Blackhole" / "Sources" / "Params" / "ParamsBuilderVisual.swift",
        [
            "--camera-model",
            'case "scientific", "science"',
            'case "camera-raw", "camera_raw", "raw", "raw-like", "rawlike"',
            'case "camera-rendered", "camera_rendered", "rendered-camera", "rendered", "photo", "photographic"',
            'case "cinema", "cinematic", "camera"',
            'case "cinema", "cinematic", "cinema-digital", "arri-like"',
            "--camera-dof-strength",
            "--camera-flare",
        ],
    )

    raw_like_pairs = {
        "camera_raw_presentation": command_has_pair(RAW_LIKE_AUDIT, "--presentation", "camera-raw"),
        "identity_camera_model": command_has_pair(RAW_LIKE_AUDIT, "--camera-model", "legacy"),
        "identity_camera_profile": command_has_pair(RAW_LIKE_AUDIT, "--camera-profile", "ideal"),
        "linear_look": command_has_pair(RAW_LIKE_AUDIT, "--look", "linear"),
        "fixed_exposure": command_has_pair(RAW_LIKE_AUDIT, "--exposure-mode", "fixed"),
        "psf_off": command_has_pair(RAW_LIKE_AUDIT, "--camera-psf-sigma", "0"),
        "read_noise_off": command_has_pair(RAW_LIKE_AUDIT, "--camera-read-noise", "0"),
        "shot_noise_off": command_has_pair(RAW_LIKE_AUDIT, "--camera-shot-noise", "0"),
        "flare_off": command_has_pair(RAW_LIKE_AUDIT, "--camera-flare", "0"),
        "dof_off": command_has_pair(RAW_LIKE_AUDIT, "--camera-dof-strength", "0"),
        "background_off": command_has_pair(RAW_LIKE_AUDIT, "--background", "off"),
    }
    cinematic_pairs = {
        "camera_rendered_presentation": command_has_pair(CINEMATIC_ON, "--presentation", "camera-rendered"),
        "cinematic_camera_model": command_has_pair(CINEMATIC_ON, "--camera-model", "cinematic"),
        "cinema_profile": command_has_pair(CINEMATIC_ON, "--camera-profile", "cinema-digital"),
        "cinematic_look": command_has_pair(CINEMATIC_ON, "--look", "cinematic"),
        "flare_enabled": command_has_pair(CINEMATIC_ON, "--camera-flare", "0.20"),
        "dof_enabled": command_has_pair(CINEMATIC_ON, "--camera-dof-strength", "1.0"),
    }

    groups: dict[str, dict[str, bool]] = {
        "help_tokens_camera": help_tokens["camera"],
        "help_tokens_modes": help_tokens["modes"],
        "analysis_mode_policy_tokens": policy_tokens,
        "visual_parser_tokens": visual_tokens,
        "raw_like_audit_command": raw_like_pairs,
        "cinematic_command": cinematic_pairs,
    }
    failures = [
        f"{group}:{name}"
        for group, checks in groups.items()
        for name, passed in checks.items()
        if not passed
    ]
    report: dict[str, Any] = {
        "phase": "Phase 5/6 observer-cinematic contract",
        "passed": not failures,
        "failures": failures,
        "checks": groups,
        "commands": {
            "raw_like_identity_audit": RAW_LIKE_AUDIT,
            "cinematic_on": CINEMATIC_ON,
        },
        "contract_gaps": [
            "camera-raw and camera-rendered are first-class presentation names; camera-raw has ideal RGGB float32 CFA and reference RGGB u16 sensor/ADC sidecars, but not proprietary RAW containers or named camera profiles.",
            "This fast check proves command/control isolation; scripts/validate_cinematic_pixel_invariance.py covers synthetic compose-path pixel-level invariance.",
            "Future Phase 6 should promote pixel-level invariance to a full black-hole source render.",
        ],
    }
    out = Path("/private/tmp/bh_observer_cinematic_contract.json")
    out.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    print(f"report={out}")
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
