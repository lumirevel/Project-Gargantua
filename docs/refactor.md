# Refactor Workflow

## Scope
This document defines behavior-preserving refactor gates for the Swift + Metal renderer.

- Keep `run_pipeline.sh` CLI behavior unchanged.
- Validate output parity before/after structural changes.
- Track performance using a fixed benchmark profile.

## Phase 0: Baseline Harness

### Baseline Manifest
- File: `tests/baseline/manifest.json`
- Cases:
1. `fast_gpu_det`
2. `medium_gpu_perf` (performance anchor)
3. `visible_gpu`

### Capture Baseline
```bash
python3 Blackhole/scripts/baseline_capture.py
```

Artifacts generated:
- Golden images: `tests/baseline/golden/*.png`
- Logs + run artifacts: `tests/baseline/reports/runs/`
- Consolidated report: `tests/baseline/reports/baseline_report.json`

### Verify Current Build Against Baseline
```bash
python3 Blackhole/scripts/baseline_verify.py --json-out tests/baseline/reports/verify_report.json
```

### Verify Extended Coverage
```bash
python3 Blackhole/scripts/baseline_verify.py \
  --manifest tests/baseline/extended_manifest.json \
  --baseline-report tests/baseline/reports/extended_baseline_report.json \
  --json-out tests/baseline/reports/extended_verify_report.json
```

Pass rules:
- Deterministic outputs: exact SHA-256 match.
- Non-deterministic outputs: `max_abs_diff <= 2`, `PSNR >= 60 dB`, size delta within ±1%.
- Performance gate (`medium_gpu_perf`): mean wall-time must be within +3% of baseline mean (`warmup=1`, `measured=5`).

ABI guard:
```bash
/tmp/BlackholeDD_refactor_phase2/Build/Products/Release/Blackhole --validate-packed-abi
```

## Phase 1: Swift Modularization

Current modular split under `Blackhole/Sources/`:
- `App/`: CLI, app entry, user-facing errors
- `Core/ABI/`: packed GPU ABI types
- `Core/Config/`: logical and resolved render config
- `Core/Math/`: shared scalar/vector helpers
- `Core/Physics/`: accretion model, visible spectrum, disk orbit policy
- `Diagnostics/`: regression helpers
- `Params/`: CLI/config/default resolution and `PackedParams` packing
- `Render/Core/`: runtime resources, outputs, setup, execution shell
- `Render/Planning/`: execution flags and trace/compose planning
- `Render/Trace/`: trace submission, traversal, tile completion
- `Render/Compose/`: legacy tiled compose, full-GPU compose, HDR intermediate compose
- `Render/Support/`: renderer facade, histogram/progress helpers

Entry point policy:
- `Blackhole/main.swift` remains a thin launcher only.

## Phase 2: Metal Split

`integral.metal` is an include aggregator and keeps kernel entry names unchanged:

- `Blackhole/Metal/gr_math.metal`
- `Blackhole/Metal/disk_models.metal`
- `Blackhole/Metal/volume_rt.metal`: entry points and trace orchestration
- `Blackhole/Metal/VolumeTransport/*.metal`: legacy, GRMHD, and commit helpers
- `Blackhole/Metal/Bundle/ray_bundle.metal`
- `Blackhole/Metal/Visible/bridge.metal`
- `Blackhole/Metal/spectrum_visible.metal`
- `Blackhole/Metal/post_compose.metal`: include wrapper
- `Blackhole/Metal/Compose/*.metalh`: compose helpers and kernels

The split is source-organization only. Current canonical wrapper routing uses GPU-only/full-compose paths, so old hash baselines can drift from earlier legacy/runtime-linear compose captures even when the visual delta is small.

## Phase 3: Model Interface Seam

Future accretion models are prepared behind a stable Swift interface:

- `Blackhole/Sources/Core/Physics/AccretionModel.swift`

Current runtime now resolves disk-policy defaults through model-specific policy objects while preserving legacy output.

## Coverage Notes
- `manifest.json`
  - protects the default GPU-only path, perf anchor, and visible GRMHD baseline
- `extended_manifest.json`
  - exercises precision/thin surface behavior
  - thick disk routing
  - atlas-driven disk ingestion
  - volume-enabled precision path
  - ray-bundle/jacobian path
  - expressive visible policy
