# Source Model Registry

The public renderer surface is intentionally small. Source formation is selected
with:

```bash
./Blackhole/run_pipeline.sh \
  --source-model canonical-visible-disk-v1 \
  --presentation scientific \
  --quality preview
```

Use `--presentation scientific|eye|cinema` to choose the observer/display layer.
Presentation modes must not change the accretion source morphology.

## Recommended Public Source Models

| Source model | Role | Scientific status |
| --- | --- | --- |
| `canonical-visible-disk-v1` | Default visible accretion disk source | Clean thin-disk visible body plus bounded disk-coordinate stochastic heating skin and weak corona |
| `thin-disk-visible-reference` | Clean reference | Analytic thin-disk visible photosphere, no procedural/GRMHD texture |
| `grmhd-hot-flow-diagnostic` | GRMHD structure diagnostic | Optically thin hot-flow/synchrotron-like diagnostic, not the default human-visible disk |
| `grmhd-temperature-flow-diagnostic` | GRMHD thermal volume diagnostic | 3D GRMHD visible thermal RT experiment, calibration/data-quality dependent |

## canonical-visible-disk-v1

This is the recommended visible source model for the current iteration.

Source branches:

```text
source radiance =
  body/photosphere
+ hot skin / heating packets
+ weak corona
```

Body/photosphere:

- uses the thin-disk ray/disk-intersection path
- uses ISCO/horizon/spin-aware inner radius
- uses the existing NT/Page-Thorne-like visible temperature profile
- defaults to a hot visible-disk calibration near `T0 = 22000 K`; this keeps the
  canonical disk in a physically more plausible blue-white thermal regime while
  avoiding immediate white saturation in the scientific display
- uses visible blackbody/graybody spectral integration before RGB display
- uses relativistic frequency shift from the trace record
- disables Perlin/fBm/albedo/normal/roughness texture in the canonical path

Heating field:

```text
x = log(r / r_in)
phi_s = phi - Omega_K(r) * t

delta_raw = sum_i A_i cos(kx_i x + m_i phi_s + phase_i(t))
A_i ~ |k_i|^(-alpha/2), alpha ~ 5/3

delta_low  = low-frequency component for very weak body heating
delta_high = positive high-frequency activity for skin emission
cloud      = positive sheared Gaussian packet heating field in (log r, phi)
filament   = positive high-mode phase-ridge heating from the same spectral basis
activity   = bounded mix(delta_high, cloud, filament)
```

The canonical default uses `diskTurbulence = 2.0`. Internally, the stochastic
support is calibrated around the previous `1.6` setting and allows controlled
validation sweeps without adding new public source models.

The current canonical heating packets are deliberately narrower than the
photospheric body and are remapped through a bounded intermittent activity
curve. This keeps the body clean while letting the hot skin behave as positive
local dissipation instead of a color/albedo texture.

Energy split:

```text
F_total  = F_disk(r) * M_low
f_skin   = bounded(activity, radius, source footprint)
f_corona = small bounded inner-flow term

F_body   = (1 - f_skin - f_corona) * F_total
F_skin   = f_skin * F_total
F_corona = f_corona * F_total

T_skin   = T_body * h_skin, h_skin > 1
```

The hot skin also receives a small positive local dissipation lift from the
same disk-coordinate heating field. This is a source-layer radiance change, not
a presentation/post-processing effect, and it does not subtract from or carve
the photospheric body.

Initial target in bright regions:

- body: 72-86%
- skin: 12-25%
- corona: 0.5-4%

The skin is positive emissive structure only. It must not darken or carve the
body.

Current calibrated default:

```bash
./Blackhole/run_pipeline.sh \
  --source-model canonical-visible-disk-v1 \
  --presentation scientific \
  --quality hq \
  --disk-turbulence 2.0
```

The selected tuning keeps the bright-region branch balance approximately:

- body/photosphere: 72%
- hot skin: 27%
- corona: 1%

This balance is intentionally body-dominant. The skin should enrich the source
as positive emissive heating structure, not replace the photosphere or create
surface scratches. The corona is a weak inner-flow accent, not a fog layer.

Recommended branch diagnostics:

```bash
# Absolute branch radiance previews. These use one fixed HDR preview scale and
# are intentionally dim; they are not normalized maps.
./Blackhole/run_pipeline.sh --source-model canonical-visible-disk-v1 --realism-debug photosphere
./Blackhole/run_pipeline.sh --source-model canonical-visible-disk-v1 --realism-debug skin
./Blackhole/run_pipeline.sh --source-model canonical-visible-disk-v1 --realism-debug corona

# Normalized diagnostics.
./Blackhole/run_pipeline.sh --source-model canonical-visible-disk-v1 --realism-debug perturbation
./Blackhole/run_pipeline.sh --source-model canonical-visible-disk-v1 --realism-debug activity
```

`perturbation` is an RGB unit branch-ratio map:

```text
R = body / total
G = skin / total
B = corona / total
```

`activity` is the unit heating/activity field used by the positive skin branch.
Do not compare the visual brightness of absolute branch previews against the
normalized maps; use the ratio map or numeric metrics for branch balance.

## Legacy / Experimental Source Families

The following remain available only for reproduction or diagnosis:

```bash
./Blackhole/run_pipeline.sh --science-regime <old-name> --experimental
```

Legacy/experimental families include:

- `plausible-disk-v1` old name, now superseded by `canonical-visible-disk-v1`
- `dngr-flow`, `dngr-volume`
- `grmhd-photosphere`, `grmhd-photosphere-atlas`
- `positive-plasma`, `hot-skin*`, `plasma-body`
- `hybrid-visible-disk*`, `visible-reference-skin*`
- `perlin*` and other procedural/material texture paths
- detailed `--grmhd-smooth-weight` branch-balancing experiments

These paths are not recommended final scientific source models. They are kept to
reproduce older renders and to inspect failure modes.

## Layer Separation

The renderer is organized conceptually as:

```text
source model -> relativistic transfer -> presentation
```

Presentation modes:

- `scientific`: idealized master/debug view
- `eye`: human-vision presentation of the same source radiance
- `cinema`: restrained camera/sensor presentation of the same source radiance

If the source looks wrong, fix the source model first. Do not use presentation
effects to invent missing plasma structure.

## Current Caveats

- `canonical-visible-disk-v1` is an analytic visible-disk source with
  disk-coordinate stochastic heating, not an evolved 3D GRMHD simulation.
- The stochastic heating field is deterministic, Kepler-sheared, and
  disk-coordinate, but it is still a surrogate for unresolved MRI/reconnection
  activity.
- The weak corona is phenomenological and optically thin. It should remain
  subordinate to the body and skin branches.
- GRMHD modes are kept as diagnostics until a suitable evolved dataset and
  visible-band electron/opacity calibration are available.
