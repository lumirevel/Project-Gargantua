# Accuracy Upgrade Plan

## Goal
Raise physical and numerical accuracy without mixing it up with speed-only changes.
This document maps literature-backed upgrades onto the current codebase.

## Primary Sources
1. Odyssey: GPU-based GRRT in Kerr spacetime
   - https://arxiv.org/abs/1601.02063
2. RAPTOR I: time-dependent radiative transfer in arbitrary spacetimes
   - https://arxiv.org/abs/1801.10452
3. ipole: semi-analytic covariant polarized radiative transport
   - https://arxiv.org/abs/1712.03057
4. RAPTOR II: polarized radiative transfer in curved spacetime
   - https://arxiv.org/abs/2007.03045
5. General relativistic radiative transfer: formulation and emission from structured tori around black holes
   - https://arxiv.org/abs/1207.4234
6. Comparison of Polarized Radiative Transfer Codes used by the EHT Collaboration
   - https://arxiv.org/abs/2303.12004

## What the literature says matters most

### 1. Event location accuracy matters
The current renderer integrates geodesics with RK4 / DP45, but disk and volume entry handling is still largely segment-based.
That is a visible source of error for:
- thin disk crossings
- photosphere hits
- photon ring sharpness
- Jacobian / ray-bundle hit positions

The practical upgrade is not a different camera model. It is better event localization inside each accepted geodesic step.

### 2. Frequency-dependent transport matters more than post-coloring
The literature consistently treats emissivity and absorption as frequency-dependent during transport, not after transport.
This matters because optical depth is frequency dependent.
Post-coloring a single scalar intensity is acceptable for speed or stylization, but not for accuracy.

### 3. Polarized transport becomes stiff
`ipole` and `RAPTOR II` both matter here.
The key lesson is that explicit per-step Stokes updates are not robust enough once Faraday depth becomes large.
A semi-analytic or hybrid implicit/analytic update is the accuracy path, not more tiny fixed steps alone.

### 4. Time dependence is a real error source
`RAPTOR I` shows fast-light is often acceptable only up to a few percent error depending on the model.
If the target is "really correct" instead of "looks right", then snapshot interpolation / slow-light eventually matters.
This is not phase 1, but it is real.

### 5. Cross-code convergence is the real standard
The EHT code-comparison paper is the right bar.
The target should be:
- convergence under step refinement
- agreement between alternative transport formulations
- stable Stokes I/Q/U/V under controlled test problems

## Recommended implementation order

### Phase A. Sub-step event localization for disk and photosphere hits
Highest ROI for visible image accuracy.

Current touchpoints:
- `Blackhole/Metal/volume_rt.metal`: `trace_single_ray` and mode-specific crossing orchestration
- `Blackhole/Metal/VolumeTransport/legacy.metal`: legacy surface/volume transport helpers
- `Blackhole/Metal/VolumeTransport/grmhd.metal`: GRMHD volume transport helpers
- `segment_enter_disk(...)` call sites in the trace/transport files

Planned change:
- keep the current accepted geodesic step
- when a step brackets a crossing, solve the hit parameter more accurately inside the step
- use a bracketed root solve on the signed disk-height / disk-surface function
- keep the current segment fallback for safety

Why this first:
- improves thin/perlin, thick, visible photosphere, and ray-bundle/Jacobian all at once
- does not require redesigning the RT model first

Expected validation:
- photon ring edge stability under step refinement
- reduced shift of hit position with smaller `P.h`
- reduced bundle Jacobian jitter

### Phase B. Frequency-dependent transport for non-GRMHD visible paths
Current GRMHD visible path already carries three representative visible bins in-loop.
Legacy/perlin/thin paths still rely more on post-colorization.

Current touchpoints:
- `Blackhole/Metal/VolumeTransport/grmhd.metal`: visible multispectral GRMHD loop
- `Blackhole/Metal/spectrum_visible.metal`
- `Blackhole/Metal/Compose/helpers.metalh`: compose-side color mapping helpers

Planned change:
- move thin/perlin visible color generation closer to in-loop transport
- integrate at least 3 representative bins with separate optical depth accumulation
- keep post-compose as display/tone mapping only, not as the place where physics color is invented

Why this second:
- it directly raises physical correctness of visible output
- it aligns legacy/thin paths with what the GRMHD visible path is already partly doing

Expected validation:
- color and structure convergence under more spectral bins
- less dependence on exposure tricks for apparent color

### Phase C. Replace explicit polarized update with semi-analytic / hybrid transport
Current code already carries `IVisNu`, `QVisNu`, `UVisNu`, `VVisNu` and performs explicit Faraday rotation / conversion updates.
That is the exact place where `ipole` and `RAPTOR II` are relevant.

Current touchpoints:
- `Blackhole/Metal/VolumeTransport/grmhd.metal`
- `Blackhole/Metal/VolumeTransport/commit.metal`
- `Blackhole/Metal/Compose/helpers.metalh` debug / inspection branches that consume the packed Stokes-like payload

Planned change:
- implement a constant-coefficient analytic update for one transport step, or a hybrid explicit/implicit switch for stiff cells
- keep the current scalar path unchanged behind a guarded mode while validating

Why this third:
- large accuracy upside, but higher implementation risk
- best done after event localization and spectral transport are stabilized

Expected validation:
- flat-space analytic tests
- high Faraday-depth stability tests
- compare against the current explicit path on optically thin cases

### Phase D. Time interpolation / slow-light support
Current code is effectively fast-light.
That is fine for many preview cases, but not the end of the road for accuracy.

Current touchpoints:
- snapshot / HDF5 preprocessing in `Blackhole/run_pipeline.sh`
- volume sampling in `Blackhole/Metal/volume_rt.metal`

Planned change:
- support two-time-slice interpolation of flow quantities along the ray
- keep fast-light as the default fast mode

Why this fourth:
- this is a physics-accuracy improvement, but broader in scope and workflow cost
- it should come after the stationary transport is made numerically cleaner

## What not to prioritize first
1. Compensated summation (`Kahan`, `Neumaier`)
   - good numerically, but low visible impact in this renderer
2. More blind micro-optimizations in the RT inner loop
   - these improve speed, not accuracy, and were often neutral or worse
3. Occupancy-grid skipping as an accuracy change
   - that is a speed feature, not an accuracy feature

## Concrete code-prep tasks before implementation
1. Add a dedicated signed surface function for disk/photosphere crossing.
2. Add a tiny convergence harness:
   - same scene, `h`, `h/2`, `h/4`
   - compare hit position, ring radius, image PSNR/SSIM
3. Isolate the current visible transport payload into a small helper type so the polarized transport swap is local.
4. Add explicit test scenes:
   - thin/perlin edge-on disk
   - thick disk self-occultation case
   - GRMHD visible volumetric case
   - polarized GRMHD debug case

## Recommended immediate next step
Start with Phase A only:
- accurate crossing solver inside accepted RK/DP45 step
- no model redesign yet
- no polarized solver change yet

That is the most defensible first accuracy upgrade for this codebase.
