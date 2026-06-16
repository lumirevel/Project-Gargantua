# Branch Strategy

## Shared Baseline

### `codex/realism-rendering`

This branch is the shared realism baseline. It owns common rules, project goals, render contract requirements, validation expectations, and later reviewed merges.

Allowed changes:

- shared documentation
- non-invasive diagnostics
- low-risk comments that clarify physics/interpreter boundaries
- reviewed fixes needed by both future branches

Forbidden changes:

- speculative physics rewrites
- speculative camera/post rewrites
- large public-option expansions
- destructive cleanup or generated artifact commits

## Feature Branches

### `codex/physics-realism-v1`

Purpose: improve physical black hole and accretion flow realism.

Allowed changes:

- metric/geodesic corrections
- disk source model improvements
- emissivity/absorptivity/optical-depth/radiative-transfer improvements
- redshift/Doppler/beaming corrections
- physical debug outputs

Forbidden changes:

- tone mapping tricks
- bloom/glare/lens flare tuning
- exposure/color grading as a realism fix
- presentation-only image manipulation

Expected validation:

- raw radiance comparisons
- optical depth maps
- redshift/g-factor maps
- hit masks
- source-location/radius diagnostics
- before/after branch or source contribution maps

### `codex/interpreter-camera-v1`

Purpose: improve camera, sensor, exposure, tone mapping, bloom/glare, and post-processing.

Allowed changes:

- eye/camera response
- exposure model
- ISO/shutter/aperture interpretation
- sensor noise/response
- tone mapping
- bloom/glare/flare
- depth of field
- presentation diagnostics

Forbidden changes:

- disk density
- emissivity
- opacity
- geodesic integration
- hit logic
- redshift
- optical depth
- physical transfer

Expected validation:

- same source radiance through multiple presentations
- tone-mapped-no-bloom outputs
- bloom-only outputs
- exposure debug outputs
- camera stress scenes, including bright highlights and high-contrast black backgrounds

### `codex/validation-lab-v1`

Purpose: build and maintain reference scenes, scalar diagnostics, route-contract
tests, and comparison harnesses. This branch is the third pillar beside physics
and interpreter work.

Allowed changes:

- reference scenes
- diagnostic render matrices
- geodesic invariant checks
- redshift and invariant-intensity sanity tests
- thin-disk known-case comparisons
- render route contract tests
- validation scripts and reports

Forbidden changes:

- physics source tuning except for dedicated validation fixtures
- camera/interpreter tuning except for dedicated validation fixtures
- cinematic look development
- broad CLI or ABI changes unless required by a validation contract

Expected validation:

- command-level reproducibility
- scalar thresholds
- image comparison sheets where applicable
- explicit PASS / FAIL / PARTIAL reports

## Integration Branch

### `codex/realism-integration-v1`

Do not create this branch yet. Create it only after both feature branches have meaningful commits to integrate.

Use it for:

- resolving cross-branch conflicts
- validating that physics and interpreter improvements still obey the render contract
- producing final comparison sheets

## Merge Strategy

- Keep feature branch commits small and topic-specific.
- Merge reviewed feature changes back into `codex/realism-rendering` or a later integration branch.
- If both branches touch shared files such as `PackedParams`, `gr_math.metal`, `ParamsBuilder*`, or compose/trace orchestration, resolve through explicit contract review instead of blind conflict resolution.
