# Physics Realism V1 Plan

## 1. Current Physical Realism Map

### Black hole physics ownership

- `Blackhole/Metal/gr_math.metal`
  - Shared Metal `Params` ABI.
  - Schwarzschild and equatorial Kerr geodesic acceleration helpers.
  - Collision payload definitions.
- `Blackhole/Metal/disk_models.metal`
  - Horizon and ISCO-derived disk radii.
  - Disk half-thickness.
  - Thin/precision disk temperature, emissivity, turbulence, cloud, and atmosphere helpers.
- `Blackhole/Metal/volume_rt.metal`
  - Ray tracing entry points.
  - Disk hit logic.
  - Volume accumulation state.
  - GRMHD and precision-volume physical transfer dispatch.
- `Blackhole/Metal/VolumeTransport/`
  - GRMHD/volume transport state sampling, local emissivity/absorptivity, optical-depth accumulation, and collision commit.
- `Blackhole/Metal/Visible/bridge.metal`
  - Visible-spectrum bridge from physical collision data to XYZ radiance for trace/bundle paths.
- `Blackhole/Sources/Core/Physics/`
  - Swift-side physical helpers such as visible spectrum, disk orbit, and accretion model policy.
- `Blackhole/Sources/Render/Trace/`
  - Trace pass orchestration and tile submission.

### Disk emission and radiative transfer ownership

- `Blackhole/Metal/disk_models.metal`
  - Disk source geometry and local thermal structure.
- `Blackhole/Metal/spectrum_visible.metal`
  - Visible spectral integration helpers.
- `Blackhole/Metal/volume_rt.metal`
  - Volumetric source and transfer accumulation.
- `Blackhole/Metal/VolumeTransport/commit.metal`
  - Commits physical volume accumulators into collision records for later compose/diagnostic use.
- `Blackhole/Sources/Params/ParamsBuilderVisible.swift`
  - Visible source model configuration.
- `Blackhole/Sources/Params/ParamsBuilderDiskVolume.swift`
  - Disk volume resource selection and metadata.
- `Blackhole/scripts/build_grmhd_volumes.py`, `Blackhole/scripts/build_thin_photosphere_volume.py`, `Blackhole/scripts/build_hdf5_volume.py`
  - Physical volume/source preparation.

### Diagnostics ownership

- `Blackhole/Sources/Params/ParamsBuilderPolicy.swift`
  - Maps `--disk-grmhd-debug` names to debug IDs.
- `Blackhole/run_pipeline.sh`
  - Public diagnostic option validation and aliases.
- `Blackhole/Metal/VolumeTransport/commit.metal`
  - Stores physics diagnostic scalars into collision payload fields.
- `Blackhole/Metal/Compose/helpers.metalh`
  - Converts physical diagnostic scalars into debug-display maps.
- `Blackhole/Sources/Render/Core/RenderOutputs.swift`
  - Metadata describing render/debug outputs and bridge fields.
- `docs/realism/05_debug_outputs.md`
  - Expected debug-output naming and branch ownership rules.

## 2. Current Suspected Realism Bottlenecks From Code Inspection

- Disk thickness: physical thickness is mode-dependent. Thin/reference paths exist, but precision/thick paths can expand vertical thickness and may visually flatten structure when optical depth is high.
- Disk smoothness: canonical visible paths already include disk-coordinate heating/structure, but several branches deliberately smooth Perlin/procedural texture. GRMHD paths depend heavily on source volume quality and residual structure.
- Disk uniformity: the visible GRMHD/temperature-volume path has many branch diagnostics, suggesting the main risk is source-function and opacity balance rather than display response.
- Contrast destruction: optical depth can physically hide interior structure. The code has both narrow and wide tau/alpha diagnostics, but users need to inspect these before judging beauty output.
- Optical depth inspectability: available through `--disk-grmhd-debug tau`, `tau-wide`, `tau1-r`, `tau1-depth`, `thermal-alpha-pre`, and `thermal-alpha-post` for GRMHD/precision-volume paths.
- Raw radiance inspectability: available through `raw-log` and linear XYZ/spectral packed paths, but the render-contract term `raw-radiance` was not accepted as a debug spelling before this work.
- Redshift / Doppler inspectability: available through `g` and `beaming` debug views.
- Source-location inspectability: emission-weighted radius and tau=1 radius are available; full source-location images remain partly overloaded through existing collision fields.

## 3. Render Contract Implications

### Fields this branch can produce or improve

- `raw_radiance`
- `optical_depth`
- `redshift` / `g-factor`
- `hit_mask`
- `emission_radius_or_source_proxy`
- physical source/transfer debug scalars

### Fields already available

- Raw radiance proxy via `raw-log`.
- Optical depth via `tau`, `tau-wide`, and related alpha/tau diagnostics.
- Redshift/g-factor via `g`.
- Doppler/beaming via `beaming`.
- Emission radius via `emission-radius`.
- Source function via `source`, `source-thermal`, and `source-thin`.
- Path/impact diagnostics via `path` and `impact`.

### Fields missing or incomplete

- Explicit multi-field render-contract buffers for raw radiance, depth, hit mask, optical depth, g-factor, and source radius.
- Full source-location images for all source modes without overloading collision fields.
- Uniform diagnostics across thin, precision-volume, GRMHD, and visible-spectrum modes.

### Fields requiring later integration

- Stable explicit physics-to-interpreter buffers.
- Multi-layer radiance/depth buffers for stronger camera depth-of-field interpretation.
- Presentation diagnostics such as tone-mapped-no-bloom, bloom-only, and exposure debug output belong on the interpreter branch or integration branch.

## 4. Proposed Changes Ranked By Safety

### Diagnostics-only changes

- Add contract-name aliases such as `raw-radiance` for existing raw-log radiance debug.
- Add explicit hit-mask diagnostic output.
- Document which existing debug views correspond to render-contract fields.
- Improve metadata labels for existing physical diagnostics.

### Low-risk physical improvements

- Improve optical-depth/source-function diagnostic scaling when current maps saturate.
- Preserve spatial contrast in raw radiance by auditing physical transfer weights and source branch ratios.
- Tighten emission-radius/source-location diagnostics without new ABI fields.

### Medium-risk physical changes

- Adjust thermal/cloud branch weighting in the physical transfer path.
- Tune thin photosphere layer weighting if diagnostics prove the current source is too optically thick or too smooth.
- Add a small source-layer option only if it reuses existing source architecture cleanly.

### High-risk changes to avoid for now

- Broad geodesic or metric rewrites.
- New packed Metal buffer layouts or collision payload layouts.
- Many new public runtime options.
- Any final-RGB, tone mapping, bloom, exposure, camera, or sensor changes.

## 5. First Implementation Target

First target: improve physical diagnostics by exposing render-contract-aligned debug names and an explicit hit mask.

This is small and physically interpretable because it does not alter radiance, geometry, opacity, transfer, exposure, tone mapping, bloom, or camera behavior. It makes the physical contract easier to inspect:

- `--disk-grmhd-debug raw-radiance` aliases the existing raw radiance/log-intensity map.
- `--disk-grmhd-debug hit-mask` produces a direct white-on-hit, black-on-miss physical hit classification map.

Validation should include Swift/Metal compilation, packed ABI validation, and at least one low-resolution debug render for `hit-mask` plus an existing physical diagnostic such as `raw-radiance` or `tau`.
