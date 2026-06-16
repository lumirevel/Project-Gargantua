#!/usr/bin/env python3
"""Validate the realism contract documentation surface."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

REQUIRED_FILES = [
    "AGENTS.md",
    "docs/realism/00_project_goal.md",
    "docs/realism/01_codex_common_rules.md",
    "docs/realism/02_branch_strategy.md",
    "docs/realism/03_render_contract_requirements.md",
    "docs/realism/04_validation_matrix.md",
    "docs/realism/05_debug_outputs.md",
    "docs/realism/06_ai_role_protocol.md",
    "docs/realism/07_physics_contract.md",
    "docs/realism/08_observation_pipeline_contract.md",
    "docs/realism/09_render_modes.md",
    "docs/realism/10_reference_validation_protocol.md",
    "docs/realism/11_target_architecture_and_performance.md",
    "docs/realism/12_contract_implementation_roadmap.md",
    "docs/realism/13_phase0_to_phase6_execution_state.md",
]

REQUIRED_TOKENS = {
    "docs/realism/06_ai_role_protocol.md": [
        "Science Architect",
        "Implementation Agent",
        "Verification Agent",
        "Integrator Agent",
        "Aesthetic Director",
        "physics contract -> implementation ticket -> verification -> integration",
    ],
    "docs/realism/07_physics_contract.md": [
        "L0",
        "L1",
        "L2",
        "L3",
        "L4",
        "L5",
        "L6",
        "I_nu / nu^3",
        "g = nu_obs / nu_emit",
    ],
    "docs/realism/08_observation_pipeline_contract.md": [
        "same_physical_radiance",
        "camera_raw",
        "camera_rendered",
        "cinematic_grade",
        "Camera RAW",
    ],
    "docs/realism/09_render_modes.md": [
        "scientific",
        "human-eye",
        "camera-raw",
        "camera-rendered",
        "cinematic",
        "legacy",
    ],
    "docs/realism/10_reference_validation_protocol.md": [
        "grtrans",
        "ipole",
        "RAPTOR",
        "Blacklight",
        "Odyssey",
        "Reference Case Template",
    ],
    "docs/realism/11_target_architecture_and_performance.md": [
        "PhysicsCore",
        "SourceModels",
        "Observer",
        "Presentation",
        "Diagnostics",
        "Performance Contract",
        "CPU-GPU synchronization",
    ],
    "docs/realism/12_contract_implementation_roadmap.md": [
        "Phase 0",
        "Phase 1",
        "Phase 2",
        "Phase 3",
        "Phase 4",
        "Phase 5",
        "Phase 6",
        "camera-raw",
        "camera-rendered",
        "validation-lab",
    ],
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
}


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def main() -> None:
    failures: list[str] = []
    for rel in REQUIRED_FILES:
        if not (ROOT / rel).exists():
            failures.append(f"missing required file: {rel}")

    agents = read("AGENTS.md") if (ROOT / "AGENTS.md").exists() else ""
    for rel in REQUIRED_FILES:
        if rel.startswith("docs/realism/") and rel not in agents:
            failures.append(f"AGENTS.md does not require reading {rel}")

    for rel, tokens in REQUIRED_TOKENS.items():
        text = read(rel) if (ROOT / rel).exists() else ""
        for token in tokens:
            if token not in text:
                failures.append(f"{rel}: missing token {token!r}")

    if failures:
        print("\n".join(failures))
        raise SystemExit(1)
    print("realism contract docs validation passed")


if __name__ == "__main__":
    main()
