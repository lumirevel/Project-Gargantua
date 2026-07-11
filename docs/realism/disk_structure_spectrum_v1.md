# Disk Structure Spectrum V1 (Grand-Design Spiral → Sheared Filaments)

Date: 2026-07-11

Branch: `disk-physics-improvement`

## Symptom

The recommended source (`canonical-visible-disk-v1`), viewed through the GUI
**Camera** observer, showed a prominent, artificial-looking grand-design
two/three-arm pinwheel. The native canonical profile (realismProfile 5,
spectral field) already looked correct — fine, tightly-wound sheared
striations — but the Camera observer overrides the source's realism profile
with **observational** (realismProfile 2), whose structure comes from a
different, coarser field.

## Root cause

`comp_thin_mri_shearing_field` (helpers.metalh, the observational/cinematic
structure) built its low-azimuthal-order channels with **fixed** radial-winding
constants:

```
channel2 = sin(2*shear + 5.2*logR + ...)   // m=2, winding 5.2/2 = 2.6 per e-fold
channel3 = sin(3*... + 8.8*logR ...)        // m=3, winding 2.9
channel5 = sin(5*... + 14.0*logR ...)       // m=5, winding 2.8
f.channel = 0.48*ch2 + 0.32*ch3 + 0.20*ch5  // m=2 dominant
raw       = 0.60*f.channel + ...            // channels = 60% of the field
```

A winding of ~2.6 per e-fold is a very **open** spiral (the arm wraps only
~0.4 turns per factor-e in radius), and with m=2 weighted highest and the
channels forming 60% of the perturbation, the surface is dominated by an open
grand-design two-arm spiral. That is not what a differentially-rotating MRI
photosphere produces: MRI trailing spirals have **small pitch angles** (a few
to ~15°), i.e. they are **tightly wound**, and the structure is turbulent
(broad wavenumber content) rather than a couple of dominant low-m arms.

A related, milder issue in the spectral field (`comp_thin_spectral_heating_
field`, realismProfile 5/6): pure Kolmogorov `k^-1/3` per-mode amplitude over a
log-uniform `kr = 0.85..170` range piles the most amplitude onto the
disk-scale `kr~1, m=2` mode. A shearing disk has **no inverse cascade**, so
there should be essentially no surface-brightness power at scales larger than
the largest eddies (~ a few H).

## Fix (both physically motivated, structure only)

`comp_thin_mri_shearing_field` (observational/cinematic, realismProfile 2/3/4):
- Tie the channel winding to the local shear coherence
  `wind = 3.6 * radialCoherence` (`radialCoherence ~ 1/(H/r)`) instead of fixed
  constants, so a given m-arm wraps many times per e-fold in a thin disk —
  small pitch angle, tightly wound.
- Rebalance the perturbation toward the fine filament/eddy content:
  `f.channel` 0.48/0.32/0.20 → 0.30/0.32/0.38 (lift higher-m), and in `raw`
  channel weight 0.60 → 0.34 with filament 0.34 → 0.52 and eddy 0.16 → 0.26.
- Legacy periodic-thin (`--disk-model periodic`) keeps its historic
  channel-dominated balance for exact reproduction.

`comp_thin_spectral_heating_field` (canonical/PCD, realismProfile 5/6):
- Add an outer-scale (driving) cutoff `outerCut = x²/(1+x²)`,
  `x = |kr| / krDrive`, `krDrive = 2π / (6·H/r)` per ln r, suppressing modes
  with radial wavelength larger than ~6 H so the disk-scale power (and the
  grand-design spiral it produces) is removed while the driving-scale-and-
  smaller filaments remain.

No physics core, no radiance, no exposure, no camera path is touched — this is
the emissivity **structure spectrum** of the phenomenological thin-disk skin
(explicitly a constrained model, resolution-honest via the existing
footprint/photospheric filters).

## Verification

- Interstellar 220×140 guardrail md5 `e0066d3fbd2784f98d8806cad3b3cf0c`
  unchanged (legacy preset does not use these skin fields).
- Native canonical (realismProfile 5) unchanged in character — still fine
  filaments (the outer-scale cut only removes residual disk-scale power).
- Observational face-on and inclined Camera renders: the grand-design pinwheel
  is gone, replaced by tightly-wound sheared striations.
- Validators PASS: presentation_modes, presentation_source_matrix,
  scientific_raw_purity, physics_constrained_cinematic_disk.

## Note (routing, out of scope)

The deeper conflation — the Camera observer replacing a *source's* physical
structure profile with `observational` — remains. This change makes the
observational structure itself physically defensible, which resolves the
appearance issue for every Camera-viewed source; decoupling source structure
from the observer profile is a separate, larger refactor.
