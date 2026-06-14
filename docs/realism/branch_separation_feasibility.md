# Branch Separation Feasibility

## Current Observed Module Boundaries

The codebase has a meaningful but not perfectly clean separation between physics, presentation, orchestration, diagnostics, and shared ABI/configuration.

## Physics-Related Files And Directories

Likely physics/source/transfer areas:

- `Blackhole/Metal/gr_math.metal`
- `Blackhole/Metal/volume_rt.metal`
- `Blackhole/Metal/disk_models.metal`
- `Blackhole/Metal/spectrum_visible.metal`
- `Blackhole/Metal/Visible/`
- `Blackhole/Metal/VolumeTransport/`
- `Blackhole/Sources/Core/Physics/`
- `Blackhole/Sources/Render/Trace/`
- `Blackhole/Sources/Render/Trace/RenderTracePhase.swift`
- `Blackhole/Sources/Render/Trace/RenderTraceTile.swift`

These areas cover geodesic integration, metric behavior, disk source models, spectral emission, GRMHD/volume transport, and trace-time radiance production.

## Interpreter / Camera / Post-Process Files And Directories

Likely interpreter/camera/post areas:

- `Blackhole/Metal/Compose/helpers.metalh`
- `Blackhole/Metal/Compose/kernels.metalh`
- `Blackhole/Sources/Render/Compose/`
- `docs/camera_profiles/`
- `docs/presentation_modes.md`
- `scripts/validate_presentation_on_rt_scene.py`
- `scripts/generate_room_rt_hdr_gpu.swift`

These areas cover exposure, tone mapping, eye/cinema presentation, bloom/glare/DOF-like interpretation, compose-stage HDR handling, and familiar-scene validation.

## Shared Or Risky Files

High-conflict or shared ABI/orchestration files:

- `Blackhole/Metal/gr_math.metal`
- `Blackhole/Sources/Core/ABI/PackedParams.swift`
- `Blackhole/Sources/Core/Config/ResolvedRenderConfig.swift`
- `Blackhole/Sources/Params/ParamsBuilder*.swift`
- `Blackhole/Sources/Render/Core/RenderExecution.swift`
- `Blackhole/Sources/Render/Core/Resources.swift`
- `Blackhole/Sources/Render/Core/RenderResourcePolicy.swift`
- `Blackhole/Sources/Render/Support/Renderer.swift`
- `Blackhole/run_pipeline.sh`
- validation scripts used by both branches

These files connect CLI/configuration, packed Metal ABI, render resources, and trace/compose execution. Both branches are likely to touch them if work is not scoped carefully.

## Is Branch Splitting Safe Now?

Yes, branch splitting is safe as a workflow baseline if both branches obey the documented ownership rules and avoid broad ABI changes. It is not safe to let both branches freely change packed structs, CLI parameter semantics, or shared render orchestration without explicit review.

## Interface Or Contract To Stabilize

The most important interface is the physics-to-interpreter render contract:

- raw radiance
- optical depth
- redshift/g-factor
- hit kind / hit mask
- emission radius or source-location proxy
- depth/distance proxy
- optional temperature, velocity, normal, and debug flags

This contract should become explicit before major camera or physics work depends on overloaded fields.

## Likely Merge Conflict Risks

- `gr_math.metal` because it stores both physical and presentation parameters.
- `PackedParams.swift` and `ParamsBuilder*.swift` because both branches may need new controls.
- `Compose/helpers.metalh` because branch-isolated previews, camera effects, and visible-source previews currently meet there.
- `RenderExecution.swift` and `Resources.swift` because trace/compose memory ownership affects both physics output and interpreter input.
- `run_pipeline.sh` because public CLI surface is shared.

## Recommended First Changes For `codex/physics-realism-v1`

- Improve physical debug outputs without changing presentation.
- Tighten canonical visible disk source diagnostics: raw radiance, g-factor, source radius, optical depth/hit mask.
- Avoid modifying eye/cinema tone mapping.
- Avoid packed ABI changes unless a small contract addition is reviewed.

## Recommended First Changes For `codex/interpreter-camera-v1`

- Use `--compose-hdr-in` and the GPU room RT validation path to improve eye/cinema behavior on known HDR radiance.
- Improve camera modeling through downstream interpretation first.
- If DOF needs more physical accuracy, prototype trace-stage aperture sampling or multi-layer depth/radiance as a documented contract extension.
- Do not alter disk emissivity, geodesics, source hit logic, or optical depth.
