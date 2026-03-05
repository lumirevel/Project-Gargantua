# Blackhole Renderer

## Current Layout

- `Blackhole/main.swift`: Swift entry point (GPU collision render)
- `Blackhole/integral.metal`: Metal shader
- `Blackhole/run_pipeline.sh`: main pipeline script (build + render + postprocess)
- `Blackhole/render_collisions.py`: Python postprocess (HDR + tone map + PNG/PPM)
- `run_pipeline.sh`: root wrapper that calls `Blackhole/run_pipeline.sh`
- `Blackhole/scripts/trace_ray_compare.py`: single-ray Schwarzschild vs Kerr trajectory comparison
- `Blackhole/scripts/select_lensed_pixels.py`: Schwarzschild collisions에서 상/하 대표 픽셀 자동 선택
- `Blackhole/scripts/analyze_kerr_gap.py`: 렌더/픽셀선정/레이추적/그래프/리포트 일괄 진단

## One-Command Render

```bash
./run_pipeline.sh
```

Output defaults:
- `collisions.bin`
- `collisions.bin.json`
- `blackhole_gpu.png`

## Common Options

```bash
./run_pipeline.sh --width 1200 --height 1200 --preset interstellar --output blackhole_gpu.png
```

Notes:
- `--output *.png|*.ppm` controls final image output.
- `--output *.bin` controls collisions output path.
- Use one line (or `\` line continuation). Do not put options on a separate line alone.

## Kerr Render

```bash
./run_pipeline.sh --metric kerr --spin 0.92 --preset interstellar --output blackhole_kerr.png
```

Spin convention:
- `--spin` range is `[-0.999, 0.999]`
- negative spin is supported (retrograde disk convention)

Kerr tuning options (Swift side):
- `--kerr-radial-scale`
- `--kerr-azimuth-scale`
- `--kerr-impact-scale`
- `--kerr-substeps`
- `--kerr-escape-mult`

Disk flow options (streamline particle model):
- `--disk-time` (phase-like animation time)
- `--disk-orbital-boost` (azimuthal flow scale)
- `--disk-radial-drift` (inward drift strength)
- `--disk-turbulence` (divergence-free turbulence strength)
- `--disk-orbital-boost-inner`, `--disk-orbital-boost-outer` (inner/outer azimuth scale)
- `--disk-radial-drift-inner`, `--disk-radial-drift-outer` (inner/outer inflow drift)
- `--disk-turbulence-inner`, `--disk-turbulence-outer` (inner/outer turbulence amplitude)
- `--disk-flow-step` (streamline integration step size)
- `--disk-flow-steps` (streamline integration steps)

Example:
```bash
./run_pipeline.sh --metric kerr --spin 0.92 --preset interstellar --disk-time 0.35 --disk-orbital-boost 1.0 --disk-radial-drift 0.02 --disk-turbulence 0.3 --disk-flow-step 0.20 --disk-flow-steps 10 --output blackhole_kerr_flow.png
```

Stage-3 bridge note:
- collisions metadata now includes `bridgeFields` and sampled emission coordinates:
  `emit_r_norm`, `emit_phi`, `emit_z_norm` (stored in collision record tail).

## Single-Ray Comparison

```bash
python3 Blackhole/scripts/trace_ray_compare.py --preset interstellar --spin 0 --pixel-x 760 --pixel-y 640 --csv /tmp/ray_compare.csv
```

This prints per-ray hit/step stats and writes:
- pair csv (`--csv`)
- full state csv (`--full-state-csv`, default: `<csv>_full_state.csv`)
- analysis json (`--analysis-json`, default: `<csv>_analysis.json`)

## Kerr Gap Diagnosis

```bash
python3 Blackhole/scripts/analyze_kerr_gap.py --out-dir /tmp/kerr_diagnosis
```

Generated outputs:
- `/tmp/kerr_diagnosis/renders/*.bin|*.json|*.png`
- `/tmp/kerr_diagnosis/traces/*_pair.csv`
- `/tmp/kerr_diagnosis/traces/*_full_state.csv`
- `/tmp/kerr_diagnosis/traces/*_analysis.json`
- `/tmp/kerr_diagnosis/plots/*.png`
- `/tmp/kerr_diagnosis/report.md`

## Stage-3 Bridge Export

```bash
python3 Blackhole/scripts/export_stage3_bridge.py --input collisions.bin --meta collisions.bin.json --output collisions.stage3.npz
```

Optional CSV:
```bash
python3 Blackhole/scripts/export_stage3_bridge.py --input collisions.bin --csv collisions.stage3.csv
```

## Stage-3 Disk Atlas (Accuracy Mode)

Disk model selector:
- `--disk-model flow`: force streamline flow disk
- `--disk-model procedural`: legacy alias for `flow`
- `--disk-model perlin`: force classic Perlin texture disk (pre-streamline style)
- `--disk-model atlas`: force atlas disk (`--disk-atlas` required, non-precision render path)
- `--disk-model auto`: default. non-precision에서는 atlas 입력이 있으면 atlas를 쓰고, precision에서는 flow로 렌더
- `--disk-model` (형성 방식)과 `--disk-mode` (물리 모드)는 분리되어 동작
- Atlas path auto-pick (non-precision + `--disk-model atlas` + no `--disk-atlas`):
  - search order: `BH_DISK_ATLAS` -> `./disk_atlas.bin` -> `/tmp/stage3_ab/disk_atlas.bin`

Build atlas from bridge samples:
```bash
python3 Blackhole/scripts/build_disk_atlas.py --input collisions.stage3.npz --output disk_atlas.bin --width 1024 --height 512 --r-max 9.0 --r-warp 0.65 --density-source density
```

Build atlas directly from an offline GRMHD snapshot (stage-1 bridge):
```bash
python3 -m pip install h5py
python3 Blackhole/scripts/build_grmhd_atlas.py --input snapshot.h5 --output disk_atlas.bin --width 1024 --height 512 --r-min 1.0 --r-max 9.0 --r-warp 0.65 --density-log
```

Run in one command from HDF5 (pipeline auto-bridge):
```bash
./run_pipeline.sh --pipeline gpu-only --metric kerr --spin 0.92 --disk-mode thick --disk-model atlas --disk-hdf5 snapshot.h5 --disk-hdf5-density-log --disk-atlas-r-warp 0.65 --output blackhole_hdf5.png
```

Shortest practical command (auto temp atlas + auto cleanup):
```bash
./run_pipeline.sh --pipeline gpu-only --disk-hdf5 snapshot.h5 --output blackhole_hdf5.png
```

No snapshot yet? Generate a physically consistent FM torus HDF5 inside `run_pipeline.sh` and render:
```bash
./run_pipeline.sh --pipeline gpu-only --disk-hdf5-sample --output blackhole_hdf5_sample.png
```
FM sample tuning (optional):
```bash
./run_pipeline.sh --pipeline gpu-only --disk-hdf5-sample \
  --disk-hdf5-sample-spin 0.92 \
  --disk-hdf5-sample-r-in 4.5 \
  --disk-hdf5-sample-r-max-pressure 6.0 \
  --disk-hdf5-sample-target-beta 100 \
  --disk-hdf5-sample-perturb 0.01 \
  --output blackhole_hdf5_sample.png
```

Stage-3 direct flow bridge (precision path, atlas bypass):
```bash
./run_pipeline.sh --pipeline gpu-only --disk-mode precision --disk-hdf5 snapshot.h5 --output blackhole_hdf5_precision.png
```
`precision + --disk-hdf5`는 atlas 대신 HDF5 flow profile을 추출해 `disk-orbital-boost`, `disk-radial-drift`, `disk-turbulence`, `disk-flow-step`, `disk-flow-steps`를 자동 보정합니다.
추가로 `disk-orbital-boost-inner/outer`, `disk-radial-drift-inner/outer`, `disk-turbulence-inner/outer`도 자동 보정되어 반지름 의존 유동 프로파일을 반영합니다.

Direct GRMHD scalar-RT volumes (vol0/vol1):
```bash
python3 Blackhole/scripts/build_grmhd_volumes.py --input snapshot.h5 --vol0 grmhd_vol0.bin --vol1 grmhd_vol1.bin --meta grmhd_meta.json
./run_pipeline.sh --pipeline gpu-only --disk-mode grmhd --disk-vol0 grmhd_vol0.bin --disk-vol1 grmhd_vol1.bin --disk-meta grmhd_meta.json --output blackhole_grmhd_rt.png
```

One-command GRMHD path from HDF5 (auto vol0/vol1 build + auto cleanup):
```bash
./run_pipeline.sh --pipeline gpu-only --disk-mode grmhd --disk-hdf5 snapshot.h5 --output blackhole_grmhd_rt.png
```
`--disk-nu-obs-hz`, `--disk-grmhd-density-scale`, `--disk-grmhd-b-scale`, `--disk-grmhd-emission-scale`, `--disk-grmhd-absorption-scale`, `--disk-grmhd-vel-scale`로 RT 스칼라 계수를 조정할 수 있습니다.

Native 3D ingest (no mid-plane collapse, uses source `r-theta-phi` directly):
```bash
./run_pipeline.sh --pipeline gpu-only --disk-mode grmhd --disk-hdf5 snapshot.h5 \
  --disk-grmhd-native-3d on \
  --output blackhole_grmhd_native3d.png
```
- `--disk-grmhd-native-3d auto`(기본): 가능한 경우 3D 직접 매핑, 아니면 2D fallback
- `--disk-grmhd-native-3d on`: 3D 매핑 강제(불가하면 에러)
- `--disk-grmhd-native-3d off`: 기존 2D+수직프로파일 경로
- 필요 시 `--disk-hdf5-theta-key`로 theta 좌표 키를 지정합니다.

For seeded initial-condition perturbation on HDF5 (phenomenological reproducible clumps, pre-render):
```bash
./run_pipeline.sh --pipeline gpu-only --disk-mode precision --disk-pluto --disk-ic-amp 0.18 --disk-ic-seed 42 --disk-ic-scale 14 --output blackhole_pluto_ic.png
```
`--disk-ic-amp`가 0보다 크면 flow/volume 브리지 전에 HDF5 스냅샷 자체를 섭동합니다.

## Fishbone-Moncrief IC (Kerr-Schild)

`Blackhole/scripts/build_sample_hdf5.py`는 Kerr-Schild 좌표계에서 Fishbone-Moncrief 평형 토러스를 생성합니다.

핵심 식:

- 상수 비각운동량:
  - `l = l_K(r_max_pressure)`
- 각 셀에서:
  - `-u_t = sqrt((g_tphi^2 - g_tt g_phiphi) / (g_phiphi + 2 l g_tphi + l^2 g_tt))`
  - `h = (-u_t)_in / (-u_t)`
  - `rho = ((h - 1) / ((n + 1) K))^n`, `p = K rho^(1 + 1/n)` (토러스 내부)
- 자기장:
  - `A_phi ∝ max(rho - rho_cut, 0)`
  - `B^i = (1/sqrt(gamma)) eps^{ijk} d_j A_k`
  - `beta = p / (B^2 / 8pi)`가 `target_beta`가 되도록 전역 정규화
- MRI 시드:
  - `rho -> rho * (1 + delta)`, `delta ~ U[-amp, amp]` (기본 `amp=0.01`)

산출 HDF5 필드:

- `rho`, `p` (`press`, `prs` alias)
- `ucon`, `u0..u3` (4-velocity)
- `Br/Bphi/Bz` 및 `B1/B2/B3`
- `bcon`, `b0..b3`, `bsq`, `sigma`
- 진단: `Aphi_axisym`, `divB_axisym`, `torus_mask_axisym`

GPU 메모리 레이아웃(현재 renderer):

- `vol0(float4) = (log_rho, log_thetae, v_r, v_phi)`
- `vol1(float4) = (v_z, B_r, B_phi, B_z)`

안정성 체크리스트:

- `divB_rms_axisym`, `divB_rel_max_axisym` 확인 (`~0`에 가까울수록 좋음)
- `sigma_max_actual <= sigma_max_target` 확인
- 토러스 파라미터 제약: `r_max_pressure > r_in > r_horizon`
- `target_beta`/`rho_cut_frac` 조합으로 과자화(magnetization spike) 방지

PLUTO preset (recommended when your HDF5 uses `x1v/x3v/rho/vx1/vx3`):
```bash
./run_pipeline.sh --pipeline gpu-only --disk-mode precision --disk-hdf5 snapshot.h5 --disk-hdf5-preset pluto --output blackhole_pluto_precision.png
```

Shortest PLUTO command (auto-discover snapshot + auto key mapping):
```bash
./run_pipeline.sh --pipeline gpu-only --disk-mode precision --disk-pluto --output blackhole_pluto_precision.png
```

If auto-discovery misses the file, pass only one path option:
```bash
./run_pipeline.sh --pipeline gpu-only --disk-mode precision --disk-pluto-path /path/to/snapshot.h5 --output blackhole_pluto_precision.png
```
You can also set `BH_PLUTO_HDF5=/path/to/snapshot.h5` and keep using `--disk-pluto`.

You can override keys explicitly:
- `--disk-hdf5-r-key`, `--disk-hdf5-phi-key`, `--disk-hdf5-rho-key`
- `--disk-hdf5-vr-key`, `--disk-hdf5-vphi-key`
- atlas path only: `--disk-hdf5-temp-key`

Useful GRMHD mapping options:
- `--list-datasets`: list dataset paths before mapping
- `--r-key --phi-key --rho-key --temp-key --vr-key --vphi-key`: explicit key/path overrides
- `--theta-index` or `--theta-average`: mid-plane slice vs averaged projection
- `--r-to-rs`: convert input radius units to `r/rs` (e.g. if input is `r/rg`, use `0.5`)
- `--vr-is-ratio`, `--vphi-is-scale`, `--temp-is-scale`: skip normalization when fields are already atlas-ready

Render with GRMHD atlas:
```bash
./run_pipeline.sh --metric kerr --spin 0.92 --disk-mode thick --disk-model atlas --disk-atlas disk_atlas.bin --output blackhole_grmhd.png
```

Precision render path:
```bash
./run_pipeline.sh --metric kerr --spin 0.92 --disk-mode precision --disk-model flow --output blackhole_precision_flow.png
```

Render with atlas-driven disk model:
```bash
./run_pipeline.sh --metric kerr --spin 0.92 --preset interstellar --disk-mdot-edd 0.1 --disk-radiative-efficiency 0.1 --disk-atlas disk_atlas.bin --disk-atlas-temp-scale 1.0 --disk-atlas-density-blend 0.7 --disk-atlas-vr-scale 0.35 --disk-atlas-vphi-scale 1.0 --disk-atlas-r-min 1.0 --disk-atlas-r-max 9.0 --disk-atlas-r-warp 0.65 --output blackhole_stage3.png
```

Atlas channels (`float4`):
- `x`: temperature scale
- `y`: density (cloud/noise blending source)
- `z`: radial velocity ratio
- `w`: azimuthal velocity scale

Physical disk controls:
- `--disk-mdot-edd <value>`: accretion rate in Eddington units (default `0.1`)
- `--disk-radiative-efficiency <value>`: thin-disk radiative efficiency `eta` (default `0.1`)
- `--disk-mode {thin|thick|precision|grmhd|auto}`:
  - `thin`: ISCO에서 엄밀 절단
  - `thick`: 플라즈마 + plunging 연속 방출 (ISCO 내부는 ISCO 보존량 기반 자유낙하 속도장 사용)
  - `precision`: Novikov-Thorne(Page-Thorne) 보정 + zero-torque ISCO + 1-회 returning-radiation 재가열 근사 + 체적(다중 샘플) 구름 복사전달 + 산란 지배 limb law + `diskH` 기반 연속 두께(얇음↔두꺼움) 기본값
  - `grmhd`: `vol0(log_rho,log_thetae,v_r,v_phi)` + `vol1(v_z,B_r,B_phi,B_z)` 볼륨을 사용한 스칼라 GRRT 누적 적분(`I_nu`) 경로
  - `auto`: `precision` 별칭. `diskH`를 보고 `plunge-floor`/`thick-scale` 기본값을 연속적으로 자동 설정
- `--disk-physics-mode`: 레거시 별칭(호환용), `--disk-mode` 사용 권장
- `--disk-vol0`, `--disk-vol1`, `--disk-meta`: grmhd 볼륨 파일 경로
- `--disk-nu-obs-hz`: grmhd 관측 주파수(기본 `230e9`)
- `--disk-grmhd-density-scale`, `--disk-grmhd-b-scale`, `--disk-grmhd-emission-scale`, `--disk-grmhd-absorption-scale`, `--disk-grmhd-vel-scale`: grmhd 스칼라 RT 계수
- `--disk-plunge-floor <value>`: ISCO 내부 최소 방출 강도 (thick 기본 `0.02`, precision/auto는 `diskH` 기반 자동 기본값)
- `--disk-thick-scale <value>`: 반두께 배율 (thick 기본 `1.3`, precision/auto는 `diskH` 기반 자동 기본값)
- `--disk-color-factor <value>`: precision 모드 스펙트럴 hardening factor `f_col` (default `1.7`)
- `--disk-returning-rad <0..1>`: precision 모드 내부 고리 returning-radiation 근사 강도 (default `0.35`)
- `--disk-precision-texture <0..1>`: precision 모드 미세 난류 텍스처 강도 (default `0.58`)
- `--disk-precision-clouds {on|off}`: precision 모드 구름 점유/차폐 전달식 사용 여부 (default `on`)
- `--disk-cloud-coverage <0..1>`: 구름 덮임 비율 (default `0.88`)
- `--disk-cloud-optical-depth <0..12>`: 시선방향 광학깊이 기준값 (default `2.0`)
- `--disk-cloud-porosity <0..1>`: 빈 공간(갭) 비율 (default `0.18`)
- `--disk-cloud-shadow-strength <0..1>`: 차폐 강도 블렌드 (default `0.90`)
- `--disk-atlas-density-blend <value>`: atlas density 혼합 비율 (default thin=`0.70`, thick=`0.55`; precision render path에서는 atlas 비활성)
- `--disk-ic-amp <>=0>`: HDF5 초기조건 섭동 강도(현상론적 seeded perturbation, default `0`, 비활성)
- `--disk-ic-seed <int>`: HDF5 초기조건 섭동 시드 (default `1337`)
- `--disk-ic-scale <cells>`: HDF5 초기조건 섭동 상관 길이(셀 단위, default `12`)
- `--background {off|stars}`: miss ray 배경 (default: cinematic 카메라에서 `stars`, 나머지는 `off`)
- `--bg-stars {on|off}`: `--background`의 on/off 별칭
- `--bg-star-density <0..4>`: 별 밀도
- `--bg-star-strength <0..4>`: 별 밝기
- `--bg-nebula-strength <0..2>`: 은하대(nebula) 강도

Thin (strict) example:
```bash
./run_pipeline.sh --metric kerr --spin 0.92 --disk-mode thin --disk-mdot-edd 0.1 --disk-radiative-efficiency 0.1 --output blackhole_thin.png
```

Thick (plasma + plunging) example:
```bash
./run_pipeline.sh --metric kerr --spin 0.92 --disk-mode thick --disk-plunge-floor 0.02 --disk-thick-scale 1.3 --disk-mdot-edd 0.1 --disk-radiative-efficiency 0.1 --output blackhole_thick.png
```

Precision (analysis-oriented) example:
```bash
./run_pipeline.sh --metric kerr --spin 0.92 --disk-mode precision --disk-color-factor 1.7 --disk-returning-rad 0.35 --disk-precision-texture 0.58 --disk-precision-clouds on --disk-cloud-coverage 0.88 --disk-cloud-optical-depth 2.0 --disk-cloud-porosity 0.18 --disk-cloud-shadow-strength 0.90 --disk-mdot-edd 0.1 --disk-radiative-efficiency 0.1 --collisions debug --output blackhole_precision.png
```
`precision` 모드는 물리식 정합을 위해 `gpu-only` compose 경로를 사용합니다.

Auto-unified (diskH 기반 thin↔thick 연속 전환) example:
```bash
./run_pipeline.sh --pipeline gpu-only --disk-mode auto --diskH 0.08 --output blackhole_auto_precision.png
```

Lensed star background example:
```bash
./run_pipeline.sh --pipeline gpu-only --disk-mode precision --camera-model cinematic --background stars --bg-star-density 1.2 --bg-star-strength 1.0 --bg-nebula-strength 0.5 --output blackhole_stars.png
```

Radial mapping:
- `--r-warp <value>` in atlas build and `--disk-atlas-r-warp <value>` in render must match.
- `< 1.0` allocates more radial bins near the inner ring (`r ~ rs`), `1.0` is linear.

## Stage-3 A/B Auto Report

Run no-atlas baseline vs atlas in one command and generate quality report:

```bash
python3 Blackhole/scripts/compare_stage3_ab.py --out-dir /tmp/stage3_ab --no-build --width 640 --height 640 --preset interstellar --metric kerr --spin 0.92 --atlas-r-warp 0.65
```

Pipeline shortcut (recommended):

```bash
./run_pipeline.sh stage3-ab --no-build --out-dir /tmp/stage3_ab --width 640 --height 640 --preset interstellar --metric kerr --spin 0.92 --atlas-r-warp 0.65
```

Outputs:
- `/tmp/stage3_ab/baseline_no_atlas.ppm`
- `/tmp/stage3_ab/atlas_stage3.ppm`
- `/tmp/stage3_ab/diff_abs_xgain.ppm`
- `/tmp/stage3_ab/report.json`
- `/tmp/stage3_ab/report.md`
