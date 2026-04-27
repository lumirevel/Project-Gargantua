# Plasma Fluctuation Notes

## Motivation

The desired cloud-like structure should not be introduced as Perlin noise or a
camera/display effect on this branch. In accretion physics the closest
interpretable source is magnetized plasma turbulence: density, electron
temperature, magnetic stress, and optically thin hot-skin or synchrotron
emission. The film reference is visually cloud-like, but the physics branch
should expose plasma fluctuation candidates and diagnostics rather than painting
image-space clouds.

References consulted:

- James, von Tunzelmann, Franklin, and Thorne, "Gravitational lensing by spinning
  black holes in astrophysics, and in the movie Interstellar",
  `https://arxiv.org/abs/1502.03808`
- CaltechAUTHORS record for the same DNGR/Interstellar paper,
  `https://authors.library.caltech.edu/records/awp8p-s4d82`

## Current Finding

Diagnostic renders using the evolved GRMHD cache under `/private/tmp` show that
the renderer already has plasma-structure signals:

- `flow-residual`
- `jthermal-cloud`
- `thermal-cloud-ratio`
- `raw-radiance`
- `grmhd-branch-isolation cloud`

The main bottleneck is not the absence of a cloud/plasma source. The thermal
volume and thin photosphere paths integrate broad emission through the line of
sight, so local turbulent structure becomes a smooth accumulated radiance field.
Branch-isolated cloud renders still resemble the total thermal result, which
means the cloud emissivity is currently too volume-filling and too smoothly
integrated for a strong 3D cloud impression.

Generated comparison sheets from this investigation:

- `/private/tmp/bh_physics_grmhd_cloud_cause_192/cloud_cause_contact_3x.png`
- `/private/tmp/bh_physics_grmhd_branch_isolation_160/branch_isolation_contact.png`
- `/private/tmp/bh_physics_source_model_cloud_probe_160/source_model_cloud_probe_contact.png`

## Implemented Small Change

`Blackhole/run_pipeline.sh` now exposes:

```bash
--source-model grmhd-plasma-fluctuation-candidate
```

This is a named physics-side alias for the existing optically thin GRMHD hot-flow
path. It deliberately does not add new post-processing, tone mapping, bloom,
exposure, or procedural texture. It gives the renderer a clear public source
model name for testing cloud-like structure from plasma fluctuations.

The optically thin visible/NIR tail now keeps a smaller continuity floor in
`disk_grmhd_visible_thin_tail_coeffs`: `0.004 + 0.996 * tailActivation` instead
of `0.012 + 0.988 * tailActivation`. This keeps the dense volume from glowing
uniformly and makes the candidate more dependent on hot/magnetized plasma cells.
The change is intentionally limited to the synchrotron/plasma-tail emissivity
path.

The script help also now lists existing physics controls that were already parsed
by Swift but were hard to discover from the public pipeline:

- `--grmhd-branch-isolation {off|smooth|cloud|body|skin|corona}`
- `--grmhd-transport-alpha-scale`
- `--grmhd-smooth-emission-scale`
- `--grmhd-cloud-emission-scale`

## Visible Disk Candidate

The movie-visible accretion disk should not be represented only by the optically
thin hot-flow candidate. That path is useful for plasma fluctuation diagnostics,
but a visible disk needs a luminous photospheric body.

`Blackhole/run_pipeline.sh` now also exposes:

```bash
--source-model grmhd-visible-disk-skin-candidate
```

This candidate routes through GRMHD visible thermal transfer with:

- a visible photospheric disk body: `--grmhd-smooth-weight visible-reference-skin`
- positive GRMHD hot-skin emissivity: `--grmhd-cloud-emission-scale 2.10`
- no procedural Perlin clouds and no camera/display changes
- `teff-T0=7200`, `teff-p=0.63`, `grmhd-smooth-emission-scale=1.75`,
  `grmhd-cloud-emission-scale=2.10`, `disk-grmhd-emission-scale=1.25e-10`,
  and scientific presentation by default

The earlier `9500 K / body 2.50 / skin 0.95` candidate looked like a gray
plastic disk in scientific output because the smooth photospheric body dominated
and the blackbody color sat near white. The current default intentionally lowers
the visible photosphere temperature scale and shifts more signal into the
positive hot/magnetized skin branch. In the same GRMHD cache, the measured final
contrast rose from about `0.412` to `0.699` without changing camera or display
mapping.

The visible-reference body also gates the photospheric body by local visible
temperature. Cooler outer photosphere cells now contribute only a weak continuum
floor instead of a broad gray slab; gas hot enough to radiate efficiently in the
visible band keeps the dominant body emission, and the hot-skin branch keeps a
less aggressive version of the same temperature support.

After this gate, the default visible-disk source budget was moved to the
moderate luminosity probe point. In the same 160px GRMHD comparison, this raised
the measured final mean from about `0.139` to `0.158` while keeping contrast at
about `0.740`; hotter probes were brighter but moved back toward a smoother
body-dominated disk.

Branch-isolation probes after the gate show the remaining realism bottleneck:
the photospheric body branch is bright but still comparatively smooth, while the
GRMHD skin/cloud branches carry more spatial structure but less total power. A
follow-up body/skin gain sweep increased apparent contrast only by making the
disk dimmer, so further work should change the physical source/transfer closure
rather than keep moving global gains.

Use this when testing a film-visible disk body with physically sourced plasma
structure. Use `grmhd-plasma-fluctuation-candidate` only when the goal is to
inspect the optically thin hot-flow tail itself.

## How To Inspect

Use the plasma fluctuation source model with physical diagnostics:

```bash
./run_pipeline.sh \
  --source-model grmhd-plasma-fluctuation-candidate \
  --presentation scientific \
  --disk-grmhd-debug raw-radiance \
  --disk-vol0 <cache>.vol0.bin \
  --disk-vol1 <cache>.vol1.bin \
  --disk-meta <cache>.meta.json \
  --output /private/tmp/plasma_raw.png
```

Recommended comparison set:

```bash
--disk-grmhd-debug flow-residual
--disk-grmhd-debug jthermal-cloud
--disk-grmhd-debug thermal-cloud-ratio
--disk-grmhd-debug raw-radiance
--grmhd-branch-isolation cloud
```

For the visible disk candidate, compare:

```bash
--source-model grmhd-visible-disk-skin-candidate
--disk-grmhd-debug raw-radiance
--disk-grmhd-debug jthermal-cloud
--disk-grmhd-debug thermal-cloud-ratio
--grmhd-branch-isolation body
--grmhd-branch-isolation cloud
```

## Remaining Scientific Risk

- The public GRMHD snapshot may not contain enough non-axisymmetric contrast at
  the selected resolution and time slice.
- Line-of-sight volume integration can physically smooth optically thin emission
  even when local emissivity is structured.
- A stronger solution may require a calibrated positive hot-skin emissivity model
  or time-dependent multi-snapshot fluctuation analysis, not a single-frame gain
  tweak.
- Any future "cloud" solution must remain source/emissivity/transfer-side and
  must not be implemented as final RGB texture, bloom, glare, exposure, or color
  grading.
