# Real Evolved GRMHD Data

Use real evolved snapshots before judging whether the renderer can show
physically meaningful turbulent accretion-flow structure.

The repository's generated Fishbone-Moncrief HDF5 samples are useful for
pipeline tests, but they are not evolved 3D GRMHD. They should not be treated as
evidence that the physical renderer is incapable of showing turbulent structure.

## Illinois v3 GRMHD Data Products

The Illinois Simulation Data Products site publishes v3 GRMHD HDF5 primitive
dumps with `MAD` and `SANE` flux states and multiple black-hole spins.

```bash
python3 Blackhole/scripts/fetch_illinois_grmhd_snapshot.py \
  --flux SANE \
  --spin 0 \
  --list
```

Download one snapshot:

```bash
python3 Blackhole/scripts/fetch_illinois_grmhd_snapshot.py \
  --flux SANE \
  --spin 0 \
  --dump 05000 \
  --out-dir /tmp/blackhole_real_grmhd
```

The downloader writes a sibling `.provenance.json` file. Keep that file with
render outputs so comparisons can be traced back to the exact public dump.

Download a short consecutive sequence for temporal-variation checks:

```bash
python3 Blackhole/scripts/fetch_illinois_grmhd_snapshot.py \
  --flux SANE \
  --spin 0 \
  --start-index 0 \
  --count 4 \
  --out-dir /tmp/blackhole_real_grmhd_sequence
```

When `--count` is greater than one, the downloader also writes a
`*_sequence_*.manifest.json` file with every local path, source URL, catalog
index, and per-file provenance path. This is the input record to use when adding
time interpolation or motion diagnostics.

Audit all snapshots in a manifest:

```bash
python3 Blackhole/scripts/audit_grmhd_snapshot.py \
  --manifest /tmp/blackhole_real_grmhd_sequence/SANE_a0_sequence_00000_00003.manifest.json \
  --json-out /tmp/blackhole_real_grmhd_sequence/audit.json
```

## Current Supported Layout

The importer and audit scripts support KHARMA/IHARM-style primitive dumps:

```text
prims[n1, n2, n3, nprim]
header/prim_names = RHO, UU, U1, U2, U3, B1, B2, B3
header/coordinates = FMKS or MKS-like coordinates
```

Current conversion policy:

- `RHO` is used as rest-mass density proxy.
- `UU / RHO` is used to derive an electron-temperature proxy when no direct
  electron temperature field exists.
- `B1..B3` are used for magnetic-field-strength and synchrotron-like diagnostics.
- `U1..U3` are imported as primitive velocity components and converted with the
  renderer's existing approximate normalization path.
- FMKS `x2 -> theta` is approximated for placing the data on the renderer's
  `r-phi-z` texture grid. This is enough for visual diagnostics, but not a full
  covariant GRRT replacement.

## First Real Snapshot Check

The first verified public snapshot used for this project was:

```text
source: Illinois v3 GRMHD
flux: SANE
spin: 0
dump: torus.out0.05000.h5
shape: prims[288, 128, 128, 8]
primitive names: RHO, UU, U1, U2, U3, B1, B2, B3
local test path: /tmp/bh_real_grmhd/SANE_a0_t05000.h5
```

Audit result before volume resampling:

```text
rating=good
flowPhiP95=0.7139
dynamicsPhiP95=0.8495
```

After the renderer's current volume crop/resample bridge, structure is still
visible, but reduced:

```text
flowPhiP95=0.1901
dynamicsPhiP95=0.9477
selectedRMax≈70
volume grid=128x256x72
```

This means the real snapshot is not intrinsically too axisymmetric. If the final
image still looks smooth or white, the next bottleneck is renderer-side transfer,
branch balance, exposure, or the current volume bridge, not the absence of real
GRMHD structure.

The first hot-flow test confirmed this: the old visible synchrotron branch had a
large nonthermal emission floor and code-unit normalization that made every
positive scale collapse into a white column. The current hot-flow diagnostic
uses a much lower synch-only code-unit normalization and gates the visible/NIR
tail by magnetization, electron-temperature proxy, and a broad corona envelope.
This does not modify the GRMHD state; it restricts which parts of the state are
allowed to contribute to the diagnostic visible/NIR optically thin branch.

## Diagnostic Render

Run the same mode comparison used for synthetic samples:

```bash
python3 Blackhole/scripts/science_regime_diagnostics.py \
  --snapshot /tmp/blackhole_real_grmhd/SANE_a0_torus.out0.05000.h5 \
  --out-dir /tmp/blackhole_real_grmhd_diag \
  --width 384 \
  --height 384 \
  --debug-map rho \
  --debug-map thetae \
  --debug-map bmag \
  --debug-map jthin \
  --debug-map raw-log \
  --debug-map g
```

Interpretation:

- `thin_visible` and `experience` remain analytic visible-thin-disk regimes.
- `grmhd_structure_flow` / `grmhd_hot_flow` should be judged as a GRMHD-native
  optically thin 9-band hot-flow structure diagnostic, not as a forced visible
  thin disk.
- `grmhd_photosphere` is a diagnostic approximation for visible photosphere
  behavior.
- `debug_rho`, `debug_thetae`, `debug_bmag`, `debug_jthin`, and `debug_raw_log`
  show whether real data structure survives into the renderer.

For the current human-visible direction, use the GRMHD temperature-flow regime:
it samples the 3D evolved state in the volume path, estimates local visible
temperature from the thermal disk plus bounded GRMHD heating proxies, and
integrates visible-band blackbody RT in Metal.

```bash
./run_pipeline.sh \
  --science-regime grmhd-temperature-flow \
  --disk-hdf5 /tmp/blackhole_real_grmhd/SANE_a0_torus.out0.05000.h5 \
  --output /tmp/blackhole_real_grmhd/temperature_flow.png
```

Avoid reducing `--max-steps` aggressively on the GRMHD volume path. The default
camera presets use roughly 1600-2000 steps because the ray must first reach and
then integrate through a finite 3D volume. Values around 512 can miss the active
volume and produce a black final image even when the HDF5/volume bridge is valid.

For a cleaner still image, use the high-quality alias. It is the same physical
transport preset, but defaults to SSAA2 unless `--ssaa` is provided explicitly:

```bash
./run_pipeline.sh \
  --science-regime grmhd-temperature-flow-hq \
  --disk-hdf5 /tmp/blackhole_real_grmhd/SANE_a0_torus.out0.05000.h5 \
  --output /tmp/blackhole_real_grmhd/temperature_flow_hq.png
```

This does not replace thermal disk emission with synchrotron RGB and does not
compose separate images. Dense hot regions use the same local source function
for opacity and re-emission, so they converge toward local Planck radiance
instead of behaving like cold absorbing clouds.

Current implementation notes:

- The final render stays on the visible thermal/blackbody branch. The
  `grmhd-hot-flow` / `grmhd-structure-flow` path remains a diagnostic for seeing
  optically thin GRMHD morphology, not the human-visible temperature target.
- `--presentation-mode scientific` with `grmhd-temperature-flow` uses a
  linear/ideal display look by default. The default human-visible render remains
  `eye + realistic`. This keeps scientific PNG comparisons from being biased by
  the observer-facing look while leaving the raw scientific HDR path unchanged.
- GRMHD density, electron-temperature proxy, magnetic field, Maxwell-stress
  proxy, and local azimuthal flow modulate the volume RT coefficients before
  transport. They are not composited as a separate PNG or display overlay.
- The thermal source now includes a bounded local dissipation proxy
  `q+ ~ -B_r B_phi * r dOmega/dr`, using Maxwell stress and the sampled
  azimuthal flow as code-unit inputs. This is not an absolute radiation field;
  it is the current physically motivated bridge between a non-radiative public
  primitive dump and visible thermal source-function variation.
- In `grmhd-temperature-flow`, unresolved cloudlet structure is biased toward
  thermal emissivity and source-function variation. It is deliberately weak in
  pure absorption so hot dense gas does not become a cold foreground slab.
- The thermal cloud term is now calibrated as a bounded fraction of the local
  thermal LTE emissivity, not as a fixed `source / rs` floor. It keeps the same
  temperature-derived spectrum as the smooth thermal branch, while GRMHD
  density, pressure, magnetic stress, and local residuals decide where the
  optically thin thermal cloud emission contributes.
- Use `--disk-grmhd-debug jthermal-cloud` and
  `--disk-grmhd-debug thermal-cloud-ratio` to verify that the cloud term is
  actually present in RT radiance. `jthermal-cloud` shows the line-integrated
  cloud emissivity; `thermal-cloud-ratio` shows its approximate post-RT
  contribution fraction in the visible thermal branch.
- Use `--disk-grmhd-debug flow-residual` to inspect the local GRMHD phi/field
  residual that is allowed to drive thermal-flow texture. If this map is smooth
  or nearly black, the input snapshot itself does not contain enough
  non-axisymmetric flow structure for the temperature-flow renderer to reveal.
- The thermal branch now computes a local 3D residual from GRMHD cells around
  the same sample point: `r +/- one local step`, `phi +/- one volume cell`,
  `z +/- one volume cell`, plus one opposite-azimuth reference for broad
  asymmetry. The residual is applied to thermal emissivity/source before RT.
  This preserves flow structure already present in the evolved data without
  image-space noise, late RGB compositing, or synthetic periodic cloud bands.
- A weak disk-coordinate thermal atmosphere floor is applied to the emissivity
  branch only, but it is intentionally small. It is tied to local GRMHD
  rho/theta_e/B and height above the midplane, and exists only to compensate for
  coarse public snapshots that under-sample visible thermal emission between
  dense cells. If it becomes visually dominant, lower it before increasing
  presentation contrast.
- The earlier advected Fourier/shear cloudlet closure has been removed from the
  default temperature-flow RT path. Structure recovery now depends on measured
  local GRMHD residuals and temporal HDF5 blending rather than a synthetic
  periodic pattern.
- The optically thin thermal cloud branch has a lower always-on floor and a
  higher smooth-continuum floor than the first structure-recovery pass. This is
  deliberate: the cloud branch should reveal density/B/stress residuals, but it
  should not become the whole temperature-flow image.
- The temperature-flow branch applies a radial thermal-coefficient weight before
  RT. The imported primitive density is a code-unit mass column, not a calibrated
  visible luminosity; weighting `j` and `alpha` by the local temperature/flux
  scale prevents cold outer mass from dominating the render as a flat gray slab.
- The finite imported volume is radially apodized near the selected crop edge.
  The sampled GRMHD state is unchanged, but emission and absorption coefficients
  fade together near `selectedRMax` so the memory/performance crop does not
  render as a hard outer sheet.
- The `grmhd-hybrid` visible temperature backbone now uses a Novikov-Thorne
  flux-shape profile normalized to `--teff-T0` at `--teff-r0`, instead of a
  pure power law. This keeps the inner-edge/radial thermal shape physically
  interpretable even when the snapshot density is still in code units.
- If `--bh-mass` and `--mdot` are supplied without an explicit `--teff-T0`, the
  GRMHD-hybrid visible path derives the `T0` anchor from the thin-disk flux at
  `--teff-r0`. The ray-tracing geometry remains scale-free in `r/rs`; the
  temperature calibration converts that dimensionless radius to the Schwarzschild
  radius implied by `--bh-mass`. The GRMHD `theta_e` proxy reference is kept
  separate from this visible color-temperature anchor so cooler physical disks do
  not artificially inflate `theta_e/theta_ref` and turn blue again.
- The `grmhd-temperature-flow` preset sets `--disk-grmhd-emission-scale 1e-10`
  by default. This is a code-unit-to-visible calibration for the public sample,
  not a claim about physical SI density normalization. Override it explicitly
  when a snapshot has calibrated density/accretion-rate units.
- The current sample still has smooth large-scale thermal source-function
  structure. The local dissipation proxy improves source contrast where stress
  and shear are present, but high-order lensing can still repeat low-resolution
  volume cells as ring/stripe artifacts. If the foreground disk remains too
  uniform or too cell-like after the data-residual closure, the next scientific
  fix is better time-dependent/radiative GRMHD input or GPU interpolation across
  snapshots, not stronger post-processing.
- GRMHD volume preprocessing now writes `rNormWarp` metadata. The default
  `--disk-grmhd-r-warp 0.65` allocates more radial texels to the inner flow,
  where lensing magnification makes coarse linear radial sampling show up as
  ring/banding artifacts. Existing volume metadata without `rNormWarp` remains
  linear (`1.0`) for backward compatibility.
- The temperature-flow preset now applies a conservative visible-structure
  `--disk-grmhd-phi-contrast 1.8` bridge by default. This still amplifies only
  deviations already present in the HDF5 azimuthal direction, but avoids turning
  already-turbulent evolved snapshots into dark crack/contour artifacts. Use
  `--disk-grmhd-phi-contrast 1.0` for raw snapshot contrast, or higher values
  only for controlled structure-sensitivity tests on nearly axisymmetric data.
- The preset also applies `--disk-grmhd-phi-residual-smooth 0.45` with one
  periodic low-pass pass and a weak `--disk-grmhd-rz-residual-smooth 0.18`.
  These preserve each phi-ring mean while band-limiting coarse-cell residuals
  that strong lensing can repeat into rings. If the output becomes too smooth,
  lower r-z smoothing first, then phi smoothing.
- The preset keeps `--disk-precision-texture 0.55` by default. The earlier
  stronger value exposed structure in weak demo samples but over-sharpened real
  evolved snapshots. The current default favors data-structure preservation over
  synthetic-looking residual contrast.
- Increasing the GRMHD volume grid from `128x256x72` to `160x384x96` reduces
  some interpolation pressure but did not materially fix the lensed cell/ring
  artifact in the current public sample. Treat higher volume resolution as a
  high-quality option, not a default, because it roughly doubles transient
  volume memory while the dominant limitation is still source-data and residual
  scale, not texture sampling alone.
- The `diskPrecisionTexture` value is intentionally preserved after
  accretion-model default packing. GRMHD visible uses this field as a
  state/flow-contrast strength, while precision NT mode uses it as microtexture.
  `--validate-packed-abi` should pass before trusting texture/flow tuning.
- The visible branch disables cool dust/gas absorption by default. If cold
  absorbing material is enabled explicitly, it is an experiment and should be
  validated with `source-thermal`, `thermal-alpha-post`, and `y` debug maps.
- GRMHD visible volume RT packs linear XYZ into the collision record; compose
  must treat the negative `noise` sentinel as "already integrated radiance", not
  as a cloud-density mask.

## When To Run Fluid Locally

Do not add random image-space texture when structure is missing. Use this order:

1. Try a real evolved GRMHD snapshot from the public catalog.
2. Audit `flowPhiP95` and `dynamicsPhiP95`.
3. If public snapshots are unsuitable for the target, run or import a fluid
   simulation with explicit density, internal energy or electron temperature,
   velocity, and magnetic field.
4. Use controlled perturbation only as a pipeline test, not as scientific truth.

For this renderer, evolved 3D GRMHD data is now available and verified, so local
fluid generation is a fallback for custom scenarios rather than the immediate
best next step.

## Current Time-Series Status

The fetcher can download consecutive evolved snapshots and preserve a sequence
manifest. The GRMHD atlas path blends post-reduction atlases, while the GRMHD
volume path now supports a conservative CPU-side temporal bridge:

```bash
./Blackhole/run_pipeline.sh \
  --science-regime grmhd-temperature-flow \
  --disk-hdf5 /tmp/bh_real_grmhd_sequence/SANE_a0_torus.out0.05000.h5 \
  --disk-hdf5-next /tmp/bh_real_grmhd_sequence/SANE_a0_torus.out0.05001.h5 \
  --disk-hdf5-time-blend 0.5
```

For the volume path this creates a cached intermediate HDF5 state before
`build_grmhd_volumes.py` runs. `RHO` and `UU` primitive components are blended in
log space, while velocity and magnetic primitive components are blended
linearly. This keeps adjacent-snapshot motion inspectable without changing the
Metal resource layout.

This is intentionally not the final interactive solution. The next
scientifically meaningful step is still a GPU two-volume binding with a runtime
time interpolation parameter. For the current temperature-flow target, compare
fixed-camera `raw-log`, `jthermal`, `jthermal-cloud`,
`thermal-cloud-ratio`, and flow-state maps across adjacent dumps before enabling
any artistic time animation. `jthin` remains useful for the hot-flow diagnostic,
but it is not the primary diagnostic for the thermal blackbody path.
