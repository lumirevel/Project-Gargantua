# Interpreter Camera V1 Branch Report

Branch: `codex/interpreter-camera-v1`

## 1. Branch Summary

This branch improves the visual interpreter/camera side of the renderer:

- Added a precise interpreter-side development plan.
- Added stage-named diagnostics for raw interpreter input, tone-mapped-no-bloom, bloom-only proxy, and final RGB.
- Expanded exposure/HDR diagnostics.
- Added a reversible `sensor-filmic` display look.
- Improved bloom/glare diagnostic metrics so optical redistribution can be inspected.
- Added an eye-only veiling-glare proxy so bright local sources reduce contrast through a small scatter veil instead of reading as an artificial dark halo.

Intentionally not changed:

- geodesics
- metric
- black-hole hit logic
- disk density/thickness/temperature
- emissivity or absorptivity
- optical-depth generation
- radiative transfer
- redshift/g-factor generation
- Doppler beaming generation
- raw physical radiance generation

## 2. Interpreter Improvements

### Diagnostics

- `scripts/render_interpreter_stage_diagnostics.py` renders:
  - `raw_interpreter_input.png`
  - `tone_mapped_no_bloom.png`
  - `bloom_only.png`
  - `final_rgb.png`
  - `interpreter_stage_sheet.png`
  - `interpreter_stage_metrics.json`
- `bloom_only.png` is explicitly documented as a display-space proxy.
- Metrics now include positive and negative delta statistics so bloom/glare additions and PSF redistribution can both be reviewed.

### Exposure/HDR

- `<output>.exposure_debug.json` now uses `interpreter_exposure_v2`.
- Added derived fields:
  - candidate high/mid exposure values
  - resolved exposure EV
  - exposure driver
  - exposed percentile levels
  - pHigh/p50 and pMid/p50 ratios in stops
  - linear histogram bounds
- Exposure solve behavior was not changed.

### Tone Mapping/Sensor Response

- Added `--look sensor-filmic` with aliases:
  - `sensor`
  - `camera-filmic`
  - `display-filmic`
- The new look is reversible and opt-in.
- Extracted highlight desaturation into `comp_apply_highlight_desaturation` so collision and HDR32 paths share the same highlight chroma handling.
- Existing default looks remain available.

### Bloom/Glare

- Existing bloom/glare/flare code remains restrained and profile-gated.
- No final-image bloom strength was increased.
- Diagnostics now measure whether optical effects add visible halo energy or remove/redistribute core detail.
- Eye presentation now adds a restrained intraocular-scatter veil in bright local surrounds. The added veil is gated by `cameraPsfSigmaPx`, so optics-off diagnostics can still remove it.

## 3. Render Contract Consumption Status

- `raw radiance`: consumed. Compose consumes collision-backed linear radiance or HDR32 input. Stage diagnostics can preview it, but same-render raw output is not universal yet.
- `optical depth`: available in physics/debug paths but not used by interpreter camera effects. It remains physics-owned.
- `redshift/g-factor`: available in physics/debug paths but not used by interpreter camera effects. Generation remains physics-owned.
- `hit mask`: consumed internally by collision-backed compose to separate source/background; not exposed as a uniform interpreter diagnostic image.
- `emission radius/source proxy`: available for selected debug/source previews, but not used by camera effects.
- `depth/distance proxy`: limited. External HDR32 can carry `w = 2 + depth`; black-hole source paths still lack a reviewed depth/distance contract for strong DOF.
- `debug flags`: consumed. `analysisMode`, `realismDebugID`, and related flags drive diagnostic views and disable camera effects where appropriate.

## 4. Validation

Commands run during this branch:

```bash
python3 -m py_compile scripts/render_interpreter_stage_diagnostics.py
python3 scripts/render_interpreter_stage_diagnostics.py --help
python3 scripts/render_interpreter_stage_diagnostics.py \
  --source-model canonical-visible-disk-v1 \
  --presentation cinema \
  --width 64 \
  --height 40 \
  --quality preview \
  --out-dir /private/tmp/bh_interpreter_stage_diag_validation
BH_ETA_HISTORY=/private/tmp/bh_exposure_hdr_diag_eta.json \
python3 scripts/render_interpreter_stage_diagnostics.py \
  --source-model canonical-visible-disk-v1 \
  --presentation cinema \
  --width 64 \
  --height 40 \
  --quality preview \
  --out-dir /private/tmp/bh_exposure_hdr_diag_validation
BH_ETA_HISTORY=/private/tmp/bh_tonemap_sensor_filmic_eta.json \
python3 scripts/render_interpreter_stage_diagnostics.py \
  --source-model canonical-visible-disk-v1 \
  --presentation cinema \
  --look sensor-filmic \
  --width 64 \
  --height 40 \
  --quality preview \
  --out-dir /private/tmp/bh_tonemap_sensor_filmic_validation
python3 -m py_compile scripts/render_interpreter_stage_diagnostics.py
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

Passed:

- Xcode build completed.
- Tiny preview renders completed.
- Final images wrote.
- `tone_mapped_no_bloom` and `bloom_only` diagnostics wrote.
- Exposure debug JSON wrote and included new fields.
- `sensor-filmic` look parsed and rendered.
- Bloom/glare metrics include positive-delta coverage and negative redistribution fields.

Failed:

- No project validation command failed during this branch.

Could not be fully validated:

- Same-render stage buffers, because this branch uses repeated renders and display-space subtraction for stage diagnostics.
- Full-resolution performance impact, because validation was intentionally small.
- Integration with future physics-side contract fields, because those fields are outside this branch.

Known environment warning:

- Xcode/CoreSimulator reports duplicate xrOS runtime warnings on this machine. They did not block build or render.

## 5. Remaining Risks

### Visual Risks

- `sensor-filmic` is an opt-in comparison look, not a calibrated final camera profile.
- Bloom-only is a display-space proxy and can include redistribution artifacts.
- Stronger bloom/glare could still hide physical defects if later tuned without stage diagnostics.
- Exposure failures can still make tone mapping look bad; diagnostics now identify this but do not automatically fix it.

### Performance Risks

- Current diagnostics use repeated renders, which are slow but avoid same-render buffer growth.
- Same-render auxiliary buffers would need memory and synchronization review.
- Full-resolution behavior of sensor-filmic and diagnostics has not been profiled.

### Merge Risks With Physics Branch

- Physics-side changes may alter raw radiance scale, dynamic range, or packed debug fields; exposure and tone mapping should be revalidated after merge.
- New physics contract fields must not overwrite interpreter-owned camera controls or diagnostics.
- Packed ABI changes from physics need alignment review before interpreter effects depend on new fields.

## 6. Recommended Integration Notes

This branch expects:

- physically meaningful raw radiance entering compose,
- stable hit/background signaling,
- debug views for optical depth and redshift/g-factor when available,
- a reviewed depth/distance proxy before stronger black-hole DOF is enabled,
- generated physical diagnostics to remain separate from display interpretation.

Check during later integration:

- raw radiance preview versus final RGB,
- exposure debug JSON for p50, pHigh, exposure driver, and exposed percentile values,
- `tone_mapped_no_bloom` before judging bloom/glare,
- `bloom_only` and negative redistribution metrics before changing flare strength,
- `sensor-filmic` against existing looks on the same physical input.

Do not overwrite:

- `scripts/render_interpreter_stage_diagnostics.py`
- `docs/realism/interpreter_diagnostics_notes.md`
- `docs/realism/exposure_hdr_notes.md`
- `docs/realism/tone_mapping_sensor_response_notes.md`
- `docs/realism/bloom_glare_notes.md`
- `docs/realism/eye_veiling_glare_notes.md`
- interpreter-owned exposure, tone mapping, camera profile, bloom/glare, and display mapping logic

Ready for integration: partial.

Reason: the interpreter branch is internally validated on small renders and keeps physics untouched, but final integration still needs physics-side contract review for radiance scale, depth/distance proxy, and any packed ABI changes.
