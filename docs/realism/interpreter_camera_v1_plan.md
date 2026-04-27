# Interpreter Camera V1 Development Plan

Branch: `codex/interpreter-camera-v1`

Purpose: improve the interpreter/camera side only: exposure, HDR statistics, sensor response, tone mapping, bloom/glare/flare, depth-of-field interpretation when a depth proxy exists, final display mapping, and interpreter diagnostics.

Do not change physical black-hole, disk, geodesic, redshift, optical-depth, transfer, or raw-radiance generation on this branch.

## 1. Current Interpreter Pipeline Map

### Where physical signal enters the interpreter

- Collision-backed path: trace/source output arrives as `CollisionInfo` records in `Blackhole/Sources/Core/ABI/PackedParams.swift`, then compose kernels in `Blackhole/Metal/Compose/kernels.metalh` call helper functions in `Blackhole/Metal/Compose/helpers.metalh`.
- HDR32 path: linear `float4` radiance enters through direct/full-frame or file-backed HDR32 intermediates. `--compose-hdr-in` is the cleanest interpreter-only validation bridge because it bypasses black-hole tracing and feeds row-major `float4` linear RGB into the Metal compose stage.
- Sentinel convention: `w > 1.25` means the HDR32 `xyz` is already final source radiance for compose; `w = 2 + depth` optionally carries a presentation depth proxy for cinema DOF validation.

### Where exposure is computed

- `Blackhole/Sources/Render/Support/HistogramMath.swift`
  - Owns target-white policy, high-percentile exposure settings, bounded mid-luminance exposure boosts, luminance log ranges, and CPU-side exposure math.
- `Blackhole/Metal/Compose/kernels.metalh`
  - `composeCloudHist*`, `composeLumHist*`, `composeSolveCloudStats`, and `composeSolveExposure` build histograms and solve GPU exposure.
- `Blackhole/Sources/Render/Compose/RenderComposeFullGPUPhase.swift`
  - Runs full-GPU cloud/luminance prepasses and persists exposure diagnostics.
- `Blackhole/Sources/Render/Compose/RenderComposeHDRIntermediatePhase.swift`
  - Runs file-backed HDR32 luminance histogram/exposure solve and persists exposure diagnostics.
- `Blackhole/Sources/Render/Compose/RenderComposeLegacyPhase.swift`
  - Runs legacy CPU/tiled exposure sampling or histogram logic and persists exposure diagnostics.
- `Blackhole/Sources/Params/ParamsBuilderVisual.swift`
  - Parses `--exposure`, `--exposure-mode`, `--exposure-ev`, `--exposure-samples`, presentation defaults, look, camera model/profile, PSF/noise/flare, aperture, focus, and DOF controls.

### Where tone mapping happens

- `Blackhole/Metal/Compose/helpers.metalh`
  - `comp_shade` and `comp_shade_linear` apply exposure, camera scene response, luminance tone mapping, highlight desaturation, look transform, camera/eye display response, and final gamma.
  - `comp_tonemap_luma` and `comp_apply_look` are the central display/tone hooks.
- `Blackhole/Sources/Params/ParamsBuilderRuntime.swift`
  - Maps `--look` names to look IDs: interstellar, eht, agx/filmic, linear, hdr-rich, realistic, structure/detail.

### Where bloom/glare/post-processing happens

- `Blackhole/Metal/Compose/helpers.metalh`
  - `comp_sample_linear_psf_full`, `comp_sample_linear_psf_tile`, and `comp_sample_collision_psf_tile` handle PSF sampling and broad wing glare.
  - `comp_flare_bright_pass_scene` extracts bright-pass energy in exposed space.
  - `comp_add_cinematic_flare_full`, `comp_add_cinematic_flare_tile`, and `comp_add_cinematic_flare_collision` add camera-like bloom, lens ghosts, starburst, and chromatic dispersion.
  - Eye mode includes human-vision display response and local adaptation helpers; scientific/debug analysis modes disable camera effects.
- `docs/camera_profiles/`
  - Stores camera profile JSON values for full-well, read noise, dark current/exposure seconds, PRNU, vignetting, PSF, flare, focus depth, DOF strength, aperture blades, and aperture rotation.

### Where final RGB is written

- `Blackhole/Metal/Compose/kernels.metalh`
  - `composeBH`, `composeBHLinear`, and `composeBHLinearTile` produce `uchar4` display RGBA tiles after helper-side interpretation.
- `Blackhole/Sources/Render/Compose/`
  - `RenderComposeFullGPUPhase.swift`, `RenderComposeHDRIntermediatePhase.swift`, and `RenderComposeLegacyPhase.swift` read back composed RGBA/RGB and call output writing.
- `Blackhole/Sources/Render/Core/RenderOutputs.swift`
  - `writeImage` writes PNG/PPM final images.
  - `writeExposureDiagnostics` writes `<output>.exposure_debug.json`.
  - `writeMetadata` writes render metadata when collision/HDR intermediates are kept.

### Where debug outputs are generated

- Presentation/debug CLI selection lives in `Blackhole/Sources/Params/ParamsBuilderVisual.swift` via `--realism-debug` and compose `analysisMode`.
- Compose debug image behavior lives mostly in `Blackhole/Metal/Compose/helpers.metalh`, including g-factor/redshift, emissivity, beaming, HDR/pre-tone, branch previews, temperature, tau, density, and activity maps.
- GRMHD/volume debug views are selected by `diskGrmhdDebugView` but are physics-owned and should not be changed on this branch.
- Validation scripts:
  - `scripts/validate_presentation_modes.py` renders scientific/eye/cinema and branch debug comparison sheets.
  - `scripts/validate_presentation_on_rt_scene.py` feeds a familiar HDR room scene through `--compose-hdr-in`.

## 2. Current Suspected Interpreter Realism Bottlenecks

- Dynamic range is not globally flattened by a single simple clamp: the code has HDR32 intermediates, quantile auto-exposure, look-specific target whites, camera scene response, highlight desaturation, and eye/camera response. The remaining bottleneck is stage visibility: it is still hard to inspect the exact split between exposed/tone-mapped base image and glare/bloom contribution.
- Highlight rolloff may still be unrealistic in some modes because tone mapping, sensor full-well shoulder, display shoulder, highlight desaturation, and human-eye bleaching all interact inside one final display path. Exposure diagnostics now make the solve inspectable, but the post-exposure stages are not separately rendered.
- Tone mapping is not too simple, but it is concentrated in `helpers.metalh` and exposed mainly through final RGB or existing analysis maps. A modular, reversible `tone_mapped_no_bloom` output would make future curve changes safer.
- Bloom/glare is present, not missing. It is gated by analysis mode and camera/eye profile, but it can still obscure source or sampling defects if reviewed only through final RGB. There is no first-class `bloom_only` or `glare_only` output from the same render.
- Raw input, tone-mapped-no-bloom, bloom-only, and final output are only partially separable:
  - Raw/HDR input is available through HDR32 intermediates, `--compose-hdr-in`, `--scientific-master-out`, and selected debug views.
  - `tone_mapped_no_bloom` is not first-class.
  - `bloom_only` / `glare_only` is not first-class.
  - `final_rgb` is the normal output.
- Exposure statistics are now inspectable through `<output>.exposure_debug.json`, including presentation/look/camera context, target white, quantiles, p50, pHigh, optional pMid, sample counts, luminance log range, cloud normalization, and resolved exposure where available.

## 3. Render Contract Consumption Status

- `raw radiance`: consumed. Compose consumes source radiance from collision records or HDR32 linear input. Access is real but not uniform as a named diagnostic image across all source paths.
- `optical depth`: partially consumed for existing debug/physical preview paths where packed helper data or analysis modes expose tau-like values. Not available as a uniform interpreter input for camera effects; interpreter effects should not infer or alter it.
- `redshift/g-factor`: partially consumed for existing debug/display analysis in compose helpers, but generation remains physics-owned. Interpreter should treat it as a diagnostic field, not a display tuning control.
- `hit mask`: consumed internally on collision-backed paths via `rec.hit` to decide background versus source. There is no first-class interpreter-stage hit-mask output across all paths.
- `emission radius/source proxy`: partially consumed for existing compose debug/source previews through packed emit/source proxy fields. Not uniform enough for new camera effects that depend on source location.
- `depth/distance proxy`: limited access. External HDR32 compose can carry `w = 2 + depth`, and cinema DOF can use that proxy. Black-hole source paths do not yet provide a reviewed depth/distance or multi-layer radiance contract suitable for physically strong DOF.
- `debug flags`: consumed. `analysisMode`, `realismDebugID`, and `diskGrmhdDebugView` drive debug behavior. Interpreter work may add presentation diagnostics, but physics-owned debug flags should remain untouched unless reviewed as contract work.

## 4. Ranked Improvement Plan

### Diagnostics-only changes

1. Add a first-class `tone_mapped_no_bloom` output path for the compose stage without changing default final RGB.
2. Add a `bloom_only` or `glare_only` output path after the no-bloom base image is available.
3. Extend validation scripts to include raw/HDR input, tone-mapped-no-bloom, bloom-only/glare-only, final RGB, and exposure-debug JSON in contact sheets and summaries.
4. Add documentation for exact stage ordering: raw radiance -> exposure -> camera scene response -> tone map/look -> eye/camera color response -> glare/PSF/flare -> sensor/display output.

### Low-risk display improvements

1. Keep tone mapping curves modular and reversible; avoid changing defaults until stage diagnostics exist.
2. Add a conservative filmic comparison mode only behind existing look/profile gates or a clearly named analysis path.
3. Tune highlight desaturation only after tone-mapped-no-bloom and exposure diagnostics show that physical radiance and exposure solve are not the source of the problem.
4. Improve camera profile docs and validation summaries before adding new runtime knobs.

### Medium-risk camera model improvements

1. Refine human-eye local adaptation and ocular-media glare using `--compose-hdr-in` room scenes and black-hole scientific/eye/cinema correlation checks.
2. Improve camera shoulder/full-well response and sensor noise ordering, while keeping generated noise/post effects disabled in diagnostic modes.
3. Calibrate cinema/photo flare strength against bloom-only/glare-only outputs so disk details are not destroyed.
4. Improve DOF only for HDR32 inputs with a depth proxy; black-hole DOF needs contract work first.

### High-risk effects to avoid for now

1. Strong lens flare or broad veil glare without a bloom/glare-only diagnostic.
2. Black-hole DOF without a reviewed depth/distance or multi-layer radiance contract.
3. New packed ABI fields or Metal buffer layout changes from this branch.
4. Any change to geodesics, metric, black-hole hit logic, disk density, disk thickness, disk temperature, emissivity, absorptivity, optical depth, radiative transfer, redshift/g-factor generation, Doppler beaming generation, or raw physical radiance generation.
5. Display changes that intentionally crush blacks or over-bloom highlights to hide source/transport defects.

## 5. First Implementation Recommendation

Recommended first implementation: expose `tone_mapped_no_bloom`.

Rationale:

- Exposure diagnostics already exist on this branch, so the next safest gap is stage separation after exposure/tone mapping and before bloom/glare/flare.
- A no-bloom output is interpreter-only and can be implemented as a diagnostic output or validation-script render path without modifying physics.
- It gives future tone mapping and bloom/glare work a stable comparison target: raw/HDR input -> tone_mapped_no_bloom -> bloom_only/glare_only -> final_rgb.
- It should be modular and reversible, preserve existing presets/render paths, avoid new packed ABI fields if possible, and write generated images outside the repository during validation.

Do not implement this until the exact output mechanism is chosen. Preferred mechanisms, in order:

1. Validation-script output using existing render/debug modes if sufficient.
2. A narrowly gated interpreter analysis mode that disables PSF/glare/flare and writes the normal output as `tone_mapped_no_bloom`.
3. A separate same-render auxiliary output only if the memory and synchronization cost is reviewed.
