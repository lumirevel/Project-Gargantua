# Disk Physics V2 Report

Branch: `codex/scientific-rigor-v1` (continuation; commits 119fc61, b30e6bd)

Driving question (from project direction): "the disk is a fluid, so should it
show fluid texture (결)? Nothing I tried ever produced it."

## 1. The Physical Answer First

Yes - the intuition is physically correct, with two qualifications.

A luminous thin disk's visible photosphere carries MRI-driven turbulent
surface-brightness fluctuations of order 10-30% locally (radiation-MHD:
Hirose+ 2006, Blaes+ 2011, Jiang+ 2013). Differential rotation shears them
into trailing, azimuthally elongated filaments with pitch angles of a few
degrees - locally they read as fine, slightly spiraled striations, not
cloud-like blobs. The two qualifications:

1. The dominant structure scale is the scale height H (~2-5% of r for a thin
   disk), so the texture only resolves when the camera actually resolves ~H.
   At low resolution a physically honest renderer must show a smooth disk.
2. Structure smaller than the camera footprint or the photospheric diffusion
   scale (~H) genuinely averages away. Both filters exist in this renderer
   and are correct; they were not the reason the texture was missing.

## 2. Why No Texture Ever Appeared (Root Cause)

Reproducing the exact shader math in Python (1440 azimuthal samples, several
radii and H/r values) localized the failure to the *activity gating*, not the
resolution chain:

- The filament channel summed ~50 positive ridge modes and normalized by the
  mean. A sum of many independent positive fields flattens as 1/sqrt(N): the
  normalized field measured mean 0.97 with sigma 0.05 against a smoothstep
  window topping out at ~0.89 - pinned at 1.0 everywhere.
- The high-pass channel's window (0.38..1.12) sat above nearly the entire
  field distribution (sigma 0.22-0.31) - pinned at ~0.
- Cloud packets are sparse by design - ~0 between packets.

Net effect: `activity = 0.34*0 + 0.20*0 + 0.46*1 = a flat constant ~0.46`.
A spatially constant activity is a uniform brightness lift - no texture at
any resolution, by construction. Widening the mode spectrum alone made it
*flatter* (more modes, stronger law-of-large-numbers averaging).

## 3. What Changed

### 3.1 Exact relativistic orbital kinematics (119fc61)

The Schwarzschild surface path fed the coordinate value sqrt(M/r) into the
g-factor contraction as the local orthonormal-frame orbital speed. The exact
static-observer speed of a circular orbit is v = sqrt(M/(r-2M)) (0.5c at the
ISCO). Validated analytically: the contraction now reproduces
u^t = 1/sqrt(1-3M/r) and face-on g = sqrt(1-3M/r) to machine precision at
r/M = 6..100; the old code under-redshifted by +5.4% in g at the ISCO. The
Kerr surface path already used exact metric contractions (omega =
1/(r^{3/2}+a), covariant u^t; plunge from conserved ISCO E, L) and is
unchanged.

### 3.2 Physical turbulence spectrum (b30e6bd)

- Radial wavenumbers log-uniform 0.85..170 per ln r (down to ~2H), replacing
  the kr <= 18 cap (~10x coarser than the MRI driving scale).
- Shear anisotropy: m = kr / elongation, elongation 3-11
  (lambda_phi/lambda_r), giving trailing azimuthally stretched filaments.
- Kolmogorov E(k) ~ k^-5/3 preserved under log-density sampling (per-mode
  amplitude ~ k^-1/3).
- Photospheric smoothing floor reduced from 1.65-2.60 H/r to 0.62-1.05 H/r
  (radiative diffusion thermalizes below ~one scale height, not ten).
  Camera-footprint filtering unchanged.

### 3.3 Log-normal dissipation intermittency (b30e6bd)

The filament channel is now the strong tail of a mean-one log-normal of the
unit-variance sheared spectral field (sigma_q = 0.70 + 0.25*turbulenceTune) -
the standard intermittency closure for turbulent dissipation, replacing the
saturating mean-of-ridges construction. The high-pass window is recalibrated
to the field's measured sigma. Energy-budget caps (fSkin clamp, branch
normalization, body backbone) are unchanged: the same skin budget is
redistributed in space/time, not increased.

## 4. Validation

- Kinematics: analytic table r/M = 6..100, old error +5.41%..+0.01%, new
  error 0.000% (face-on g vs sqrt(1-3M/r)).
- Field statistics (Python replica of shader math): activity mean 0.07-0.14,
  sigma up to 0.24, bright-filament area 13-23%, azimuthal correlation width
  7-16 degrees across H/r = 0.01-0.04, r/r_in = 1.7-4.7.
- Rendered behavior: fine sheared striations resolve at fov 25, 1280x720 and
  are absent (averaged) at full-disk 640x360 - resolution-honest. Under a
  30 s shutter with --motion-blur-samples 24 the striations wash back into
  smooth bands by orbital shear advection, as a real 30 s exposure of a
  ~23 s ISCO-period disk would. 1280x720 with 24 temporal samples renders in
  ~4 s (no meaningful cost regression).
- The motion-blur-off render of the previous canonical baseline changes by
  design (source morphology refinement); diagnostics confirm the body branch
  energy backbone is unchanged.

## 5. Remaining Limits

- The turbulence remains a constrained closure (deterministic sheared modes +
  log-normal intermittency), not an MHD solve; its statistics are calibrated
  to radiation-MHD literature, not to a specific simulation snapshot.
- Mode phases advect with Keplerian shear but only slowly decorrelate; eddy
  turnover decorrelation (~orbital period) is approximate for exposures of
  several periods.
- The structure-bearing skin sits on top of an axisymmetric NT body; true
  density-wave/spiral-arm structure in the *body* temperature profile remains
  out of scope.
- Radial inflow drift (v_r ~ alpha (H/r)^2 v_K ~ 1e-4 v_K) is physically
  negligible for Doppler purposes outside the plunge region and remains
  unmodeled there; the plunge region itself uses exact conserved-quantity
  kinematics.
