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
| `cinematic-physical-disk-v1` | Production visible source | Physically constrained procedural source for camera/cinema exploration; must remain source-layer, not post-processing |
| `physics-constrained-cinematic-disk-v1` | Production candidate | Science-gated cinematic disk search target; requires diagnostics before promotion |
| `thin-disk-visible-reference` | Clean reference | Analytic thin-disk visible photosphere, no procedural/GRMHD texture |
| `static-transfer-reference-v1` | Transfer diagnostic | Motionless Schwarzschild thin-disk transfer fixture; source orbital/radial/turbulent motion disabled |
| `grmhd-surrogate-disk-v1` | Synthetic surrogate | Deterministic GRMHD-like preview; not real evolved GRMHD data |
| `grmhd-hot-flow-diagnostic` | GRMHD structure diagnostic | Optically thin hot-flow/synchrotron-like diagnostic, not the default human-visible disk |
| `grmhd-temperature-flow-diagnostic` | GRMHD thermal volume diagnostic | 3D GRMHD visible thermal RT experiment, calibration/data-quality dependent |

## Source Model Status Classes

| Status | Meaning | GUI treatment |
| --- | --- | --- |
| recommended | Stable enough for normal source selection. | Show in the main source list. |
| production-candidate | Useful but still requires source diagnostics and validation notes. | Show with candidate labeling. |
| surrogate | Synthetic approximation, not an evolved simulation. | Show with surrogate warning. |
| diagnostic | Intended for debug/validation, not final beauty output. | Show under diagnostics or advanced source list. |
| legacy | Reproduction path. | Show only in legacy/reproduction section. |

The GUI must preserve these labels instead of flattening all source models into
one aesthetic preset list.

## Source Model Contract Matrix

Every public or candidate source model must carry the same documentation
contract. This keeps GUI options from becoming unlabeled image presets.

| Source model | Assumptions | Inputs | Outputs | Known limitations | Allowed render modes | Validation scenes | Forbidden hacks |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `canonical-visible-disk-v1` | Analytic visible thin disk with bounded positive hot-skin and weak corona source branches. | Metric/spin, visible temperature controls, disk-coordinate heating controls, presentation-independent source parameters. | Physical visible radiance proxy, branch diagnostics, g/beaming-compatible source records. | Not evolved GRMHD; heating field is deterministic surrogate; corona is phenomenological. | scientific, eye, camera-raw, camera-rendered, cinema. | branch diagnostics, presentation isolation, g/beaming maps, camera-raw sidecar. | No albedo/normal texture, no presentation bloom/color grade as source repair. |
| `cinematic-physical-disk-v1` | Production visible source with stronger but still source-layer disk structure. | Source-model defaults, disk flow controls, visible/temperature controls, camera-independent structure parameters. | Visible disk radiance with bounded physical-looking source morphology. | Candidate/cinematic tuning needs diagnostics before being treated as scientific default. | scientific, eye, camera-raw, camera-rendered, cinema. | presentation source matrix, source-model registry, scientific linear comparison. | No post-processing morphology changes, no hiding transfer/geodesic defects. |
| `physics-constrained-cinematic-disk-v1` | Science-gated search target over constrained source-layer parameters. | PCD density/emissivity/opacity/spiral/clump/hot-crescent controls, disk orbital controls. | Diagnostic source fields plus final radiance for candidate selection. | Surrogate parameter search, not a plasma solve; requires diagnostics for promotion. | scientific, eye, camera-raw, camera-rendered, cinema. | low/baseline/high Doppler g-factor maps, presentation source matrix, PCD diagnostics. | No parameter set promoted from beauty image alone; no cinematic effect as validation evidence. |
| `thin-disk-visible-reference` | Clean analytic thin-disk visible photosphere without procedural or GRMHD texture. | Metric/spin, thin-disk temperature and photosphere controls. | Reference radiance for thin-disk transfer and presentation checks. | Simplified source physics; no turbulent structure or evolved plasma variability. | scientific, eye, camera-raw, camera-rendered, cinema. | source matrix, render-mode contract, geodesic/transfer sanity comparisons. | No procedural texture, no GRMHD atlas perturbation, no presentation-side source shaping. |
| `static-transfer-reference-v1` | Motionless Schwarzschild thin-disk transfer diagnostic with source orbital/radial/turbulent motion disabled. | Schwarzschild metric, spin 0, zero orbital/radial/turbulent source controls, thin-disk temperature controls. | Renderer-produced g-factor and beaming maps for a no-flow transfer fixture. | Gravitational redshift and lens geometry remain; this is not a flat-space same-tetrad `g ~= 1` fixture. | scientific, eye, camera-raw, camera-rendered, cinema. | static-transfer renderer fixture, low-vs-orbiting Doppler comparison, g/beaming diagnostics. | No residual asymmetry hidden by tone mapping; no relabeling as a full static-emitter/static-observer proof. |
| `grmhd-surrogate-disk-v1` | Synthetic GRMHD-like preview used for visual/diagnostic iteration. | Surrogate atlas/flow controls and source-model defaults. | Deterministic GRMHD-like visible source preview. | Not real evolved GRMHD data; cannot validate plasma dynamics. | scientific, eye, camera-raw, camera-rendered, cinema. | source registry, GUI labeling, presentation isolation where supported. | Must not be labeled as real GRMHD; no use as paper-grade evidence. |
| `grmhd-hot-flow-diagnostic` | GRMHD-native hot-flow/synchrotron-like diagnostic source. | GRMHD volume/snapshot resources, density/B/emission/absorption/velocity scales. | Diagnostic hot-flow radiance and GRMHD debug maps. | Calibration and data quality dependent; not default human-visible disk. | scientific, eye, camera-raw, camera-rendered, cinema when data is available. | GRMHD debug maps, source registry, data-backed presentation fixture when fixture exists. | No silent fallback to procedural texture; no camera grade used to validate plasma structure. |
| `grmhd-temperature-flow-diagnostic` | 3D GRMHD visible thermal volume RT experiment. | HDF5 snapshot or converted volume, temperature/emission/absorption/velocity controls. | Data-backed thermal visible volume radiance and GRMHD diagnostics. | Snapshot/electron-temperature/opacity calibration dependent; currently diagnostic. | scientific, eye, camera-raw, camera-rendered, cinema when HDF5 data is supplied. | optional GRMHD presentation fixture, raw-radiance/g/beaming/tau diagnostics. | No missing-data fallback disguised as GRMHD; no presentation smoothing as physics repair. |

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
- defaults to a visible-disk calibration near `T0 = 18000 K`; this keeps the
  disk in a hot blue-white thermal regime while preserving more visible-band
  contrast than the earlier 22000 K default. Use `--teff-T0` for explicit
  temperature-scale sweeps.
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

The default metric remains explicit/reproducible rather than assuming an
astrophysical spin. For a more realistic spinning-black-hole scenario, use a
Kerr sweep and state the spin in the render metadata:

```bash
./Blackhole/run_pipeline.sh \
  --source-model canonical-visible-disk-v1 \
  --metric kerr \
  --spin 0.6 \
  --presentation scientific \
  --quality hq
```

Validation note: in the current camera setup, moderate Kerr spin (`a ~ 0.6`)
adds stronger inner-disk/lensing hierarchy without making the disk body as
smooth and enlarged as very high spin. Treat spin as a physical scene parameter,
not a hidden presentation preset.

The selected tuning keeps the bright-region branch balance approximately:

- body/photosphere: 75%
- hot skin: 24%
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

Recommended source-survival check:

```bash
python3 scripts/validate_presentation_modes.py \
  --source-model canonical-visible-disk-v1 \
  --width 384 \
  --height 216 \
  --quality preview \
  --disk-turbulence 2.0 \
  --stable-debug-trace
```

For physically richer review renders, use an explicit Kerr scene parameter
rather than a hidden source-model preset:

```bash
python3 scripts/validate_presentation_modes.py \
  --source-model canonical-visible-disk-v1 \
  --width 384 \
  --height 216 \
  --quality preview \
  --disk-turbulence 2.0 \
  --stable-debug-trace \
  --extra --metric kerr --spin 0.6
```

Important numeric checks:

- `skin_ratio_mean_active` and `skin_abs_share_mean_active` should agree within a few percent.
- `activity_vs_skin_abs_corr_active` should be positive; otherwise the heating field is not actually feeding the skin branch.
- `activity_vs_total_residual_corr_active` should be positive for review scenes; otherwise skin energy exists but is visually buried by transfer/geometry.
- `abs_total_vs_scientific_corr_active` should stay high, so scientific display is not changing source morphology.

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
