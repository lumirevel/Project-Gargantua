# Room RT Validation Notes

Branch: `codex/interpreter-camera-v1`

## Purpose

The room RT scene is an interpreter/camera validation target. It is not part of the black-hole or accretion-disk physical source model.

## Transparent Sphere Update

The room scene now includes a high-contrast rear-wall target directly behind the glass sphere. This makes it easier to inspect whether the transparent sphere shows the background through both front and back surfaces.

The GPU room RT glass path was also updated to trace:

1. front-surface refraction from air into glass,
2. exit-surface refraction from glass back into air,
3. weak Beer-Lambert tint through the sphere,
4. Schlick reflection mix at the front surface.

This keeps the validation scene more useful for judging camera/interpreter behavior such as glare, tone mapping, highlight rolloff, and display response on familiar refractive content.

The GPU room RT metal path now shades reflected glass with the same
refraction/Fresnel approximation used by primary glass hits. Previously the
metal sphere's reflection path used a simple secondary shader, so the reflected
glass sphere could read as diffuse/tinted instead of transparent. This change is
limited to the room validation renderer and does not alter black-hole source
physics.

## Camera/Depth Proxy Fix

The room HDR alpha channel carries a single depth proxy for compose-stage camera depth of field. That is inherently lossy for transparent objects because one pixel can contain:

- front-surface reflection,
- transmitted/refracted background,
- the glass medium itself.

The glass sphere now writes an approximate visible-layer depth instead of always writing the front surface depth:

1. refract through the front surface,
2. find the sphere exit point,
3. refract back into air,
4. intersect the visible scene behind the sphere,
5. blend transmitted depth with front-surface depth using the same Schlick Fresnel term used for color.

This is still a single-layer approximation, but it prevents the camera interpreter from treating the refracted rear-wall target as if it were opaque glass sitting only at the front surface.

## Multi-Layer Transparent DOF Reference

`scripts/validate_presentation_on_rt_scene.py` now supports
`--transparent-dof-reference`. This is a validation reference for the real
transparent-object failure mode of single-depth post-process DOF:

1. primary glass pixels are split into a front layer and a transmitted layer,
2. the front layer carries local/front-surface reflection depth,
3. the transmitted layer carries the refracted background depth,
4. each layer is blurred with the same camera CoC/aperture proxy,
5. the blurred layers are recombined in linear HDR before display mapping.

The script writes:

- `rt_room_transparent_front_layer.linear32f32`
- `rt_room_transparent_back_layer.linear32f32`
- `rt_room_transparent_multilayer_dof.linear32f32`
- `rt_room_transparent_multilayer_dof_cinema.png`

Metrics now include a glass-sphere ROI block so transparent DOF differences are
not hidden by whole-image averages.

The script also writes glass-focused visual diagnostics:

- `rt_room_glass_roi_sheet.png`: cropped comparison of scientific, eye,
  cinema, stochastic thin-lens reference when requested, and multi-layer
  transparent DOF reference when requested.
- `rt_room_glass_roi_error_vs_thin_lens.png`: cropped heatmap of cinema output
  error versus the stochastic aperture-sampled reference when
  `--lens-reference-spp` is enabled.
- `rt_room_glass_roi_error_vs_transparent_multilayer_dof.png`: cropped heatmap
  of cinema output error versus the layer-aware transparent DOF reference when
  `--transparent-dof-reference` is enabled.

These images are diagnostic-only. They make the known single-depth transparency
failure local and visible before any production render-contract change.

The same ROI comparisons can now be turned into validation gates:

- `--max-glass-roi-mae-vs-transparent-dof <value>`
- `--min-glass-roi-corr-vs-transparent-dof <value>`
- `--max-glass-roi-mae-vs-thin-lens <value>`
- `--min-glass-roi-corr-vs-thin-lens <value>`

When a gate is supplied, the script records `validation_gates` in
`metrics.json` and exits non-zero if the required reference output is missing or
the metric falls outside the threshold. These gates are intended for regression
checks and integration review, not for tuning the physical source.

This does not change the black-hole renderer's physical source model or packed
physics outputs. It also does not pretend the production compose path has a full
multi-layer depth contract. It creates an interpreter-side reference image for
judging how far the current single-depth compose approximation deviates from a
layer-aware camera result.

For stochastic/lens-integrated validation, use the existing
`--lens-reference-spp <N>` path. That path traces rays over a finite aperture
before writing the HDR input, so transparent refraction is sampled through the
lens rather than repaired by a post-process depth proxy.

References:

- NVIDIA GPU Gems 3, "Practical Post-Process Depth of Field": https://developer.nvidia.com/gpugems/gpugems3/part-iv-image-effects/chapter-28-practical-post-process-depth-field
- NVIDIA GPU Gems, "Depth of Field: A Survey of Techniques": https://developer.nvidia.com/gpugems/gpugems/part-iv-image-processing/chapter-23-depth-field-survey-techniques
- PBRT v4, "Projective Camera Models": https://www.pbr-book.org/4ed/Cameras_and_Film/Projective_Camera_Models
- Eidos-Montreal, "Depth Proxy Transparency Rendering": https://www.eidosmontreal.com/news/depth-proxy-transparency-rendering/

## Files

- `scripts/generate_room_rt_hdr_gpu.swift`
- `scripts/validate_presentation_on_rt_scene.py`

## Limits

- This is still a compact validation ray tracer, not a full spectral path tracer.
- The glass sphere uses a simple two-interface refraction approximation.
- Transparent shadows/caustics are not physically complete.
- The depth proxy cannot represent multiple simultaneous focus layers.
- The production compose path still receives only one depth value per `float4`
  HDR sample; multi-layer transparent DOF is currently a validation reference,
  not a universal render contract.
- Changes do not affect black-hole geodesics, disk radiance, optical depth, redshift, or radiative transfer.
