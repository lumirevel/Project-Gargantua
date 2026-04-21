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
blackbody/XYZ integration before RGB display conversion. The `physical` realism
profile is the strict baseline: NT-like radial temperature/emissivity, frequency
shift, limb darkening, and no atmosphere/corona/microstructure layer.

The `observational` and `cinematic` profiles add a phenomenological thin-disk
surface layer after that baseline. The layer uses disk-coordinate shear
perturbations and a Shakura-Sunyaev-inspired radial opacity proxy tied to
`mdot`, radiative efficiency, and the inner boundary. It is more constrained than
image-space noise, but it is not a solved GRMHD or vertical radiative-transfer
model.

## Physical vs Presentation Responsibilities

Physical layer:
- geodesic stepping and disk intersections
- disk-space flow time, orbital shear, turbulence parameters
- visible-band spectral emission integrated to linear XYZ/RGB
- relativistic g-factor / beaming diagnostics
- HDR radiance before display mapping
- strict `physical` mode without phenomenological surface microstructure

Human/experience layer:
- human-vision display response, not camera sensor simulation
- exposure and tone mapping
- background star field for perceptual context
- optional observational thin-disk surface layer for perceptual exploration

Cinema-only layer:
- flare and stronger camera artifacts
- presentation choices that are not part of the scientific master

## Diagnostics

Use `--realism-debug` with `g`, `emissivity`, `beaming`, `photosphere`,
`atmosphere`, `corona`, `perturbation`, `hdr`, `temperature`, `tau`, `density`,
or `radial-tau`.
These maps disable camera presentation so the output remains a direct diagnostic.

## Near-Term Upgrade Hooks

The current atmosphere and corona are controlled thin-disk approximations, not a full
radiative-transfer or GRMHD solver. The next physics-facing extension point is to feed
the emission helper with richer disk state: density, electron temperature, velocity,
magnetic field, and optical-depth fields from analytic or simulation sources.
