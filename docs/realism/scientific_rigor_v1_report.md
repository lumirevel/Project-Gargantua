# Scientific Rigor V1 Report

Branch: `codex/scientific-rigor-v1` (from `codex/integration/physics-camera-v1-legacy-recovery` @ 11a728d)

Goal: move both the physical source model and the interpreter/camera layer
closer to "measured-at-the-black-hole" rigor, per the project goal of
paper-grade physical correctness with film-grade visual realism.

## 1. What Changed

### 1.1 Tabulated CIE 1931 standard observer (93425f7)

- `Blackhole/Metal/cie_cmf.metalh` (new): CIE 1931 2-degree color matching
  functions tabulated at 5 nm, 380-780 nm, with linear interpolation, shared
  by all Metal spectral paths through `integral.metal`.
- `comp_cie_xyz_bar` (spectrum_visible.metal), `volume_cie_xyz_bar`
  (volume_rt.metal), and the Swift `cieXYZBar`
  (Sources/Core/Physics/VisibleSpectrum.swift) now delegate to the same table,
  replacing three copies of a multi-Gaussian analytic fit.

Why: the fit carried up to 0.0023 xy chromaticity error on the blackbody
locus, worst at low temperatures - exactly where disk redshift pushes the
observed spectrum on the receding side. The table is the standard itself.

### 1.2 ISO 12232 saturation-based photographic exposure (c11f603)

- `--exposure-mode photographic` now applies the physical exposure equation:
  sensor exposure `H = q * (pi/4) * L * t / N^2` with `q = 0.65`, clipping at
  `H_sat = 78 / ISO`, scene luminance `L = 683.002 * CIE-Y cd/m^2` (the
  canonical visible spectral path integrates SI spectral radiance, so its Y is
  already `W m^-2 sr^-1`).
- `--photographic-calibration legacy` reproduces the previous arbitrary
  `100 * t * (ISO/100) / N^2` scale; `--camera-luminance-scale` is the
  documented cd/m^2-per-Y bridge for non-SI sources.
- Metadata and exposure diagnostics record `photographicCalibration`,
  `cameraLuminanceScale`, and `photometricSaturationLuminance` (the absolute
  luminance in cd/m^2 that exactly saturates the sensor at the chosen
  settings).

Why: the previous note in `photographic_camera_controls_notes.md` explicitly
labelled the old constant "an interpreter calibration, not a physics-unit
claim". This change upgrades it to the physics-unit claim: a real camera at
the same aperture/shutter/ISO pointed at a scene of the same absolute
luminance clips at the same point.

### 1.3 Geodesic-level bracketed bisection for disk surface hits (3499407, 8ba1f5e)

- `trace_refine_schwarzschild_surface_hit_state` and
  `trace_refine_kerr_surface_hit_state` previously located the disk crossing
  on the straight chord between integrated step endpoints and re-integrated to
  that chord parameter, inheriting the chord's curvature error near the photon
  sphere. The bracket is now tightened with 5 bisection iterations against
  true integrated states (single RK4 / DP45 trial steps from the sub-segment
  start). The chord solution seeds the bracket; the segment fallback is
  preserved (accuracy plan Phase A).
- The thin-crossing predicate (midplane z-sign flip) requires the trial point
  radius to lie within the emission annulus, mirroring
  `segment_enter_disk`'s validation of the chord z-crossing.
- Also fixes `pipeline_eta.py` argument splitting (argparse.REMAINDER
  abbreviation-matched wrapped flags such as `--h` on Python 3.12).

Why: per `docs/accuracy_upgrade_plan.md`, sub-step event localization is the
highest-ROI accuracy upgrade: it sharpens thin-disk crossings, photon-ring
edges, and the hit positions that feed the invariant g-factor and the NT
temperature.

### 1.4 Physical shutter-time motion blur (8ecb5c6)

- `--motion-blur-samples N` (with `--camera-shutter`) time-averages the
  disk-coordinate heating skin, spiral, and corona branches of the canonical
  visible source over the real shutter window, inside compose.
- Physical mapping: one `diskFlowTime` unit equals `sqrt(2) * rs / c` seconds,
  derived from the heating-field shear convention
  `phase = diskFlowTime * (r/rs)^-1.5` against the Keplerian rate
  `dphi/dt = (c / (sqrt(2) rs)) * (r/rs)^-1.5`. For the geometry-default
  black hole (`M = 1e35 kg`, `rs = 1.485e8 m`) the ISCO orbital period is
  ~23 s, so ordinary shutter speeds correctly freeze the disk and
  tens-of-seconds exposures smear the turbulent skin along the orbital shear.
- `--motion-blur-time-lapse` scales simulation seconds per camera second for
  labelled time-lapse output.
- ABI: `PackedParams` grew one trailing `float4 motionBlurParams`
  (672 -> 688 bytes), covered by `--validate-packed-abi`.

Why and why this is exact for this source: geodesics, the stationary flow
field, the g-factor, and the analytic photosphere are all time-independent in
this renderer; the only time-dependent quantity is the advected heating
pattern, which is evaluated in compose at the shared hit geometry. Averaging
the resulting radiance branches over the shutter window is therefore exact
temporal supersampling, not a screen-space approximation. Radiance (not the
heating field) is averaged so the nonlinear field-to-radiance response is
preserved.

## 2. Validation

- CIE table: `scripts/validate_cie_cmf_accuracy.py` checks the table against
  published Planckian-locus chromaticities (agreement within 0.00006 xy;
  transcription verified) and quantifies the retired fit's error (up to
  0.00234 xy at 2500 K).
- Photographic exposure: f/1.4 vs f/2.8 = 4.0000x, ISO 800 vs ISO 100 =
  8.0000x, reciprocity f/5.6 + 1/240 + ISO 1600 == f/2.8 + 1/60 + ISO 100
  exactly, legacy ratio 0.2237 = 1/4.4699 as derived. Saturation luminance at
  f/2.8, 1/60 s, ISO 100 is 718.7 cd/m^2, consistent with the standard
  ~3.6-stop saturation headroom above a metered mid-grey.
- Bisection: with matched ray budgets (`--max-steps` scaled with 1/h) on
  `thin-disk-visible-reference`, the mean 8-bit image difference between
  h = 0.01 and h = 0.005 dropped from 0.0212 to 0.0003 (Schwarzschild) and
  from 0.0879 to 0.0039 (Kerr a = 0.9); pixels differing by more than 32
  dropped to ~0. Render time unchanged. After the radial-bounds guard, the
  canonical 640x360 render differs by 3 bytes of 691,560.
- Motion blur: with blur off, renders are byte-identical (PNG IDAT equality at
  640x360) to the pre-change binary; 1/60 s with 24 samples differs by at most
  1/255 (dither); 30 s shutter shows local smearing up to 31/255 in skin
  regions. ABI validation passes with `motionBlurParams` at offset 672.

## 3. Remaining Risks / Known Limits

- The three-band GRMHD visible reconstruction
  (`comp_visible_xyz_from_three_band_inu`) still log-linearly interpolates the
  spectrum through anchors that were grid-searched under the old Gaussian CMF;
  the anchors remain reasonable but could be re-optimized against the table.
- Absolute photometric calibration assumes the SI visible spectral path. Other
  source paths must declare `--camera-luminance-scale`; nothing enforces this.
- Motion blur covers the canonical/thin visible source family (compose-side
  emission). Trace-side time-dependent paths (precision clouds, GRMHD volume
  flows) ignore the shutter window; a full slow-light/subframe trace remains
  future work (accuracy plan Phase D).
- The bisection improves event localization within the accepted step; the
  step acceptance itself (RK4/DP45 tolerances) is unchanged, as planned.
- Filmic looks approximate a camera's shoulder response near saturation;
  `--look none` is the exact clip path for radiometric reads.
