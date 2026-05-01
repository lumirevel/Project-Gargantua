# Physics Diagnostics Notes

## Diagnostic added or improved

Optical depth is easier to request through the existing GRMHD debug system.

The renderer already computes integrated optical depth in the volume transfer path and exposes it through `--disk-grmhd-debug tau` and the wider-range view `--disk-grmhd-debug tau-wide`. This change adds render-contract-friendly aliases:

- `optical_depth`
- `physics_optical_depth`
- `optical_depth_wide`
- `physics_optical_depth_wide`

Hyphenated aliases remain available:

- `optical-depth`
- `physics-optical-depth`
- `optical-depth-wide`
- `physics-optical-depth-wide`

## Files changed

- `Blackhole/Sources/Params/ParamsBuilderPolicy.swift`
- `Blackhole/run_pipeline.sh`
- `docs/realism/physics_diagnostics_notes.md`

## How to inspect it

For GRMHD volume renders, request the optical-depth diagnostic through the existing debug option:

```bash
./run_pipeline.sh --disk-mode grmhd --disk-grmhd-debug optical_depth ...
```

For high-dynamic-range optical-depth inspection, use:

```bash
./run_pipeline.sh --disk-mode grmhd --disk-grmhd-debug optical_depth_wide ...
```

The shell wrapper normalizes these names to the existing Swift/Metal debug channels:

- `optical_depth` -> `tau`
- `optical_depth_wide` -> `tau-wide`

The direct Swift executable also accepts the same aliases via `--disk-grmhd-debug`.

## Ownership

This diagnostic is physics-owned. It exposes transfer-side optical depth already computed during GRMHD volume radiative transfer. It does not change exposure, tone mapping, bloom, glare, color grading, camera response, sensor response, or the final display curve.

## What remains missing

- A single scripted validation matrix that renders `optical_depth`, `redshift/g-factor`, `raw_radiance`, `hit_mask`, and `emission_radius` for the same scene.
- A canonical debug-output export path for non-GRMHD/canonical visible modes where optical-depth coverage is currently weaker.
- Side-by-side documentation of the exact numeric scaling used by `tau` versus `tau-wide`.
