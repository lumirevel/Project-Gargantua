# Scientific Rendering Policy

This renderer should produce visually compelling black-hole imagery by making the physical model richer, not by hiding it under arbitrary image-space effects.

## Core Principle

1. Preserve physical truth at the radiance/transport layer.
2. Separate scientific image formation from eye/camera/cinema presentation.
3. Use visual styling only after the physical master image exists, and label it as presentation.
4. Prefer model improvements that create structure in disk/world space, not screen space.

## Accretion Flow Target

The target accretion flow is not a single mathematical 2D ribbon. It should be treated as a finite 3D participating medium made from gas/plasma with density, temperature, velocity, opacity, and emission distributed through a volume.

The practical public hierarchy is:

1. `canonical-visible-disk-v1`: recommended visible source model. It combines a clean thin-disk photospheric body, positive disk-coordinate stochastic heating skin, and weak corona before scientific/eye/cinema presentation.
2. `thin-disk-visible-reference`: clean analytic thin-disk reference with no procedural/GRMHD texture.
3. `grmhd-hot-flow-diagnostic`: GRMHD-native optically thin structure diagnostic.
4. `grmhd-temperature-flow-diagnostic`: GRMHD/HDF5-driven 3D visible thermal volume RT diagnostic when suitable evolved data exists.

Older DNGR/flow/volume/plasma-skin variants are legacy experiments. They remain
available only behind `--experimental` for reproduction and debugging.

Current operational baseline:

```bash
./Blackhole/run_pipeline.sh \
  --source-model canonical-visible-disk-v1 \
  --disk-turbulence 2.0 \
  --presentation scientific \
  --quality hq
```

This is the protected visible-disk source baseline for the current iteration.
Scientific, eye, and cinema renders should be produced from this same source
radiance unless a new source candidate is explicitly being tested.

## Optical-Depth Rules

The volume renderer should expose rather than hide the following regimes:

- `tau << 1`: transparent cloud. Interior structure and line-of-sight accumulation remain visible.
- `tau ~ 1`: photospheric layer. This is usually the most useful visible-disk regime.
- `tau >> 1`: opaque surface/slab. Internal structure is physically hidden and the image can flatten.

If the disk looks like a black slab or smooth white ribbon, first inspect opacity, source function, and exposure before changing geometry.

Implementation note: a volume path that compresses accumulated gas into a single
surface-like hit is only a diagnostic bridge. The final 3D disk target must
accumulate radiance through the medium and pass that radiance to the scientific
master without turning every weak foreground sample into an opaque hit.

## Color And Temperature

Visible color should come from local physical state and relativistic transport:

- local temperature/electron-temperature proxy
- density/opacity
- velocity and Doppler/gravitational shift
- spectral or multi-band integration
- display transform only after physical radiance exists

Do not replace this with arbitrary RGB painting. Any surrogate flow field must modulate physical state variables before radiance/spectrum conversion.

## Eye, Camera, Cinema

- Scientific mode: minimally transformed physical image/debug radiance.
- Eye mode: human-vision presentation derived from the physical image.
- Camera/cinema mode: sensor/lens artifacts are allowed only as a separate presentation layer.

Forced shadows, image-space occluders, and hand-painted halos are not acceptable as scientific fixes.

Presentation-side glare, bloom, adaptation, or camera response must not be used
to manufacture missing plasma structure. If body/skin/corona branch diagnostics
show weak or misleading source structure, fix the source branch model first and
then re-render eye/cinema.

## Sensor Validation Track

The next stable engineering boundary is to validate the observer layer on generic
HDR radiance inputs before using it to judge accretion-flow source changes.

Recommended fixed sensor tests:

1. Blackbody ramp: spectral blackbody temperature sweep -> CIE XYZ -> display RGB.
2. HDR point/line source: fixed radiance with eye/cinema glare enabled and disabled.
3. Smooth extended emitter: no source texture, only tone/adaptation response.
4. Branch-preservation check: scientific, eye, and cinema must preserve the same
   source morphology and only change perceptual/display response.

Accepted basis:

- CIE 1931 2-degree color matching functions for spectral-to-XYZ conversion.
- Psychophysically based glare/PSF only in eye/cinema presentation, not in the
  scientific master.
- Exposure/adaptation may compress dynamic range, but must not alter branch
  ratios or invent disk-space structure.

## Data Priority

When real evolved 3D GRMHD/fluid data is available and scientifically suitable, it should drive the flow. Analytic or procedural volume fields are acceptable only as fallback/surrogate test fields and must be documented as such.

For now, GRMHD paths are diagnostic rather than the recommended visible source
model. They are useful for testing density, temperature, magnetization, velocity,
and opacity interpretations, but the current canonical human-visible disk uses a
thin-disk photosphere plus disk-coordinate stochastic heating until the GRMHD
visible-band calibration is strong enough to replace it.

## Experimental Atmosphere And Corona Notes

The precision/GRMHD diagnostic paths currently contain experimental physically
motivated approximations:

- Eddington gray-atmosphere temperature profile:
  `T^4 = (3/4) T_eff^4 (tau + 2/3)`.
- Gaussian vertical density/opacity support for finite-thickness volume tests.
- MRI-inspired disk-coordinate heating modes in `(log r, phi)` advected by
  Keplerian shear. This replaces Perlin/material texture in the affected
  precision path but is still a surrogate stress/heating model, not an MHD solve.
- Conservative unsaturated Compton corona proxy gated to optically thin plasma.
  It is bounded and diagnostic; it is not a full Kompaneets or Monte-Carlo
  scattering solver.

These approximations are more defensible than decorative texture or unbounded
spectral boosts, but they should remain experimental until before/after validation
shows a clear improvement in physical diagnostics and rendered morphology.
