# Disk Physics Modes

This project keeps legacy behavior by default and adds optional physics-profile routing via:

```bash
--disk-physics {legacy|thin|thick|eht}
```

If `--disk-physics` is omitted, existing `--disk-mode ...` behavior is preserved.

## Mode Quick Start

### 1) Legacy (default compatibility)
```bash
./run_pipeline.sh --pipeline gpu-only --disk-mode thin --output out_legacy.png
```

### 2) Thin (Novikov–Thorne-ish surface profile)
```bash
./run_pipeline.sh --pipeline gpu-only --disk-physics thin \
  --mdot-edd 0.08 --eta 0.10 --fcol 1.6 \
  --output out_thin.png
```

### 3) Thick (puffed geometry + optional cloud attenuation)
```bash
./run_pipeline.sh --pipeline gpu-only --disk-physics thick \
  --thick-scale 1.5 --cloud-tau 1.2 --rt-steps 12 \
  --output out_thick.png
```

### 4) EHT-style RIAF (GRMHD volume RT path)
```bash
./run_pipeline.sh --pipeline gpu-only --disk-physics eht \
  --nu-obs-hz 230000000000 --rt-steps 16 \
  --output out_eht.png
```

## Visible Policy

`--visible-policy` controls how RIAF intensity is visualized in visible output:

- `physical` (default): keep physical visible-spectrum interpretation.
- `expressive`: map `nu_obs`-driven emissivity into visible palette for readability.

Example:
```bash
./run_pipeline.sh --pipeline gpu-only --disk-physics eht --visible-mode on \
  --visible-policy expressive --output out_eht_expressive.png
```
