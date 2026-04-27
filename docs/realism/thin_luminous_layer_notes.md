# Thin Luminous Layer Notes

## Current disk and emission structure

- Analytic thin disk and surface paths use `disk_half_thickness_m` in `Blackhole/Metal/disk_models.metal`; thin mode returns the configured geometric half-thickness, while thick/precision modes broaden the disk with a radius-dependent multiplier.
- The physical atmosphere helpers in `disk_models.metal` already assume a Gaussian vertical density profile for optical-depth and Eddington-atmosphere temperature estimates.
- GRMHD and imported volume renders integrate radiative transfer in `Blackhole/Metal/volume_rt.metal` through `volume_integrate_segment`.
- GRMHD visible transfer samples `vol0`/`vol1`, computes local emissivity/absorptivity in `Blackhole/Metal/VolumeTransport/grmhd.metal`, and accumulates visible-band radiance, optical depth, source proxies, branch contributions, and emission-height diagnostics.
- The GRMHD visible path already has a rendering-layer photosphere weight: `disk_grmhd_visible_photosphere_weight`. It constrains thermal visible emission with a Gaussian vertical H/R envelope without changing the imported GRMHD density, velocity, or magnetic field.
- Existing diagnostics relevant to layer inspection include `thin-weight`, `emission-layer`, `body-proxy`, `tau`, `optical_depth`, `tau1-r`, `tau1-depth`, `raw-radiance`, `g`, and `emission-radius`.

## Feasibility

A thin luminous layer is feasible without changing Metal buffer layouts or final display behavior.

The cleanest current path is not a new shader model. The renderer already has the necessary physical controls:

- `--thin-photosphere`
- `--thin-h-over-r-base`
- `--thin-h-over-r-inner`
- `--thin-h-over-r-outer`
- `--thin-weight-power-emission`
- `--thin-weight-power-absorption`
- `--thermal-transfer-mode tau-surface`

The safe implementation is a named source model, `thin-luminous-layer-candidate`, that activates those existing controls for GRMHD visible thermal transfer. Existing presets remain unchanged.

## Safest implementation point

`Blackhole/run_pipeline.sh` is the safest implementation point because it can define one physics source candidate using existing Swift/Metal parameters:

```bash
./run_pipeline.sh --source-model thin-luminous-layer-candidate ...
```

The candidate uses GRMHD mode, visible physical blackbody transfer, a GRMHD-hybrid temperature model, tau-surface transfer, and a narrower Gaussian photosphere layer. It does not add new Metal fields, new packed parameters, or new public shader logic.

## Risks

- This candidate requires a GRMHD volume or HDF5-to-volume input; it is not a standalone analytic thin-disk render.
- A very thin H/R layer can miss structure if the volume resolution in `z` is too coarse.
- Tau-surface transfer is physically interpretable as a photosphere approximation, but it is still an approximation and should be compared against full volume RT.
- The candidate may underrepresent optically thin corona or hot-skin emission because it intentionally disables the corona layer by default.

## Validation method

Minimum validation:

- Compile Swift and Metal.
- Confirm `run_pipeline.sh` parses and advertises `thin-luminous-layer-candidate`.
- For a GRMHD/HDF5 test volume, render the same scene with:
  - `--source-model thin-luminous-layer-candidate --disk-grmhd-debug thin-weight`
  - `--source-model thin-luminous-layer-candidate --disk-grmhd-debug emission-layer`
  - `--source-model thin-luminous-layer-candidate --disk-grmhd-debug optical_depth`
  - `--source-model thin-luminous-layer-candidate --disk-grmhd-debug raw-radiance`

The layer is behaving as intended only if `thin-weight` and `emission-layer` show a narrow emitting region while `raw-radiance` and `optical_depth` remain physically structured rather than display-tuned.
