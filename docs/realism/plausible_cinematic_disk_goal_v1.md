# Plausible Cinematic Disk Goal V1

Date: 2026-05-02

Branch: `codex/integration/physics-camera-v1-legacy-recovery`

## Target

The target is the most aesthetically compelling disk within a scientifically plausible parameter space.

This is intentionally neither:

- a beautiful fake disk, nor
- a boring scientific reference disk.

The source must first be physically interpretable. Scientific, eye, and cinema presentation modes may interpret that source, but they must not create the missing physical structure.

## Scientifically Plausible But Aesthetically Maximized

In this project, scientifically plausible means:

- radial temperature generally decreases outward,
- radial density/emissivity has a physically interpretable disk profile,
- orbital velocity proxy is stronger inward and remains compatible with Keplerian shear,
- Doppler/g-factor brightening should correlate with the bright crescent when inclination allows it,
- optical-depth/photosphere proxies must not be globally saturated,
- turbulent/clump/spiral structure must live in disk coordinates and be subordinate to density, temperature, velocity, and optical-depth fields,
- generated source structure must be positive emissivity/heating, not screen-space scratches or material shading.

Aesthetically maximized means:

- high visual impact inside the above constraints,
- readable black hole silhouette and lensed disk/ring structure,
- structured luminous disk body rather than a flat membrane,
- compelling crescent asymmetry and radial depth,
- controlled high dynamic range without full-frame clipping,
- plasma-like or cloud-like source structure that remains explainable through diagnostics.

## Forbidden Shortcuts

- Do not use Perlin/noise/procedural legacy texture as a production scientific model.
- Do not treat `--disk-model perlin`, `perlin-classic`, `perlin-ec7`, `noise`, or `flow` legacy behavior as the production source explanation.
- Do not optimize final RGB alone.
- Do not use tone mapping, exposure, bloom, glare, or cinematic grading to hide a weak source model.
- Do not use screen-space noise, albedo maps, normal maps, roughness modulation, or specular tricks to create plasma structure.
- Do not remove or weaken physical debug outputs to make a beauty image look better.

## Allowed Surrogate Strategy

When real evolved GRMHD data is unavailable, a physics-constrained surrogate is allowed if and only if:

- it is clearly labeled synthetic/surrogate,
- its fields are disk-coordinate, not screen-space,
- stochastic structure is tied to radial density, temperature, orbital shear, optical-depth/photosphere support, and emissivity,
- it exposes diagnostics for source fields and transfer/presentation behavior,
- it is not presented as a GRMHD simulation result.

## Production Versus Legacy

Production source models:

- define physically interpretable radiance fields,
- expose diagnostics,
- can be searched in constrained parameter space,
- remain separate from eye/cinema presentation.

Legacy/procedural disk models:

- remain available for reproduction and regression,
- may be useful visual references,
- are not production scientific models,
- must not be used as the final explanation for disk structure.

## Required Diagnostics

Final RGB is not enough. A candidate must be evaluated with available diagnostics such as:

- raw radiance / HDR pre-tone-map,
- emissivity or radial source strength,
- optical-depth / tau proxy,
- g-factor / redshift,
- beaming / Doppler proxy,
- branch/body/skin/corona diagnostics where available,
- transfer saturation where available,
- tone-mapped-no-bloom and bloom-only for interpreter validation.

For thin/intersection source models, `--realism-debug` provides the relevant source/transfer diagnostics. For GRMHD models, `--disk-grmhd-debug` provides GRMHD-native diagnostics.

## Acceptance Criteria

A candidate can be accepted only if:

- it passes a scientific plausibility gate before aesthetic scoring,
- final RGB improvement is supported by source/transfer diagnostics,
- structure is disk-coordinate and physically interpretable,
- saturation and background washout remain controlled,
- top candidates are not near-duplicates,
- eye/cinema outputs preserve source morphology rather than inventing it.

Failure must be explicit if:

- the disk remains flat or too uniform,
- diagnostics show structure exists only after presentation,
- top candidates differ only by exposure/tone mapping,
- optical depth or transfer collapses the source to a featureless surface,
- the best-looking output depends on legacy Perlin/noise/procedural texture.
