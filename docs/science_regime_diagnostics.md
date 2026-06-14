# Science Regime Diagnostics

Use this workflow when judging whether a render problem is caused by the
renderer, the emission model, or the input GRMHD state.

```bash
python3 Blackhole/scripts/science_regime_diagnostics.py \
  --snapshot path/to/snapshot.h5 \
  --out-dir /tmp/blackhole_science_diagnostics \
  --width 384 --height 384
```

If no `--snapshot` is provided, the script generates a small Fishbone-Moncrief
initial-condition sample. That sample is useful for pipeline tests, but it is
not evolved GRMHD and should not be used as evidence of real turbulent structure.

## Outputs

The script writes:

- `report.json`: command log, audit stats, image stats, notes.
- `contact_sheet.png`: side-by-side visual summary.
- `thin_visible.png`: visible thin-disk scientific master.
- `experience.png`: human-eye presentation.
- `grmhd_structure_flow.png`: GRMHD-native optically thin 9-band hot-flow structure diagnostic.
- `grmhd_hot_flow.png`: backward-compatible alias render for older comparisons.
- `grmhd_photosphere.png`: GRMHD visible-photosphere diagnostic.
- `debug_*.png`: GRMHD maps for density, electron temperature, emissivity, raw log intensity, and other requested fields.
- `freq_*.png`: frequency sweep outputs when enabled.
- `electron_*.png`: electron-temperature prescription sweep outputs when enabled.
- `synch_scale_*.png`: GRMHD hot-flow nonthermal branch scale sweep.
- `photo_kappa_*.png`: GRMHD visible-photosphere opacity sweep.

## Structure Test

To test whether the renderer can reveal non-axisymmetric structure when the data
contains it, use a controlled perturbation:

```bash
python3 Blackhole/scripts/science_regime_diagnostics.py \
  --snapshot path/to/snapshot.h5 \
  --structure-test-amp 0.10 \
  --structure-test-scale 12 \
  --out-dir /tmp/blackhole_structure_test
```

This writes a separate HDF5 file and labels it as a controlled structure test.
It is not evolved GRMHD truth. It exists to separate two questions:

- Does the input data actually contain phi-direction structure?
- If it does, does the renderer preserve that structure into emissivity and raw intensity?

## Interpreting Phi Variation

The GRMHD audit reports `flowPhiP95` and `dynamicsPhiP95`.

- `flowPhiP95 < 0.02`: expect very smooth, nearly axisymmetric visible flow.
- `0.02...0.08`: limited structure may survive, depending on transfer opacity.
- `> 0.08`: the snapshot has enough density/temperature phi contrast for visible structure tests.

`dynamicsPhiP95` is driven by magnetic-field and velocity variation. If it stays
near zero, synchrotron or Doppler-driven texture will remain weak even if density
has been perturbed.

## Electron Sweep

The script renders `single-temp` and `r-beta` electron models:

```bash
python3 Blackhole/scripts/science_regime_diagnostics.py \
  --snapshot path/to/snapshot.h5 \
  --out-dir /tmp/blackhole_electron_check
```

The sweep changes the render only when `thetae` is derived from internal energy.
If the snapshot already provides a direct `thetae` dataset, the renderer uses that
dataset and the electron-model sweep should be visually identical. That is not a
bug; it means the data source already supplied the electron-temperature field.

## Recommended Use

1. Run the script on the real snapshot without perturbation.
2. Check `report.json` for `quality.rating`, `flowPhiP95`, and `dynamicsPhiP95`.
3. Inspect `debug_rho`, `debug_thetae`, `debug_jthin`, and `debug_raw_log`.
4. If the real snapshot is too axisymmetric, run a controlled structure test.
5. If the controlled test shows structure but the real snapshot does not, the next
   upgrade is better/evolved input data, not stronger post-processing.

For real evolved primitive dumps, judge `grmhd_structure_flow` together with the
`synch_scale_*` sweep. If all positive scales collapse to the same white mask,
the synchrotron code-unit calibration is too high. If `synch_scale_1p0` preserves
inner-flow structure but remains dim, that is expected for the current
scientific diagnostic path; tune exposure/presentation separately rather than
raising the physical branch until it saturates again.

`debug_raw_log` uses a broad GRMHD diagnostic range that is intentionally
separate from the exposure histogram range. Do not treat it as a display image:
it exists to answer whether raw scientific intensity still carries structure
before exposure, tone mapping, and camera/eye presentation.

For `grmhd-temperature-flow`, `--disk-grmhd-debug source` is calibrated to the
current code-unit thermal source-function range rather than final frame
luminance. If `branch-ratio` is black/blue while `source` has structure, the
temperature-flow render is thermal-dominated and the optically thin/kappa branch
is not contributing meaningfully. That is a branch-balance diagnosis, not a
display failure.

If the final target is a human-visible temperature disk with GRMHD flow texture,
do not use `grmhd_structure_flow.png` as the final frame. Use
`--science-regime grmhd-temperature-flow`, which samples the 3D GRMHD state and
integrates visible-band thermal RT in the Metal volume loop. `grmhd_structure_flow`
remains useful only to inspect whether the input data contains visible flow
structure before thermal source-function smoothing.

`--disk-grmhd-debug flow-residual` shows the maximum local GRMHD phi/field
residual sampled by each ray. It is the first check when the temperature-flow
image looks too smooth: a structured residual map plus smooth `source` map means
the source-function closure is still smoothing the data; a smooth residual map
means the current snapshot is intrinsically too axisymmetric for rich flow
texture.

## Time Variation

Use the Illinois fetcher range mode to collect adjacent evolved dumps:

```bash
python3 Blackhole/scripts/fetch_illinois_grmhd_snapshot.py \
  --flux SANE \
  --spin 0 \
  --start-index 0 \
  --count 4 \
  --out-dir /tmp/blackhole_real_grmhd_sequence
```

The GRMHD volume path can now build a cached intermediate HDF5 state from two
adjacent dumps. Use the temporal diagnostic sweep to compare final temperature
RT against the same flow/transfer debug maps:

```bash
python3 Blackhole/scripts/science_regime_diagnostics.py \
  --snapshot /tmp/bh_real_grmhd_sequence/SANE_a0_torus.out0.05000.h5 \
  --snapshot-next /tmp/bh_real_grmhd_sequence/SANE_a0_torus.out0.05001.h5 \
  --time-blend 0.0 \
  --time-blend 0.5 \
  --time-blend 1.0 \
  --temporal-only \
  --out-dir /tmp/blackhole_temporal_diag \
  --width 384 \
  --height 240
```

This writes per-map contact sheets such as `temporal_raw_log_contact_sheet.png`,
`temporal_jthermal_cloud_contact_sheet.png`, and
`temporal_thermal_cloud_ratio_contact_sheet.png`, plus `imageDiffs` in
`report.json`. In `grmhd-temperature-flow`, `jthin` is intentionally not the
primary map because the final visible target is the thermal blackbody path, not
the optically thin synchrotron diagnostic. Use the thermal/cloud maps before
tuning transfer coefficients: if `rho/thetae/bmag/jthermal-cloud/raw-log`
change more than `final`, the remaining bottleneck is source-function or display
smoothing rather than missing fluid motion. GPU-side two-snapshot interpolation
is still the right later step for interactive animation, but this diagnostic is
the safer scientific gate.

`thermal-alpha-pre` and `thermal-alpha-post` are centered on high-column
line-integrated opacity in the current public GRMHD dumps. Treat these as
structure/relative-opacity maps, not calibrated SI opacity measurements. If a
future dataset uses a different density/accretion-rate normalization, inspect
the raw collision `noise/emit_r_norm` value range before retuning the diagnostic
ramp.

`source` and `source-thermal` are also code-unit transfer diagnostics, not final
display luminance. Their debug ramp is intentionally centered on the current
visible thermal source-function range so Maxwell-stress/shear heating structure
can be inspected directly. If these maps are smooth while `rho/thetae/bmag` are
structured, the remaining bottleneck is still the source-function model or the
input radiation/electron thermodynamics, not camera presentation.

## Coarse-Cell Ringing Check

If a temperature-flow frame shows thin repeated rings or stripe-like cell
boundaries even when SSAA does not help, test the GRMHD volume preprocessing
rather than post-blurring the image:

```bash
./Blackhole/run_pipeline.sh \
  --science-regime grmhd-temperature-flow \
  --disk-hdf5 path/to/snapshot_05000.h5 \
  --disk-hdf5-next path/to/snapshot_05001.h5 \
  --disk-hdf5-time-blend 0.5 \
  --disk-grmhd-phi-residual-smooth 0.0 \
  --disk-grmhd-rz-residual-smooth 0.0

./Blackhole/run_pipeline.sh \
  --science-regime grmhd-temperature-flow \
  --disk-hdf5 path/to/snapshot_05000.h5 \
  --disk-hdf5-next path/to/snapshot_05001.h5 \
  --disk-hdf5-time-blend 0.5 \
  --disk-grmhd-phi-residual-smooth 0.45 \
  --disk-grmhd-rz-residual-smooth 0.18
```

`phi-residual-smooth` preserves the imported phi-ring mean and only low-passes
the zero-mean azimuthal residual. The current temperature-flow preset uses
`0.45`, `--disk-grmhd-rz-residual-smooth 0.18`, and
`--disk-precision-texture 0.55` because real evolved snapshots already contain
strong phi structure. These defaults preserve flow structure while reducing
dark crack/contour artifacts from over-amplified coarse residuals. If the output
becomes too smooth, lower r-z smoothing first, then phi smoothing; if it remains
too cell-like, lower `--disk-precision-texture` before increasing presentation
contrast.
