# Camera Profile Notes

These JSON profiles are not exact vendor clones. They are renderer-facing calibration presets
that use public sensor-report style quantities and map them into the current camera response
model.

## Physical Fields

- `fullWellElectrons`: sensor saturation capacity in electrons.
- `readNoiseElectrons`: temporal dark/read noise in electrons.
- `peakQuantumEfficiency`: peak photon-to-electron conversion efficiency, 0...1.
- `darkCurrentElectronsPerSecond`: dark current rate at the assumed sensor temperature.
- `exposureSeconds`: exposure duration used when estimating black level from dark current.
- `dsnuElectrons`: dark signal non-uniformity.
- `prnuPercent`: photo-response non-uniformity in percent.
- `pixelPitchMicrons`: pixel pitch, used with `lensFNumber` to estimate diffraction blur.
- `lensFNumber`: lens f-number, used to estimate a conservative Airy-disc PSF width.
- `lensVignettingStops`: approximate corner falloff in stops.

## Mapping Caveats

The renderer currently applies noise after tone mapping, so electron-domain values are converted
into perceptual strengths rather than simulated as raw Poisson samples. This keeps the path fast
and non-invasive while giving the defaults realistic ordering: larger full-well sensors get lower
shot noise, lower read-noise sensors get cleaner shadows, and stronger PRNU/vignetting produces
more visible fixed-pattern/lens shading.

For a true raw camera pipeline, the next step is to move shot/read/dark/PRNU noise into a raw
sensor buffer before demosaic and display rendering.
