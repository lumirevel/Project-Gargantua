#!/usr/bin/env python3
"""Fast readiness checks for Phase 0-6 and the GUI prototype surface."""

from __future__ import annotations

import subprocess
from pathlib import Path

from gargantua_gui_contract import launcher_sources_text


ROOT = Path(__file__).resolve().parents[1]


FILES = {
    "phase0": [
        "docs/realism/06_ai_role_protocol.md",
        "docs/realism/12_contract_implementation_roadmap.md",
        "docs/realism/13_phase0_to_phase6_execution_state.md",
        "scripts/validate_realism_contract_docs.py",
        "scripts/validate_phase_completion_audit.py",
    ],
    "phase1": [
        "docs/realism/08_observation_pipeline_contract.md",
        "docs/realism/09_render_modes.md",
        "scripts/validate_render_mode_contract.py",
        "scripts/validate_run_pipeline_look_policy.py",
    ],
    "phase2": [
        "docs/realism/07_physics_contract.md",
        "Blackhole/Metal/gr_math.metal",
        "Blackhole/Metal/volume_rt.metal",
        "scripts/validate_geodesic_scalar_baseline.py",
    ],
    "phase3": [
        "docs/realism/07_physics_contract.md",
        "Blackhole/Metal/spectrum_visible.metal",
        "Blackhole/Sources/Params/ParamsBuilderVisual.swift",
        "scripts/validate_transfer_scalar_baseline.py",
        "scripts/validate_transfer_gfactor_maps.py",
        "scripts/validate_transfer_static_renderer_fixture.py",
        "scripts/validate_transfer_raw_g_debug.py",
    ],
    "phase4": [
        "docs/source_models.md",
        "Blackhole/run_pipeline.sh",
        "scripts/validate_source_model_registry.py",
    ],
    "phase5": [
        "docs/realism/08_observation_pipeline_contract.md",
        "scripts/render_interpreter_stage_diagnostics.py",
        "scripts/validate_observer_cinematic_contract.py",
        "scripts/validate_camera_raw_sidecar.py",
        "scripts/validate_scientific_raw_purity.py",
    ],
    "phase6": [
        "docs/realism/09_render_modes.md",
        "Blackhole/Sources/Params/ParamsBuilderVisual.swift",
        "scripts/validate_observer_cinematic_contract.py",
        "scripts/validate_cinematic_pixel_invariance.py",
        "scripts/validate_blackhole_presentation_invariance.py",
        "scripts/validate_presentation_source_matrix.py",
        "scripts/validate_grmhd_presentation_fixture.py",
    ],
    "gui": [
        "docs/realism/gui_option_surface_v1.md",
        "docs/realism/gui_option_manifest_v1.json",
        "tools/GargantuaLauncher/GargantuaLauncher.swift",
        "tools/GargantuaLauncher/LauncherModels.swift",
        "tools/GargantuaLauncher/RenderCommandPlanner.swift",
        "tools/GargantuaLauncher/run_gui.sh",
        "scripts/gargantua_gui_contract.py",
        "scripts/validate_gui_option_manifest.py",
        "scripts/validate_gui_command_matrix.py",
    ],
}

TOKENS = {
    "docs/realism/13_phase0_to_phase6_execution_state.md": [
        "Phase 0",
        "Phase 1",
        "Phase 2",
        "Phase 3",
        "Phase 4",
        "Phase 5",
        "Phase 6",
        "GUI Position",
    ],
    "docs/realism/09_render_modes.md": [
        "scientific",
        "human-eye",
        "camera-raw",
        "camera-rendered",
        "cinematic",
        "legacy",
    ],
    "docs/realism/07_physics_contract.md": [
        "k_mu k^mu",
        "g = nu_obs / nu_emit",
        "I_nu / nu^3",
    ],
    "scripts/validate_geodesic_scalar_baseline.py": [
        "Phase 2",
        "Kerr null",
        "Carter Q",
        "Schwarzschild-vs-Kerr",
    ],
    "scripts/validate_phase_completion_audit.py": [
        "Phase 0-6 + GUI completion audit",
        "completion_status",
        "reference RGGB u16 sensor/ADC outputs",
        "3x3 near-critical image-plane",
        "same-tetrad renderer fixture",
    ],
    "scripts/validate_transfer_scalar_baseline.py": [
        "Phase 3",
        "g = nu_obs / nu_emit",
        "I_nu / nu^3",
        "doppler",
    ],
    "scripts/validate_transfer_gfactor_maps.py": [
        "Phase 3",
        "renderer-produced g-factor",
        "--realism-debug g",
        "--realism-debug beaming",
        "low-Doppler",
    ],
    "scripts/validate_transfer_static_renderer_fixture.py": [
        "Phase 3",
        "static-transfer-reference-v1",
        "no-flow transfer check",
        "not the final same-tetrad static-emitter/static-observer",
    ],
    "scripts/validate_transfer_raw_g_debug.py": [
        "Phase 3",
        "--realism-debug raw-g",
        "float diagnostics",
        "not a same-tetrad flat-space proof",
    ],
    "scripts/validate_transfer_same_tetrad_renderer_fixture.py": [
        "Phase 3",
        "--realism-debug",
        "same-tetrad-g",
        "u_emit == u_obs",
    ],
    "scripts/validate_observer_cinematic_contract.py": [
        "Phase 5/6",
        "RAW-like",
        "cinematic off-switch",
        "pixel-level invariance",
    ],
    "scripts/validate_camera_raw_sidecar.py": [
        "Phase 5",
        "camera-raw linear32 sidecar",
        "ideal Bayer",
        "--camera-raw-out",
        "--hdr-intermediate",
        "--hdr-out",
        "bayer-rggb-u16",
        "sensorShotNoise",
        "adcBits",
    ],
    "scripts/validate_scientific_raw_purity.py": [
        "Phase 1/5/6",
        "scientific and camera-raw purity audit",
        "presentation-effect leakage",
        "reference RGGB u16 sensor/ADC sidecar",
    ],
    "scripts/validate_cinematic_pixel_invariance.py": [
        "Phase 5/6",
        "camera-raw",
        "compose-hdr-in",
        "pixel-level presentation isolation",
    ],
    "scripts/validate_blackhole_presentation_invariance.py": [
        "Phase 5/6",
        "black-hole source",
        "camera-raw",
        "presentation isolation",
    ],
    "scripts/validate_presentation_source_matrix.py": [
        "Phase 6",
        "source-model presentation isolation matrix",
        "cinematic-physical-disk-v1",
        "physics-constrained-cinematic-disk-v1",
    ],
    "scripts/validate_grmhd_presentation_fixture.py": [
        "Phase 6",
        "GRMHD data-backed presentation fixture suite",
        "grmhd-temperature-flow-diagnostic",
        "--disk-hdf5",
        "--suite",
        "suite_min_count",
    ],
    "scripts/validate_run_pipeline_look_policy.py": [
        "Phase 1/5/6",
        "camera-raw defaults to linear",
        "camera-raw rejects non-linear user --look values",
        "cinema may keep source-model filmic defaults",
    ],
    "docs/source_models.md": [
        "canonical-visible-disk-v1",
        "thin-disk-visible-reference",
        "Source Model Contract Matrix",
        "Forbidden hacks",
    ],
    "scripts/validate_source_model_registry.py": [
        "Source Model Contract Matrix",
        "SOURCE_TEMPLATE_FIELDS",
        "Forbidden hacks",
    ],
    "docs/realism/gui_option_surface_v1.md": [
        "Accretion Source",
        "Observer",
        "Camera Rendered",
        "Cinematic Grade",
        "RAW-like",
        "manifest-backed",
    ],
    "docs/realism/gui_option_manifest_v1.json": [
        "schemaVersion",
        "sourceModels",
        "renderIntents",
        "requiresDiskHDF5",
        "defaultDiskHDF5",
        "legacy-perlin",
    ],
    "tools/GargantuaLauncher/*.swift": [
        "gui_option_manifest_v1.json",
        "JSONDecoder",
        "manifestSearchPaths",
        "isCameraAdjustmentEnabled",
        "selectedSourceRequiresDiskHDF5",
        "--disk-hdf5",
        "rawBufferPath",
        "sensorRawBufferPath",
    ],
    "scripts/gargantua_gui_contract.py": [
        "COMMAND_MATRIX_MODES",
        "RAW_LIKE_ARGS",
        "command_for",
        "launcher_sources_text",
    ],
    "scripts/validate_gui_command_matrix.py": [
        "raw-like",
        "camera-rendered",
        "cinematic",
        "RAW-like audit commands must explicitly disable camera effects",
        "requiresDiskHDF5",
        "--hdr-out",
        "--camera-raw-out",
    ],
    "scripts/validate_gui_primary_target.py": [
        "GUI primary target",
        "GargantuaLauncher",
        "com.apple.product-type.application",
        "no_renderer_files_in_gui_target",
    ],
}


def read(rel: str) -> str:
    if rel == "tools/GargantuaLauncher/*.swift":
        return launcher_sources_text()
    return (ROOT / rel).read_text(encoding="utf-8")


def run_help(topic: str) -> str:
    cmd = ["bash", "Blackhole/run_pipeline.sh", "--help", topic]
    return subprocess.run(cmd, cwd=str(ROOT), check=True, text=True, capture_output=True).stdout


def main() -> None:
    failures: list[str] = []

    for phase, files in FILES.items():
        for rel in files:
            if not (ROOT / rel).exists():
                failures.append(f"{phase}: missing {rel}")

    for rel, tokens in TOKENS.items():
        text = read(rel) if rel == "tools/GargantuaLauncher/*.swift" or (ROOT / rel).exists() else ""
        for token in tokens:
            if token not in text:
                failures.append(f"{rel}: missing {token!r}")

    try:
        source_help = run_help("source-models")
        camera_help = run_help("camera")
        legacy_help = run_help("legacy")
    except subprocess.CalledProcessError as exc:
        failures.append(f"help command failed: {exc}")
        source_help = camera_help = legacy_help = ""

    for token in [
        "canonical-visible-disk-v1",
        "physics-constrained-cinematic-disk-v1",
        "grmhd-temperature-flow-diagnostic",
    ]:
        if token not in source_help:
            failures.append(f"source-model help missing {token}")

    for token in [
        "--presentation",
        "--look",
        "--camera-profile",
        "--camera-flare",
        "--camera-dof-strength",
    ]:
        if token not in camera_help:
            failures.append(f"camera help missing {token}")

    for token in ["perlin", "perlin-classic", "perlin-ec7"]:
        if token not in legacy_help:
            failures.append(f"legacy help missing {token}")

    if failures:
        print("\n".join(failures))
        raise SystemExit(1)

    print("phase readiness validation passed")


if __name__ == "__main__":
    main()
