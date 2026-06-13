# Recommended Commands

Curated commands that produce good results with the physically anchored
observer chain. All run from the repo root. Add `--quality hq --width 1920
--height 1080` for finals; previews below render in seconds.

Source models:
- `canonical-visible-disk-v1` - sub-Eddington thin NT disk. Warm gold outer
  annuli, white-hot inner disk, fine turbulent striations when resolved.
- `slim-disk-visible-v1` - super-Eddington slim disk. Blue-white
  Rayleigh-Jeans disk, radially extended brightness, thick-disk side walls,
  ~77x the canonical luminance.
- `volumetric-visible-disk-v1` - true volumetric disk: LTE gray radiative
  transfer through the analytic medium, photosphere emerging at tau ~ 1,
  per-sample exact-metric g-factors and slow-light emission times, sheared
  MRI turbulence in 3D, and a clumpy magnetically supported atmosphere
  (`--disk-cloud-coverage 0..1`, default 0.45; 0 = smooth photosphere only).
  Thickness follows the matter supply `--mdot-edd` (default 0.18): the
  hydrostatic scale height H = (3/2)(L/L_Edd) r_g sets both temperature and
  geometric thickness, so ~0.05 is a thin blade and ~0.6 a puffed band.
  Best viewed tilted: `--camX 19 --camZ 11`.

## Eye (인간 눈 - 차광 필터 뒤에서 적응된 맨눈)

```bash
# The reference experience: auto ND (resolves ~ND6, solar-filter class),
# photopic adaptation, warm outer-disk color.
./Blackhole/run_pipeline.sh --source-model canonical-visible-disk-v1 \
  --presentation eye --quality hq --width 1920 --height 1080

# Zoomed: resolves the turbulent fluid striations (structure scale ~ H).
./Blackhole/run_pipeline.sh --source-model canonical-visible-disk-v1 \
  --presentation eye --quality hq --width 1920 --height 1080 --fov 25

# Mesopic experience: deep filter, Purkinje desaturation begins.
./Blackhole/run_pipeline.sh --source-model canonical-visible-disk-v1 \
  --presentation eye --quality hq --width 1920 --height 1080 --eye-nd 9.5

# The super-Eddington disk to the adapted eye (auto ND ~7.9).
./Blackhole/run_pipeline.sh --source-model slim-disk-visible-v1 \
  --presentation eye --quality hq --width 1920 --height 1080

# The volumetric disk, tilted: turbulent face, soft atmosphere edges,
# patchy clumps above the photosphere (raise coverage for heavier clouds).
./Blackhole/run_pipeline.sh --source-model volumetric-visible-disk-v1 \
  --presentation eye --quality hq --width 1920 --height 1080 \
  --camX 19 --camZ 11 --disk-cloud-coverage 0.65
```

Eye knobs: `--eye-nd <density>` (log10 attenuation; auto if unset),
`--eye-adaptation <cd/m2>`, `--eye-target-luminance` (default 8000),
`--eye-white-multiple` (default 8), `--eye-photometric off` for the legacy
auto-exposed eye.

## Camera (실제 카메라 - 절대 노출, 광자 노이즈, 회절)

The disk median is ~6.4e8 cd/m^2 (canonical): proper exposure needs
EV ~32, beyond mechanical limits (f/16, 1/8000 s, ISO 100 is EV ~21), so a
real shoot needs an ND filter. `--exposure-ev -N` is the ND equivalent
(-10 EV = ND 3.0; -13.3 EV = ND 4.0).

```bash
# Properly exposed photograph: ND ~3.4 + landscape settings.
# Clean base-ISO image, photon-statistics grain, iris diffraction veil.
./Blackhole/run_pipeline.sh --source-model canonical-visible-disk-v1 \
  --presentation cinema --quality hq --width 1920 --height 1080 \
  --exposure-mode photographic \
  --camera-f-number 16 --camera-shutter 1/8000 --camera-iso 100 \
  --exposure-ev -11.3

# High-ISO grain study: equivalent exposure, 64x fewer photons.
./Blackhole/run_pipeline.sh --source-model canonical-visible-disk-v1 \
  --presentation cinema --quality hq --width 1920 --height 1080 \
  --exposure-mode photographic \
  --camera-f-number 16 --camera-shutter 1/512000 --camera-iso 6400 \
  --exposure-ev -11.3

# Long exposure: 30 s shutter on a ~23 s ISCO-period disk smears the
# turbulent skin along the orbital shear (real motion blur).
./Blackhole/run_pipeline.sh --source-model canonical-visible-disk-v1 \
  --presentation cinema --quality hq --width 1920 --height 1080 \
  --exposure-mode photographic \
  --camera-f-number 22 --camera-shutter 30 --camera-iso 100 \
  --exposure-ev -22 --motion-blur-samples 24

# Overexposed sun-style shot: clipped disk, strong diffraction streaks.
./Blackhole/run_pipeline.sh --source-model canonical-visible-disk-v1 \
  --presentation cinema --quality hq --width 1920 --height 1080 \
  --exposure-mode photographic \
  --camera-f-number 8 --camera-shutter 1/1000 --camera-iso 200 \
  --exposure-ev -10.3 --camera-aperture-blades 7 --camera-diffraction 0.05

# The super-Eddington disk on a full-frame profile.
./Blackhole/run_pipeline.sh --source-model slim-disk-visible-v1 \
  --presentation cinema --quality hq --width 1920 --height 1080 \
  --exposure-mode photographic --camera-profile full-frame \
  --camera-f-number 11 --camera-shutter 1/8000 --camera-iso 100 \
  --exposure-ev -14.5
```

Camera knobs: `--camera-f-number --camera-shutter --camera-iso` (the
exposure triangle, ISO 12232 absolute), `--camera-photon-noise auto|on|off`,
`--camera-diffraction <x>` (iris spikes), `--camera-aperture-blades <n>`,
`--motion-blur-samples <n>` (+ `--camera-shutter` drives the window),
`--camera-profile {scientific|cinema-digital|full-frame}` or
`--camera-profile-json docs/camera_profiles/imx455_full_frame_astro_like.json`.

## Scientific master (물리 원본 점검)

```bash
./Blackhole/run_pipeline.sh --source-model canonical-visible-disk-v1 \
  --presentation scientific --look linear --quality hq

# Kerr a = 0.9 (exact metric kinematics).
./Blackhole/run_pipeline.sh --source-model canonical-visible-disk-v1 \
  --presentation scientific --metric kerr --spin 0.9 --quality hq
```
