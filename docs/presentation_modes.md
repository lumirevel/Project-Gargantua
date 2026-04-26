# Presentation Modes

The renderer separates the physical transport result from display presentation through
`--presentation-mode` or its short alias `--presentation`. The mode selects defaults only; explicit CLI flags such as
`--camera-model`, `--camera-profile`, `--realism-profile`, and `--background` still win.
Use `--scientific-master-out <path>` through `run_pipeline.sh` when the HDR32
scientific-master intermediate should be persisted for inspection or comparison.

For normal rendering, prefer the consolidated source-model registry first:

```bash
./Blackhole/run_pipeline.sh \
  --source-model canonical-visible-disk-v1 \
  --presentation scientific \
  --quality preview
```

Recommended final-output commands for the current canonical source:

```bash
# Scientific validation / master-style display.
./Blackhole/run_pipeline.sh \
  --source-model canonical-visible-disk-v1 \
  --presentation scientific \
  --look linear \
  --quality hq

# Human-eye presentation of the same source radiance.
./Blackhole/run_pipeline.sh \
  --source-model canonical-visible-disk-v1 \
  --presentation eye \
  --quality hq

# Restrained camera/cinema presentation of the same source radiance.
./Blackhole/run_pipeline.sh \
  --source-model canonical-visible-disk-v1 \
  --presentation cinema \
  --quality hq
```

Recommended public source models are documented in `docs/source_models.md`:
`canonical-visible-disk-v1`, `thin-disk-visible-reference`,
`grmhd-hot-flow-diagnostic`, and `grmhd-temperature-flow-diagnostic`.

Older `--science-regime` names remain available for reproduction, but they are
legacy/experimental unless they map to the public registry. Use
`--science-regime <old-name> --experimental` when intentionally reproducing an
old path.

## Modes

| Mode | Intended output | Default observer model | Default disk realism | Default background | Use when |
| --- | --- | --- | --- | --- | --- |
| `legacy` | Backward-compatible behavior | Existing defaults | Existing defaults | Existing defaults | Reproducing older renders or tests |
| `scientific` | Ideal master / diagnostic output | no eye/camera response (`legacy`) | `physical` | `off` | Comparing radiance, g-factor, emissivity, or numerical changes |
| `eye` | Human observer display | human-eye display transform | `physical` unless explicitly overridden | `stars` | Default visually grounded render for `--look realistic` |
| `cinema` | Camera observer display | camera/sensor pipeline | `cinematic` | `stars` | Optional presentation with camera/lens artifacts |

For `canonical-visible-disk-v1`, all three presentation modes consume the same
source radiance. They must not change the body/skin/corona source morphology.
If an image only looks correct in `eye` or `cinema`, treat that as a source-model
problem rather than a presentation success.

## Current Boundary

Current Metal kernels still produce the same packed trace/hit state and compose path.
This mode layer is a configuration boundary, not a new physical solver. It prevents
observer-model effects and stronger presentation defaults from becoming implicit
source physics, and it makes rendered metadata state which layer produced the image.

`scientific`, `eye`, and `cinema` can all be scientifically modeled. The distinction
is not "science vs non-science"; it is where the image is formed:
`scientific` preserves an idealized radiance/master view, `eye` applies a human
observer response, and `cinema` applies a camera/sensor/lens response. The highest
risk of non-physical behavior is the accretion source model, so disk realism profiles
are kept explicit.

The thin-disk compose path now keeps local emission as an explicit visible-band
blackbody/XYZ integration before RGB display conversion. The `physical` realism
profile is the strict baseline: NT-like radial temperature/emissivity, frequency
shift, limb darkening, and no atmosphere/corona/microstructure layer.

The GRMHD hot-flow structure path is not the final eye target by itself. It is a
diagnostic for density, magnetization, temperature proxy, and velocity-driven
structure. The human-visible GRMHD path is `grmhd-temperature-flow`, which keeps
color in the visible blackbody/photosphere model and performs the thermal RT in
the Metal volume loop rather than as a post-image composite.

When `grmhd-temperature-flow` is explicitly combined with
`--presentation-mode scientific`, `run_pipeline.sh` now leaves the PNG path on a
linear/ideal display look instead of injecting the human-facing `realistic` look.
The default temperature-flow render remains `eye + realistic`. This keeps
diagnostic comparisons from inheriting the observer-facing look while preserving
the recommended human-visible default.

The `dngr-thin` / `interstellar-thin` preset is intended as the current
reference for the movie-like thin-disk geometry: it keeps the physical
thin-disk radiance model and changes only the observer/display side by default.
Use `--presentation-mode scientific` with the same preset when the eye response
should be removed for a master/debug comparison.

The `physical-flow` realism profile is the middle ground for a living, but still
disciplined, accretion photosphere. It is not RGB painting and it is not a
cinematic post effect. It perturbs the thermal photosphere through disk-space
orbital shear, optical-depth/covering fraction, and temperature-source modulation
before visible-band blackbody integration. If a GRMHD photosphere atlas is
provided, the atlas dominates the unresolved structure; otherwise the built-in
periodic shearing field is a constrained surrogate and should be labeled as such
in comparisons.

`dngr-volume` moves the same idea from a surface/photosphere approximation into
ray-sampled 3D transport. The fallback volume stores temperature scale, density,
radial drift, and azimuthal velocity scale in disk coordinates, then the Metal
volume loop integrates finite optical depth along the geodesic. In
`physical-flow` volume mode the renderer uses the volume as the transport state
and avoids adding a second random cloud/perlin layer on top of it.

The `observational` and `cinematic` profiles add a phenomenological thin-disk
surface layer after that baseline. The layer uses disk-coordinate shear
perturbations and a Shakura-Sunyaev-inspired radial opacity proxy tied to
`mdot`, radiative efficiency, and the inner boundary. It is more constrained than
image-space noise, but it is not a solved GRMHD or vertical radiative-transfer
model.

For color-corrected thin-disk emission, the color hardening factor `f_col`
shifts the local thermal spectrum but applies the matching `1/f_col^4`
dilution so it does not create extra bolometric power. Disk-space temperature
perturbations in observational/camera profiles are evaluated by re-integrating
the visible-band spectrum at the perturbed observed temperature, not by painting
a late RGB tint over a scalar intensity.

The observational photosphere treats disk-space density as optical
depth/covering fraction. Surface emission uses a saturating
`1 - exp(-tau / mu)` term so optically thick regions approach the local
blackbody source function instead of growing linearly with density.

## Physical vs Presentation Responsibilities

Physical transport/source layer:
- geodesic stepping and disk intersections
- disk-space flow time, orbital shear, turbulence parameters
- visible-band spectral emission integrated to linear XYZ/RGB
- relativistic g-factor / beaming diagnostics
- HDR radiance before display mapping
- strict `physical` mode without phenomenological surface microstructure
- `physical-flow` mode for photosphere-flow structure before spectral/display
  conversion

Human observer layer:
- human-vision display response, not camera sensor simulation
- exposure and tone mapping
- low/mid luminance retinal adaptation in `eye` mode only; this is a
  presentation transform and does not modify scientific radiance or debug maps
- photoreceptor-style response compression and mesopic rod/cone blending in
  `eye` mode. This is an observer model, not an accretion-flow edit.
- ocular-media PSF/glare is handled in the eye/camera presentation stage. Do not
  force a black-hole shadow or suppress GRMHD caustics by impact-parameter masks
  in the transport/radiance layer.
- In `eye` mode, the broad ocular-media wing uses a bright-pass additive scatter
  term rather than mixing the whole image into a fog layer. This keeps faint/dark
  accretion-flow structure from being smeared by presentation glare while still
  letting bright inner-flow highlights veil nearby pixels.
- GRMHD eye exposure uses a bounded mid-luminance solve in addition to the
  highlight percentile, so a bright lensed ring does not force the extended
  foreground flow into near-black display values. This changes presentation
  exposure only; raw scientific radiance is unchanged.
- GRMHD temperature-flow structure strength is not a presentation effect. The
  `--disk-precision-texture` value is packed into the physical parameter buffer
  and changes RT coefficients before display. Keep this moderate; if the output
  becomes striped, lower the parameter rather than hiding it in tone mapping.
- `grmhd-temperature-flow-hq` is a quality preset, not a new physical model. It
  only defaults SSAA to 2 when `--ssaa` was not set explicitly, reducing
  high-order ring and central-edge aliasing while using the same transport
  coefficients as `grmhd-temperature-flow`.
- Scientific and debug outputs keep raw radiance. Use `--disk-grmhd-debug path`
  to inspect accumulated ray path length when central speckles look suspicious.
- background star field for perceptual context
- optional observational thin-disk surface layer for perceptual exploration

Camera observer layer:
- sensor/lens response, PSF, flare, and stronger camera artifacts
- camera-specific presentation choices that are not part of the ideal master

Current caveat: the cinema presentation is intentionally restrained, but its
large low-level halo is still a presentation artifact. It should be reduced
before using cinema output as a scientific illustration. The scientific and eye
outputs are the preferred review targets for source-model work.

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
