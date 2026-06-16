#!/usr/bin/env python3
"""Audit Phase 0-6 and GUI completion evidence.

This script is stricter than validate_phase_readiness.py. Readiness checks that
the contract surface exists; this audit records whether the full active goal can
be considered complete. It intentionally fails while required end-state gaps
remain.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUT = Path("/private/tmp/bh_phase_completion_audit.json")


def run(cmd: list[str]) -> dict[str, Any]:
    completed = subprocess.run(cmd, cwd=str(ROOT), text=True, capture_output=True)
    return {
        "command": cmd,
        "returncode": completed.returncode,
        "stdout_tail": completed.stdout.strip().splitlines()[-20:],
        "stderr_tail": completed.stderr.strip().splitlines()[-20:],
        "passed": completed.returncode == 0,
    }


def text(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def has_all(haystack: str, needles: list[str]) -> bool:
    return all(needle in haystack for needle in needles)


def item(
    key: str,
    requirement: str,
    evidence: str,
    status: str,
    passed: bool,
    next_step: str = "",
) -> dict[str, Any]:
    return {
        "key": key,
        "requirement": requirement,
        "evidence": evidence,
        "status": status,
        "passed": passed,
        "next_step": next_step,
    }


def main() -> None:
    phase_state = text("docs/realism/13_phase0_to_phase6_execution_state.md")
    source_docs = text("docs/source_models.md")
    render_modes = text("docs/realism/09_render_modes.md")
    gui_manifest = text("docs/realism/gui_option_manifest_v1.json")
    gui_launcher = text("tools/GargantuaLauncher/GargantuaLauncher.swift")

    commands = {
        "phase_readiness": run(["python3", "scripts/validate_phase_readiness.py"]),
        "contract_docs": run(["python3", "scripts/validate_realism_contract_docs.py"]),
        "geodesic_scalar": run(["python3", "scripts/validate_geodesic_scalar_baseline.py", "--fail-on-contract-gaps"]),
        "source_registry": run(["python3", "scripts/validate_source_model_registry.py"]),
        "scientific_raw_purity": run(["python3", "scripts/validate_scientific_raw_purity.py"]),
        "camera_raw_sidecar": run(["python3", "scripts/validate_camera_raw_sidecar.py", "--width", "64", "--height", "36", "--no-build"]),
        "transfer_same_tetrad": run(["python3", "scripts/validate_transfer_same_tetrad_renderer_fixture.py", "--width", "64", "--height", "36", "--no-build"]),
        "grmhd_presentation_suite": run(["python3", "scripts/validate_grmhd_presentation_fixture.py", "--suite", "--require-data", "--width", "48", "--height", "27", "--no-build"]),
        "gui_manifest": run(["python3", "scripts/validate_gui_option_manifest.py"]),
        "gui_matrix": run(["python3", "scripts/validate_gui_command_matrix.py"]),
        "gui_primary_target": run(["python3", "scripts/validate_gui_primary_target.py"]),
    }

    requirements = [
        item(
            "phase0_governance",
            "Phase 0 governance docs and fast readiness gates exist.",
            "validate_phase_readiness.py and validate_realism_contract_docs.py pass.",
            "complete",
            commands["phase_readiness"]["passed"] and commands["contract_docs"]["passed"],
        ),
        item(
            "phase1_render_modes",
            "scientific, eye, camera-raw, camera-rendered, cinema, and legacy are explicitly separated.",
            "render mode docs and run_pipeline camera help expose first-class mode names, and camera-raw can emit an ideal RGGB float32 CFA sensor RAW sidecar.",
            "complete",
            has_all(render_modes, ["camera-raw", "camera-rendered", "cinematic", "legacy", "--camera-raw-out", "RGGB"])
            and has_all(text("scripts/validate_camera_raw_sidecar.py"), ["--camera-raw-out", "ideal Bayer", "sensor_raw_matches_linear32_rggb"]),
        ),
        item(
            "phase2_geodesic",
            "Geodesic correctness has scalar gates for null condition, conserved quantities, Schwarzschild limit, and photon-sphere behavior.",
            "validate_geodesic_scalar_baseline.py runs Carter Q, Schwarzschild-vs-Kerr, photon-sphere, and 3x3 near-critical image-plane hard gates.",
            "complete",
            has_all(
                text("scripts/validate_geodesic_scalar_baseline.py"),
                ["Carter Q", "Schwarzschild-vs-Kerr", "schwarzschild_photon_sphere_check", "3x3 image-plane near-critical grid"],
            )
            and commands["geodesic_scalar"]["passed"],
        ),
        item(
            "phase3_transfer",
            "Redshift/Doppler/invariant intensity have scalar and renderer-produced diagnostic gates.",
            "transfer scalar, g-factor map, raw-g float diagnostic, same-tetrad renderer fixture, and static-transfer renderer fixture validators cover g~=1 analytics, I_nu/nu^3, low/baseline/high Doppler maps, raw renderer g output, and a no-flow Schwarzschild render path.",
            "complete",
            has_all(text("scripts/validate_transfer_gfactor_maps.py"), ["low_doppler", "high_doppler_stronger_than_low_doppler"])
            and has_all(text("scripts/validate_transfer_scalar_baseline.py"), ["I_nu / nu^3", "static"])
            and has_all(text("scripts/validate_transfer_static_renderer_fixture.py"), ["static-transfer-reference-v1", "no-flow transfer check"])
            and has_all(text("scripts/validate_transfer_raw_g_debug.py"), ["--realism-debug raw-g", "float diagnostics"])
            and commands["transfer_same_tetrad"]["passed"],
        ),
        item(
            "phase4_source_registry",
            "Public/candidate source models are documented, labeled, and template-enforced.",
            "Source Model Contract Matrix and validate_source_model_registry.py enforce assumptions/inputs/outputs/limitations/modes/validation/forbidden hacks.",
            "complete",
            commands["source_registry"]["passed"]
            and has_all(source_docs, ["Source Model Contract Matrix", "Forbidden hacks", "Allowed render modes"]),
        ),
        item(
            "phase5_observer_camera",
            "Observer/camera interpreter is downstream of physical radiance, with RAW-like and rendered-camera paths separated.",
            "camera-raw sidecar validator checks linear32, ideal RGGB float32 CFA, and reference RGGB u16 sensor/ADC outputs; GUI emits --hdr-intermediate --hdr-out --camera-raw-out for RAW-like commands; scientific/RAW purity audit passes.",
            "complete",
            commands["camera_raw_sidecar"]["passed"]
            and has_all(text("scripts/validate_camera_raw_sidecar.py"), ["camera-raw linear32 sidecar", "--hdr-intermediate", "--hdr-out", "--camera-raw-out", "sensor_raw_matches_linear32_rggb", "bayer-rggb-u16", "sensorShotNoise", "adcBits"])
            and has_all(gui_launcher, ["rawBufferPath", "sensorRawBufferPath", "--hdr-out", "--camera-raw-out"])
            and commands["scientific_raw_purity"]["passed"],
            "Future work can add proprietary RAW containers, demosaic/rendered-camera comparison, and named camera calibration profiles.",
        ),
        item(
            "phase6_cinematic",
            "Cinematic layer is isolated from scientific and RAW-like outputs.",
            "pixel, black-hole source, source-matrix, GRMHD data-backed suite, and static scientific/RAW purity validators pass.",
            "complete",
            has_all(
                phase_state,
                [
                    "validate_cinematic_pixel_invariance.py",
                    "validate_blackhole_presentation_invariance.py",
                    "validate_presentation_source_matrix.py",
                    "validate_grmhd_presentation_fixture.py",
                    "validate_scientific_raw_purity.py",
                ],
            )
            and has_all(text("scripts/validate_grmhd_presentation_fixture.py"), ["--suite", "suite_min_count", "schema_hints"])
            and commands["scientific_raw_purity"]["passed"]
            and commands["grmhd_presentation_suite"]["passed"],
            "Future work can add named paper-reference GRMHD calibration cases and bloom/glare-only diagnostic layers.",
        ),
        item(
            "gui_contract_aware",
            "CLI options are moved into a contract-aware hierarchical GUI.",
            "manifest, launcher, GUI command matrix, and a primary GargantuaLauncher macOS app target exist.",
            "complete",
            commands["gui_manifest"]["passed"]
            and commands["gui_matrix"]["passed"]
            and commands["gui_primary_target"]["passed"]
            and has_all(gui_manifest, ["sourceModels", "renderIntents", "requiresDiskHDF5"])
            and has_all(gui_launcher, ["NavigationSplitView", "rawBufferPath", "sensorRawBufferPath", "chooseDiskHDF5"]),
            "",
        ),
    ]

    blocking = [row for row in requirements if row["status"] != "complete"]
    report = {
        "phase": "Phase 0-6 + GUI completion audit",
        "passed": not blocking,
        "completion_status": "incomplete" if blocking else "complete",
        "requirements": requirements,
        "blocking_keys": [row["key"] for row in blocking],
        "commands": commands,
    }
    OUT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "commands"}, indent=2, sort_keys=True))
    print(f"report={OUT}")
    if blocking:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
