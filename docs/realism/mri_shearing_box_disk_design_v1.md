# MRI Shearing-Box Disk — Design V1 (DESIGN ONLY, not implemented)

Date: 2026-07-11

Branch: `disk-physics-improvement`

Status: **design / proposal for review.** No renderer code changes yet.

## Motivation

The recommended thin disk's surface structure is a deterministic sum of ~96
sinusoidal modes plus Gaussian packets (`comp_thin_spectral_heating_field` /
`comp_thin_mri_shearing_field`). Even with a correct spectrum it reads as
synthetic: fixed phases produce a visible interference pattern, every frame is
the same field rigidly advected by shear, and the emergent intermittency of
real turbulence is absent. The goal is to drive the disk skin from a **genuine
MHD simulation** of MRI turbulence instead of closed-form functions, so the
statistics (power spectrum, shear anisotropy, log-normal intermittency, orbital
decorrelation) emerge from physics.

Chosen approach (user-selected): **offline local shearing-box MHD simulation →
2D disk atlas**. This is the tractable point on the fidelity/cost curve: a
local box is a real MHD solve that resolves MRI on a workstation, and the
renderer already has the ingestion path.

## What already exists (injection points — reuse, do not rebuild)

- **Atlas format** (`loadDiskAtlas`, Resources.swift:396): raw
  `width × height × float4` row-major, indexed (r, φ), with an `<atlas>.json`
  sidecar `{width, height, rNormMin, rNormMax, rNormWarp}`. Channels consumed
  by `disk_sample_atlas` (volume_rt.metal): **x = temperature multiplier**
  (clamped 0.65–1.80), **y = structure/skin field** (→ `info.noise`),
  z = v_r, w = v_φ.
- **Blend knob**: `--disk-atlas-density-blend` mixes atlas structure with the
  procedural field; `--disk-atlas-r-min/-r-max/-r-warp` set the radial mapping.
- **HDF5→atlas bridge**: `--disk-hdf5 <snap.h5> [--disk-hdf5-out atlas.bin]`
  already converts an (r, θ, φ) HDF5 snapshot into this atlas format;
  `build_sample_hdf5.py` and `build_grmhd_volumes.py` are working templates for
  the python bridge.
- **PLUTO hook**: `--disk-pluto` + `resolve_pluto_hdf5` (run_pipeline.sh) route
  a PLUTO snapshot through the same bridge. PLUTO emits HDF5 natively, so the
  existing path can carry shearing-box output with a dedicated builder.

So the work is: (1) produce the simulation, (2) write a box→atlas builder in the
established style, (3) add a source model that loads it and blends over the NT
temperature backbone, (4) document/label per the physics contract.

## The simulation (offline, one-time per parameter set)

- **Code**: PLUTO (already hooked) or Athena++, isothermal or ideal-MHD,
  **stratified shearing box** (vertical gravity → a real photosphere + a
  buoyancy-driven magnetic corona, which is exactly the emitting skin).
- **Setup**: co-rotating Cartesian patch (x=radial, y=azimuthal, z=vertical) at
  a reference radius r0; Keplerian shear v_y = −(3/2)Ω x; shear-periodic in x,
  periodic in y, outflow in z. Seed a weak net-flux or zero-net-flux field;
  evolve through MRI growth into saturated turbulence (~tens of orbits).
- **Resolution**: ≥ ~32 cells per scale height H to resolve the MRI channel and
  the turbulent cascade to a few tenths of H (the photospheric smoothing scale
  the renderer already assumes).
- **Output**: a time series (cadence ~0.05–0.1 orbital period, spanning ≳1
  orbit) of the τ≈1 surface **dissipation/stress field** D(x, y, t) — the
  physical driver of surface-brightness fluctuation for an optically-thick disk.
  Normalize to δ = D/⟨D⟩ (dimensionless local emissivity modulation) and the
  local color-temperature perturbation.

## The box→atlas bridge (new python, `build_shearing_box_atlas.py`)

Mirrors the existing HDF5 bridges. Steps:

1. **Read** the box snapshots (HDF5); extract δ(x, y, t) at the τ≈1 surface and
   the associated T-perturbation.
2. **Map to (log r, φ)** with physically-correct warping:
   - Azimuthal: the box y-extent L_y ≈ (few) H covers Δφ = L_y/r0; tile around
     φ ∈ [0, 2π]. Seams/periodicity handled by phase-randomized tiling with
     reflection and a shear-consistent offset per tile (the box is already
     shear-periodic, so its statistics tile without a preferred seam).
   - Radial: a single-radius box is mapped across r by **rescaling the fluctuation
     scale with the local H(r) and the amplitude with the NT dissipation profile
     F_NT(r)** (so inner-disk structure is finer and stronger, matching the disk
     solution). Optionally run 2–3 boxes at representative radii and interpolate
     for a better radial trend.
   - Shear winding: imprint the local trailing pitch from the shear rate q so the
     mapped filaments wind correctly in (log r, φ) — the statistics come from the
     box, the global winding from the analytic shear.
3. **Footprint/photosphere floor**: apply the same ~(0.6–1.0) H smoothing floor
   the procedural path uses, so sub-photosphere structure does not masquerade as
   resolvable — keeps the result resolution-honest.
4. **Write** `atlas.bin` (float4: x = 1 + T-perturbation, y = δ structure,
   z/w = 0 or the box's v_r/v_φ perturbation) + `atlas.json`. For animation,
   write a small stack of atlases (one per snapshot) + a manifest; the renderer
   interpolates by disk flow-time.

## Renderer integration (small, mostly wiring)

- New source model **`mri-shearing-box-disk-v1`** (run_pipeline expansion +
  GUI manifest): thin disk, NT/grmhd-hybrid temperature backbone (unchanged),
  `--disk-model atlas` with the shearing-box atlas, `--disk-atlas-density-blend`
  high, procedural skin as the no-data fallback.
- The skin already consumes `atlasSample.y` as `info.noise` and `atlasSample.x`
  as a temperature multiplier — so **no new trace/compose math** is needed for
  the static case; the structure just comes from data instead of the sinusoids.
- Time animation: extend the atlas load to a snapshot stack keyed to
  `diskFlowTime` (new, small: load N atlases, lerp in the sampler). Optional for
  V1 (a single snapshot advected by the existing shear is already better than
  the frozen procedural pattern).

## Physics contract / labeling (mandatory)

- Document the simulation provenance: code + version, box size in H, resolution
  per H, field topology (net-flux/zero-net-flux), β, orbits evolved, snapshot
  cadence. This becomes the source model's contract block.
- Label honestly: **"local shearing-box MRI turbulence statistics mapped onto an
  analytic thin-disk backbone,"** NOT "a global MHD disk." The forbidden-hacks
  clause ("procedural texture reported as turbulence from real data") is
  satisfied because the structure genuinely is MHD-simulated; the mapping
  approximation is stated, not hidden.
- Model level: ~L2.5 — genuine MHD turbulence input, not a self-consistent
  global disk (that is Tier 3).

## Phasing & verification

- **Phase A (bridge + static atlas)**: run one stratified box; build the atlas;
  wire `mri-shearing-box-disk-v1`; render and compare to the procedural skin.
  Verify: interference-pattern gone; measured structure statistics (spectrum
  slope, PDF skew/kurtosis from the render vs the box) match the simulation;
  interstellar guardrail md5 unchanged (new source only, default disk untouched);
  raw-purity / presentation gates green.
- **Phase B (radial fidelity)**: 2–3 boxes at representative radii, interpolated;
  verify the inner-vs-outer structure scale tracks H(r).
- **Phase C (animation)**: snapshot stack + flow-time interpolation; verify
  orbital-timescale decorrelation against the box autocorrelation.

## Risks / honest limits

- Local box ≠ global disk: no grand-scale spiral/global modes, no radial
  transport coupling, curvature neglected. (This is acceptable — those global
  coherent modes are exactly the artifacts we removed; the LOCAL turbulence is
  what reads as "real.")
- Single-radius mapping is an approximation; mitigated by H(r)/F_NT(r) scaling
  and optional multi-radius boxes.
- Requires an offline MHD toolchain (PLUTO/Athena++ + h5py); the sim is a
  one-time cost per parameter set, cached as atlas data in-repo like the GRMHD
  dumps.
- Not Tier 3 (global rad-MHD); this is deliberately the tractable step that
  replaces the synthetic math with genuine MHD statistics.

## Not doing (explicitly out of scope for this design)

- Solving global disk MHD in-renderer.
- Changing the physics core, transfer, exposure, or camera paths.
- Touching the default/legacy disks — this is a new, opt-in source model.
