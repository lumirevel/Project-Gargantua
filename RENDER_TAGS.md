# Blackhole Render Tags

## Purpose
This document maps the current runtime flags and metadata outputs to the refactored Swift + Metal pipeline.

Current flow:
- `main.swift` -> `AppMain`
- `CLI.swift` / `ParamsBuilder.swift` resolve flags
- `Renderer` orchestrates setup + execution + outputs
- `PackedParams` is the ABI boundary into Metal

## Core Runtime Flags
- `--preset balanced|realistic|interstellar|eht`
- `--width <int>`
- `--height <int>`
- `--metric schwarzschild|kerr`
- `--spin <float>`
- `--output <path>`
- `--image-out <path>`
- `--compose-gpu`
- `--gpu-full-compose`
- `--linear32-intermediate`
- `--discard-collisions`
- `--downsample 1|2|4`
- `--tile-size <int>`
- `--trace-inflight <int>`

## Disk Policy Flags
Mode selectors:
- `--disk-mode thin|thick|precision|grmhd|auto`
- `--disk-physics legacy|thin|thick|eht`
- `--disk-model flow|procedural|perlin|perlin-classic|perlin-ec7|atlas|auto`

Disk dynamics:
- `--disk-time`
- `--disk-orbital-boost`
- `--disk-radial-drift`
- `--disk-turbulence`
- `--disk-flow-step`
- `--disk-flow-steps`

Disk policy/detail:
- `--mdot-edd`
- `--eta`
- `--fcol`
- `--disk-plunge-floor`
- `--thick-scale`
- `--disk-returning-rad`
- `--disk-precision-texture`
- `--disk-precision-clouds on|off`
- `--disk-cloud-coverage`
- `--cloud-tau` / `--disk-cloud-optical-depth`
- `--disk-cloud-porosity`
- `--disk-cloud-shadow-strength`
- `--disk-return-bounces`
- `--rt-steps`
- `--disk-scattering-albedo`

## Atlas / Volume Inputs
Atlas:
- `--disk-atlas <path>`
- `--disk-atlas-width <int>`
- `--disk-atlas-height <int>`
- `--disk-atlas-temp-scale`
- `--disk-atlas-density-blend`
- `--disk-atlas-vr-scale`
- `--disk-atlas-vphi-scale`
- `--disk-atlas-r-min`
- `--disk-atlas-r-max`
- `--disk-atlas-r-warp`

Volume:
- `--disk-volume <path>`
- `--disk-vol0 <path>`
- `--disk-vol1 <path>`
- `--disk-meta <path>`
- `--disk-volume-r`, `--disk-volume-phi`, `--disk-volume-z`
- `--disk-volume-tau-scale`
- `--nu-obs-hz`
- `--disk-grmhd-density-scale`
- `--disk-grmhd-b-scale`
- `--disk-grmhd-emission-scale`
- `--disk-grmhd-absorption-scale`
- `--disk-grmhd-vel-scale`
- `--disk-grmhd-debug off|rho|b2|jnu|inu|teff|g|y|peak|pol`

## Visible / Camera / Background
Visible:
- `--visible-mode on|off`
- `--visible-policy physical|expressive`
- `--visible-emission-model blackbody|synchrotron`
- `--visible-samples <int>`
- `--teff-model parametric|thin-disk|nt`
- `--teff-T0`, `--teff-r0`, `--teff-p`
- `--bh-mass`, `--mdot`, `--r-in`
- `--photosphere-rho-threshold`
- `--visible-synch-alpha`
- `--visible-kappa`

Camera/background:
- `--camera-model legacy|scientific|cinematic`
- `--look balanced|realistic|interstellar|eht|agx|hdr`
- `--camera-psf-sigma`
- `--camera-read-noise`
- `--camera-shot-noise`
- `--camera-flare`
- `--background off|stars`
- `--bg-star-density`
- `--bg-star-strength`
- `--bg-nebula-strength`

## Ray Bundle / SSAA
- `--ssaa <int>`: high-resolution render then downsample
- `--ray-bundle off|on|jacobian`: per-pixel sub-ray bundle path
- `--ray-bundle-jacobian on|off`: explicit override for legacy compatibility
- `--ray-bundle-jacobian-strength <float>`
- `--ray-bundle-footprint-clamp <float>`

## Metadata Output
Collision metadata is written to `<output>.json` or `<linear32-out>.json` and currently includes:
- camera and geodesic controls
- disk mode / disk model / atlas / volume descriptors
- visible-mode parameters
- compose/camera/background settings
- output resolution and effective exposure
- `collisionStride`
- `bridgeCoordinateFrame`
- `bridgeFields`

## ABI / Regression Utilities
- `--print-packed-layout`
- `--dump-packed-params <path>`
- `--validate-packed-abi`
- `--regression-run <manifest.json>`
- `--regression-out <dir>`
- `--regression-case <name|all>`

## Regression Coverage
- `tests/baseline/manifest.json`
  - legacy/default hash protection + perf anchor
- `tests/baseline/extended_manifest.json`
  - precision / thick / atlas / volume / ray-bundle / expressive-visible branches
