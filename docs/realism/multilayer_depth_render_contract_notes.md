# Multi-Layer Depth Render Contract Notes

Branch: `codex/interpreter-camera-v1`

## Decision

Do not change the production black-hole render ABI in this interpreter branch.

Transparent-object DOF cannot be made physically correct with one color and one
depth value per pixel. The correct future integration path is to add an explicit
multi-layer radiance/depth contract, or to render DOF by stochastic lens
integration before the final camera/display mapping.

This document records the contract work so it can be merged later on an
integration branch without hiding the limitation behind tuning.

## Current Contract Limitation

The current external HDR bridge is `float4 linear32`:

- `xyz`: linear source radiance for compose
- `w`: sentinel or `2 + depth`

That is useful for opaque objects and simple validation, but it cannot represent
one pixel containing both:

- front glass reflection at the front surface depth,
- transmitted/refracted background at a farther depth,
- volumetric or semi-transparent contributions along the same camera ray.

A single blended depth can only choose a compromise. It will be wrong when the
lens focus, aperture, or object transparency makes multiple layers visible.

## Future Contract Options

### Option A: Sidecar Multi-Layer Buffers

Keep the existing `float4 linear32` path as layer 0 and add sidecar buffers:

- `layerColor[N]`: linear RGB radiance per layer
- `layerDepth[N]`: source distance/depth per layer
- `layerAlphaOrWeight[N]`: opacity, throughput, or contribution weight
- optional `layerKind[N]`: opaque, reflective, transmissive, volumetric, sky

Pros:

- preserves the existing HDR path,
- lets compose perform layer-aware DOF without changing every source at once,
- easier to gate behind a feature flag.

Cons:

- adds memory bandwidth and storage,
- needs exact alignment/stride review,
- needs clear rules for layer ordering and empty layers.

### Option B: Packed Multi-Layer Pixel Format

Replace or extend `float4 linear32` with a wider packed format such as:

- `float4 layer0ColorDepth`
- `float4 layer1ColorDepth`
- `float4 layer2ColorDepth`
- metadata word for layer count/type/weight

Pros:

- compact for a fixed layer count,
- GPU-friendly contiguous reads.

Cons:

- invasive ABI change,
- fixed layer count may still fail on complex volumetric paths,
- more risk when merging with physics-side packed payload changes.

### Option C: Stochastic Lens-Integrated Rendering

Instead of post-process DOF, trace camera rays over the aperture and integrate
the lens before writing final radiance.

Pros:

- physically strongest for transparent/refraction cases,
- no depth proxy ambiguity,
- handles glass, reflection, and refraction naturally.

Cons:

- much more expensive,
- needs temporal/noise handling,
- less useful for cheap interactive presentation previews.

## Recommended Integration Plan

1. Keep current single-depth DOF for preview and opaque validation.
2. Use `scripts/validate_presentation_on_rt_scene.py --transparent-dof-reference`
   as a reference when judging transparent-object DOF.
3. On an integration branch, add an opt-in layer contract first, not a default
   replacement.
4. Validate with both:
   - multi-layer post-process DOF,
   - stochastic/lens-integrated reference.
5. Only then decide whether production black-hole DOF should use layer-aware
   compose, stochastic lens sampling, or both depending on quality mode.

## Contract Fields Needed

For each visible layer:

- linear radiance RGB,
- source depth or distance proxy in camera space,
- contribution weight or alpha,
- layer kind or hit kind,
- optional physical diagnostics for debugging:
  - hit mask,
  - optical depth,
  - redshift/g-factor,
  - source radius/location proxy.

The interpreter consumes these values but must not generate or modify physical
fields. Physics remains responsible for radiance, hit classification, optical
depth, redshift, and source-location proxies.

## Validation Gates

Before enabling production multi-layer DOF:

- compare final RGB, tone-mapped-no-bloom, and raw layer previews,
- inspect glass/transparent ROI metrics rather than only whole-image averages,
- inspect glass/transparent ROI crop sheets and error heatmaps against
  layer-aware or stochastic lens references,
- verify memory growth at target resolution,
- verify no CPU-GPU synchronization regression,
- document packed ABI changes and alignment,
- keep a single-depth fallback path.

## Reference Basis

The current branch follows the standard limitation called out by practical DOF
implementations: post-process blur based on a single depth buffer is useful for
opaque previews but breaks on semi-transparent or multi-layer pixels. GPU Gems
discusses post-process DOF as a depth-buffer approximation, while PBRT's camera
models use aperture/lens sampling as the physically grounded reference path.

References:

- NVIDIA GPU Gems 3, "Practical Post-Process Depth of Field": https://developer.nvidia.com/gpugems/gpugems3/part-iv-image-effects/chapter-28-practical-post-process-depth-field
- PBRT v4, "Projective Camera Models": https://www.pbr-book.org/4ed/Cameras_and_Film/Projective_Camera_Models

## Current Branch Status

Implemented in this branch:

- validation-only multi-layer transparent DOF reference for the room RT scene,
- stochastic thin-lens reference path,
- glass ROI metrics to make transparent DOF errors visible,
- glass ROI crop sheet and error heatmaps for local visual inspection.

Deferred:

- production multi-layer black-hole render buffers,
- packed ABI changes,
- layer-aware compose kernels for black-hole source paths,
- stochastic aperture sampling in black-hole tracing.
