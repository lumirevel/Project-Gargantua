# Legacy Disk Model Recovery V1

Date: 2026-05-02

Branch: `codex/integration/physics-camera-v1-legacy-recovery`

## Goal

Recover distinct legacy disk model behavior for the old `--disk-model` family while keeping the newer `--source-model`, `realism-profile`, physics, and interpreter/camera integration intact.

## Historical Cause

The collapse started in commit:

```text
34aee18 Keep perlin path legacy
```

That commit changed:

- `Blackhole/run_pipeline.sh`: `canonical_disk_model(perlin)` from `perlin` to `perlin-ec7`.
- `Blackhole/Sources/Params/ParamsBuilderPolicy.swift`: `resolveDiskModel("perlin")` from `perlin` to `perlin-ec7`.

This made explicit `--disk-model perlin` resolve to the same model as `--disk-model perlin-ec7`, so the soft Perlin model path with `diskNoiseModel == 1` was no longer reachable through the normal CLI.

## Model Semantics

Recovered distinct models:

- `perlin`: soft Perlin/cloud model, `diskNoiseModel == 1`.
- `perlin-ec7`: crisp legacy EC7 Perlin texture, `diskNoiseModel == 2`.
- `perlin-classic`: classic/F552 stripe model, `diskNoiseModel == 3`.

Intentional aliases left in place:

- `flow`, `procedural`, `legacy`, and `noise` remain aliases for the streamline/flow disk model.
- `perlin-f552` remains an alias of `perlin-classic`.
- `perlin-legacy` remains an alias of `perlin-ec7`.
- `auto` remains context-dependent and usually resolves to `flow` unless an atlas is explicitly relevant.

## Current Source-Model Relationship

The recommended public source model remains `canonical-visible-disk-v1`.

This recovery does not make Perlin a recommended scientific source model. It restores legacy compatibility for explicit `--disk-model` and `--disk-source` use so old model families can be reproduced and compared without silently collapsing.

Source-model defaults still use `append_swift_default`, so an explicit user-provided `--disk-model` has precedence over defaults inserted by `--source-model` or `--science-regime`.

## Code Changes

Changed:

- `Blackhole/run_pipeline.sh`
  - `canonical_disk_model(perlin)` now returns `perlin`, not `perlin-ec7`.
- `Blackhole/Sources/Params/ParamsBuilderPolicy.swift`
  - `resolveDiskModel("perlin")` now resolves to `perlin`, not `perlin-ec7`.
- `scripts/validate_legacy_disk_models.py`
  - Added low-resolution regression validator for `flow`, `procedural`, `noise`, `perlin`, `perlin-classic`, and `perlin-ec7`.

Not changed:

- Physics/camera integration code paths.
- Packed Metal ABI.
- Modern canonical source model defaults.
- GRMHD transport/source logic.

## Validation Plan

Required commands:

```bash
bash -n Blackhole/run_pipeline.sh
xcodebuild -project Blackhole.xcodeproj -scheme Blackhole -configuration Release -derivedDataPath /private/tmp/ProjectGargantuaLegacyDiskModelsDerivedData build
/private/tmp/ProjectGargantuaLegacyDiskModelsDerivedData/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout
python3 scripts/validate_legacy_disk_models.py
```

Public render smoke commands:

```bash
bash Blackhole/run_pipeline.sh --disk-mode thin --disk-model perlin --presentation scientific --look linear --width 80 --height 45 --output /private/tmp/bh_legacy_disk_model_smoke/perlin.png
bash Blackhole/run_pipeline.sh --disk-mode thin --disk-model perlin-classic --presentation scientific --look linear --width 80 --height 45 --output /private/tmp/bh_legacy_disk_model_smoke/perlin-classic.png --no-build
bash Blackhole/run_pipeline.sh --disk-mode thin --disk-model perlin-ec7 --presentation scientific --look linear --width 80 --height 45 --output /private/tmp/bh_legacy_disk_model_smoke/perlin-ec7.png --no-build
bash Blackhole/run_pipeline.sh --disk-mode thin --disk-model flow --presentation scientific --look linear --width 80 --height 45 --output /private/tmp/bh_legacy_disk_model_smoke/flow.png --no-build
```

Validation results should be appended after running the commands.

## Validation Results

Completed commands:

```bash
bash -n Blackhole/run_pipeline.sh
python3 -m py_compile scripts/validate_legacy_disk_models.py
xcodebuild -project Blackhole.xcodeproj -scheme Blackhole -configuration Release -derivedDataPath /private/tmp/ProjectGargantuaLegacyDiskModelsDerivedData build
/private/tmp/ProjectGargantuaLegacyDiskModelsDerivedData/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout
BH_DERIVED_DATA_PATH=/private/tmp/ProjectGargantuaLegacyDiskModelsDerivedData python3 scripts/validate_legacy_disk_models.py --out-dir /private/tmp/bh_legacy_disk_model_validation --width 80 --height 45 --no-build
```

Results:

- Shell syntax: passed.
- Regression script syntax: passed.
- Xcode Release build: passed.
- Packed ABI validation: passed.
- Legacy model image differentiation: passed.

Observed ABI:

```text
PackedParams.layout size=616 stride=624 align=16
CollisionInfo.layout size=64 stride=64 align=16
CollisionLite32.layout size=32 stride=32 align=16
ComposeParams.layout size=320 stride=320 align=16
ComposeSolveParams.layout size=32 stride=32 align=4
ComposeSolveResult.layout size=32 stride=32 align=4
```

Regression outputs:

- `/private/tmp/bh_legacy_disk_model_validation/flow.png`
- `/private/tmp/bh_legacy_disk_model_validation/procedural.png`
- `/private/tmp/bh_legacy_disk_model_validation/noise.png`
- `/private/tmp/bh_legacy_disk_model_validation/perlin.png`
- `/private/tmp/bh_legacy_disk_model_validation/perlin-classic.png`
- `/private/tmp/bh_legacy_disk_model_validation/perlin-ec7.png`
- `/private/tmp/bh_legacy_disk_model_validation/metrics.json`

Key differentiation metrics:

| Pair | Intended alias | RMSE | MAE | Result |
| --- | --- | ---: | ---: | --- |
| `flow` vs `procedural` | yes | 0.000000 | 0.000000 | allowed identical |
| `flow` vs `noise` | yes | 0.000000 | 0.000000 | allowed identical |
| `perlin` vs `perlin-ec7` | no | 0.031979 | 0.006993 | distinct |
| `perlin` vs `perlin-classic` | no | 0.038969 | 0.009153 | distinct |
| `perlin-classic` vs `perlin-ec7` | no | 0.033156 | 0.007467 | distinct |
| `flow` vs `perlin` | no | 0.016612 | 0.003773 | distinct |
| `flow` vs `perlin-ec7` | no | 0.030570 | 0.006871 | distinct |

Thresholds:

- `min_rmse_distinct=0.003`
- `min_mae_distinct=0.0015`

All non-alias model pairs exceeded the thresholds and had distinct SHA-256 hashes.

## Remaining Risks

- The legacy Perlin family is for reproduction/regression, not the scientific canonical model.
- `flow`, `procedural`, and `noise` still intentionally alias to one model. If the project wants `noise` to become a separate historic shader, that needs a separate reconstruction pass.
- Precision and GRMHD modes still force non-flow disk models to `flow`, preserving the current source/volume architecture. Legacy Perlin should be tested with `--disk-mode thin`.
- Existing untracked generated exposure JSON files at repo root should not be committed.
