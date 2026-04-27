# Eye Veiling Glare Notes

Branch: `codex/interpreter-camera-v1`

## Observed Issue

The room RT eye presentation can make regions close to bright lights read unnaturally dark. The scientific and no-optics comparisons showed that this was not caused by physical light generation or by the room RT source itself. The issue sits in the visual interpreter: bright local surround adaptation reduced retinal gain in places where the perceptual glare model should mostly add equivalent veiling luminance from intraocular scatter.

## Scientific Interpretation

Real glare in the human eye is not primarily a local gain reduction around bright sources. Forward scatter in the ocular media superimposes stray light on the retinal image, reducing contrast. Lighting literature describes this as disability glare or equivalent veiling luminance: a luminance veil that has the same contrast-reducing effect as scattered retinal illuminance.

This means a bright lamp should usually wash out nearby contrast before it produces a clean black halo. A local gain model can look wrong if it darkens the surround in response to the lamp instead of adding the scatter veil that the eye would see.

References used for this interpreter change:

- Illuminating Engineering Society, "Equivalent Veiling Luminance": https://ies.org/definitions/equivalent-veiling-luminance/
- Kretz et al., "Standardized Measurement of Straylight in the Human Eye", Journal of Imaging 2024: https://www.mdpi.com/2313-433X/10/4/89
- Federal Highway Administration lighting handbook, "Vision and Fundamental Concepts": https://highways.fhwa.dot.gov/safety/other/visibility/fhwa-lighting-handbook-august-2012/3-vision-and-fundamental-concepts

## Code Ownership

- `Blackhole/Metal/Compose/helpers.metalh`
  - `comp_eye_scene_adapt_rgb` owns the eye-only local adaptation before the eye tone curve.
  - This is interpreter/camera behavior. It does not change scene radiance, physical light transport, disk emission, redshift, optical depth, or ray generation.

## Implemented Improvement

`comp_eye_scene_adapt_rgb` now treats eye glare as a restrained neutral veiling-luminance proxy near bright sources:

- local surround luminance only drives a conservative low-light adaptation lift,
- bright surround luminance no longer directly darkens scene RGB before tone mapping,
- a separate distance-weighted bright-pass sample drives the scatter veil,
- gated by `cameraPsfSigmaPx`, so diagnostics that disable optical PSF also disable this added veil,
- added before the eye tone curve, keeping the effect in the eye/display interpreter,
- no new buffers, no ABI changes, no CPU-GPU synchronization change.

The change is intentionally small. It is not a full CIE glare spread function or age/pigment-dependent human observer model. It prevents the most obvious non-physiological dark-halo behavior while keeping diagnostics reversible through existing optics-off controls.

## Angular Proxy Update

The first veil implementation used the same coarse local surround estimate for both adaptation and glare. That was scientifically incomplete: adaptation can follow average local luminance, but disability glare is driven by bright off-axis sources and their angular separation from the retinal point.

The current implementation therefore adds:

- `comp_eye_scene_glare_full`
- `comp_eye_scene_glare_tile`
- `comp_eye_glare_source_y`

These helpers collect bright-pass scene luminance from nearby and farther samples with lower weight at the farther radius. The resulting `glareY` is passed separately into `comp_eye_scene_adapt_rgb`, so a dark wall average no longer incorrectly removes the veil caused by a nearby lamp. Bright-source glare now reduces visible contrast by adding a veil, not by multiplying the local image darker.

## FOV-Normalized Angular Falloff

The glare spread proxy now receives `cameraGlareParams` in `ComposeParams`:

- `x`: pixel visual angle in degrees, derived from `fovDeg / width`
- `y`: minimum glare angle in degrees
- `z`: angular falloff exponent
- `w`: max-sample mix for sparse bright sources

This keeps the interpreter-side glare weights closer to disability-glare models where veiling luminance depends on the angular separation between the glare source and the viewed point. It also reduces sensitivity to output resolution and FOV changes compared with fixed screen-space weights.

## How To Inspect

Use an existing HDR room input and compose it through eye mode:

```bash
BH_ETA_HISTORY=/private/tmp/bh_room_eye_veil_eta.json \
bash Blackhole/run_pipeline.sh \
  --compose-hdr-in /private/tmp/bh_room_rt_camera_validation/rt_room.linear32f32 \
  --width 420 \
  --height 240 \
  --presentation eye \
  --output /private/tmp/bh_room_rt_camera_validation/rt_room_eye_veiling_fix.png
```

For an optics-off comparison:

```bash
BH_ETA_HISTORY=/private/tmp/bh_room_eye_veil_no_optics_eta.json \
bash Blackhole/run_pipeline.sh \
  --compose-hdr-in /private/tmp/bh_room_rt_camera_validation/rt_room.linear32f32 \
  --width 420 \
  --height 240 \
  --presentation eye \
  --camera-psf-sigma 0 \
  --camera-flare 0 \
  --camera-dof-strength 0 \
  --camera-read-noise 0 \
  --camera-shot-noise 0 \
  --output /private/tmp/bh_room_rt_camera_validation/rt_room_eye_veiling_fix_no_optics.png
```

The expected comparison is:

- eye mode with optics: less artificial dark halo around bright lights,
- eye mode optics-off: no added veiling-glare proxy,
- scientific mode: unchanged physical/display baseline.

## Risks

- The current proxy uses FOV-normalized sample radii, but it is still sparse sampling rather than a calibrated full-image glare convolution.
- The strength is intentionally restrained and may still be too weak for extreme high-luminance sources.
- A future calibrated eye model should consider glare angle, pupil size, observer age, ocular media, and source spectral distribution.
- The optics-off diagnostic must remain available when reviewing raw tone mapping and exposure behavior.
