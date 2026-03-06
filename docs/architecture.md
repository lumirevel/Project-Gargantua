# Architecture

## Runtime Flow
1. `Blackhole/main.swift`
   - thin entrypoint only
   - forwards `CommandLine.arguments` into `AppMain.run(arguments:)`
2. `Blackhole/Sources/AppMain.swift`
   - parses CLI via `CLI.parse`
   - resolves config via `ParamsBuilder.build`
   - routes special modes (`--regression-run`, `--print-packed-layout`, `--validate-packed-abi`, `--dump-packed-params`)
   - calls `Renderer.render(config:params:)`
3. `Blackhole/Sources/Renderer.swift`
   - orchestration only
   - `RenderSetup.prepare(...)` -> `RenderExecution.execute(...)`
4. `Blackhole/Sources/RenderSetup.swift`
   - creates `MTLDevice`, queue, default library
   - loads atlas/volume textures
   - builds function-constant-specialized pipeline states through `MetalPipelines`
5. `Blackhole/Sources/RenderExecution.swift`
   - trace / light / compose dispatch order
   - tile scheduling, in-flight buffers, encoder lifecycle, synchronization
   - no CLI parsing or disk-policy interpretation
6. `Blackhole/Sources/RenderOutputs.swift`
   - image writing
   - metadata JSON creation/writing
7. `Blackhole/Sources/Resources.swift`
   - raw file IO helpers
   - atlas / volume metadata decoding and texture upload helpers

## Config Flow
1. `CLI.swift`
   - raw token helpers and public flag parsing entrypoint
2. `LogicalParams.swift`
   - top-level user-intent flags used before render starts
3. `ParamsBuilder.swift`
   - converts raw CLI into `ResolvedRenderConfig`
   - builds `PackedParams` for the Metal constant buffer ABI
4. `AccretionModel.swift`
   - disk-physics policy boundary for mode-specific defaults and validation
   - current models: legacy, thick, thin precision, eht

## ABI Boundary
- Swift host -> Metal kernels is carried by `PackedParams` in `Blackhole/Sources/PackedParams.swift`.
- `PackedParams` must match the `Params` struct in Metal exactly.
- Debug/support paths:
  - `--print-packed-layout`
  - `--dump-packed-params <path>`
  - `--validate-packed-abi`
- `validatePackedParamsABIOrThrow()` asserts the current expected size, stride, alignment, and selected critical offsets.

## Metal Layout
`Blackhole/Metal/integral.metal` is an include aggregator that preserves kernel entry names. Logic is split across:
- `gr_math.metal`
- `disk_models.metal`
- `volume_rt.metal`
- `spectrum_visible.metal`
- `post_compose.metal`

This keeps the Swift pipeline names stable while separating math, disk logic, volume RT, spectrum, and compose.

## Where New Physics Should Go
- Swift-side mode defaults / validation:
  - `Blackhole/Sources/AccretionModel.swift`
  - `Blackhole/Sources/ParamsBuilder.swift`
- Metal-side runtime routing:
  - `Blackhole/Metal/disk_models.metal`
  - `Blackhole/Metal/volume_rt.metal`
- Output or metadata additions:
  - `Blackhole/Sources/RenderOutputs.swift`

## Regression Coverage
- Baseline manifest: `tests/baseline/manifest.json`
  - protects current legacy/default behavior and perf anchor
- Extended manifest: `tests/baseline/extended_manifest.json`
  - covers precision, thick, atlas, volume, ray-bundle, and expressive-visible branches
