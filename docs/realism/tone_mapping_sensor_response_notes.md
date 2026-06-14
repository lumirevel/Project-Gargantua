# Tone Mapping And Sensor Response Notes

Branch: `codex/interpreter-camera-v1`

## Current Tone Mapping Behavior

Display mapping is interpreter-owned and happens after physical or HDR32 radiance enters compose.

- `Blackhole/Metal/spectrum_visible.metal`
  - Defines the luma tone curves: ACES-like default, AgX-like, HDR-rich, realistic, linear, and structure/detail.
  - Defines look-specific color transforms.
- `Blackhole/Metal/Compose/helpers.metalh`
  - `comp_shade` and `comp_shade_linear` apply exposure, optional camera scene response, luma tone mapping, highlight desaturation, look color handling, camera/eye display response, and final sRGB-ish gamma.
  - Both collision-backed and HDR32 paths use the same display functions.
- `Blackhole/Sources/Params/ParamsBuilderRuntime.swift`
  - Maps `--look` names to compact look IDs.
- `Blackhole/Sources/Render/Support/HistogramMath.swift`
  - Chooses target-white policy for auto exposure before tone mapping.

The existing tone mapping is not just simple gamma. It is mostly luma-preserving tone mapping with RGB scaled by the tone-mapped luminance, followed by highlight desaturation, look color handling, camera/eye response, and final gamma.

## Why It May Look Unrealistic

- Several tone curves are useful, but the main display response can still feel CG-like if highlights hit the shoulder too abruptly or near-white chroma is clipped instead of rolling off.
- Highlight desaturation existed in two duplicated shader blocks, making small changes harder to audit across collision and HDR32 compose paths.
- The existing `linear` look is intentionally diagnostic and can clip harshly; it should remain available, but it is not a camera/display response.
- Bloom or flare should not be used to hide tone-mapping issues, so highlight rolloff needs to be inspectable with `tone_mapped_no_bloom`.

## Implemented Safe Improvement

Added a reversible comparison look:

- `--look sensor-filmic`
- aliases: `sensor`, `camera-filmic`, `display-filmic`

This look uses a named `comp_sensor_filmic_like` luma curve:

- Hable-style filmic shoulder
- modest exposure-domain scale
- no bloom or glare change
- no physical radiance change
- no new Metal buffer fields

Also added `comp_apply_highlight_desaturation` so collision-backed and HDR32 paths use the same highlight chroma handling. Existing looks keep their prior desaturation strengths, while `sensor-filmic` uses a slightly gentler near-white desaturation to preserve source hue through the new shoulder.

## How To Compare Before And After

Use the existing stage diagnostics so bloom/glare do not hide tone mapping behavior.

Baseline:

```bash
python3 scripts/render_interpreter_stage_diagnostics.py \
  --source-model canonical-visible-disk-v1 \
  --presentation cinema \
  --width 384 \
  --height 216 \
  --quality preview \
  --out-dir /private/tmp/bh_tonemap_baseline
```

Sensor-filmic comparison:

```bash
python3 scripts/render_interpreter_stage_diagnostics.py \
  --source-model canonical-visible-disk-v1 \
  --presentation cinema \
  --look sensor-filmic \
  --width 384 \
  --height 216 \
  --quality preview \
  --out-dir /private/tmp/bh_tonemap_sensor_filmic
```

Inspect:

- `tone_mapped_no_bloom.png` for tone curve and highlight rolloff.
- `final_rgb.png` for interaction with camera optics/post effects.
- `bloom_only.png` to ensure the visual change is not just extra glare.
- `*.exposure_debug.json` to confirm exposure behavior remains explainable.

## Risks

- The new look is calibrated as a conservative comparison curve, not a final camera profile.
- Hable-style shoulders can still compress very hot radiance into a narrow near-white range if exposure is poor.
- The validation script separates stages through repeated renders, so `bloom_only` remains a display-space proxy rather than a same-render radiance buffer.
- Broader default-look changes should wait for side-by-side review of raw input, `tone_mapped_no_bloom`, `bloom_only`, `final_rgb`, and exposure diagnostics.
