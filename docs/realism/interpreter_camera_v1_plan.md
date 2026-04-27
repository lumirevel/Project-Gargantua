# Interpreter Camera V1 Plan

Branch: `codex/interpreter-camera-v1`

## 1. Current Interpreter Pipeline Map

Files/directories that appear to own final RGB:

- `Blackhole/Metal/Compose/helpers.metalh`: converts compose-stage linear radiance to display RGB through exposure, camera scene response, tone mapping, look transforms, eye/camera color response, PSF/glare, and final gamma encoding.
- `Blackhole/Metal/Compose/kernels.metalh`: dispatch-facing compose kernels that call the helper functions for collision-backed, full HDR32, and tiled HDR32 paths.
- `Blackhole/Sources/Render/Compose/`: Swift orchestration for full-GPU, HDR32 intermediate, and legacy tiled compose paths.

Files/directories that appear to own exposure:

- `Blackhole/Sources/Render/Support/HistogramMath.swift`: exposure target, quantile policy, luminance log range, and bounded mid-luminance exposure solve.
- `Blackhole/Metal/Compose/kernels.metalh`: GPU cloud/luminance histogram and exposure solve kernels.
- `Blackhole/Sources/Render/Compose/RenderComposeFullGPUPhase.swift`: full-GPU exposure prepasses and solve readback.
- `Blackhole/Sources/Render/Compose/RenderComposeHDRIntermediatePhase.swift`: file-backed HDR32 luminance histogram and exposure solve.
- `Blackhole/Sources/Render/Compose/RenderComposeLegacyPhase.swift`: CPU and tiled legacy exposure sampling/histogram paths.
- `Blackhole/Sources/Params/ParamsBuilderVisual.swift`: CLI/default exposure mode, manual exposure, exposure EV, presentation mode defaults, and camera/profile defaults.

Files/directories that appear to own tone mapping:

- `Blackhole/Metal/Compose/helpers.metalh`: `comp_tonemap_luma`, `comp_apply_look`, highlight desaturation, camera scene response, eye response, and display gamma.
- `Blackhole/Sources/Params/ParamsBuilderRuntime.swift`: maps `--look` names to compose look IDs.

Files/directories that appear to own bloom/glare/post-processing:

- `Blackhole/Metal/Compose/helpers.metalh`: PSF sampling, bright-pass scene extraction, cinematic flare, ocular-media wing glare, eye local adaptation, sensor noise, vignetting, and depth-of-field sampling for HDR32 input with depth sentinel.
- `docs/camera_profiles/` and `docs/camera_profile.example.json`: camera calibration inputs for PSF, noise, sensor response, flare, and DOF defaults.

Files/directories that appear to own output writing or debug views:

- `Blackhole/Sources/Render/Core/RenderOutputs.swift`: final PNG/PPM writing and render metadata writing.
- `Blackhole/Sources/Render/Core/RenderExecution.swift`: final render orchestration and metadata emission.
- `Blackhole/Sources/Params/ParamsBuilderVisual.swift`: `--realism-debug` mapping to compose analysis modes.
- `Blackhole/Metal/Compose/helpers.metalh`: compose analysis/debug map display behavior.
- `scripts/validate_presentation_modes.py`: scientific/eye/cinema and branch debug comparison harness.
- `scripts/validate_presentation_on_rt_scene.py`: non-black-hole HDR scene validation through `--compose-hdr-in`.

## 2. Current Suspected Visual Realism Bottlenecks From Code Inspection

- Dynamic range is not simply flattened globally; the pipeline has HDR32 paths, quantile exposure, filmic/realistic looks, camera scene response, and eye/camera profiles. The main risk is that exposure decisions are hard to audit after a render because percentile values are printed but not persisted.
- Highlights can clip harshly in fixed/manual exposure or when look/display shoulder settings are too aggressive. The code mitigates this with luma tone mapping and highlight desaturation, but diagnostics must distinguish physical saturation from display clipping.
- Tone mapping is moderately complex and distributed inside `helpers.metalh`. It is modular at helper-function level, but not yet exposed as separate output stages such as tone-mapped-no-bloom.
- Bloom/glare exists and is gated by camera/eye model and analysis mode. The current implementation is intentionally restrained for eye mode and stronger for cinema/photo profiles. Risk: bloom/glare can still mask small high-order caustic defects if reviewed only through final RGB.
- Separation between raw input and final output exists through `--compose-hdr-in`, `--scientific-master-out`, `--realism-debug hdr`, and branch debug previews, but there are not yet first-class outputs named `tone_mapped_no_bloom` and `bloom_only`.
- Exposure statistics are inspectable only from stdout today. They should be persisted as an interpreter diagnostic artifact next to the output image.

## 3. Render Contract Implications

Contract fields this branch consumes:

- Raw radiance / final source radiance, either from collision records or HDR32 linear input.
- Hit classification through collision records where compose still needs legacy collision-backed behavior.
- Source-location proxies and packed visible-band fields when existing compose debug modes consume them.
- Optional depth proxy from `--compose-hdr-in` alpha sentinel `w = 2 + depth` for compose-stage DOF validation.
- Presentation parameters: exposure, look, presentation mode, camera model/profile, PSF/noise/flare, background, analysis/debug mode.

Fields already available:

- Collision-backed source records with `hit`, `T`, `v_disk`, `direct_world`, `noise`, and emit/source proxy fields.
- HDR32 linear RGB intermediate and external HDR32 input.
- Some physical/debug views: g-factor, emissivity, beaming, branch/source previews, temperature/tau/density/activity, and GRMHD debug views.
- Compose-stage camera profile parameters and optional external depth proxy for HDR32 input.

Fields missing or incomplete:

- Uniform explicit raw radiance image output for every source path.
- First-class hit mask, optical depth, redshift/g-factor, and emission-radius/source-location outputs across all source modes.
- Multi-layer depth/radiance buffers for physically strong camera DOF on black-hole renders.
- Explicit `tone_mapped_no_bloom`, `bloom_only`, and `final_rgb` stage outputs from the same render invocation.

Interpreter effects that should wait for better physics-side fields:

- Physically strong depth of field on black-hole sources should wait for a reviewed depth/distance or multi-layer radiance contract.
- Lens flare or glare tuned to specific physical structures should wait until raw radiance, hit mask, optical depth, and redshift diagnostics make the source defects visible.
- Any effect that depends on disk temperature, velocity, or normal should wait for explicit contract fields rather than reinterpreting packed/debug fields.

## 4. Proposed Changes Ranked By Safety

Diagnostics-only changes:

- Persist exposure diagnostics as JSON: quantile targets, p50, high percentile, optional mid percentile, sample counts, cloud normalization, solve mode, and resolved exposure.
- Add stage-named interpreter outputs in validation scripts: raw input/HDR32, tone-mapped-no-bloom, bloom-only/glare-only, final RGB.
- Extend validation summaries to list presentation mode, look, camera model, exposure, and solve statistics for every image.

Low-risk display improvements:

- Keep tone curves modular and document exact look behavior.
- Add a reversible `tone_mapped_no_bloom` analysis path without changing default final RGB.
- Tune highlight desaturation conservatively only after diagnostics show source radiance is intact.

Medium-risk camera model improvements:

- Improve filmic tone mapping or camera shoulder response behind existing look/profile gates.
- Refine eye/cinema glare bright-pass thresholds while preserving bloom/glare-only diagnostics.
- Improve sensor noise and vignetting calibration from camera profiles, keeping defaults restrained.

High-risk effects to avoid for now:

- Strong lens flare or broad veil glare that hides disk/ring source defects.
- DOF for black-hole renders without a real depth/distance proxy.
- New packed ABI fields or Metal buffer layout changes on this branch.
- Any change to geodesics, disk density/thickness/temperature, emissivity, absorptivity, optical depth, radiative transfer, redshift/g-factor generation, Doppler beaming, or raw physical radiance generation.

## 5. First Implementation Target

First target: persist exposure diagnostics beside the final output image as `<output>.exposure_debug.json`.

Why this target:

- It is interpreter-only and uses values already computed by the exposure solve.
- It does not change physical radiance, tone mapping, bloom/glare, buffer layouts, or render results.
- It makes exposure decisions reviewable after the render, which is required before safely tuning tone mapping or glare.

Validation target:

- Build the Swift/Metal target.
- Run the smallest available compose/render validation command that writes a final image.
- Confirm that the final image still writes and the new exposure diagnostic JSON is created outside the repository output path.
