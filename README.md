# Blackhole Renderer

## Current Layout

- `Blackhole/main.swift`: Swift entry point (GPU collision render)
- `Blackhole/integral.metal`: Metal shader
- `Blackhole/run_pipeline.sh`: main pipeline script (build + render + postprocess)
- `Blackhole/render_collisions.py`: Python postprocess (HDR + tone map + PNG/PPM)
- `run_pipeline.sh`: root wrapper that calls `Blackhole/run_pipeline.sh`

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
