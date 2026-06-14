# Bloom And Glare Notes

Branch: `codex/interpreter-camera-v1`

## Current Bloom/Glare Behavior

Bloom and glare are present. They are interpreter/camera effects, not physical radiance generation.

- `Blackhole/Metal/Compose/helpers.metalh`
  - `comp_flare_bright_pass_scene` extracts bright-pass energy after exposure in scene-linear space.
  - `comp_psf_wing_strength` gates broad PSF/veil glare by camera profile, PSF sigma, and flare strength.
  - `comp_sample_linear_psf_full`, `comp_sample_linear_psf_tile`, and `comp_sample_collision_psf_tile` apply finite PSF sampling and broad wing glare.
  - `comp_add_cinematic_flare_full`, `comp_add_cinematic_flare_tile`, and `comp_add_cinematic_flare_collision` add camera-like local bloom, lens ghosts, weak aperture starburst, and chromatic dispersion.
- `Blackhole/Sources/Params/ParamsBuilderVisual.swift`
  - Owns `--camera-psf-sigma`, `--camera-flare`, camera profile defaults, and related lens controls.
- `Blackhole/Sources/Params/ParamsBuilderPolicy.swift`
  - Disables camera effects in analysis/debug compose modes by forcing camera model/effects to zero when `composeAnalysisMode != 0`.
- `scripts/render_interpreter_stage_diagnostics.py`
  - Separates `tone_mapped_no_bloom` from `final_rgb` by rendering with PSF/glare/flare/DOF/noise disabled, then writes a display-space positive-delta `bloom_only.png`.

## Assessment

- Bloom/glare is not absent.
- It is already restrained by bright-pass thresholding, profile gates, exposed-space caps, and analysis-mode disabling.
- The main remaining risk is diagnostic ambiguity: a positive-only `bloom_only` proxy shows where visible display energy is added, but it does not show where PSF/glare redistributed energy away from the source core.
- Final composition is modular enough for diagnostics because PSF/glare/flare can be disabled through existing runtime controls without changing physical source generation.

## Implemented Safe Improvement

The stage diagnostics metrics now include negative and coverage statistics:

- `positive_delta_luma_p95`
- `positive_delta_luma_p99`
- `positive_delta_luma_p999`
- `positive_delta_luma_max`
- `positive_delta_coverage_gt_0_01`
- `positive_delta_coverage_gt_0_05`
- `negative_delta_luma_mean`
- `negative_delta_luma_p95`
- `negative_delta_luma_p99`
- `negative_delta_luma_max`
- `redistribution_negative_to_positive_luma_mean_ratio`

This does not change final rendering. It makes `bloom_only` review safer by exposing when optics/post effects are redistributing or suppressing core disk detail instead of merely adding a plausible halo.

## Proposed Safe Next Improvement

If same-render stage outputs are later approved, add explicit buffers for:

1. tone-mapped-no-bloom display output
2. glare/bloom-only contribution
3. final RGB

That should be reviewed for memory growth and CPU-GPU synchronization cost before implementation.

## Risks

- `bloom_only.png` remains a display-space proxy from repeated renders, not a physical additive radiance buffer.
- Positive deltas can include display differences from PSF redistribution, flare, DOF, or noise if those effects are enabled in final output.
- Same-render bloom-only buffers would be more accurate but may increase memory use or synchronization cost.
- Increasing bloom/flare strength should be avoided until raw input, `tone_mapped_no_bloom`, `bloom_only`, final RGB, and exposure diagnostics agree.

## Validation Method

Run a small stage diagnostic render outside the repository:

```bash
BH_ETA_HISTORY=/private/tmp/bh_bloom_glare_eta.json \
python3 scripts/render_interpreter_stage_diagnostics.py \
  --source-model canonical-visible-disk-v1 \
  --presentation cinema \
  --look sensor-filmic \
  --width 64 \
  --height 40 \
  --quality preview \
  --out-dir /private/tmp/bh_bloom_glare_validation
```

Verify:

- build/render completes,
- `tone_mapped_no_bloom.png` still writes,
- `bloom_only.png` still writes,
- `interpreter_stage_metrics.json` contains positive and negative delta metrics,
- exposure debug JSON still writes.
