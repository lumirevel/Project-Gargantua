# Radiative Transfer Contrast Notes

## Current transfer algorithm

GRMHD visible-volume transfer is integrated in `Blackhole/Metal/volume_rt.metal` inside `volume_integrate_segment`.

For each accepted ray segment:

1. Sample local GRMHD state from `vol0`/`vol1`: density, electron temperature proxy, velocity, and magnetic field.
2. Compute local emission and absorption coefficients in `Blackhole/Metal/VolumeTransport/grmhd.metal`:
   - `disk_visible_rt_components` computes thermal emissivity `jThermal`, thin-tail emissivity `jThin`, total opacity `aTotal`, thermal source `sourceThermal`, and source-function-like values.
   - Visible thermal flow applies physically motivated weights before transfer: thin photosphere, corona layer, thermal source modulation, local dissipation, cloud/skin/body branches, and optional branch isolation diagnostics.
3. Convert comoving coefficients to observed-frame coefficients:
   - `jObs = jCom * g^2`
   - `aObs = aCom / g`
4. Accumulate optical depth:
   - `dTau = min(aObs * ds, 40)`
   - wavelength-aware visible paths accumulate `tauVis`; scalar paths accumulate `tau`.
5. Accumulate radiance:
   - optically thick form: `I_next = I_prev * exp(-dTau) + (jObs / aObs) * (1 - exp(-dTau))`
   - optically thin form: `I_next = I_prev + jObs * ds`
6. Record diagnostics such as `raw-radiance`, `optical_depth`, `source`, `tau1-r`, `tau1-depth`, branch integrals, and emission layer proxies.

## Where contrast may be lost

- High optical depth: once `tau` is large, foreground source-function values dominate and deeper emissivity contrast is physically hidden.
- Source-function smoothing: when `j/alpha` approaches a smooth Planck-like source, structured emissivity can become a smooth photosphere even if local `j` is structured.
- Thermal branch dominance: the smooth thermal/body branch can dominate over cloud/skin/corona branches if branch diagnostics show high `i-thermal-body` and low cloud/corona contribution.
- Tau-surface mode: the Eddington-Barbier shortcut intentionally replaces the integrated path with a local `tau ~= 1` source. This is useful for a photosphere candidate but should be compared with full volume RT.
- Display-side interpretation is not the primary suspect for this branch. The relevant physical debug fields exist before exposure/tone mapping, and this change avoids display tuning.

## Bottleneck assessment

The most likely bottleneck is transfer-side opacity/source-function closure, not lack of local emissivity structure. The code already contains explicit comments and branch logic intended to prevent `j/alpha` from collapsing the visible flow into a uniform slab. The remaining uncertainty is diagnostic: it should be easy to compare pre-transfer emissivity, post-transfer radiance, optical depth, and transfer saturation for the same ray field.

## Implemented low-risk improvement

Added a diagnostic-only transfer saturation view:

```bash
--disk-grmhd-debug transfer-saturation
```

Aliases:

- `transfer_saturation`
- `tau-saturation`
- `tau_saturation`
- `saturation-from-tau`

The diagnostic maps existing accumulated optical depth to:

```text
1 - exp(-tau)
```

This does not change radiative transfer. It makes saturated rays visible as values near 1 and optically thin rays visible near 0.

Also added clearer aliases for the existing pre/post comparison:

- `emissivity-pre-transfer` -> existing `jthermal-weighted`
- `radiance-post-transfer` -> existing `ithermal`

Added branch-balance diagnostics for the visible disk candidate:

- `body-ratio`: post-transfer photospheric body contribution divided by the
  thermal/visible branch total.
- `skin-body-balance`: post-transfer skin plus corona contribution divided by
  body plus skin plus corona.

These diagnostics are intentionally physics-side. They expose whether the
photospheric body is dominating the raw signal before any camera/interpreter
work, and they do not change the rendered radiance.

`raw-radiance` now explicitly emits the accumulated visible luminance used by
the GRMHD visible/XYZ path instead of a per-sample peak or scalar fallback. This
makes the diagnostic represent post-transfer physical signal before
interpreter/camera effects.

The compose stage now routes GRMHD state diagnostics as scalar physical maps for
`raw-radiance`, post-transfer branch radiance, emission-layer, body/source
proxies, `transfer-saturation`, `body-ratio`, and `skin-body-balance`. This
prevents debug payload fields from being reinterpreted as visible spectral
anchors during visible-volume renders. It is diagnostic plumbing only and does
not alter the final non-debug radiance path.

The visible reference-skin body now also ties its weak absorption screen to the
same photospheric layer that emits the body and skin. Earlier changes moved body
emission toward a tau-surface-like layer, but the residual absorption screen
remained broader and could drive nearly uniform transfer saturation. The screen
still has a floor, so this is not a global opacity removal; it prevents
off-photosphere volume from acting like a gray slab over the structured source.

Added a narrow-window raw visible-radiance diagnostic:

```bash
--disk-grmhd-debug raw-radiance-detail
```

This stores the same accumulated visible luminance as `raw-radiance` but maps it
through a narrower diagnostic log window during compose. It is diagnostic-only:
the stored radiance and final image path are unchanged. The current 160 px
visible-disk cache shows why this matters: `raw-radiance` has active
coefficient-of-variation about `0.019`, while `raw-radiance-detail` shows the
same signal with active coefficient-of-variation about `0.402`. This indicates
that some physically meaningful variation survives in the raw signal but is
hidden by the broader debug scale; `radiance-post-transfer` and
`transfer-saturation` remain nearly uniform, so source-function/opacity closure
is still the next physical bottleneck to inspect.

Follow-up comparison added the same kind of narrow-window diagnostics for the
transfer chain:

```bash
--disk-grmhd-debug source-detail
--disk-grmhd-debug emissivity-detail
--disk-grmhd-debug radiance-post-transfer-detail
```

These views reuse the existing source-function, weighted thermal emissivity,
and post-transfer thermal radiance accumulators. They only change the debug
mapping window, not the physical transfer or final image. They are intended to
answer a narrower question: does contrast disappear in local emissivity, in the
`j/alpha` source-function closure, or only after optical-depth integration?
The Swift packing layer keeps these detail views tied to the same trace-side
payload IDs as their broad views, so the comparison changes only the display
window used by the physics diagnostic.
The initial ranges are calibrated from the current 160 px visible-disk cache:
source around `log10(S) ~= -14.8`, weighted emissivity around
`log10(int j ds) ~= -2..2`, and post-transfer thermal radiance around
`log10(I) ~= -8..-6`.

Validation of these detail maps showed:

- `emissivity-detail` exposes substantially more structure than the broad
  emissivity map (`active_cv` about `0.17` vs `0.05` in the 160 px cache).
- `source-detail` exposes weak source-function variation (`active_cv` about
  `0.30`, but most pixels remain near the floor).
- `radiance-post-transfer-detail` remains spatially flat for the current
  scalar thermal accumulator, while `raw-radiance-detail` still shows strong
  structure (`active_cv` about `0.41`). This means the next physical
  investigation should compare the scalar `intIThermal` diagnostic against the
  visible XYZ/band-integrated radiance path; the visible radiance path preserves
  structure that the scalar thermal branch diagnostic does not.

Use these together:

```bash
--disk-grmhd-debug emissivity-pre-transfer
--disk-grmhd-debug emissivity-detail
--disk-grmhd-debug raw-radiance-detail
--disk-grmhd-debug radiance-post-transfer
--disk-grmhd-debug radiance-post-transfer-detail
--disk-grmhd-debug optical_depth
--disk-grmhd-debug transfer-saturation
--disk-grmhd-debug source
--disk-grmhd-debug source-detail
--disk-grmhd-debug body-ratio
--disk-grmhd-debug skin-body-balance
```

## Recommended low-risk changes

- Render a matrix for the same GRMHD/HDF5 volume with `emissivity-pre-transfer`, `radiance-post-transfer`, `optical_depth`, `transfer-saturation`, `source`, `thin-weight`, and `emission-layer`.
- Compare `emissivity-pre-transfer` against `radiance-post-transfer`: if structure exists before transfer but disappears afterward while `transfer-saturation` is near 1, opacity/source-function closure is the likely cause.
- Compare `source` against `radiance-post-transfer`: if both are smooth, the source function is likely flattening the physical signal.

## High-risk changes to avoid

- Do not lower opacity globally just to reveal structure.
- Do not add exposure, tone mapping, bloom, glare, or final-RGB contrast tricks.
- Do not rewrite the transfer integrator before diagnostic comparisons identify whether the failure is local emissivity, optical depth, or source-function closure.
- Do not change packed buffer layouts for this diagnostic; existing collision/debug fields are sufficient.
