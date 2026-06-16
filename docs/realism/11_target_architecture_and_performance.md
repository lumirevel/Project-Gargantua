# Target Architecture And Performance Contract

The proposed architecture is a target boundary model. It should guide future
refactors, but it must be mapped onto the current Swift/Metal codebase
incrementally rather than imposed as a broad directory rewrite.

## Target Conceptual Architecture

```text
Project-Gargantua
  PhysicsCore
    Metrics
    Geodesics
    Tetrads
    Redshift
    RadiativeTransfer
  SourceModels
    ThinDisk
    HotSpot
    Corona
    GRMHDAdapter
  Observer
    HumanVision
    CameraOptics
    SensorModel
    RAWPipeline
    ToneMapping
  Presentation
    Scientific
    HumanEye
    CameraRAW
    CameraRendered
    Cinematic
  Diagnostics
    Invariants
    ReferenceScenes
    RegressionTests
```

## Current Code Mapping

| Target area | Current main locations | Notes |
| --- | --- | --- |
| Metrics / geodesics | `Blackhole/Metal/gr_math.metal`, `Blackhole/Metal/volume_rt.metal` | Keep metric and stepping changes in physics branches. |
| Radiative transfer | `Blackhole/Metal/volume_rt.metal`, `Blackhole/Metal/VolumeTransport/*`, `Blackhole/Metal/spectrum_visible.metal` | Owns raw radiance, optical depth, redshift, and spectral transport. |
| Source models | `Blackhole/Metal/disk_models.metal`, `Blackhole/Metal/VolumeTransport/*`, `docs/source_models.md` | Source-model docs must state assumptions, inputs, outputs, and limitations. |
| Observer/camera | `Blackhole/Metal/Compose/*`, `Blackhole/Sources/Render/Compose/*`, camera parameters in `Blackhole/Sources/Params/*` | Consumes physical radiance; must not change source fields. |
| Presentation modes | CLI presentation/look options, compose helpers/kernels, validation scripts | Scientific, eye, camera, and cinema must remain separable. |
| Diagnostics/regression | `scripts/*validation*.py`, `Blackhole/Sources/Diagnostics/*`, `tests/baseline/*` | Validation-lab work should expand these without changing physical output. |

## Refactor Rule

Do not reorganize files just to resemble the target tree. Prefer:

1. document the boundary
2. add or improve diagnostics
3. isolate one narrow implementation ticket
4. validate behavior and performance
5. only then move code if the move reduces real coupling

Broad directory moves are allowed only when they preserve git history, avoid ABI
changes, and have a clear verification plan.

## Performance Contract

Physical correctness is not permission to make the renderer impractical. Every
nontrivial realism change should check the relevant performance risks.

Required guardrails:

- avoid CPU-GPU synchronization in render loops
- avoid readback-dependent diagnostics in normal rendering
- keep Metal buffer layout changes explicit and ABI-validated
- keep memory growth bounded and reported when adding buffers or debug outputs
- keep diagnostic outputs opt-in unless they are cheap metadata
- prefer tiled or cached validation for expensive matrices
- keep low-resolution smoke tests available for iteration
- report render time changes when a change affects kernels, sample counts,
  volume stepping, ray bundles, or compose passes

## Performance Evidence Levels

| Change type | Minimum performance evidence |
| --- | --- |
| Docs or CLI help only | No runtime performance evidence required. |
| Parser/default changes | Syntax checks and a low-resolution smoke command. |
| Compose/interpreter shader changes | Low-resolution render timing plus scientific/eye/cinema comparison. |
| Physics shader changes | Low-resolution diagnostic matrix, ABI validation, and render timing before/after. |
| Buffer layout changes | ABI printout, build, smoke render, and memory-risk note. |
| New high-quality mode | Preview timing, final-resolution timing, and documented default/off behavior. |

## Optimization Priorities

1. Preserve correctness and diagnostics first.
2. Reduce redundant CPU orchestration and rebuilds.
3. Avoid extra GPU passes unless they produce required contract fields.
4. Use lower-resolution validation and cached inputs for search.
5. Promote expensive modes only as explicit high-quality options.
6. Keep default preview settings responsive on Apple Silicon.

## Validation-Lab Performance Duties

`codex/validation-lab-v1` should eventually own:

- standard preview render timings
- standard final render timings
- shader/pass count notes for major routes
- memory footprint notes for additional buffers
- regression thresholds for scalar diagnostics
- a small set of cached external reference inputs

The validation lab should catch both physical regressions and performance
regressions before integration.
