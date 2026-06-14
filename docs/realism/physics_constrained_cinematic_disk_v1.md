# Physics-Constrained Cinematic Disk V1

Date: 2026-05-02

Branch: `codex/integration/physics-camera-v1-legacy-recovery`

## Status

`physics-constrained-cinematic-disk-v1` is a production source-model workflow for finding the most aesthetically compelling accretion disk inside a scientifically plausible surrogate parameter space. It is not a legacy Perlin/noise/procedural texture path, and it is not an alias for `canonical-visible-disk-v1`.

## Architecture

The model uses the existing thin/intermediate disk ray-intersection and relativistic transfer path, then selects a distinct source profile:

```text
--source-model physics-constrained-cinematic-disk-v1
-> --realism-profile physics-constrained-cinematic-disk-v1
-> realismProfileID = 6
```

Profile 5 remains `canonical-visible-disk-v1`. Profile 6 adds source-layer fields and branch logic only; scientific/eye/cinema presentation remains downstream.

## ABI Source Contract

Three tail-aligned `SIMD4<Float>` fields were added to `PackedParams` and the Metal `Params` mirror:

| Field | Meaning |
| --- | --- |
| `pcdSourceA.x` | density exponent |
| `pcdSourceA.y` | emissivity scale |
| `pcdSourceA.z` | opacity scale |
| `pcdSourceA.w` | seed |
| `pcdSourceB.x` | structure scale |
| `pcdSourceB.y` | spiral amplitude |
| `pcdSourceB.z` | spiral pitch |
| `pcdSourceB.w` | clump contrast |
| `pcdSourceC.x` | hot crescent strength |
| `pcdSourceC.y` | debug field selector |
| `pcdSourceC.zw` | reserved |

Validated layout:

```text
PackedParams.size = 672
PackedParams.stride = 672
PackedParams.align = 16
pcdSourceA offset = 624
pcdSourceB offset = 640
pcdSourceC offset = 656
```

## CLI Controls

Profile 6 exposes bounded physical source controls:

- `--pcd-density-exp` default `1.15`, clamp `0.3...3.0`
- `--pcd-emissivity-scale` default `1.0`, clamp `0.1...5.0`
- `--pcd-opacity-scale` default `1.0`, clamp `0.0...6.0`
- `--pcd-seed` default `1729`
- `--pcd-structure-scale` default `1.0`, clamp `0.2...3.0`
- `--pcd-spiral-amp` default `0.25`, clamp `0.0...1.0`
- `--pcd-spiral-pitch` default `5.0`, clamp `0.5...14.0`
- `--pcd-clump-contrast` default `0.35`, clamp `0.0...1.0`
- `--pcd-hot-crescent` default `0.35`, clamp `0.0...1.0`

## Source Formula

At each thin/intermediate disk source hit, profile 6 computes disk-coordinate fields:

```text
rRatio = max(r / rIn, 1)
radialGate = inner support * outer taper
rho_proxy = radialGate * (r/rIn)^(-densityExp) * outerTaper
spiral = spiralAmp * positive(cos(phi - OmegaK(r)*t - spiralPitch*log(r/rIn) + phase(seed))) * radialGate
clump = clumpContrast * max(heating.cloud, heating.filament) * radialGate
hot_crescent = hotCrescent * innerGate * radialGate * smoothstep(1.0, 1.55, g)
activity = clamp(structureScale * (0.42*activity_base + 0.24*spiral + 0.24*clump + 0.10*filament) * radialGate, 0, 1)
```

Opacity and transfer saturation proxies:

```text
opacity = opacityScale * rho_proxy * (0.55 + 0.30*spiral + 0.15*clump)
tau = clamp(opacity / max(mu, 0.22), 0, 4)
transfer_saturation = radialGate * smoothstep(0.45, 1.80, opacityScale) * smoothstep(0.15, 0.30, tau)
```

The opacity-scale support avoids classifying deliberately low-opacity control renders as saturated only because of grazing-angle geometry.

## Branch Budget

Profile 6 preserves a luminous photospheric body while allowing positive hot-skin structure:

```text
positive_heating_lift = 1 + clamp(radialGate * (0.96*activity + 0.26*spiral + 0.36*clump + 0.52*hot_crescent), 0, 1.65)
sourceScale = emissivityScale * max(rho_proxy, 0.05*radialGate) * positive_heating_lift
fSkin = bounded positive activity/spiral/clump/hot-crescent support, cap 0.48
fCorona = weak inner/hot support, cap 0.045
fBody = clamp(1 - fSkin - fCorona, 0.52, 1)
normalize(fBody, fSkin, fCorona)
```

Branch radiance:

- body: lower-frequency photospheric blackbody/graybody from thin visible path
- skin: hotter positive emissive branch using observed temperature hardening and bounded dissipation lift
- corona: weak inner bluish-white optically thin accent

There is no negative carving and no albedo/normal/roughness/specular modulation.

## Diagnostics

Profile 6 supports source-layer diagnostics via `--realism-debug`:

- `g`
- `beaming`
- `emissivity`, `emissivity-pre-transfer`
- `raw-radiance`, `hdr`, `final-rgb`
- `photosphere`, `body`, `skin`, `corona`, `branch-ratio`
- `density`, `temperature`
- `opacity`, `alpha`
- `tau`, `optical-depth`
- `transfer-saturation`
- `activity`, `spiral`, `clump`, `hot-crescent`

Absolute branch previews use fixed branch scale. Ratio/activity/field maps are normalized diagnostics and should not be confused with absolute radiance.

## Validation Result

A/B validation output: `/private/tmp/bh_pcd_goal_validation/ab_sheet.png`

Key gate metrics from `/private/tmp/bh_pcd_goal_validation/ab_metrics.json`:

| Gate | Value | Pass |
| --- | ---: | --- |
| no/high activity RMSE | 0.178328 | yes |
| no/high emissivity RMSE | 0.040818 | yes |
| no/high final RGB RMSE | 0.012572 | yes |
| high/low tau optical-depth RMSE | 0.185753 | yes |
| high/low tau transfer-saturation mean diff | 0.055730 | yes |
| high-Doppler asymmetry ratio | 37.201658 | yes |

## Limitations

- This is a physics-constrained surrogate, not evolved GRMHD.
- The optical-depth and transfer-saturation terms are local source proxies, not a full vertical radiative-transfer solve.
- Field amplitudes are intended for parameter search and diagnostic comparison; high-structure presets are validation extremes, not default production values.
