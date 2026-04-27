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

Use these together:

```bash
--disk-grmhd-debug emissivity-pre-transfer
--disk-grmhd-debug radiance-post-transfer
--disk-grmhd-debug optical_depth
--disk-grmhd-debug transfer-saturation
--disk-grmhd-debug source
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
