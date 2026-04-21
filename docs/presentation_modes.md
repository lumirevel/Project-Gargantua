# Presentation Modes

The renderer separates the physical transport result from display presentation through
`--presentation-mode`. The mode selects defaults only; explicit CLI flags such as
`--camera-model`, `--camera-profile`, `--realism-profile`, and `--background` still win.
Use `--scientific-master-out <path>` through `run_pipeline.sh` when the HDR32
scientific-master intermediate should be persisted for inspection or comparison.

## Modes

| Mode | Intended output | Default camera | Default realism | Default background | Use when |
| --- | --- | --- | --- | --- | --- |
| `legacy` | Backward-compatible behavior | Existing defaults | Existing defaults | Existing defaults | Reproducing older renders or tests |
| `scientific` | Scientific master / diagnostic output | no sensor model (`legacy`) | `physical` | `off` | Comparing radiance, g-factor, emissivity, or numerical changes |
| `eye` | Human-experience display | human-eye display transform | `observational` | `stars` | Default visually grounded render for `--look realistic` |
| `cinema` | Camera/cinematic presentation | `cinematic` sensor pipeline | `cinematic` | `stars` | Optional presentation with camera artifacts |

## Current Boundary

Current Metal kernels still produce the same packed trace/hit state and compose path.
This mode layer is a configuration boundary, not a new physical solver. It prevents
camera artifacts and stronger presentation defaults from becoming implicit scientific
truth, and it makes rendered metadata state which layer produced the image.

The thin-disk compose path now keeps local emission as an explicit visible-band
blackbody/XYZ integration before RGB display conversion. The observational/cinematic
profiles add disk-coordinate shear perturbation, density/opacity modulation, and a
thin atmosphere/corona approximation after the scientific emission step.

## Physical vs Presentation Responsibilities

Physical layer:
- geodesic stepping and disk intersections
- disk-space flow time, orbital shear, turbulence parameters
- visible-band spectral emission integrated to linear XYZ/RGB
- relativistic g-factor / beaming diagnostics
- HDR radiance before display mapping

Human/experience layer:
- human-vision display response, not camera sensor simulation
- exposure and tone mapping
- background star field for perceptual context

Cinema-only layer:
- flare and stronger camera artifacts
- presentation choices that are not part of the scientific master

## Diagnostics

Use `--realism-debug` with `g`, `emissivity`, `beaming`, `photosphere`,
`atmosphere`, `corona`, `perturbation`, `hdr`, `temperature`, `tau`, or `density`.
These maps disable camera presentation so the output remains a direct diagnostic.

## Near-Term Upgrade Hooks

The current atmosphere and corona are controlled thin-disk approximations, not a full
radiative-transfer or GRMHD solver. The next physics-facing extension point is to feed
the emission helper with richer disk state: density, electron temperature, velocity,
magnetic field, and optical-depth fields from analytic or simulation sources.
