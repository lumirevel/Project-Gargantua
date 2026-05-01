# Integration Report: Physics + Camera V1

Date: 2026-05-01

Branch: `codex/integration/physics-camera-v1`

## Merge Order

1. `origin/codex/physics-realism-v1` at `4556f88`
2. `origin/codex/interpreter-camera-v1` at `180435d`

Base lineage: `codex/realism-rendering`

## Conflict List

### `Blackhole/run_pipeline.sh`

Two conflict regions were resolved:

- CLI help text for Swift-only options.
- Runtime argument forwarding list.

Resolution principle:

- Preserve physics-owned options from `physics-realism-v1`:
  - `--disk-grmhd-debug optical_depth`
  - `--disk-grmhd-debug transfer-saturation`
  - `--disk-grmhd-debug emissivity-pre-transfer`
  - GRMHD branch isolation and smooth/cloud emission controls.
- Preserve interpreter/camera-owned options from `interpreter-camera-v1`:
  - `--look sensor-filmic`
  - `--exposure-mode photographic`
  - `--camera-f-number`
  - `--camera-iso`
  - `--camera-shutter`
  - camera focus, DOF, aperture blade, flare/noise controls.

No physics transfer/source logic conflicts were encountered.

## Ownership Preservation

Physics-owned changes preserved:

- GRMHD diagnostic aliases remained visible in `run_pipeline.sh --help`.
- Packed ABI fields for GRMHD branch isolation and smooth weighting remained intact:
  - `PackedParams.offset grmhdBranchIsolationMode=596`
  - `PackedParams.offset grmhdSmoothWeightMode=612`
- Source/transfer debug aliases parsed successfully:
  - `optical_depth`
  - `transfer-saturation`
  - `emissivity-pre-transfer`

Interpreter/camera-owned changes preserved:

- `sensor-filmic` look parsed successfully.
- `photographic` exposure mode parsed successfully.
- Photographic camera controls parsed and were recorded in exposure debug JSON:
  - `cameraFNumber`
  - `cameraShutterSeconds`
  - `cameraISO`
  - `photographicExposureScale`
- Stage diagnostic outputs were generated:
  - `raw_interpreter_input`
  - `tone_mapped_no_bloom`
  - `bloom_only`
  - `final_rgb`

## ABI Layout Results

After the physics merge:

- `PackedParams.layout size=616 stride=624 align=16`
- `CollisionInfo.layout size=64 stride=64 align=16`
- `CollisionLite32.layout size=32 stride=32 align=16`
- `ComposeParams.layout size=304 stride=304 align=16`

After the camera merge:

- `PackedParams.layout size=616 stride=624 align=16`
- `CollisionInfo.layout size=64 stride=64 align=16`
- `CollisionLite32.layout size=32 stride=32 align=16`
- `ComposeParams.layout size=320 stride=320 align=16`
- `ComposeSolveParams.layout size=32 stride=32 align=4`
- `ComposeSolveResult.layout size=32 stride=32 align=4`

Interpretation:

- `PackedParams` stayed stable across the camera merge.
- `ComposeParams` grew from `304` to `320` bytes due to interpreter/camera parameters and passed runtime ABI validation.

## Validation Commands And Results

Syntax and script validation:

```bash
bash -n Blackhole/run_pipeline.sh
python3 -m py_compile scripts/render_interpreter_stage_diagnostics.py scripts/validate_presentation_on_rt_scene.py
git diff --cached --check
```

Result: passed.

Build:

```bash
xcodebuild -project Blackhole.xcodeproj -scheme Blackhole -configuration Release -derivedDataPath /private/tmp/ProjectGargantuaIntegrationDerivedData build
```

Result: passed with existing duplicate xrOS simulator/runtime warnings.

ABI validation:

```bash
/private/tmp/ProjectGargantuaIntegrationDerivedData/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout --disk-mode grmhd --disk-grmhd-debug optical_depth
/private/tmp/ProjectGargantuaIntegrationDerivedData/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout --disk-mode grmhd --disk-grmhd-debug transfer-saturation
/private/tmp/ProjectGargantuaIntegrationDerivedData/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout --disk-mode grmhd --disk-grmhd-debug emissivity-pre-transfer
/private/tmp/ProjectGargantuaIntegrationDerivedData/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout --look sensor-filmic --exposure-mode photographic --camera-f-number 2.8 --camera-shutter 1/60 --camera-iso 100
```

Result: passed.

CLI surface check:

```bash
./Blackhole/run_pipeline.sh --help | rg "sensor-filmic|photographic|camera-iso|camera-shutter|optical_depth|transfer-saturation|emissivity-pre-transfer"
```

Result: passed.

Interpreter stage diagnostics:

```bash
BH_DERIVED_DATA_PATH=/private/tmp/ProjectGargantuaIntegrationDerivedData \
BH_ETA_HISTORY=/private/tmp/bh_integration_stage_diag_eta.json \
python3 scripts/render_interpreter_stage_diagnostics.py \
  --source-model canonical-visible-disk-v1 \
  --presentation cinema \
  --look sensor-filmic \
  --width 64 \
  --height 40 \
  --quality preview \
  --out-dir /private/tmp/bh_integration_stage_diag \
  --extra --exposure-mode photographic --camera-f-number 2.8 --camera-shutter 1/60 --camera-iso 100
```

Result: passed.

Key outputs:

- `/private/tmp/bh_integration_stage_diag/raw_interpreter_input.png`
- `/private/tmp/bh_integration_stage_diag/tone_mapped_no_bloom.png`
- `/private/tmp/bh_integration_stage_diag/bloom_only.png`
- `/private/tmp/bh_integration_stage_diag/final_rgb.png`
- `/private/tmp/bh_integration_stage_diag/interpreter_stage_sheet.png`
- `/private/tmp/bh_integration_stage_diag/interpreter_stage_metrics.json`

Stage diagnostic metrics:

- `final_luma_mean=0.3599140644`
- `tone_mapped_no_bloom_luma_mean=0.0670387521`
- `positive_delta_luma_mean=0.2930094898`
- `positive_delta_coverage_gt_0_01=0.48828125`
- `negative_delta_luma_mean=0.0001341709`

Room RT presentation validation:

```bash
BH_DERIVED_DATA_PATH=/private/tmp/ProjectGargantuaIntegrationDerivedData \
BH_ETA_HISTORY=/private/tmp/bh_integration_room_rt_eta.json \
python3 scripts/validate_presentation_on_rt_scene.py \
  --gpu-room-rt \
  --out-dir /private/tmp/bh_integration_room_rt \
  --width 160 \
  --height 90 \
  --spp 1 \
  --bokeh-targets \
  --color-chart \
  --focus-depth 4.55 \
  --f-number 1.4 \
  --dof-strength 1.8 \
  --aperture-blades 6 \
  --lens-reference-spp 4
```

Result: passed.

Key outputs:

- `/private/tmp/bh_integration_room_rt/rt_room_scientific.png`
- `/private/tmp/bh_integration_room_rt/rt_room_eye.png`
- `/private/tmp/bh_integration_room_rt/rt_room_cinema.png`
- `/private/tmp/bh_integration_room_rt/rt_room_thin_lens_reference_cinema.png`
- `/private/tmp/bh_integration_room_rt/rt_room_presentation_sheet.png`
- `/private/tmp/bh_integration_room_rt/metrics.json`

Room RT metrics:

- scientific mean luma: `0.3805959523`
- eye mean luma: `0.6129916906`
- cinema mean luma: `0.5623334050`
- eye luma correlation vs scientific: `0.9729072819`
- cinema luma correlation vs scientific: `0.9665544772`
- cinema luma correlation vs thin lens reference: `0.9880013680`

## Failed Or Incomplete Validation

- A tiny physics debug smoke render using `--disk-grmhd-debug optical_depth` was started after the physics merge but did not complete promptly and was terminated. This remains an incomplete render validation.
- The integration validates debug alias parsing and ABI layout, but it does not yet prove full GRMHD diagnostic image generation for all requested modes.
- No large GRMHD HDF5 asset render was run in this integration pass.

## Generated Output Safety

Generated images, HDR buffers, metrics, and temporary render outputs were written only under `/private/tmp`.

No generated PNG, EXR, HDR, `linear32f32`, DerivedData, build product, or log output should be staged or committed.

## Promotion Decision

Recommendation: do not promote automatically to `codex/realism-rendering` yet.

Reason:

- Build, ABI, CLI, compose-stage diagnostics, photographic metadata, and room RT presentation validation passed.
- However, full physics smoke rendering for GRMHD diagnostics remains incomplete due to the small optical-depth smoke render hang.

This integration branch is suitable for review and targeted follow-up validation, but promotion should wait until GRMHD debug smoke renders complete reliably.

## Required Follow-Up Before Promotion

1. Run a bounded-time GRMHD diagnostic smoke matrix for:
   - `--disk-grmhd-debug optical_depth`
   - `--disk-grmhd-debug transfer-saturation`
   - `--disk-grmhd-debug emissivity-pre-transfer`
2. Confirm stage diagnostics with a black-hole render at a practical preview resolution.
3. Confirm no camera/post-processing effects are applied to physics diagnostic outputs.
4. Re-run `git diff --check`, Release build, and ABI validation immediately before promotion.
