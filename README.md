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
