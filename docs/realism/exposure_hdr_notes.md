# Exposure And HDR Diagnostics Notes

Branch: `codex/interpreter-camera-v1`

## Current Exposure Algorithm

Exposure is interpreter-owned and is applied in the compose stage after the physical or HDR32 source signal exists.

- CLI ownership starts in `Blackhole/Sources/Params/ParamsBuilderVisual.swift`.
  - `--exposure-mode fixed` or positive `--exposure` disables auto exposure.
  - `--exposure-ev` maps fixed exposure to `2^EV`.
  - Most analysis/debug modes force fixed diagnostic exposure so maps remain comparable.
- Shared exposure policy lives in `Blackhole/Sources/Render/Support/HistogramMath.swift`.
  - The normal auto solve exposes a high luminance quantile, usually p99.5, to a look/presentation-specific target white.
  - Selected eye/volume cases can use a bounded mid-luminance boost: a mid quantile proposes a brighter exposure, but only up to `maxExposureBoost` above the high-quantile solve.
  - Luminance histograms are log-domain. Current log ranges are `1e-8...1e8` for GRMHD/external HDR32 paths and `1e8...1e20` for older non-GRMHD paths.
- GPU histogram solves live in `Blackhole/Metal/Compose/kernels.metalh`.
  - `composeSolveExposure` reads the luminance histogram, reconstructs p50, pHigh, optional pMid, and writes the resolved exposure.
- CPU/tiled and file-backed paths persist diagnostics through `RenderOutputs.writeExposureDiagnostics`.

Plain language: the renderer does not expose from a single maximum pixel. It usually aims a high percentile at target white to avoid one-pixel outliers, with a carefully capped midtone lift only for known presentation cases where a small bright ring can otherwise make the broad disk body unreadable.

## Suspected Problems

- Diagnostics showed the solved exposure and percentile values, but not the candidate exposures used to choose the final value.
- It was difficult to tell whether a frame was controlled by the high percentile, by the capped midtone boost, or by manual/fixed exposure.
- The JSON did not report the post-exposure percentile levels, so highlight rolloff failures could be confused with exposure failures.
- The JSON did not report dynamic-range ratios such as pHigh/p50 in stops, making outlier domination harder to diagnose from logs alone.
- Histogram domain limits were reported only as log10 bounds, not as luminance bounds.

## Implemented Safe Change

`<output>.exposure_debug.json` now includes additive interpreter diagnostics:

- `highExposureCandidate`
- `midExposureCandidate`
- `resolvedExposureEV`
- `effectiveMidBoost`
- `maxMidBoost`
- `exposureDriver`
- `exposedP50`
- `exposedPHigh`
- `exposedPMid`
- `pHighOverP50`
- `pHighStopsOverP50`
- `pMidOverP50`
- `pMidStopsOverP50`
- `luminanceHistogramMin`
- `luminanceHistogramMax`

This does not change the exposure solve, tone mapping, bloom, physical radiance, Metal buffer layout, or final image. It only makes already-computed interpreter statistics easier to inspect.

## Recommended Safe Changes

- Keep collecting stage diagnostics from `scripts/render_interpreter_stage_diagnostics.py` and compare `tone_mapped_no_bloom` against `final_rgb`.
- Add same-render stage outputs only after reviewing memory and synchronization cost.
- If exposure failures are found, prefer narrowly scoped policy changes in `HistogramMath.swift` with before/after exposure debug JSON.
- Avoid changing tone mapping or bloom strength until exposure diagnostics show the solve is behaving as intended.

## Validation Method

Use a tiny preview render to verify that:

- the renderer still compiles and runs,
- final RGB still writes,
- `<output>.exposure_debug.json` still writes,
- new exposure diagnostic fields appear,
- generated validation images and logs stay outside the repository.

Example:

```bash
python3 scripts/render_interpreter_stage_diagnostics.py \
  --source-model canonical-visible-disk-v1 \
  --presentation cinema \
  --width 64 \
  --height 40 \
  --quality preview \
  --out-dir /private/tmp/bh_exposure_hdr_diag_validation
```
