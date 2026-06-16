# CLI Option Cleanup V1

Date: 2026-05-02

Branch: `codex/integration/physics-camera-v1-legacy-recovery`

## Goal

Separate CLI documentation into public, advanced, and legacy layers while preserving the recovered legacy disk model compatibility layer.

## Help Layers

Public help:

```bash
./Blackhole/run_pipeline.sh --help
```

Public help now focuses on the recommended workflow:

- `--source-model`
- `--quality`
- `--width`
- `--height`
- `--output`
- `--presentation`
- `--look`
- `--exposure-mode`
- `--camera-f-number`
- `--camera-shutter`
- `--camera-iso`
- `--disk-grmhd-debug`

Topic help:

```bash
./Blackhole/run_pipeline.sh --help source-models
./Blackhole/run_pipeline.sh --help camera
./Blackhole/run_pipeline.sh --help grmhd
./Blackhole/run_pipeline.sh --help legacy
./Blackhole/run_pipeline.sh --help advanced
```

## Public / Advanced / Legacy Criteria

Public:

- Recommended high-level workflows.
- Source/presentation controls needed by normal users.
- Minimal diagnostics that define the physics/interpreter boundary.

Advanced:

- Low-level geometry, Kerr, disk physics, bridge, runtime, debug, and data IO controls.
- Options useful for development or validation but too noisy for public help.

Legacy:

- Reproduction and compatibility paths.
- Legacy disk procedural models.
- Deprecated `--science-regime` experiments and old DNGR/Interstellar/plausible aliases.

## Restored Legacy Models

The legacy recovery pass restored distinct behavior for:

- `--disk-model perlin`
- `--disk-model perlin-classic`
- `--disk-model perlin-ec7`

Intentional aliases:

- `flow`, `procedural`, `legacy`, `noise` -> flow model.
- `perlin-f552` -> `perlin-classic`.
- `perlin-legacy` -> `perlin-ec7`.

## Source-Model Relationship

`--source-model` is the recommended high-level workflow selector.

`--disk-model` is a low-level legacy/procedural selector. It remains supported for reproduction, regression, and comparison.

Implementation rule:

- Source-model defaults use `append_swift_default`.
- Explicit user-provided `--disk-model` remains present in `SWIFT_ARGS`.
- Therefore source-model defaults do not overwrite an explicit disk model.
- Conflicting `--disk-source` and explicit `--disk-model` values still produce an explicit error.

## Deprecated But Supported Aliases

Kept for reproduction:

- `--science-regime <old-name> --experimental`
- `dngr-thin`, `interstellar-thin`, `gargantua-thin`
- `dngr-flow`, `interstellar-flow`, `photosphere-flow`
- `dngr-volume`, `interstellar-volume`, `photosphere-volume`
- `plausible-disk-v1`, `thin-plausible-disk`
- `perlin-f552`, `perlin-legacy`

These are not recommended public source models.

## Validation

Required commands:

```bash
bash -n Blackhole/run_pipeline.sh
./Blackhole/run_pipeline.sh --help
./Blackhole/run_pipeline.sh --help legacy
./Blackhole/run_pipeline.sh --help source-models
./Blackhole/run_pipeline.sh --help camera
./Blackhole/run_pipeline.sh --help grmhd
python3 scripts/validate_cli_surface.py
python3 scripts/validate_legacy_disk_models.py
xcodebuild -project Blackhole.xcodeproj -scheme Blackhole -configuration Release -derivedDataPath /private/tmp/ProjectGargantuaCliCleanupDerivedData build
/private/tmp/ProjectGargantuaCliCleanupDerivedData/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout
```

Validation results should be appended after execution.

Executed results:

- `bash -n Blackhole/run_pipeline.sh`: passed.
- `./Blackhole/run_pipeline.sh --help`: passed, public help remains recommendation-focused.
- `./Blackhole/run_pipeline.sh --help legacy`: passed, restored legacy models are documented.
- `./Blackhole/run_pipeline.sh --help source-models`: passed, recommended source-model registry is documented.
- `./Blackhole/run_pipeline.sh --help camera`: passed, interpreter/camera controls are documented separately.
- `./Blackhole/run_pipeline.sh --help grmhd`: passed, GRMHD physics diagnostics are documented separately.
- `python3 scripts/validate_cli_surface.py`: passed.
- `python3 scripts/validate_legacy_disk_models.py`: passed using `/private/tmp/bh_legacy_disk_model_validation_cli_cleanup`.
- Xcode Release build: passed using `/private/tmp/ProjectGargantuaCliCleanupDerivedData`.
- Packed ABI validation: passed.

Legacy model validation confirmed:

- `flow`, `procedural`, and `noise` remain intentional aliases.
- `perlin`, `perlin-classic`, and `perlin-ec7` remain distinct.
- `perlin` vs `perlin-classic`: MAE `0.009153`, RMSE `0.038969`.
- `perlin` vs `perlin-ec7`: MAE `0.006993`, RMSE `0.031979`.
- `perlin-classic` vs `perlin-ec7`: MAE `0.007467`, RMSE `0.033156`.

## Future Option Rules

1. Add new commonly recommended workflows to public help only if they are stable and documented.
2. Add source model explanations under `--help source-models`.
3. Add camera/sensor/post controls under `--help camera`.
4. Add GRMHD physical diagnostics under `--help grmhd`.
5. Add old or compatibility aliases under `--help legacy`, not public help.
6. Add low-level runtime/data bridge controls under `--help advanced`.
7. Keep source physics and interpreter/camera responsibilities separate in help text.
