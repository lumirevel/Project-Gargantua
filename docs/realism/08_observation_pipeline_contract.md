# Observation Pipeline Contract

The observer pipeline consumes physical radiance. It must not rewrite what the
source model, geodesics, redshift, optical depth, or radiative transfer produced.

## Required Pipeline Separation

```text
same_physical_radiance
  -> scientific_false_color
  -> human_eye_perception
  -> camera_raw
  -> camera_rendered
  -> cinematic_grade
```

The same source radiance should be usable across these outputs. If a mode needs
different input data, the required physical fields must be added to the render
contract rather than inferred with image-space tricks.

## Human Eye Mode

Human eye mode may model:

- absolute or relative luminance adaptation
- pupil or aperture-like eye response
- photopic, scotopic, and mesopic weighting where implemented
- color appearance and chromatic adaptation approximations
- physiologically motivated glare or veiling response
- display transform from a perceptual image

Human eye mode must not:

- change disk density, emissivity, opacity, or source morphology
- change geodesic hit logic
- erase critical-curve artifacts with masks presented as physics
- manufacture missing plasma structure

## Camera RAW Mode

Camera RAW is the closest device record of the physical image. The idealized
pipeline is:

```text
scene spectral radiance
  -> lens transmission / aperture / shutter
  -> sensor quantum efficiency
  -> CFA sampling
  -> photon shot noise
  -> read noise
  -> ISO gain
  -> black level
  -> RAW buffer
```

RAW output may include sensor and exposure metadata. It should avoid filmic
tone curves, creative color grading, and bloom that cannot be separated from the
recorded signal.

## Camera Rendered Mode

Camera rendered output may apply:

- demosaic approximation
- white balance
- color transform
- tone curve
- output display transform
- named-camera approximations when documented

It must remain downstream of RAW-like sensor formation. A camera-rendered image
cannot be used as proof that physics improved unless scientific and RAW-like
diagnostics also support the claim.

## Cinematic Layer

Cinematic output may apply:

- bloom
- lens flare
- film look
- grading
- artistic framing

Cinematic output must not modify physics buffers. It must be possible to render
the same scene without cinematic effects and inspect physical diagnostics.

## Observer Validation

Observer changes require:

- same physical source rendered through scientific, human-eye, camera-RAW,
  camera-rendered, and cinematic modes where available
- tone-mapped-no-bloom output when bloom/glare is touched
- bloom-only or glare-only output when such effects are touched
- exposure/adaptation debug JSON or equivalent scalar diagnostics
- a non-black-hole HDR stress scene when validating generic camera/eye behavior
