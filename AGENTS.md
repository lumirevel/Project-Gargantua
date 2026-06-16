# AGENTS.md

Project goal: **paper-grade physical correctness with film-grade visual realism**.

Before realism work, read:

- `docs/realism/00_project_goal.md`
- `docs/realism/01_codex_common_rules.md`
- `docs/realism/02_branch_strategy.md`
- `docs/realism/03_render_contract_requirements.md`
- `docs/realism/04_validation_matrix.md`
- `docs/realism/05_debug_outputs.md`
- `docs/realism/06_ai_role_protocol.md`
- `docs/realism/07_physics_contract.md`
- `docs/realism/08_observation_pipeline_contract.md`
- `docs/realism/09_render_modes.md`
- `docs/realism/10_reference_validation_protocol.md`
- `docs/realism/11_target_architecture_and_performance.md`
- `docs/realism/12_contract_implementation_roadmap.md`
- `docs/realism/13_phase0_to_phase6_execution_state.md`

## Core Rule

Physical reality and visual interpretation must remain separate.

Physics includes spacetime, metric, geodesics, black hole model, accretion disk model, emissivity, absorptivity, optical depth, radiative transfer, redshift, Doppler beaming, and raw radiance.

Interpreter/camera includes eye/camera model, exposure, ISO/shutter/aperture, sensor response, tone mapping, bloom, glare, lens flare, depth of field, and final display mapping.

Do not optimize the beauty image by hiding physical defects.

## Branch-Specific Rules

- Do not mix physics and interpreter changes unless explicitly working on an integration branch.
- Physics work must not solve realism with tone mapping, bloom, lens flare, exposure hacks, color grading, or aesthetic-only tricks.
- Interpreter work must not change disk density, emissivity, opacity, geodesic integration, hit logic, redshift, optical depth, or physical transfer.
- Preserve debug outputs and improve them when practical.

## Validation Expectations

Every realism change must report:

1. what changed
2. why it changed
3. how it was validated
4. what risks remain

AI work must follow the authority model in
`docs/realism/06_ai_role_protocol.md`: Science Architect defines contracts,
Implementation Agent implements narrow tickets, Verification Agent audits diffs,
Integrator merges only validated work, and Aesthetic Director may choose looks
only after physical and observer contracts remain intact.

Beauty images alone are insufficient. Prefer raw radiance, optical depth, redshift/g-factor, hit mask, source-location, tone-mapped-no-bloom, bloom-only, and exposure diagnostics when relevant.

## Swift / Metal / Apple Silicon Constraints

- Avoid CPU-GPU synchronization regressions.
- Avoid unnecessary memory growth.
- Avoid changing Metal buffer layouts without checking alignment and compatibility.
- Keep packed ABI changes small and reviewed.
- Prefer incremental changes over broad refactors.

## Git And Generated File Safety

- Prefer small commits and reviewable diffs.
- Do not commit secrets, API keys, credentials, `.env` files, private tokens, private configs, DerivedData, build products, generated render outputs, large binary artifacts, logs, or temporary files.
- Do not run destructive commands such as `git reset --hard`, `git clean -fd`, `git checkout .`, or force pushes unless explicitly requested and safe.
- Generated images should usually go under `/private/tmp` or another non-repository output directory.
