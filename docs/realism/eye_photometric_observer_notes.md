# Physically Anchored Eye Observer Notes

Branch: `codex/scientific-rigor-v1` (commit f4ef97c)

## What this is

`--presentation eye` previously used histogram auto-exposure plus display tone
curves - an abstract observer. It is now a physical interpreter: the chain the
project goal demands ("safe filtering -> retina -> adaptation -> brightness and
color perception") is modeled explicitly, anchored in absolute luminance.

## The chain

1. **Absolute luminance.** All visible spectral paths now integrate SI
   spectral radiance (the missing dLambda factor was fixed in three places),
   so `683.002 * CIE-Y * cameraLuminanceScale` is luminance in cd/m^2. The
   canonical disk measures ~7.7e9 cd/m^2 at p99.5 - about five times the
   solar surface, as expected for annuli hotter than the sun.
2. **Safe-viewing filter.** Direct viewing is impossible (retinal damage), so
   the eye path inserts a neutral-density filter: `--eye-nd <density>` (log10
   attenuation), auto-solved so the p99.5 luminance lands at
   `--eye-target-luminance` (default 8000 cd/m^2, bright sky). Auto resolves
   ND 5.98 for the canonical scene - the same order as real solar filters.
   The ND is a pure linear attenuation carried through the exposure
   multiplier, which is exactly what a physical ND filter is.
3. **Adaptation.** The retina adapts to the filtered scene median
   (`--eye-adaptation` override). Stanley-Davies pupil diameter is computed
   and reported.
4. **Photoreceptor response.** Naka-Rushton compression
   R = L^n/(L^n + sigma^n), n = 0.74, sigma at the adaptation luminance,
   display white anchored at `--eye-white-multiple` x adaptation (default 8).
5. **Mesopic vision.** Rod weight rises below ~3 cd/m^2 (rod saturation
   limit) and is total below 0.005 cd/m^2. The rod signal uses the Larson et
   al. (1997) scotopic luminance estimate from XYZ and renders as the
   achromatic Purkinje blue-gray. Lineage: Ferwerda et al. 1996, Durand &
   Dorsey 2000.

## Validated behavior

- Auto-ND (photopic): warm gold-brown outer disk (the real color of the
  cooler annuli) with the hot inner disk compressed toward white - the
  appearance an adapted eye behind a solar filter would get.
- `--eye-nd 9.5` (mesopic, adaptation ~0.2 cd/m^2): desaturation and Purkinje
  blue shift; warm outer color disappears.
- `--eye-nd 11` (near-scotopic, ~0.006 cd/m^2): nearly achromatic, dimmer.
- Cross-interpreter consistency: the photographic camera at its mechanical
  limits (f/16, 1/8000 s, ISO 100, EV ~21) is still ~11 stops over for the
  same scene (proper exposure needs EV ~32.3, i.e. an ND ~3.4 filter);
  with `--exposure-ev -11.3` the photographic render lands at proper
  exposure. Eye and camera agree on the same absolute light.

## Limits / next

- The physiological path runs on the GPU compose paths (full-GPU and
  hdr32-file); the legacy CPU compose keeps the previous eye behavior.
- Temporal adaptation (light/dark adaptation dynamics) is not modeled; the
  eye is in steady state.
- Veiling glare / caustic-spike handling from the previous eye path still
  applies before the physiological mapping.
- The photon-statistics sensor noise model is implemented (commit e750659):
  electrons per photosite follow the absolute exposure exactly
  (N_sat = min(QE * 11000 * pitch^2 * 78/ISO, fullWell)), with Poisson shot
  noise, read/dark/DSNU floor, PRNU, and hard ADC clip at saturation, applied
  in the linear domain at full input resolution. Validated quantitatively:
  predicted correlated-noise diff 0.99 DN vs measured 1.08 DN between
  equivalent exposures at ISO 100 and ISO 6400 under --look none. The
  heuristic display-domain noise scalars are replaced when the model is
  active (photographic + photometric; --camera-photon-noise off to disable).
