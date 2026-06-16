# Physics Contract

This document is the high-level physical law for realism work. It defines what
the renderer may claim at each model level and what must be validated before a
change can be accepted.

## Model Levels

| Level | Name | Goal | Allowed claim |
| --- | --- | --- | --- |
| L0 | Vacuum Geodesic Baseline | Schwarzschild/Kerr null geodesics work and are numerically stable. | The ray path is consistent with the chosen metric within tested tolerances. |
| L1 | Thin Disk Reference | A clean analytic thin disk or Novikov-Thorne-like reference exists. | This is a reference disk source under stated approximations. |
| L2 | Relativistic Transfer | Redshift, Doppler beaming, absorption, emission, and optical depth are accumulated consistently. | Radiance follows the stated transfer approximation and invariant checks. |
| L3 | GRMHD Snapshot Postprocess | External/sample GRMHD snapshots are postprocessed; the project does not solve GRMHD. | This is a postprocess of the named snapshot and variable mapping. |
| L4 | Polarized GRRT | Stokes I,Q,U,V, parallel transport, and Faraday effects are modeled. | Polarized transfer is implemented for the stated approximations. |
| L5 | Observer Interpreter | Human eye, camera RAW, and rendered camera outputs interpret physical radiance. | This is an observer or device interpretation of the same radiance. |
| L6 | Cinematic Layer | Bloom, lens flare, film look, and grading are optional presentation effects. | This is cinematic presentation, not physical truth. |

L6 must never overwrite L0-L5. Cinematic output is an interpretation lens, not a
truth generator.

## Coordinate And Unit Rules

- Every physics contract item must name coordinate conventions.
- Every metric/geodesic item must name the metric signature used by the code
  path under review.
- All dimensional quantities must state project units or conversion assumptions.
- Scene parameters such as spin, disk inner radius, camera distance, and
  observer tetrad must be explicit in validation reports.

## Required Invariants And Sanity Checks

L0 geodesics:

- Null condition: `k_mu k^mu = 0` remains bounded by a stated tolerance.
- Schwarzschild limit: Kerr with `a = 0` agrees with the Schwarzschild path.
- Conserved quantities drift remains bounded for fixed-step or adaptive-step
  validation scenes.
- Horizon crossing and escape classification are stable.
- Photon-sphere or critical-curve scenes do not rely on hidden image masks.

L2 transfer:

- Redshift factor is computed from photon momentum and observer/emitter
  four-velocities:

```text
g = nu_obs / nu_emit = (k_mu u_obs^mu) / (k_mu u_emit^mu)
```

- Specific intensity transport preserves the invariant:

```text
I_nu / nu^3
```

- Static emitter/static observer reference cases should give `g ~= 1` under the
  stated geometry.
- Approaching and receding disk sides must differ because of the velocity and
  redshift model, not because of a screen-space brightness multiplier.

L3 GRMHD postprocess:

- The snapshot path, simulation family, variables, units, and coordinate mapping
  must be named.
- Synthetic or surrogate flow fields must be labeled as surrogate.
- Missing temperature, electron thermodynamics, magnetization, or opacity
  mappings must be listed as limitations.

## Forbidden Physics Shortcuts

- Arbitrary scientific-mode brightness multipliers.
- Fake color remapping in the physics core.
- Image-space shadows used to hide geodesic, source, or optical-depth errors.
- Procedural texture reported as turbulence from real GRMHD data.
- Presentation bloom/glare used to create missing plasma structure.
- Changing disk density, emissivity, opacity, hit logic, redshift, or optical
  depth from an interpreter branch.

## Source Model Documentation Contract

Every recommended source model must document:

- assumptions
- inputs
- outputs
- units and coordinate conventions
- known limitations
- allowed render modes
- required diagnostics
- validation scenes
- forbidden hacks

Legacy source models may remain available for reproduction, but must be labeled
legacy and must not be promoted as current science without a new contract.
