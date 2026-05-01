# Physics Realism V1 Plan

This branch is `codex/physics-realism-v1`. Its scope is physical source and transfer realism only: metric, geodesics, disk/volume source state, emissivity, absorptivity, optical depth, redshift/Doppler, raw radiance, hit classification, and physical diagnostics. It must not solve realism with exposure, tone mapping, bloom, glare, lens flare, color grading, or camera/sensor changes.

## 1. Current Physical Pipeline Map

### Ray generation

- `Blackhole/Metal/volume_rt.metal`
  - `renderBH_core_simple` computes full-frame pixel coordinates and calls `trace_single_ray`.
  - `renderBH_core_bundle` traces four jittered sub-pixel rays for selected visible/diagnostic modes and averages physical hit/radiance/source-location quantities.
  - `renderBH`, `renderBHGlobal`, `renderBHClassic`, `renderBHClassicLite`, and bundle variants are the Metal trace kernels.
- `Blackhole/Metal/Compose/kernels.metalh`
  - `renderBHLinearGlobal` can trace directly into a linear HDR intermediate, bypassing stored collision payloads for some paths.
- `Blackhole/Sources/Render/Trace/`
  - `RenderTracePhase.swift`, `RenderTraceTile.swift`, `RenderTraceSubmission.swift`, and `RenderTraceTraversal.swift` schedule trace kernels and collect hit counts.

### Geodesic integration

- `Blackhole/Metal/gr_math.metal`
  - `schwarzschild_accel`, `kerr_equatorial_accel`, and `metric_accel` provide metric acceleration helpers.
  - `Params` carries metric/geodesic controls such as `metric`, `spin`, `h`, `maxSteps`, `kerrSubsteps`, `kerrTol`, and escape/horizon controls.
- `Blackhole/Metal/volume_rt.metal`
  - `trace_single_ray` builds the initial camera ray direction and dispatches to Schwarzschild or Kerr tracing.
  - `trace_schwarzschild_ray` routes to surface or volume tracing.
  - `trace_kerr_ray` routes to surface or volume tracing.
  - `trace_schwarzschild_volume_ray` uses RK stepping (`rk4_step_h`) and integrates transfer along segments.
  - `trace_kerr_volume_ray` uses adaptive Kerr Hamiltonian stepping (`kerr_dp45_trial`) and integrates transfer along accepted segments.

### Disk and volume interaction

- `Blackhole/Metal/disk_models.metal`
  - Owns horizon/ISCO-derived radii: `disk_horizon_radius_m`, `disk_inner_radius_m`, `disk_emit_min_radius_m`.
  - Owns disk geometric thickness: `disk_half_thickness_m`.
  - Owns thin/precision source helpers: NT flux, color temperature, atmosphere, turbulence/heating, cloud/noise, radial profiles.
- `Blackhole/Metal/volume_rt.metal`
  - Surface paths test disk hits and populate `CollisionInfo`.
  - Volume paths call `volume_integrate_segment` along geodesic segments and accumulate into `VolumeAccum`.
  - `trace_commit_volume_hit` converts accumulated physical state into `CollisionInfo`.
- `Blackhole/Metal/VolumeTransport/`
  - `legacy.metal` handles older thick/precision volume optical-depth behavior.
  - `grmhd.metal` handles GRMHD-like scalar/visible transfer state and source coefficients.
  - `commit.metal` prepares and stores volume hit data and diagnostics.
- `Blackhole/Sources/Params/ParamsBuilderDiskVolume.swift` and `Blackhole/Sources/Params/ParamsBuilderAssets.swift`
  - Load, size, and classify disk volume resources (`vol0`, `vol1`, metadata).

### Emissivity, absorptivity, and transfer

- `Blackhole/Metal/volume_rt.metal`
  - `VolumeAccum` stores accumulated intensity, visible-band radiance proxies, optical depth, transfer maxima, source-function proxies, weighted radius, temperature, g-factor, path, and debug counters.
  - `volume_accum_note_transfer` records `j/alpha`-like source function and first tau=1 radius/path.
  - Visible/volume transfer calls update `A.I`, `A.IVisNu`, `A.tau`, `A.tauVis`, branch integrals, source maxima, and alpha/tau diagnostics.
- `Blackhole/Metal/VolumeTransport/grmhd.metal`
  - Computes GRMHD-derived density, magnetic, temperature, thermal source, thin tail, opacity, photosphere/body/corona weights, and branch contributions.
  - Current comments show active work to avoid flattening structure by over-closing optically thin tails with `j/alpha` and by using state-dependent source/emissivity modifiers before RT.
- `Blackhole/Metal/spectrum_visible.metal`
  - `comp_visible_iNu_emit` and `comp_visible_xyz_from_spectrum` convert physical temperature/g-factor into visible observer-frame XYZ using invariant `I_nu / nu^3` transport.
- `Blackhole/Metal/Visible/bridge.metal`
  - Converts trace-time collision data into visible XYZ for ray-bundle averaging.

### Redshift and Doppler

- `CollisionInfo.v_disk.x` carries the g-factor/redshift proxy in current collision payloads.
- `Blackhole/Metal/VolumeTransport/commit.metal`
  - `trace_prepare_volume_hit` computes weighted `gMean` from `VolumeAccum.g`.
  - `trace_store_volume_hit` stores `gMean` into `info.v_disk.x`.
- `Blackhole/Metal/spectrum_visible.metal`
  - Uses `g_total`: `nu_em = nu_obs / g`, `I_nu_obs = g^3 I_nu_emit`.
- `Blackhole/Metal/Compose/helpers.metalh`
  - Diagnostics expose `g` and `beaming` (`g^3`) views through `analysisMode`.

### Raw radiance or equivalent signal

- `CollisionInfo.v_disk.w` carries scalar intensity/radiance proxy for several paths.
- `CollisionInfo.emit_r_norm`, `emit_phi`, `emit_z_norm` are overloaded in visible-volume paths to carry either source coordinates, three-band `I_nu`, or linear XYZ depending on sentinel values.
- `VolumeAccum.I`, `IVisNu`, and branch integrals hold raw physical signal before display interpretation.
- `Blackhole/Metal/Compose/helpers.metalh`
  - `comp_linear_rgb_precloud` converts collision/volume physical signal into linear RGB/XYZ diagnostics and render intermediates.
  - `raw-radiance` is currently an alias for raw-log/log-intensity style physical radiance inspection on GRMHD/precision-volume diagnostics.
- `Blackhole/Sources/Render/Core/RenderOutputs.swift`
  - Metadata lists bridge fields: `emit_r_norm`, `emit_phi`, `emit_z_norm`, `ct`, `T`, `v_disk`, `direct_world`, `noise`.

## 2. Current Suspected Physical Realism Bottlenecks

- Disk too thick: possible in thick/precision paths. `disk_half_thickness_m` explicitly thickens inner/mid disk in non-thin modes and precision mode blends geometric H/rs into thickening. This can be physically valid for hot flow tests but can hide a thin photosphere if used as the visible source baseline.
- Emission too smooth: possible in canonical/GRMHD-visible paths when source-function closure or thermal body weighting dominates. The code already contains state-dependent GRMHD thermal/cloud modifiers, but branch-ratio diagnostics are needed to confirm whether the rendered signal is mostly smooth body emission.
- Optical depth hiding structure: likely for high-column GRMHD/precision-volume cases. `tau`, `tau-wide`, `tau1-r`, `tau1-depth`, `thermal-alpha-pre`, and `thermal-alpha-post` exist, but they are not yet packaged as a standard validation matrix for canonical visible renders.
- `j/alpha` or source-function flattening contrast: plausible. `volume_accum_note_transfer` tracks `j/alpha`, and `grmhd.metal` comments explicitly warn against forcing optically thin synchrotron-like tails back to a Planck/Rayleigh-Jeans source. The key risk is too much thermal LTE/source-function behavior creating a uniform slab.
- Raw radiance available for inspection: partially yes. `raw-radiance`/`raw-log`, `inu`, and visible XYZ/Y paths expose physical signal, but explicit per-field raw-radiance buffers do not exist.
- Redshift/g-factor available for inspection: yes for GRMHD/precision-volume and thin physical debug paths via `g`; beaming proxy via `beaming`.
- Emission/source location available for inspection: partially yes. `emission-radius`, `tau1-r`, `tau1-depth`, `path`, `impact`, and bridge coordinates exist, but full source-location images for every source mode are still overloaded through `CollisionInfo` fields.

## 3. Render Contract Status

| Field | Status | Current implementation |
| --- | --- | --- |
| raw radiance | Partially exists | `VolumeAccum.I`, `IVisNu`, `CollisionInfo.v_disk.w`, linear XYZ sentinel payloads, `raw-radiance`/`raw-log`, `inu`, Y luminance diagnostics. No dedicated raw-radiance buffer. |
| optical depth | Partially exists | `VolumeAccum.tau`, `tauVis`, `tau1` fields, `--disk-grmhd-debug tau`, `tau-wide`, `tau1-r`, `tau1-depth`, `thermal-alpha-pre`, `thermal-alpha-post`. Coverage is strongest for GRMHD/precision volume, weaker for all thin/canonical source modes. |
| redshift / g-factor | Exists | `CollisionInfo.v_disk.x`, `VolumeAccum.g`, visible spectral integration using `g^3`, `--disk-grmhd-debug g`, `beaming`. |
| hit kind / hit mask | Partially exists | `CollisionInfo.hit`, `CollisionLite32.noise_dirOct_hit.w`, GPU hit counts, current `hit-mask` diagnostic. Hit kind is still binary rather than a richer classification such as horizon/disk/volume/background. |
| emission radius or source-location proxy | Partially exists | `emit_r_norm`, `emit_phi`, `emit_z_norm`, weighted `VolumeAccum.r / w`, `emission-radius`, `tau1-r`, bridge metadata. Overloaded fields make this mode-dependent. |
| depth/distance proxy | Partially exists | `ct`, `path`, `tau1-depth`, `direct_world.w` for impact or bundle/Jacobian/position depending on path. Not yet a stable interpreter-facing depth buffer. |
| disk velocity | Partially exists | `CollisionInfo.v_disk` carries g/r/vr/scalarI-like data in volume paths and disk velocity-like values in legacy paths; `speed` and `gamma` debug views exist. No clean contract field for full velocity vector across all modes. |
| disk normal | Missing | No stable disk normal contract field was found. Some local geometry uses disk plane/ray direction, but no exported normal buffer exists. |
| temperature or temperature proxy | Exists | `CollisionInfo.T`, `VolumeAccum.temp4`, visible `Teff` models, `teff`/`thetae` diagnostics. Physical meaning varies by source mode. |
| debug flags | Partially exists | `diskGrmhdDebugView`, `analysisMode`, sentinels in `noise`, packed bridge fields, invalid/sample diagnostics. No unified debug-flag buffer. |

## 4. Ranked Improvement Plan

### Diagnostics-only changes

- Build a repeatable physics diagnostic matrix that renders `raw-radiance`, `tau`, `tau-wide`, `g`, `beaming`, `emission-radius`, `source`, `branch-ratio`, `hit-mask`, `path`, and `impact` for canonical visible and GRMHD/precision-volume scenes.
- Document the exact payload meaning of `CollisionInfo.v_disk`, `noise`, and `emit_*` per source mode to reduce accidental interpreter misuse.
- Add or improve source-location diagnostics for modes where `emit_*` is currently reused for XYZ or spectral anchors.
- Add explicit labels in metadata for active physical diagnostic view and whether `emit_*` contains coordinates, spectral anchors, or XYZ.

### Low-risk physical improvements

- Inspect and tune diagnostic scaling for `tau`, `tau-wide`, `source`, `raw-radiance`, and branch-contribution views so physical structure is visible without changing final radiance.
- Preserve spatial contrast by auditing GRMHD thermal/cloud branch ratios and ensuring smooth body emission does not dominate when optically thin diagnostics show structured plasma.
- Add thin luminous layer validation using existing `thinPhotosphereEnabled`, `thinHOverR*`, `thinWeightPower*`, and `thermal-transfer-mode` controls before adding new options.
- Improve source-radius/source-location coverage using existing fields and debug views rather than changing ABI.

### Medium-risk physical improvements

- Adjust GRMHD visible thermal/cloud source weighting if diagnostics show `j/alpha` flattening or excessive LTE body dominance.
- Tune optical-depth weighting before/after thin-photosphere gates to keep true optically thick regions opaque while preserving optically thin structure.
- Add a clearer physical hit-kind classification if it can reuse existing payload space or metadata without packed ABI expansion.
- Introduce a stable depth/distance proxy only after agreeing on whether it belongs in collision payload, linear32 alpha, or a separate buffer.

### High-risk changes to avoid for now

- Broad metric/geodesic rewrites.
- Changing `PackedParams`, `CollisionInfo`, `CollisionLite32`, or texture/buffer layouts without an explicit ABI review.
- Adding many public runtime options.
- Solving physical realism with exposure, tone mapping, bloom, glare, lens flare, color grading, camera response, or sensor behavior.
- Large source-model refactors before diagnostics prove which physical term is failing.

## 5. First Implementation Recommendation

Recommended next target: expose and standardize optical-depth diagnostics across the canonical visible and GRMHD/precision-volume paths.

Reasoning:

- Raw radiance and hit-mask diagnostics already exist on this branch through `raw-radiance` and `hit-mask`.
- Redshift/g-factor is already inspectable through `g` and `beaming`.
- Optical depth is the most likely physical cause of lost structure: high tau can legitimately hide flow detail, while over-broad `j/alpha`/source-function behavior can make a disk look like a smooth slab.
- The safest first step is diagnostic, not a source-model change: produce reliable `tau`, `tau-wide`, `tau1-r`, `tau1-depth`, and branch-ratio outputs for the same scene before changing emissivity, opacity, or geometry.

Validation target for the future implementation:

- Compile Swift/Metal.
- Render a low-resolution physics diagnostic matrix outside the repo, preferably under `/private/tmp`.
- Confirm `raw-radiance`, `optical-depth`, `redshift/g-factor`, `hit-mask`, and `emission-radius/source-location` can be compared for the same preset without interpreter/camera changes.
