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
- `eye` mode uses a stronger display-side Naka-Rushton-style receptor response
  than `scientific`, dim-surround gain for dark-adapted regions, highlight gain
  reduction in bright local surrounds, Hunt-effect saturation changes, Purkinje
  blue-green bias in dim values, and lens/macular short-wavelength attenuation
  in bright fields. These are deliberately downstream of source/RT.
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
before using cinema output as a scientific illustration. Cinema mode now also
supports a limited thin-lens depth-of-field approximation when the source buffer
contains depth. It uses `--camera-f-number`, `--camera-focus-depth`,
`--camera-dof-strength`, `--camera-aperture-blades`, and
`--camera-aperture-rotation` to form a circle-of-confusion and polygonal
aperture gather. This is a camera presentation effect, not a source-physics
edit. The scientific and eye
outputs are the preferred review targets for source-model work.

## Diagnostics

Use `--realism-debug` with `g`, `emissivity`, `beaming`, `photosphere`,
`atmosphere`, `corona`, `perturbation`, `hdr`, `temperature`, `tau`, `density`,
or `radial-tau`.
These maps disable camera presentation so the output remains a direct diagnostic.

## Presentation Validation Harness

Use the validation harness when changing eye/cinema response, exposure, glare, or
source/presentation boundaries:

```bash
python3 scripts/validate_presentation_modes.py \
  --source-model canonical-visible-disk-v1 \
  --width 384 \
  --height 216 \
  --out-dir /private/tmp/bh_presentation_validation
```

The script renders the same source model as:

- `scientific`
- `eye`
- `cinema`
- absolute branch previews for total, body, skin, and corona
- normalized branch/activity diagnostics

It writes `metrics.json`, `summary.md`, and a contact sheet. The key sanity
checks are:

- eye/cinema should keep high luminance-gradient correlation with scientific
  output, so presentation does not invent morphology.
- branch-ratio diagnostics should agree with numeric body/skin/corona means.
- absolute branch previews should be interpreted with the same fixed preview
  scale, not as normalized brightness maps.
- `activity_vs_total_residual_corr_active` is a source-survival check: it should
  be positive when the hot-skin activity field is visible in the final source,
  not only in normalized debug maps.
- Use `--stable-debug-trace` for slower Kerr/debug validation sweeps on
  interactive Apple GPUs; it routes debug maps through the stable collision
  buffer path instead of direct HDR trace maps.

If eye/cinema only look good while scientific source validation fails, treat it
as a source-model problem. If morphology correlations collapse without a clear
optical reason, treat it as a presentation bug.

For a black-hole-independent sanity check, render a small everyday HDR
ray-traced scene and feed that HDR file into the actual Metal compose stage:

```bash
python3 scripts/validate_presentation_on_rt_scene.py \
  --width 420 \
  --height 240 \
  --color-chart \
  --bokeh-targets \
  --out-dir /private/tmp/bh_eye_rt_validation
```

Use `--color-chart` when validating human-eye chroma behavior and `--bokeh-targets`
when validating camera aperture/DOF behavior. Both are validation scene features;
they do not change black-hole source physics.

For depth-of-field validation, render a slow CPU thin-lens reference and compare
it with the Metal compose-stage approximation:

```bash
python3 scripts/validate_presentation_on_rt_scene.py \
  --width 140 \
  --height 80 \
  --spp 1 \
  --focus-depth 2.5 \
  --f-number 1.0 \
  --dof-strength 4.0 \
  --aperture-blades 6 \
  --lens-reference-spp 12 \
  --exposure 1.0 \
  --out-dir /private/tmp/bh_eye_rt_metal_lens_reference_fixed
```

Use fixed exposure for this comparison. Separate auto-exposure solves make the
compose approximation and thin-lens reference visually incomparable.

This CPU harness renders a simple room with a ceiling area light, a metal sphere,
a glass sphere, and a diffuse plastic sphere. It writes a float4 linear32 HDR
file, then calls:

```bash
./Blackhole/run_pipeline.sh \
  --compose-hdr-in <scene.linear32f32> \
  --width <w> \
  --height <h> \
  --presentation scientific|eye|cinema \
  --output <png>
```

`--compose-hdr-in` is a presentation-only path. It bypasses black-hole tracing
and uses the existing HDR32 file-backed Metal compose kernels, including
exposure solve, eye response, camera response, PSF/glare, and sensor noise.
The input format is tightly defined as row-major `float4` linear RGB with
`w > 1.25`; the alpha sentinel tells compose to treat `xyz` as final source
radiance rather than a disk cloud/branch diagnostic. `w=2` means unknown or
focused depth, while `w=2+depth` optionally provides a source-depth proxy for
cinema depth-of-field validation. It is not an astrophysics test; it answers
whether eye/cinema behavior remains plausible on familiar radiance before
source-model changes are judged through those observer layers.

## Near-Term Upgrade Hooks

The current atmosphere and corona are controlled thin-disk approximations, not a full
radiative-transfer or GRMHD solver. The next physics-facing extension point is to feed
the emission helper with richer disk state: density, electron temperature, velocity,
magnetic field, and optical-depth fields from analytic or simulation sources.
