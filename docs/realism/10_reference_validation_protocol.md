# Reference Validation Protocol

Metal-native implementation is the project direction. External public GRRT and
GRMHD tools are validation references, not code to copy into the renderer.

## Reference Philosophy

```text
Project-Gargantua implements the renderer.
Reference codes define tests the renderer must survive.
```

Use references as case law:

- equations and invariants
- known scenes
- scalar diagnostics
- image morphology under stated assumptions
- limits of approximation

Do not import an external code path blindly when it would break Swift/Metal
architecture, Apple Silicon constraints, or the render contract.

## Useful Reference Families

| Reference family | Useful for | Notes |
| --- | --- | --- |
| grtrans | Kerr geodesics, polarized radiative transfer, parallel transport. | Good reference for L4 direction and equation-level checks. |
| ipole | Covariant polarized radiative transfer and GRRT comparisons. | Useful for Stokes transport and code-to-code tests. |
| RAPTOR | Time-dependent radiative transfer and ray integration in strong gravity. | Useful for ray/transfer test design and CPU/GPU comparison concepts. |
| Blacklight | GR ray tracing and analysis for GRMHD simulation data. | Useful for L3 snapshot postprocess expectations and slow-light/adaptive-ray concepts. |
| Odyssey | GPU-based Kerr spacetime image/spectrum calculation. | Useful for GPU GRRT architecture comparison and image/spectrum tests. |
| EHT synthetic-imaging literature | Model-library and observation-comparison workflow. | Useful process reference: images are judged by model and validation, not beauty alone. |
| GRMHD code comparison projects | Numerical maturity and cross-code expectations. | Useful for understanding Athena++, BHAC, Cosmos++, ECHO, H-AMR, iharm3D, HARM-Noble, IllinoisGRMHD, and KORAL differences. |

## Reference Case Template

Every reference case should specify:

```text
Reference:
Level:
Metric:
Coordinates:
Units:
Observer:
Emitter/source:
Expected scalar checks:
Expected image morphology:
Allowed tolerance:
Required diagnostics:
Known mismatch risks:
```

## Minimum Validation Ladder

1. L0: geodesic invariants and Schwarzschild/Kerr limiting cases.
2. L1: thin-disk reference morphology and source-radius diagnostics.
3. L2: redshift/Doppler/invariant-intensity checks.
4. L3: named GRMHD snapshot postprocess with variable mapping and scalar
   diagnostics.
5. L4: polarized transport only after Stokes and parallel-transport contracts
   exist.
6. L5: observer/camera validation on generic HDR radiance scenes and black-hole
   radiance.
7. L6: cinematic comparisons with proof that scientific/RAW diagnostics remain
   stable.

## Acceptance Rule

A render is accepted when the contract, scalar diagnostics, reference cases, and
mode separation agree. A beautiful image without those checks is not evidence.
