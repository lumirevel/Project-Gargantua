# Interpreter Diagnostics Notes

Branch: `codex/interpreter-camera-v1`

## Diagnostic Stage Improved

This pass adds a small validation harness for stage-named interpreter outputs:

- `raw_interpreter_input`
- `tone_mapped_no_bloom`
- `bloom_only`
- `final_rgb`

It does not change the renderer's default final image path. It uses existing interpreter controls to disable PSF/glare/flare/DOF/noise for the no-bloom stage, then derives a display-space bloom/glare proxy from the difference between final and no-bloom images.

## Stages Currently Available

- `final_rgb`: normal renderer output from the requested presentation mode.
- `exposure_debug`: `<output>.exposure_debug.json`, written by compose paths after exposure solve.
- `raw interpreter input preview`: available through scientific/linear presentation, `--compose-hdr-in`, HDR32 intermediates, or `--realism-debug hdr` where supported.

## Stages Added Or Clarified

- `tone_mapped_no_bloom`: rendered by `scripts/render_interpreter_stage_diagnostics.py` with the requested presentation while forcing:
  - `--camera-psf-sigma 0`
  - `--camera-flare 0`
  - `--camera-dof-strength 0`
  - `--camera-read-noise 0`
  - `--camera-shot-noise 0`
- `bloom_only`: a diagnostic display-space positive delta:
  - `max(final_rgb - tone_mapped_no_bloom, 0) * bloom_scale`
  - This is not a physical additive radiance buffer. It is a proxy for inspecting where optics/post effects add visible display energy.
- `raw_interpreter_input`: generated as a scientific/linear preview. For black-hole source renders, the script requests `--realism-debug hdr`; for `--compose-hdr-in`, it uses the external HDR32 input through scientific/linear presentation.

## Files Changed

- `scripts/render_interpreter_stage_diagnostics.py`
- `docs/realism/interpreter_diagnostics_notes.md`

## How To Inspect Outputs

Example black-hole source diagnostic:

```bash
python3 scripts/render_interpreter_stage_diagnostics.py \
  --source-model canonical-visible-disk-v1 \
  --presentation cinema \
  --width 384 \
  --height 216 \
  --out-dir /private/tmp/bh_interpreter_stage_diagnostics
```

Example external HDR32 interpreter-only diagnostic:

```bash
python3 scripts/render_interpreter_stage_diagnostics.py \
  --compose-hdr-in /path/to/input.linear32f32 \
  --presentation eye \
  --width 420 \
  --height 240 \
  --out-dir /private/tmp/bh_interpreter_stage_diagnostics_hdr
```

Generated files:

- `raw_interpreter_input.png`
- `tone_mapped_no_bloom.png`
- `bloom_only.png`
- `final_rgb.png`
- `interpreter_stage_sheet.png`
- `interpreter_stage_metrics.json`
- per-render `*.exposure_debug.json` files from the renderer

Generated images and metrics should stay outside the repository, normally under `/private/tmp`.

## Safe For Final Rendering

- `final_rgb` is the only normal final-render output.
- `exposure_debug` JSON is safe metadata for diagnosis, not a beauty output.

## Diagnostic Only

- `raw_interpreter_input` is a preview of the interpreter input, not a display-approved final.
- `tone_mapped_no_bloom` is a controlled diagnostic render with optics/post effects disabled.
- `bloom_only` is a display-space proxy, not a physical bloom buffer.
- `interpreter_stage_sheet` and `interpreter_stage_metrics.json` are validation artifacts.

## Next Step Needed For True Same-Render Stage Buffers

The script separates stages through repeated renders and display-space subtraction. A future same-render implementation should add explicit stage outputs after reviewing memory growth and GPU synchronization cost:

1. raw/HDR32 interpreter input
2. tone-mapped-no-bloom display buffer
3. bloom/glare-only display or radiance buffer
4. final RGB

That follow-up should avoid packed ABI changes unless the render contract is reviewed.
