# Architecture

## Runtime Flow
1. `Blackhole/main.swift`
   - thin entrypoint only
   - forwards `CommandLine.arguments` into `AppMain.run(arguments:)`
2. `Blackhole/Sources/App/AppMain.swift`
   - parses CLI via `CLI.parse`
   - resolves config via `ParamsBuilder.build`
   - routes special modes (`--regression-run`, `--print-packed-layout`, `--validate-packed-abi`, `--dump-packed-params`)
   - calls `Renderer.render(config:params:)`
3. `Blackhole/Sources/Render/Support/Renderer.swift`
   - orchestration only
   - `RenderSetup.prepare(...)` -> `RenderExecution.execute(...)`
4. `Blackhole/Sources/Render/Core/RenderSetup.swift`
   - creates `MTLDevice`, queue, default library
   - uploads atlas/volume textures through resource helpers
   - builds function-constant-specialized pipeline states through `MetalPipelines`
5. `Blackhole/Sources/Render/Core/RenderExecution.swift`
   - high-level render execution orchestration
   - consumes `RenderExecutionPlan`
   - delegates trace, compose, and output handling
6. `Blackhole/Sources/Render/Planning/RenderExecutionPlan.swift`
   - resolves execution flags, active pipelines, tile geometry, threadgroup sizing, and progress totals
7. `Blackhole/Sources/Render/Trace/*`
   - `RenderTracePhase.swift`: trace phase orchestration
   - `RenderTraceTraversal.swift`: tile traversal and slot selection
   - `RenderTraceSubmission.swift`: submit/complete wiring
   - `RenderTraceTile.swift`: per-tile params and command encoding
   - `RenderTraceCompletion.swift`: per-tile readback/file-write/hit counting
   - `RenderTraceRuntime.swift`: mutable trace counters, first error, and progress accumulation
8. `Blackhole/Sources/Render/Compose/*`
   - `RenderComposePhase.swift`: compose routing only
   - `RenderComposeFullGPUPhase.swift`: full-frame GPU compose path
   - `RenderComposeHDRIntermediatePhase.swift`: file-backed HDR32 intermediate path
   - `RenderComposeLegacyPhase.swift`: legacy tiled / CPU fallback path
   - `RenderThreadgroups.swift`: pipeline-aware dispatch shape helpers
9. `Blackhole/Sources/Render/Core/RenderResourcePolicy.swift`
   - execution-time memory/intermediate-policy boundary
   - decides collision64/lite32/HDR-direct eligibility and mode-specific compose preference
10. `Blackhole/Sources/Render/Core/RenderOutputs.swift`
    - image writing and metadata JSON output
11. `Blackhole/Sources/Render/Core/Resources.swift`
    - raw file IO helpers, atlas/volume texture upload, frame resource allocation

## Config Flow
1. `Blackhole/Sources/App/CLI.swift`
   - raw token helpers and public flag parsing entrypoint
2. `Blackhole/Sources/Core/Config/LogicalParams.swift`
   - top-level user-intent flags used before render starts
3. `Blackhole/Sources/Params/ParamsBuilder.swift`
   - coordinates config assembly only
   - delegates runtime, policy, visual, visible, disk-volume, asset, diagnostics, summary, and packing work to sibling helpers
4. `Blackhole/Sources/Params/ParamsBuilderPacking.swift`
   - maps `ResolvedRenderConfig` into `PackedParams`
5. `Blackhole/Sources/Core/Physics/AccretionModel.swift`
   - disk-physics policy boundary for mode-specific defaults and validation
6. `Blackhole/Sources/Core/Physics/*`
   - `DiskOrbit.swift`: orbital/horizon helpers
   - `VisibleSpectrum.swift`: CPU-side visible spectrum helpers
7. `Blackhole/Sources/Core/Math/VectorMath.swift`
   - small SIMD/math utilities

## ABI Boundary
- Swift host -> Metal kernels is carried by `PackedParams` in `Blackhole/Sources/Core/ABI/PackedParams.swift`.
- `PackedParams` must match the `Params` struct in `Blackhole/Metal/gr_math.metal` exactly.
- Debug/support paths:
  - `--print-packed-layout`
  - `--dump-packed-params <path>`
  - `--validate-packed-abi`
- `validatePackedParamsABIOrThrow()` asserts the current expected size, stride, alignment, and selected critical offsets.

## Metal Layout
`Blackhole/integral.metal` remains the include aggregator that preserves stable kernel names. Logic is split across:
- `Blackhole/Metal/gr_math.metal`: ABI structs, GR/math primitives, shared types
- `Blackhole/Metal/disk_models.metal`: disk surface/model helpers
- `Blackhole/Metal/volume_rt.metal`: kernel entry, trace dispatch, metric/mode loops, surface routing
- `Blackhole/Metal/VolumeTransport/legacy.metal`: legacy/thick volume shaping and accumulation
- `Blackhole/Metal/VolumeTransport/grmhd.metal`: GRMHD scalar/visible transport helpers
- `Blackhole/Metal/VolumeTransport/commit.metal`: `VolumeAccum -> CollisionInfo` commit
- `Blackhole/Metal/Bundle/ray_bundle.metal`: ray-bundle and Jacobian helpers
- `Blackhole/Metal/Visible/bridge.metal`: `CollisionInfo -> visible XYZ` bridge
- `Blackhole/Metal/spectrum_visible.metal`: visible spectrum integration and CIE helpers
- `Blackhole/Metal/post_compose.metal`: include wrapper for compose kernels
- `Blackhole/Metal/Compose/helpers.metalh`: compose math/helpers
- `Blackhole/Metal/Compose/kernels.metalh`: compose/histogram kernels

## Where New Physics Should Go
- Swift-side mode defaults / validation:
  - `Blackhole/Sources/Core/Physics/AccretionModel.swift`
  - `Blackhole/Sources/Params/*`
- Metal-side surface models:
  - `Blackhole/Metal/disk_models.metal`
- Metal-side volume transport:
  - `Blackhole/Metal/VolumeTransport/*`
- Metal-side bundle/Jacobian logic:
  - `Blackhole/Metal/Bundle/ray_bundle.metal`
- Visible spectrum/color reconstruction:
  - `Blackhole/Metal/spectrum_visible.metal`
  - `Blackhole/Metal/Visible/bridge.metal`
- Output or metadata additions:
  - `Blackhole/Sources/Render/Core/RenderOutputs.swift`

## Regression Coverage
- Baseline manifest: `tests/baseline/manifest.json`
  - protects current legacy/default behavior and perf anchor
- Extended manifest: `tests/baseline/extended_manifest.json`
  - covers precision, thick, atlas, volume, ray-bundle, and expressive-visible branches
