# Disk Physics Modes

This project keeps legacy behavior by default and adds optional physics-profile routing via:

```bash
--disk-physics {legacy|thin|thick|eht}
```

If `--disk-physics` is omitted, existing `--disk-mode ...` behavior is preserved.

## Mode Quick Start

### Recommended high-level regimes

Use `--science-regime` when the goal is a coherent physical/rendering
configuration rather than low-level option mixing:

```bash
# Visible/near-visible thin photosphere, minimal presentation.
./run_pipeline.sh --science-regime thin-visible --preset thin-disk --output out_thin_science.png

# Human-eye presentation derived from the thin visible model.
./run_pipeline.sh --science-regime experience --preset thin-disk --output out_eye.png

# DNGR/Interstellar-style reference track: physical thin disk + eye presentation.
./run_pipeline.sh --science-regime dngr-thin --preset interstellar --metric kerr --spin 0.92 --output out_dngr_eye.png

# Living photosphere track: same thermal disk, with disk-space flow structure
# before spectral integration.
./run_pipeline.sh --science-regime dngr-flow --preset interstellar --metric kerr --spin 0.92 --output out_dngr_flow_eye.png

# Experimental finite-optical-depth 3D photospheric bridge. This treats the disk
# as a thin participating medium rather than a mathematical surface. Without
# HDF5/GRMHD input it uses a documented deterministic surrogate volume.
./run_pipeline.sh --science-regime dngr-volume --preset interstellar --metric kerr --spin 0.92 --output out_dngr_volume_eye.png

# GRMHD-native structure diagnostic. Use this to inspect the 3D flow morphology;
# do not treat it as the final human-visible temperature-disk target.
./run_pipeline.sh --science-regime grmhd-structure-flow --disk-hdf5 snapshot.h5 --output out_grmhd_structure.png

# Equivalent lower-level alias.
./run_pipeline.sh --science-regime grmhd-hot-flow --disk-hdf5 snapshot.h5 --output out_grmhd_hot.png

# Human-visible temperature flow: 3D GRMHD state sampled in volume, local
# temperature estimated from the thermal disk + GRMHD heating proxies, and
# visible-band blackbody RT integrated in Metal.
./run_pipeline.sh --science-regime grmhd-temperature-flow --disk-hdf5 snapshot.h5 --output out_temperature_flow.png

# Diagnostic only: GRMHD visible photosphere approximation.
./run_pipeline.sh --science-regime grmhd-photosphere --disk-hdf5 snapshot.h5 --output out_grmhd_photo.png
```

The current recommendation is:

- `thin-visible` for the scientific visible thin-disk master.
- `experience` for the human-observer render of the physical thin-disk model.
- `dngr-thin` / `interstellar-thin` when the desired reference is the
  Interstellar/DNGR-style thin thermal disk geometry with eye presentation.
- `dngr-flow` / `interstellar-flow` when the same reference should include a
  scientifically constrained photosphere-flow layer.
- `dngr-volume` / `interstellar-volume` only as the current experimental bridge
  for finite-optical-depth 3D photosphere work.
- `grmhd-temperature-flow` for the current human-visible GRMHD thermal volume RT path.
- `grmhd-structure-flow` / `grmhd-hot-flow` for GRMHD-native structure diagnostics.
- `grmhd-photosphere` only to inspect the current visible-photosphere approximation.

GRMHD is the stronger model for plasma dynamics, but a hot, optically thin GRMHD
torus is not automatically the correct model for a visible/near-visible thin,
radiatively efficient photosphere. The regimes keep those assumptions explicit.

The DNGR/Interstellar-like target belongs on the thin thermal disk track, not on
the hot-flow diagnostic track. The movie reference is useful for lensing and
thin-disk image formation, but matching its presentation does not make GRMHD
code-unit plasma coloring physically calibrated.

`dngr-flow` does not composite a separate texture over the image. It modulates
the local thermal photosphere source through disk-space shear, optical depth, and
covering/source terms before visible-band blackbody integration. With a
GRMHD-derived atlas, those unresolved structures come from the imported flow
reduction; without one, the periodic shearing field is a controlled surrogate for
orbital flow structure and should not be mistaken for evolved GRMHD truth.

`dngr-volume` is the first volume bridge for the Interstellar/DNGR-like visible
track. It routes through precision-mode 3D volume transport and samples a
`float4(temp_scale, density, vr_ratio, vphi_scale)` volume along the ray. If
`--disk-volume` or `--disk-volume-hdf5` is supplied, that data is used. If no
volume source is provided, `run_pipeline.sh` builds a cached deterministic thin
photospheric volume with `Blackhole/scripts/build_thin_photosphere_volume.py`.
That fallback is a disk-space participating-medium surrogate, not evolved
GRMHD. It exists to test the correct rendering architecture: finite optical
depth, depth accumulation, temperature-scaled emission, relativistic g-factor,
and presentation separation.

Current limitation: the precision legacy volume path still compresses the
volume into a hit record before compose. This is useful for testing resource
flow and geodesic sampling, but it can make weak foreground gas read like an
opaque slab. The next required upgrade is a direct visible/spectral volume
radiance path analogous to the GRMHD visible volume integrator.

`grmhd-structure-flow` is the current recommended GRMHD structure-inspection
target, not the final visible temperature-disk target. It is an alias of
`grmhd-hot-flow` with scientific presentation and the
structure-preserving 9-band visible integration path. It treats the visible/NIR
synchrotron branch as an optically thin hot-electron diagnostic. The dense bulk
flow is not allowed to emit a large floor of nonthermal visible light; the branch
is gated by local magnetization, electron-temperature proxy, and a broad corona
envelope. This is still a code-unit prescription, but it preserves real GRMHD
structure better than the old full-column white silhouette.

For the current human-visible direction, use `grmhd-temperature-flow`: the 3D
GRMHD state is sampled along the geodesic, local temperature is estimated from
the thermal disk plus bounded GRMHD heating proxies, and visible-band blackbody
RT is integrated in the Metal volume loop. Dense hot gas is not treated as a
separate dark occluder; opacity and thermal re-emission share the same local
source function.

When using `grmhd-temperature-flow`, `--teff-T0` is the explicit visible
color-temperature anchor. If `--bh-mass` and `--mdot` are supplied and
`--teff-T0` is omitted, the renderer now computes that anchor from a thin-disk
flux estimate at `--teff-r0`. The geometry remains in dimensionless `r/rs`, so
the temperature calculation converts `r/rs` to the Schwarzschild radius of the
user-supplied `--bh-mass`.

`grmhd-photosphere` disables the cool absorber by default and uses a lower
visible opacity calibration. It remains a diagnostic approximation, not the
recommended human-visible thin-disk render.

For structured scientific checks across these regimes, use
`Blackhole/scripts/science_regime_diagnostics.py`. It audits GRMHD phi variation,
renders the recommended regimes side-by-side, and can run controlled structure,
frequency, and electron-model sweeps. See `docs/science_regime_diagnostics.md`.

### 1) Legacy (default compatibility)
```bash
./run_pipeline.sh --pipeline gpu-only --disk-mode thin --output out_legacy.png
```

### 2) Thin (Novikov–Thorne-ish surface profile)
```bash
./run_pipeline.sh --pipeline gpu-only --disk-physics thin \
  --mdot-edd 0.08 --eta 0.10 --fcol 1.6 \
  --output out_thin.png
```

### 3) Thick (puffed geometry + optional cloud attenuation)
```bash
./run_pipeline.sh --pipeline gpu-only --disk-physics thick \
  --thick-scale 1.5 --cloud-tau 1.2 --rt-steps 12 \
  --output out_thick.png
```

### 4) EHT-style RIAF (GRMHD volume RT path)
```bash
./run_pipeline.sh --pipeline gpu-only --disk-physics eht \
  --nu-obs-hz 230000000000 --rt-steps 16 \
  --output out_eht.png
```

## Visible Policy

`--visible-policy` controls how RIAF intensity is visualized in visible output:

- `physical` (default): keep physical visible-spectrum interpretation.
- `expressive`: map `nu_obs`-driven emissivity into visible palette for readability.

Example:
```bash
./run_pipeline.sh --pipeline gpu-only --disk-physics eht --visible-mode on \
  --visible-policy expressive --output out_eht_expressive.png
```
