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
python3 scripts/baseline_capture.py
```

Artifacts generated:
- Golden images: `tests/baseline/golden/*.png`
- Logs + run artifacts: `tests/baseline/reports/runs/`
- Consolidated report: `tests/baseline/reports/baseline_report.json`

### Verify Current Build Against Baseline
```bash
python3 scripts/baseline_verify.py --json-out tests/baseline/reports/verify_report.json
```

Pass rules:
- Deterministic outputs: exact SHA-256 match.
- Non-deterministic outputs: `max_abs_diff <= 2`, `PSNR >= 60 dB`, size delta within ±1%.
- Performance gate (`medium_gpu_perf`): mean wall-time must be within +3% of baseline mean (`warmup=1`, `measured=5`).

## Phase 1: Swift Modularization

Planned modular split under `Blackhole/Sources/`:
- `CLI.swift`
- `LogicalParams.swift`
- `PackedParams.swift`
- `ParamsBuilder.swift`
- `Resources.swift`
- `MetalPipelines.swift`
- `Renderer.swift`
- `Regression.swift`
- `AppMain.swift`

Entry point policy:
- `Blackhole/main.swift` remains a thin launcher only.
