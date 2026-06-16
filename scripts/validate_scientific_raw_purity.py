#!/usr/bin/env python3
"""Audit scientific/camera-raw purity against presentation-effect leakage.

This is a fast static policy gate. Pixel invariance is covered by the compose
and source-render validators; this script catches drift in the command/parser
surface before a render is needed.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUT = Path("/private/tmp/bh_scientific_raw_purity.json")


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def has_all(text: str, tokens: list[str]) -> dict[str, bool]:
    return {token: token in text for token in tokens}


def group(name: str, rel: str, tokens: list[str]) -> dict[str, Any]:
    text = read(rel)
    checks = has_all(text, tokens)
    return {
        "file": rel,
        "checks": checks,
        "passed": all(checks.values()),
    }


def main() -> None:
    groups: dict[str, dict[str, Any]] = {
        "camera_raw_parser_defaults": group(
            "camera_raw_parser_defaults",
            "Blackhole/Sources/Params/ParamsBuilderVisual.swift",
            [
                'case "camera-raw", "camera_raw", "raw", "raw-like", "rawlike"',
                'case 4: return "legacy"',
                'case 4: return "ideal"',
                'case 4: return "physical"',
                'case 4: return "off"',
                "if composeLookID == 4 { return 0.0 }",
                "camera-raw is a RAW-like identity audit route",
                "camera-raw requires --look linear/none",
                "camera-raw requires --dither 0",
                "camera-raw requires PSF, read noise, shot noise, flare, and depth of field disabled",
                'presentationModeID == 4 ? "fixed" : "auto"',
                "if presentationModeID == 4 { return 0.0 }",
                '"--camera-psf-sigma"',
                '"--camera-read-noise"',
                '"--camera-shot-noise"',
                '"--camera-flare"',
                '"--camera-dof-strength"',
            ],
        ),
        "analysis_mode_effect_zeroing": group(
            "analysis_mode_effect_zeroing",
            "Blackhole/Sources/Params/ParamsBuilderVisual.swift",
            [
                "let composeCameraModelID = (composeAnalysisMode == 0) ? composePolicy.composeCameraModelID : 0",
                "let composeCameraPsfSigmaArg = (composeAnalysisMode == 0) ? composePolicy.composeCameraPsfSigmaArg : 0.0",
                "let composeCameraReadNoiseArg = (composeAnalysisMode == 0) ? composePolicy.composeCameraReadNoiseArg : 0.0",
                "let composeCameraShotNoiseArg = (composeAnalysisMode == 0) ? composePolicy.composeCameraShotNoiseArg : 0.0",
                "let composeCameraFlareStrengthArg = (composeAnalysisMode == 0) ? composePolicy.composeCameraFlareStrengthArg : 0.0",
                "if composeAnalysisMode != 0 && composeAnalysisMode != 31 && composeAnalysisMode != 32 { return false }",
                "if exposureModeID == 1 { return false }",
                "if exposureModeID == 2 { return false }",
            ],
        ),
        "policy_effect_zeroing": group(
            "policy_effect_zeroing",
            "Blackhole/Sources/Params/ParamsBuilderPolicy.swift",
            [
                "composeCameraModelID: (composeAnalysisMode == 0) ? cameraModelID : 0",
                "composeCameraPsfSigmaArg: (composeAnalysisMode == 0) ? cameraPsfSigmaArg : 0.0",
                "composeCameraReadNoiseArg: (composeAnalysisMode == 0) ? cameraReadNoiseArg : 0.0",
                "composeCameraShotNoiseArg: (composeAnalysisMode == 0) ? cameraShotNoiseArg : 0.0",
                "composeCameraFlareStrengthArg: (composeAnalysisMode == 0) ? cameraFlareStrengthArg : 0.0",
            ],
        ),
        "runtime_scientific_look_policy": group(
            "runtime_scientific_look_policy",
            "Blackhole/Sources/Params/ParamsBuilderRuntime.swift",
            [
                '["scientific", "science", "master", "camera-raw", "raw", "camera_raw"].contains(presentationModeRaw)',
                'if scientificPresentation && !hasLookArg { return "linear" }',
                'case "none", "linear": composeLookID = 4',
            ],
        ),
        "metal_effect_gates": group(
            "metal_effect_gates",
            "Blackhole/Metal/Compose/helpers.metalh",
            [
                "return (C.analysisMode == 0u) &&",
                "comp_camera_dof_enabled",
                "if (profile < 2u || !(s > 1e-6)) return base;",
                "return (C.cameraModel == 3u) &&",
                "comp_eye_local_adaptation_enabled",
                "if (C.analysisMode != 0u) return rgb;",
            ],
        ),
        "gui_raw_like_command": group(
            "gui_raw_like_command",
            "tools/GargantuaLauncher/GargantuaLauncher.swift",
            [
                '"--presentation", "camera-raw"',
                '"--camera-model", "legacy"',
                '"--camera-profile", "ideal"',
                '"--look", "linear"',
                '"--exposure-mode", "fixed"',
                '"--camera-psf-sigma", "0"',
                '"--camera-read-noise", "0"',
                '"--camera-shot-noise", "0"',
                '"--camera-flare", "0"',
                '"--camera-dof-strength", "0"',
                '"--background", "off"',
                '"--hdr-intermediate"',
                '"--hdr-out", rawBufferPath',
            ],
        ),
        "gui_matrix_raw_like_gate": group(
            "gui_matrix_raw_like_gate",
            "scripts/validate_gui_command_matrix.py",
            [
                '("--presentation", "camera-raw")',
                '("--camera-model", "legacy")',
                '("--camera-profile", "ideal")',
                '("--look", "linear")',
                '("--exposure-mode", "fixed")',
                '("--camera-psf-sigma", "0")',
                '("--camera-read-noise", "0")',
                '("--camera-shot-noise", "0")',
                '("--camera-flare", "0")',
                '("--camera-dof-strength", "0")',
                '("--background", "off")',
                '"--hdr-intermediate"',
                '"--hdr-out"',
            ],
        ),
    }

    failures = [
        f"{name}:{token}"
        for name, data in groups.items()
        for token, passed in data["checks"].items()
        if not passed
    ]

    report = {
        "phase": "Phase 1/5/6 scientific and camera-raw purity audit",
        "passed": not failures,
        "failures": failures,
        "groups": groups,
        "scope": [
            "static parser/policy/GUI/Metal gate audit",
            "proves default and audit routes keep presentation effects off for scientific and camera-raw",
            "does not replace pixel-level validators or the camera RAW sidecar validator",
        ],
        "contract_gaps": [
            "camera-raw now has ideal RGGB float32 CFA and reference RGGB u16 sensor/ADC sidecars, but not proprietary RAW containers or named camera profiles.",
            "Metal gates are static-token audited here; source-render pixel invariance remains covered by separate validators.",
        ],
    }
    OUT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "groups"}, indent=2, sort_keys=True))
    print(f"report={OUT}")
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
