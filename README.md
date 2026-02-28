# Blackhole Renderer

## Current Layout

- `Blackhole/main.swift`: Swift entry point (GPU collision render)
- `Blackhole/integral.metal`: Metal shader
- `Blackhole/run_pipeline.sh`: main pipeline script (build + render + postprocess)
- `Blackhole/render_collisions.py`: Python postprocess (HDR + tone map + PNG/PPM)
- `run_pipeline.sh`: root wrapper that calls `Blackhole/run_pipeline.sh`
- `scripts/trace_ray_compare.py`: single-ray Schwarzschild vs Kerr trajectory comparison
- `scripts/select_lensed_pixels.py`: Schwarzschild collisions에서 상/하 대표 픽셀 자동 선택
- `scripts/analyze_kerr_gap.py`: 렌더/픽셀선정/레이추적/그래프/리포트 일괄 진단

## One-Command Render

```bash
./run_pipeline.sh
```

Output defaults:
- `collisions.bin`
- `collisions.bin.json`
- `blackhole_gpu.png`

## Common Options

```bash
./run_pipeline.sh --width 1200 --height 1200 --preset interstellar --output blackhole_gpu.png
```

Notes:
- `--output *.png|*.ppm` controls final image output.
- `--output *.bin` controls collisions output path.
- Use one line (or `\` line continuation). Do not put options on a separate line alone.

## Kerr Render

```bash
./run_pipeline.sh --metric kerr --spin 0.92 --preset interstellar --output blackhole_kerr.png
```

Kerr tuning options (Swift side):
- `--kerr-radial-scale`
- `--kerr-azimuth-scale`
- `--kerr-impact-scale`
- `--kerr-substeps`
- `--kerr-escape-mult`

Disk flow options (streamline particle model):
- `--disk-time` (phase-like animation time)
- `--disk-orbital-boost` (azimuthal flow scale)
- `--disk-radial-drift` (inward drift strength)
- `--disk-turbulence` (divergence-free turbulence strength)
- `--disk-flow-step` (streamline integration step size)
- `--disk-flow-steps` (streamline integration steps)

Example:
```bash
./run_pipeline.sh --metric kerr --spin 0.92 --preset interstellar --disk-time 0.35 --disk-orbital-boost 1.0 --disk-radial-drift 0.02 --disk-turbulence 0.3 --disk-flow-step 0.20 --disk-flow-steps 10 --output blackhole_kerr_flow.png
```

Stage-3 bridge note:
- collisions metadata now includes `bridgeFields` and sampled emission coordinates:
  `emit_r_norm`, `emit_phi`, `emit_z_norm` (stored in collision record tail).

## Single-Ray Comparison

```bash
python3 scripts/trace_ray_compare.py --preset interstellar --spin 0 --pixel-x 760 --pixel-y 640 --csv /tmp/ray_compare.csv
```

This prints per-ray hit/step stats and writes:
- pair csv (`--csv`)
- full state csv (`--full-state-csv`, default: `<csv>_full_state.csv`)
- analysis json (`--analysis-json`, default: `<csv>_analysis.json`)

## Kerr Gap Diagnosis

```bash
python3 scripts/analyze_kerr_gap.py --out-dir /tmp/kerr_diagnosis
```

Generated outputs:
- `/tmp/kerr_diagnosis/renders/*.bin|*.json|*.png`
- `/tmp/kerr_diagnosis/traces/*_pair.csv`
- `/tmp/kerr_diagnosis/traces/*_full_state.csv`
- `/tmp/kerr_diagnosis/traces/*_analysis.json`
- `/tmp/kerr_diagnosis/plots/*.png`
- `/tmp/kerr_diagnosis/report.md`

## Stage-3 Bridge Export

```bash
python3 scripts/export_stage3_bridge.py --input collisions.bin --meta collisions.bin.json --output collisions.stage3.npz
```

Optional CSV:
```bash
python3 scripts/export_stage3_bridge.py --input collisions.bin --csv collisions.stage3.csv
```

## Stage-3 Disk Atlas (Accuracy Mode)

Disk model selector:
- `--disk-model procedural`: force legacy/procedural disk
- `--disk-model perlin`: force classic Perlin texture disk (pre-streamline style)
- `--disk-model atlas`: force atlas disk (`--disk-atlas` required)
- `--disk-model auto`: use atlas only when `--disk-atlas` is provided (default)
- Atlas path auto-pick (`--disk-model atlas` + no `--disk-atlas`):
  - search order: `BH_DISK_ATLAS` -> `./disk_atlas.bin` -> `/tmp/stage3_ab/disk_atlas.bin`

Build atlas from bridge samples:
```bash
python3 scripts/build_disk_atlas.py --input collisions.stage3.npz --output disk_atlas.bin --width 1024 --height 512 --r-max 9.0 --r-warp 0.65
```

Render with atlas-driven disk model:
```bash
./run_pipeline.sh --metric kerr --spin 0.92 --preset interstellar --disk-atlas disk_atlas.bin --disk-atlas-temp-scale 1.0 --disk-atlas-density-blend 0.7 --disk-atlas-vr-scale 0.35 --disk-atlas-vphi-scale 1.0 --disk-atlas-r-min 1.0 --disk-atlas-r-max 9.0 --disk-atlas-r-warp 0.65 --output blackhole_stage3.png
```

Atlas channels (`float4`):
- `x`: temperature scale
- `y`: density (cloud/noise blending source)
- `z`: radial velocity ratio
- `w`: azimuthal velocity scale

Radial mapping:
- `--r-warp <value>` in atlas build and `--disk-atlas-r-warp <value>` in render must match.
- `< 1.0` allocates more radial bins near the inner ring (`r ~ rs`), `1.0` is linear.

## Stage-3 A/B Auto Report

Run no-atlas baseline vs atlas in one command and generate quality report:

```bash
python3 scripts/compare_stage3_ab.py --out-dir /tmp/stage3_ab --no-build --width 640 --height 640 --preset interstellar --metric kerr --spin 0.92 --atlas-r-warp 0.65
```

Pipeline shortcut (recommended):

```bash
./run_pipeline.sh stage3-ab --no-build --out-dir /tmp/stage3_ab --width 640 --height 640 --preset interstellar --metric kerr --spin 0.92 --atlas-r-warp 0.65
```

Outputs:
- `/tmp/stage3_ab/baseline_no_atlas.ppm`
- `/tmp/stage3_ab/atlas_stage3.ppm`
- `/tmp/stage3_ab/diff_abs_xgain.ppm`
- `/tmp/stage3_ab/report.json`
- `/tmp/stage3_ab/report.md`
