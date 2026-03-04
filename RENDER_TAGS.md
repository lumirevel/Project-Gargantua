# Blackhole Render Tags

## Goal
- `main.swift` and `testGPU.py` share settings through metadata (`<output>.json`).
- Default output is `dense_pruned_v1`: no precision loss (`float32` kept), only unused fields/padding removed.

## Accuracy Policy
- `dense_v1`: full raw struct dump (largest file).
- `dense_pruned_v1` (default): keeps per-pixel `hit`, `T`, `v_disk(3)`, `direct_world(3)`, `noise` in `float32`.
- `sparse_v1`: hit-only records (smallest, but non-uniform indexing).

`dense_pruned_v1` is the recommended mode when you want exact numeric behavior without huge padding/unused data.

## `main.swift` Tags
- `--preset balanced|interstellar|eht`
  - base camera/disk preset.
- `--width <int>` image width.
- `--height <int>` image height.
- `--tileHeight <int>` GPU tile rows per dispatch.
- `--camX <float>` camera x in units of `rs`.
- `--camZ <float>` camera z in units of `rs`.
- `--fov <float>` field of view in degrees.
- `--rcp <float>` disk outer radius multiplier (`re = rcp * rs`).
- `--diskH <float>` disk half-thickness factor (`he = diskH * rs`).
- `--maxSteps <int>` geodesic integration steps.
- `--h <float>` RK4 step size (default `0.01`).
- `--format pruned|dense|sparse`
  - `pruned` -> `dense_pruned_v1` (default)
  - `dense` -> `dense_v1`
  - `sparse` -> `sparse_v1`
- `--metric schwarzschild|kerr`
  - `kerr` = Kerr exact (Boyer-Lindquist geodesic).
  - `schwarzschild` = original Schwarzschild solver path.
  - `kerr --spin 0` runs the Kerr solver at zero spin (used for parity checks vs Schwarzschild).
- `--spin <float>`
  - Kerr dimensionless spin `a*` in `[0, 0.998]`.
- `--disk-time <float>`
  - streamline particle phase/time for disk advection.
- `--disk-orbital-boost <float>`
  - scales Keplerian angular flow in disk density model.
- `--disk-radial-drift <float>`
  - inward radial drift strength of disk flow.
- `--disk-turbulence <float>`
  - divergence-free turbulence strength for disk clumping.
- `--disk-flow-step <float>`
  - streamline backtrace step size for disk density evaluation.
- `--disk-flow-steps <int>`
  - streamline backtrace step count (higher = slower, more accurate).
- `--disk-atlas <path>`
  - stage-3 disk atlas binary (`float4`) path.
- `--disk-atlas-width <int>`
  - atlas width override if `<atlas>.json` is missing.
- `--disk-atlas-height <int>`
  - atlas height override if `<atlas>.json` is missing.
- `--disk-atlas-temp-scale <float>`
  - global multiplier for atlas temperature channel.
- `--disk-atlas-density-blend <float>`
  - blend factor between procedural density and atlas density.
- `--disk-atlas-vr-scale <float>`
  - scale for atlas radial-velocity ratio.
- `--disk-atlas-vphi-scale <float>`
  - scale for atlas azimuthal velocity factor.
- `--output <path>` collisions output path.

Legacy:
- `--dense` is kept as alias for `--format dense`.

Outputs:
- collisions file: `<output>`
- metadata JSON: `<output>.json`

Bridge fields for stage-3 handoff (`dense_pruned_v6`):
- collision record tail stores:
  - `emit_r_norm` (`r / rs`),
  - `emit_phi` (`atan2(y, x)`),
  - `emit_z_norm` (`z / rs`).
- metadata includes:
  - `bridgeCoordinateFrame`
  - `bridgeFields`

Disk atlas format:
- binary: row-major `height x width x 4` `float32`
- channels:
  - `0`: temperature scale
  - `1`: density
  - `2`: radial velocity ratio
  - `3`: azimuthal velocity scale

## `testGPU.py` Tags
- `--input <path>` collisions file path.
- `--meta <path>` optional metadata override.
  - if omitted, auto-loads `<input>.json`.
- `--output <path>` output PPM path.
- `--width`, `--height`
  - optional if metadata exists.
- `--rcp <float>`
  - optional if metadata exists.
- `--look balanced|interstellar|eht`
  - tone/color look transform.
- `--spectral-step <float>`
  - spectral integration step in nm (smaller = slower, smoother).
- `--chunk <int>`
  - processing chunk size.
- `--exposure <float>`
  - `<0`: auto exposure, `>0`: manual exposure multiplier.
- `--dither <float>`
  - ordered dithering strength.
- `--inner-edge-mult <float>`
  - ISCO/inner-edge shaping factor.

Format detection:
- prefers metadata `format`.
- auto-detect fallback by file size supports:
  - `dense_v1`
  - `dense_pruned_v1`
  - `sparse_v1`

## Recommended Runs

### Interstellar-like
```bash
# 1) GPU simulation
<run-main> --preset interstellar --metric kerr --spin 0.92 --format pruned --width 1200 --height 1200 \
  --output /Users/kimryeong-gyo/PycharmProjects/blackhole/collisions_interstellar.bin

# 2) Post-process
python3 /Users/kimryeong-gyo/PycharmProjects/blackhole/testGPU.py \
  --input /Users/kimryeong-gyo/PycharmProjects/blackhole/collisions_interstellar.bin \
  --look interstellar \
  --output /Users/kimryeong-gyo/PycharmProjects/blackhole/interstellar.ppm
```

### EHT-like
```bash
# 1) GPU simulation
<run-main> --preset eht --metric kerr --spin 0.94 --format pruned --width 1200 --height 1200 \
  --output /Users/kimryeong-gyo/PycharmProjects/blackhole/collisions_eht.bin

# 2) Post-process
python3 /Users/kimryeong-gyo/PycharmProjects/blackhole/testGPU.py \
  --input /Users/kimryeong-gyo/PycharmProjects/blackhole/collisions_eht.bin \
  --look eht \
  --output /Users/kimryeong-gyo/PycharmProjects/blackhole/eht.ppm
```

## Troubleshooting
- If you see `warning: collisions.bin noise is all zero`, your input was generated by an older kernel or noise path was not active.
- If side-entry still looks missing, re-run `main.swift` after rebuilding with the latest `integral.metal`.
- Kerr exact mode is slower than Schwarzschild because it solves full Kerr null geodesic equations in BL coordinates.
