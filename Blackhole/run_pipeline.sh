#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Blackhole.xcodeproj"
SCHEME="Blackhole"
CONFIGURATION="Release"
DERIVED_DATA_PATH="${BH_DERIVED_DATA_PATH:-/tmp/BlackholeDD_rebuild}"
BIN_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Blackhole"
COLLISIONS_OUT="${BH_COLLISIONS_OUT:-$ROOT_DIR/collisions.bin}"
IMAGE_OUT="${BH_IMAGE_OUT:-$ROOT_DIR/blackhole_gpu.png}"
NO_BUILD=0
MODE="fast"
COLLISIONS_MODE="auto"
COLLISIONS_POLICY="temp"
PIPELINE_MODE="gpu-only"
SSAA=1
WIDTH_SET=0
HEIGHT_SET=0
WIDTH_VALUE=""
HEIGHT_VALUE=""
TILE_SIZE_VALUE=""
TILE_SIZE_EXPLICIT=0
COLLISIONS_OUT_EXPLICIT=0
METRIC_VALUE="schwarzschild"
MAX_STEPS_VALUE=""
KERR_SUBSTEPS_VALUE=""
SPECTRAL_STEP_VALUE="5.0"
EXPOSURE_VALUE=""
DISK_ATLAS_WIDTH_VALUE=""
DISK_ATLAS_HEIGHT_VALUE=""
DISK_ATLAS_R_MIN_VALUE=""
DISK_ATLAS_R_MAX_VALUE=""
DISK_ATLAS_R_WARP_VALUE=""
DISK_HDF5_PATH=""
DISK_PLUTO_MODE=0
DISK_HDF5_PRESET="auto"
DISK_HDF5_OUT=""
DISK_HDF5_OUT_EXPLICIT=0
DISK_HDF5_R_TO_RS=""
DISK_HDF5_KEPLER_GM=""
DISK_HDF5_R_KEY=""
DISK_HDF5_PHI_KEY=""
DISK_HDF5_RHO_KEY=""
DISK_HDF5_TEMP_KEY=""
DISK_HDF5_VR_KEY=""
DISK_HDF5_VPHI_KEY=""
DISK_HDF5_THETA_INDEX=""
DISK_HDF5_DENSITY_P_LO=""
DISK_HDF5_DENSITY_P_HI=""
DISK_HDF5_THETA_AVERAGE=0
DISK_HDF5_DENSITY_LOG=0
DISK_HDF5_TEMP_IS_SCALE=0
DISK_HDF5_VR_IS_RATIO=0
DISK_HDF5_VPHI_IS_SCALE=0
DISK_HDF5_FLOW=0
DISK_HDF5_SAMPLE=0
DISK_HDF5_SAMPLE_OUT=""
DISK_HDF5_SAMPLE_OUT_EXPLICIT=0
DISK_HDF5_SAMPLE_NR="96"
DISK_HDF5_SAMPLE_NPHI="192"
TEMP_HDF5_ATLAS=""
TEMP_HDF5_SAMPLE=""
TEMP_HDF5_FLOW_PROFILE=""
TEMP_COLLISIONS=""
DISK_ORBITAL_BOOST_SET=0
DISK_RADIAL_DRIFT_SET=0
DISK_TURBULENCE_SET=0
DISK_ORBITAL_BOOST_INNER_SET=0
DISK_ORBITAL_BOOST_OUTER_SET=0
DISK_RADIAL_DRIFT_INNER_SET=0
DISK_RADIAL_DRIFT_OUTER_SET=0
DISK_TURBULENCE_INNER_SET=0
DISK_TURBULENCE_OUTER_SET=0
DISK_FLOW_STEP_SET=0
DISK_FLOW_STEPS_SET=0

SWIFT_ARGS=()
PY_ARGS=()
PY_MODE=0
LOOK_SET=0
PRESET_VALUE=""
ETA_SCRIPT="$ROOT_DIR/scripts/pipeline_eta.py"
ETA_HISTORY_OLD="$ROOT_DIR/.pipeline_eta_history.json"
ETA_HISTORY="${BH_ETA_HISTORY:-$ROOT_DIR/pipeline_eta_history.json}"
ETA_RELAY="${BH_ETA_RELAY:-errors}"
COMPOSE_BACKEND="python"
MATCH_CPU=1
GPU_FULL_COMPOSE=0
GPU_STREAM_LINEAR32=0
LINEAR32_OUT=""
LEGACY_COMPOSE_OVERRIDE=""
DISK_MODEL_VALUE="auto"
DISK_MODEL_SET=0
DISK_ATLAS_VALUE=""
DISK_ATLAS_SET=0
DISK_PHYSICS_MODE_VALUE=""
DISK_MODE_ARG_PRESENT=0
DISK_REPR_VALUE=""
DISK_REPR_SET=0
DISK_SOURCE_VALUE=""
DISK_SOURCE_SET=0
PIPELINE_ARG_PRESENT=0
PYTHON_BIN="${BH_PYTHON:-python3}"
VERIFY_REF=""
VERIFY_OUT=""
VERIFY_MAX_RMSE=""
VERIFY_MAX_REL_L2=""
VERIFY_MASK_LUMA=""

case "$ETA_RELAY" in
  always|errors|none) ;;
  *)
    echo "error: BH_ETA_RELAY must be one of always, errors, none" >&2
    exit 2
    ;;
esac

cleanup_temp_artifacts() {
  if [[ -n "${TEMP_COLLISIONS:-}" ]]; then
    rm -f "${TEMP_COLLISIONS}" "${TEMP_COLLISIONS}.json"
  fi
  if [[ -n "${LINEAR32_OUT:-}" && "${GPU_STREAM_LINEAR32:-0}" -eq 1 && -n "${TEMP_COLLISIONS:-}" ]]; then
    rm -f "${LINEAR32_OUT}" "${LINEAR32_OUT}.json"
  fi
  if [[ -n "${TEMP_HDF5_ATLAS:-}" ]]; then
    rm -f "${TEMP_HDF5_ATLAS}" "${TEMP_HDF5_ATLAS}.json"
  fi
  if [[ -n "${TEMP_HDF5_SAMPLE:-}" ]]; then
    rm -f "${TEMP_HDF5_SAMPLE}"
  fi
  if [[ -n "${TEMP_HDF5_FLOW_PROFILE:-}" ]]; then
    rm -f "${TEMP_HDF5_FLOW_PROFILE}"
  fi
}

trap cleanup_temp_artifacts EXIT

# Migrate old hidden ETA history path to the new visible default path.
if [[ -z "${BH_ETA_HISTORY:-}" && -f "$ETA_HISTORY_OLD" && ! -f "$ETA_HISTORY" ]]; then
  mv "$ETA_HISTORY_OLD" "$ETA_HISTORY" 2>/dev/null || cp "$ETA_HISTORY_OLD" "$ETA_HISTORY"
fi

log_section() {
  printf "\n== %s ==\n" "$1"
}

log_item() {
  printf "  %-16s %s\n" "$1" "$2"
}

to_gib() {
  awk -v b="$1" 'BEGIN { printf "%.1f", b / 1073741824.0 }'
}

normalize_dash() {
  local s="$1"
  s="${s/#—/--}"
  s="${s/#–/--}"
  s="${s/#−/--}"
  printf '%s' "$s"
}

need_value() {
  local key="$1"
  if [[ "$#" -lt 2 || -z "${2:-}" ]]; then
    echo "missing value for $key" >&2
    exit 2
  fi
}

canonical_disk_model() {
  local model="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$model" in
    flow|procedural|legacy|noise)
      printf 'flow'
      ;;
    perlin)
      printf 'perlin'
      ;;
    atlas)
      printf 'atlas'
      ;;
    auto|"")
      printf 'auto'
      ;;
    *)
      printf '%s' "$model"
      ;;
  esac
}

python_executable_exists() {
  local py="$1"
  if [[ "$py" == */* ]]; then
    [[ -x "$py" ]]
  else
    command -v "$py" >/dev/null 2>&1
  fi
}

python_has_module() {
  local py="$1"
  local module="$2"
  "$py" - "$module" <<'PY' >/dev/null 2>&1
import importlib
import sys

importlib.import_module(sys.argv[1])
PY
}

resolve_python_with_module() {
  local module="$1"
  local preferred="${BH_PYTHON:-}"
  local candidates=()
  local cand=""
  local seen="|"
  local resolved=""

  if [[ -n "$preferred" ]]; then
    if python_executable_exists "$preferred" && python_has_module "$preferred" "$module"; then
      printf '%s' "$preferred"
      return 0
    fi
    return 1
  fi

  candidates+=("python3" "python")
  candidates+=("$HOME/opt/anaconda3/bin/python3")
  candidates+=("/opt/homebrew/bin/python3")
  candidates+=("/usr/local/bin/python3")

  for cand in "${candidates[@]}"; do
    if [[ -z "$cand" || "$seen" == *"|$cand|"* ]]; then
      continue
    fi
    seen+="$cand|"
    if ! python_executable_exists "$cand"; then
      continue
    fi
    if python_has_module "$cand" "$module"; then
      resolved="$cand"
      break
    fi
  done

  if [[ -n "$resolved" ]]; then
    printf '%s' "$resolved"
    return 0
  fi
  return 1
}

ensure_h5py_python() {
  if python_has_module "$PYTHON_BIN" "h5py"; then
    return 0
  fi
  local resolved=""
  if resolved="$(resolve_python_with_module "h5py")"; then
    if [[ "$resolved" != "$PYTHON_BIN" ]]; then
      echo "info: selected python with h5py: $resolved" >&2
    fi
    PYTHON_BIN="$resolved"
    return 0
  fi
  if [[ -n "${BH_PYTHON:-}" ]]; then
    echo "error: BH_PYTHON does not provide h5py: $BH_PYTHON" >&2
  else
    echo "error: no python interpreter with h5py found for PLUTO/HDF5 preprocessing." >&2
  fi
  echo "hint: install h5py (python3 -m pip install h5py) or set BH_PYTHON to a compatible interpreter." >&2
  exit 2
}

if ! python_executable_exists "$PYTHON_BIN"; then
  echo "error: python interpreter not found: $PYTHON_BIN" >&2
  echo "hint: set BH_PYTHON to a valid python executable path/name." >&2
  exit 2
fi

resolve_pluto_hdf5() {
  local root="$1"
  local env_path="${BH_PLUTO_HDF5:-}"
  local candidates=()
  if [[ -n "$env_path" ]]; then
    candidates+=("$env_path")
  fi
  candidates+=(
    "$root/pluto_snapshot.h5"
    "$root/pluto.h5"
    "$root/snapshot.h5"
    "$root/pluto/snapshot.h5"
    "$root/data/pluto/snapshot.h5"
  )
  local p=""
  for p in "${candidates[@]}"; do
    if [[ -n "$p" && -f "$p" ]]; then
      printf '%s' "$p"
      return 0
    fi
  done
  "$PYTHON_BIN" - "$root" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
dirs = [root, root / "pluto", root / "data", root / "data" / "pluto"]
files = []
for d in dirs:
    if not d.exists():
        continue
    for p in d.rglob("*.h5"):
        if p.is_file():
            files.append(p.resolve())
if not files:
    print("", end="")
    raise SystemExit(0)

def rank(path: Path):
    name = path.name.lower()
    pri = 0 if "pluto" in name else 1
    return (pri, -path.stat().st_mtime)

best = sorted(set(files), key=rank)[0]
print(str(best), end="")
PY
}

show_help() {
  cat <<'USAGE'
Usage: ./run_pipeline.sh [options]

One-command pipeline:
1) Build and run Swift/Metal renderer
2) Compose final image (GPU Metal or Python)
3) Save final image (PNG default)

Routing rules:
- Shared: --width --height --rcp
- Spin range: --spin [-0.999, 0.999] (negative = retrograde orbit convention)
- Swift-only: --preset --camX --camY --camZ --fov --roll --diskH --maxSteps --h --metric --spin --kerr-substeps --kerr-tol --kerr-escape-mult --kerr-radial-scale --kerr-azimuth-scale --kerr-impact-scale --disk-time --disk-orbital-boost --disk-radial-drift --disk-turbulence --disk-orbital-boost-inner --disk-orbital-boost-outer --disk-radial-drift-inner --disk-radial-drift-outer --disk-turbulence-inner --disk-turbulence-outer --disk-flow-step --disk-flow-steps --disk-mdot-edd --disk-radiative-efficiency --disk-mode --disk-physics-mode --disk-plunge-floor --disk-thick-scale --disk-color-factor --disk-returning-rad --disk-return-bounces --disk-rt-steps --disk-scattering-albedo --disk-precision-texture --disk-precision-clouds --disk-cloud-coverage --disk-cloud-optical-depth --disk-cloud-porosity --disk-cloud-shadow-strength --disk-model --disk-atlas --disk-atlas-width --disk-atlas-height --disk-atlas-temp-scale --disk-atlas-density-blend --disk-atlas-vr-scale --disk-atlas-vphi-scale --disk-atlas-r-min --disk-atlas-r-max --disk-atlas-r-warp
- Disk model values: --disk-model {flow|perlin|atlas|auto} (alias: procedural)
- Disk mode values: --disk-mode {thin|thick|precision} (legacy: --disk-physics-mode)
- Disk representation selector: --disk-repr {2d|3d}
- Disk source selector: --disk-source {flow|perlin|atlas|hdf5|pluto}
  - 2d + {perlin|atlas|hdf5|pluto}: textured/atlas path (hdf5/pluto auto-bridge to atlas)
  - 3d + {flow|hdf5|pluto}: precision flow path (hdf5/pluto auto-bridge to flow profile)
- Precision texture controls: --disk-returning-rad <0..1> --disk-return-bounces <1..4> --disk-rt-steps <0..32> --disk-scattering-albedo <0..1> --disk-precision-texture <0..1>
- Precision cloud controls: --disk-precision-clouds {on|off} --disk-cloud-coverage <0..1> --disk-cloud-optical-depth <0..12> --disk-cloud-porosity <0..1> --disk-cloud-shadow-strength <0..1>
- Precision physics requires GPU compose path (--pipeline gpu-only).
- Atlas auto path: in non-precision mode, when --disk-model atlas is set and --disk-atlas is omitted, auto-search order is BH_DISK_ATLAS, ./disk_atlas.bin, /tmp/stage3_ab/disk_atlas.bin
- Compose controls: --chunk --spectral-step --exposure --exposure-samples --dither --inner-edge-mult --look
- PLUTO shortcut: --disk-pluto (auto-discover .h5, fallback to auto sample) or --disk-pluto-path <snapshot.h5>
- HDF5 auto bridge: --disk-hdf5 <snapshot.h5> [--disk-hdf5-out <atlas.bin>] [--disk-hdf5-r-to-rs <x>] [--disk-hdf5-kepler-gm <x>] [--disk-hdf5-theta-index <i>|--disk-hdf5-theta-average] [--disk-hdf5-density-log]
  - default atlas output is temporary and auto-cleaned; use --disk-hdf5-out to keep it
- HDF5 mapping preset: --disk-hdf5-preset {auto|pluto}
  - pluto preset defaults: r=x1v phi=x3v rho=rho vr=vx1 vphi=vx3 temp=prs (override with key args)
- HDF5 key overrides: --disk-hdf5-r-key --disk-hdf5-phi-key --disk-hdf5-rho-key --disk-hdf5-temp-key --disk-hdf5-vr-key --disk-hdf5-vphi-key
- HDF5 flow bridge: --disk-hdf5-flow (force direct flow-profile bridge; precision mode uses this path automatically)
- HDF5 sample generator: --disk-hdf5-sample [--disk-hdf5-sample-out <snapshot.h5>] [--disk-hdf5-sample-nr <n>] [--disk-hdf5-sample-nphi <n>]
- Python override: BH_PYTHON=<python> (default: auto-detect; PLUTO/HDF5 paths require h5py)
- Pipeline quality: --ssaa {1|2|4} (2=2x2, 4=4x4 supersampling)
- Swift memory: --tile-size <pixels> (optional, e.g. 512/1024)
- Pipeline mode:
  - --pipeline {cpu-mixed|gpu-only}
  - shortcut: --cpu-mixed / --gpu-only
- Collisions mode:
  - --collisions {debug|auto|linear32|none}
  - debug: keep collisions.bin (+meta), debug/inspection mode
  - auto: choose none first, switch to linear32 if memory risk is detected (default)
  - linear32: always streamed float32 intermediate chunks
  - none: no intermediate collision files (low-quality/quick mode)
  - compatibility: --temp-collisions => linear32, --keep-collisions => debug
- Compatibility aliases (deprecated):
  - mode: --mode {debug|fast}, --debug, --fast (maps to collisions mode)
  - pipeline: --match-cpu / --gpu-native / --gpu-pure / --gpu-hybrid / --compose {gpu|python}
- Default collisions mode is auto (none -> linear32 fallback on memory pressure).
- Intermediate artifacts are auto-managed by default (temporary files are created and cleaned automatically).
- Explicit output paths keep artifacts only when explicitly requested (e.g. --collisions-out, --disk-hdf5-out, --disk-hdf5-sample-out).
- Unknown options go to Swift by default.
- Use --py to forward the remaining args to Python.

Output controls:
- --output <path>: final image output path (PNG/PPM)
- --image-out <path>: alias of --output
- --collisions-out <path>: optional explicit intermediate path (advanced)
- --verify-ref <path>: reference image for post-render verification
- --verify-out <path>: optional JSON report path for verification metrics
- --verify-max-rmse <x>: optional verification fail threshold
- --verify-max-rel-l2 <x>: optional verification fail threshold
- --verify-mask-luma <0..1>: compare only pixels above reference luma threshold

Special mode:
- stage3-ab (or --stage3-ab): run stage-3 A/B automation in one shot
  - forwards remaining args to scripts/compare_stage3_ab.py
  - example: ./run_pipeline.sh stage3-ab --no-build --width 640 --height 640 --preset interstellar --metric kerr --spin 0.92 --atlas-r-warp 0.65

Example:
  ./run_pipeline.sh --width 1200 --height 1200 --preset interstellar --output blackhole_gpu.png
USAGE
}

STAGE3_AB_MODE=0
if [[ "$#" -gt 0 ]]; then
  for raw_arg in "$@"; do
    arg="$(normalize_dash "$raw_arg")"
    if [[ "$arg" == "stage3-ab" || "$arg" == "--stage3-ab" ]]; then
      STAGE3_AB_MODE=1
      break
    fi
  done
fi

if [[ "$STAGE3_AB_MODE" -eq 1 ]]; then
  COMPARE_STAGE3_SCRIPT="$ROOT_DIR/scripts/compare_stage3_ab.py"
  if [[ ! -f "$COMPARE_STAGE3_SCRIPT" ]]; then
    echo "error: stage3-ab helper script not found: $COMPARE_STAGE3_SCRIPT" >&2
    exit 2
  fi

  STAGE3_AB_ARGS=()
  for raw_arg in "$@"; do
    arg="$(normalize_dash "$raw_arg")"
    if [[ "$arg" == "stage3-ab" || "$arg" == "--stage3-ab" ]]; then
      continue
    fi
    STAGE3_AB_ARGS+=("$raw_arg")
  done

  log_section "Mode"
  log_item "stage3" "ab-report"
  log_item "script" "$COMPARE_STAGE3_SCRIPT"
  "$PYTHON_BIN" "$COMPARE_STAGE3_SCRIPT" --run-pipeline "$ROOT_DIR/Blackhole/run_pipeline.sh" "${STAGE3_AB_ARGS[@]}"
  exit $?
fi

while [[ "$#" -gt 0 ]]; do
  raw_arg="$1"
  shift
  arg="$(normalize_dash "$raw_arg")"

  case "$arg" in
    -h|--help)
      show_help
      exit 0
      ;;
    --py|--python)
      PY_MODE=1
      continue
      ;;
    --no-build)
      NO_BUILD=1
      continue
      ;;
    --collisions-out|--bin-out|--swift-output)
      need_value "$arg" "$@"
      COLLISIONS_OUT="$1"
      COLLISIONS_OUT_EXPLICIT=1
      shift
      continue
      ;;
    --image-out|--png-out|--py-output)
      need_value "$arg" "$@"
      IMAGE_OUT="$1"
      shift
      continue
      ;;
    --output)
      need_value "$arg" "$@"
      out_path="$1"
      shift
      case "$out_path" in
        *.bin)
          echo "warn: --output *.bin is deprecated. Use --collisions-out for intermediates and --output for final image." >&2
          COLLISIONS_OUT="$out_path"
          COLLISIONS_OUT_EXPLICIT=1
          ;;
        *)
          IMAGE_OUT="$out_path"
          ;;
      esac
      continue
      ;;
    --verify-ref)
      need_value "$arg" "$@"
      VERIFY_REF="$1"
      shift
      continue
      ;;
    --verify-out)
      need_value "$arg" "$@"
      VERIFY_OUT="$1"
      shift
      continue
      ;;
    --verify-max-rmse)
      need_value "$arg" "$@"
      VERIFY_MAX_RMSE="$1"
      shift
      continue
      ;;
    --verify-max-rel-l2)
      need_value "$arg" "$@"
      VERIFY_MAX_REL_L2="$1"
      shift
      continue
      ;;
    --verify-mask-luma)
      need_value "$arg" "$@"
      VERIFY_MASK_LUMA="$1"
      shift
      continue
      ;;
    --disk-hdf5)
      need_value "$arg" "$@"
      DISK_HDF5_PATH="$1"
      shift
      continue
      ;;
    --disk-repr)
      need_value "$arg" "$@"
      DISK_REPR_VALUE="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
      DISK_REPR_SET=1
      shift
      continue
      ;;
    --disk-source)
      need_value "$arg" "$@"
      DISK_SOURCE_VALUE="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
      DISK_SOURCE_SET=1
      shift
      continue
      ;;
    --disk-pluto)
      DISK_PLUTO_MODE=1
      continue
      ;;
    --disk-pluto-path)
      need_value "$arg" "$@"
      DISK_PLUTO_MODE=1
      DISK_HDF5_PATH="$1"
      shift
      continue
      ;;
    --disk-hdf5-preset)
      need_value "$arg" "$@"
      DISK_HDF5_PRESET="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
      shift
      continue
      ;;
    --disk-hdf5-r-key)
      need_value "$arg" "$@"
      DISK_HDF5_R_KEY="$1"
      shift
      continue
      ;;
    --disk-hdf5-phi-key)
      need_value "$arg" "$@"
      DISK_HDF5_PHI_KEY="$1"
      shift
      continue
      ;;
    --disk-hdf5-rho-key)
      need_value "$arg" "$@"
      DISK_HDF5_RHO_KEY="$1"
      shift
      continue
      ;;
    --disk-hdf5-temp-key)
      need_value "$arg" "$@"
      DISK_HDF5_TEMP_KEY="$1"
      shift
      continue
      ;;
    --disk-hdf5-vr-key)
      need_value "$arg" "$@"
      DISK_HDF5_VR_KEY="$1"
      shift
      continue
      ;;
    --disk-hdf5-vphi-key)
      need_value "$arg" "$@"
      DISK_HDF5_VPHI_KEY="$1"
      shift
      continue
      ;;
    --disk-hdf5-flow)
      DISK_HDF5_FLOW=1
      continue
      ;;
    --disk-hdf5-sample)
      DISK_HDF5_SAMPLE=1
      continue
      ;;
    --disk-hdf5-sample-out)
      need_value "$arg" "$@"
      DISK_HDF5_SAMPLE_OUT="$1"
      DISK_HDF5_SAMPLE_OUT_EXPLICIT=1
      shift
      continue
      ;;
    --disk-hdf5-sample-nr)
      need_value "$arg" "$@"
      DISK_HDF5_SAMPLE_NR="$1"
      shift
      continue
      ;;
    --disk-hdf5-sample-nphi)
      need_value "$arg" "$@"
      DISK_HDF5_SAMPLE_NPHI="$1"
      shift
      continue
      ;;
    --disk-hdf5-out)
      need_value "$arg" "$@"
      DISK_HDF5_OUT="$1"
      DISK_HDF5_OUT_EXPLICIT=1
      shift
      continue
      ;;
    --disk-hdf5-r-to-rs)
      need_value "$arg" "$@"
      DISK_HDF5_R_TO_RS="$1"
      shift
      continue
      ;;
    --disk-hdf5-kepler-gm)
      need_value "$arg" "$@"
      DISK_HDF5_KEPLER_GM="$1"
      shift
      continue
      ;;
    --disk-hdf5-theta-index)
      need_value "$arg" "$@"
      DISK_HDF5_THETA_INDEX="$1"
      shift
      continue
      ;;
    --disk-hdf5-theta-average)
      DISK_HDF5_THETA_AVERAGE=1
      continue
      ;;
    --disk-hdf5-density-log)
      DISK_HDF5_DENSITY_LOG=1
      continue
      ;;
    --disk-hdf5-temp-is-scale)
      DISK_HDF5_TEMP_IS_SCALE=1
      continue
      ;;
    --disk-hdf5-vr-is-ratio)
      DISK_HDF5_VR_IS_RATIO=1
      continue
      ;;
    --disk-hdf5-vphi-is-scale)
      DISK_HDF5_VPHI_IS_SCALE=1
      continue
      ;;
    --disk-hdf5-density-p-lo)
      need_value "$arg" "$@"
      DISK_HDF5_DENSITY_P_LO="$1"
      shift
      continue
      ;;
    --disk-hdf5-density-p-hi)
      need_value "$arg" "$@"
      DISK_HDF5_DENSITY_P_HI="$1"
      shift
      continue
      ;;
    --mode)
      need_value "$arg" "$@"
      MODE="$1"
      shift
      case "$MODE" in
        debug)
          COLLISIONS_MODE="debug"
          ;;
        fast)
          COLLISIONS_MODE="auto"
          ;;
        *)
          echo "error: --mode must be one of debug, fast" >&2
          exit 2
          ;;
      esac
      continue
      ;;
    --collisions)
      need_value "$arg" "$@"
      mode_value="$1"
      shift
      case "$mode_value" in
        debug)
          COLLISIONS_MODE="debug"
          MODE="debug"
          ;;
        auto)
          COLLISIONS_MODE="auto"
          MODE="fast"
          ;;
        linear32)
          COLLISIONS_MODE="linear32"
          MODE="fast"
          ;;
        none)
          COLLISIONS_MODE="none"
          MODE="fast"
          ;;
        keep)
          # Backward compatibility alias
          COLLISIONS_MODE="debug"
          MODE="debug"
          ;;
        temp)
          # Backward compatibility alias
          COLLISIONS_MODE="linear32"
          MODE="fast"
          ;;
        *)
          echo "error: --collisions must be one of debug, auto, linear32, none" >&2
          exit 2
          ;;
      esac
      continue
      ;;
    --temp-collisions)
      COLLISIONS_MODE="linear32"
      MODE="fast"
      continue
      ;;
    --keep-collisions)
      COLLISIONS_MODE="debug"
      MODE="debug"
      continue
      ;;
    --compose)
      need_value "$arg" "$@"
      LEGACY_COMPOSE_OVERRIDE="$1"
      shift
      case "$LEGACY_COMPOSE_OVERRIDE" in
        gpu|python)
          echo "warn: --compose is deprecated and will be mapped to --pipeline." >&2
          ;;
        *)
          echo "error: --compose must be one of gpu, python" >&2
          exit 2
          ;;
      esac
      continue
      ;;
    --cpu-mixed)
      PIPELINE_MODE="cpu-mixed"
      PIPELINE_ARG_PRESENT=1
      continue
      ;;
    --gpu-only)
      PIPELINE_MODE="gpu-only"
      PIPELINE_ARG_PRESENT=1
      continue
      ;;
    --pipeline)
      need_value "$arg" "$@"
      pipeline_mode="$1"
      shift
      PIPELINE_ARG_PRESENT=1
      case "$pipeline_mode" in
        cpu-mixed)
          PIPELINE_MODE="cpu-mixed"
          ;;
        gpu-only)
          PIPELINE_MODE="gpu-only"
          ;;
        *)
          echo "error: --pipeline must be one of cpu-mixed, gpu-only" >&2
          exit 2
          ;;
      esac
      continue
      ;;
    --match-cpu)
      # Kept for backward compatibility: map to cpu-mixed terminology.
      PIPELINE_MODE="cpu-mixed"
      PIPELINE_ARG_PRESENT=1
      continue
      ;;
    --gpu-native)
      # Kept for backward compatibility: map to cpu-mixed terminology.
      PIPELINE_MODE="cpu-mixed"
      PIPELINE_ARG_PRESENT=1
      continue
      ;;
    --gpu-pure)
      # Kept for backward compatibility: map to gpu-only terminology.
      PIPELINE_MODE="gpu-only"
      PIPELINE_ARG_PRESENT=1
      continue
      ;;
    --gpu-hybrid)
      # Kept for backward compatibility: map to cpu-mixed terminology.
      PIPELINE_MODE="cpu-mixed"
      PIPELINE_ARG_PRESENT=1
      continue
      ;;
    --fast)
      MODE="fast"
      COLLISIONS_MODE="auto"
      continue
      ;;
    --debug)
      MODE="debug"
      COLLISIONS_MODE="debug"
      continue
      ;;
    --ssaa)
      need_value "$arg" "$@"
      SSAA="$1"
      shift
      case "$SSAA" in
        1|2|4) ;;
        *)
          echo "error: --ssaa must be one of 1, 2, 4" >&2
          exit 2
          ;;
      esac
      continue
      ;;
    --sample)
      echo "error: --sample has been removed. Use --ssaa (1, 2, 4)." >&2
      exit 2
      ;;
    --width)
      need_value "$arg" "$@"
      WIDTH_VALUE="$1"
      WIDTH_SET=1
      shift
      continue
      ;;
    --height)
      need_value "$arg" "$@"
      HEIGHT_VALUE="$1"
      HEIGHT_SET=1
      shift
      continue
      ;;
    --tile-size)
      need_value "$arg" "$@"
      TILE_SIZE_VALUE="$1"
      TILE_SIZE_EXPLICIT=1
      shift
      continue
      ;;
  esac

  if [[ "$PY_MODE" -eq 1 ]]; then
    PY_ARGS+=("$arg")
    continue
  fi

  case "$arg" in
    --rcp)
      need_value "$arg" "$@"
      val="$1"
      shift
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
      ;;
    --metric)
      need_value "$arg" "$@"
      val="$1"
      shift
      METRIC_VALUE="$val"
      SWIFT_ARGS+=("$arg" "$val")
      ;;
    --disk-model)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_MODEL_VALUE="$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')"
      DISK_MODEL_SET=1
      SWIFT_ARGS+=("$arg" "$val")
      ;;
    --disk-physics-mode)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_PHYSICS_MODE_VALUE="$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')"
      DISK_MODE_ARG_PRESENT=1
      SWIFT_ARGS+=("$arg" "$val")
      ;;
    --disk-mode)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_PHYSICS_MODE_VALUE="$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')"
      DISK_MODE_ARG_PRESENT=1
      SWIFT_ARGS+=("$arg" "$val")
      ;;
    --disk-atlas)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_ATLAS_VALUE="$val"
      DISK_ATLAS_SET=1
      SWIFT_ARGS+=("$arg" "$val")
      ;;
    --disk-atlas-width)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_ATLAS_WIDTH_VALUE="$val"
      SWIFT_ARGS+=("$arg" "$val")
      ;;
    --disk-atlas-height)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_ATLAS_HEIGHT_VALUE="$val"
      SWIFT_ARGS+=("$arg" "$val")
      ;;
    --disk-atlas-r-min)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_ATLAS_R_MIN_VALUE="$val"
      SWIFT_ARGS+=("$arg" "$val")
      ;;
    --disk-atlas-r-max)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_ATLAS_R_MAX_VALUE="$val"
      SWIFT_ARGS+=("$arg" "$val")
      ;;
    --disk-atlas-r-warp)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_ATLAS_R_WARP_VALUE="$val"
      SWIFT_ARGS+=("$arg" "$val")
      ;;
    --disk-orbital-boost)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_ORBITAL_BOOST_SET=1
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
      ;;
    --disk-orbital-boost-inner)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_ORBITAL_BOOST_INNER_SET=1
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
      ;;
    --disk-orbital-boost-outer)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_ORBITAL_BOOST_OUTER_SET=1
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
      ;;
    --disk-radial-drift)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_RADIAL_DRIFT_SET=1
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
      ;;
    --disk-radial-drift-inner)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_RADIAL_DRIFT_INNER_SET=1
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
      ;;
    --disk-radial-drift-outer)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_RADIAL_DRIFT_OUTER_SET=1
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
      ;;
    --disk-turbulence)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_TURBULENCE_SET=1
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
      ;;
    --disk-turbulence-inner)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_TURBULENCE_INNER_SET=1
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
      ;;
    --disk-turbulence-outer)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_TURBULENCE_OUTER_SET=1
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
      ;;
    --disk-flow-step)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_FLOW_STEP_SET=1
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
      ;;
    --disk-flow-steps)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_FLOW_STEPS_SET=1
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
      ;;
    --maxSteps)
      need_value "$arg" "$@"
      val="$1"
      shift
      MAX_STEPS_VALUE="$val"
      SWIFT_ARGS+=("$arg" "$val")
      ;;
    --kerr-substeps)
      need_value "$arg" "$@"
      val="$1"
      shift
      KERR_SUBSTEPS_VALUE="$val"
      SWIFT_ARGS+=("$arg" "$val")
      ;;
    --preset)
      need_value "$arg" "$@"
      val="$1"
      shift
      PRESET_VALUE="$val"
      SWIFT_ARGS+=("$arg" "$val")
      ;;
    --kerr-legacy)
      echo "error: --kerr-legacy has been removed. Kerr now uses a single 3D Hamiltonian path." >&2
      exit 2
      ;;
    --kerr-use-u)
      echo "error: --kerr-use-u has been removed after validation tests showed no practical gain." >&2
      exit 2
      ;;
    --camX|--camY|--camZ|--fov|--roll|--diskH|--h|--spin|--kerr-tol|--kerr-escape-mult|--kerr-radial-scale|--kerr-azimuth-scale|--kerr-impact-scale|--disk-time|--disk-orbital-boost|--disk-radial-drift|--disk-turbulence|--disk-orbital-boost-inner|--disk-orbital-boost-outer|--disk-radial-drift-inner|--disk-radial-drift-outer|--disk-turbulence-inner|--disk-turbulence-outer|--disk-flow-step|--disk-flow-steps|--disk-mdot-edd|--disk-radiative-efficiency|--disk-mode|--disk-physics-mode|--disk-plunge-floor|--disk-thick-scale|--disk-color-factor|--disk-returning-rad|--disk-return-bounces|--disk-rt-steps|--disk-scattering-albedo|--disk-precision-texture|--disk-precision-clouds|--disk-cloud-coverage|--disk-cloud-optical-depth|--disk-cloud-porosity|--disk-cloud-shadow-strength|--disk-model|--disk-atlas|--disk-atlas-width|--disk-atlas-height|--disk-atlas-temp-scale|--disk-atlas-density-blend|--disk-atlas-vr-scale|--disk-atlas-vphi-scale|--disk-atlas-r-min|--disk-atlas-r-max|--disk-atlas-r-warp)
      need_value "$arg" "$@"
      val="$1"
      shift
      SWIFT_ARGS+=("$arg" "$val")
      ;;
    --spectral-step)
      need_value "$arg" "$@"
      val="$1"
      shift
      SPECTRAL_STEP_VALUE="$val"
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
      ;;
    --chunk)
      need_value "$arg" "$@"
      val="$1"
      shift
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
      ;;
    --exposure-samples)
      need_value "$arg" "$@"
      val="$1"
      shift
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
      ;;
    --exposure)
      need_value "$arg" "$@"
      val="$1"
      shift
      EXPOSURE_VALUE="$val"
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
      ;;
    --dither|--inner-edge-mult)
      need_value "$arg" "$@"
      val="$1"
      shift
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
      ;;
    --look)
      need_value "$arg" "$@"
      val="$1"
      shift
      LOOK_SET=1
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
      ;;
    *)
      SWIFT_ARGS+=("$arg")
      ;;
  esac
done

if [[ "$DISK_REPR_SET" -eq 1 ]]; then
  case "$DISK_REPR_VALUE" in
    2d|3d) ;;
    *)
      echo "error: --disk-repr must be one of 2d, 3d" >&2
      exit 2
      ;;
  esac
fi

if [[ "$DISK_SOURCE_SET" -eq 1 ]]; then
  case "$DISK_SOURCE_VALUE" in
    flow|perlin|atlas|hdf5|pluto) ;;
    *)
      echo "error: --disk-source must be one of flow, perlin, atlas, hdf5, pluto" >&2
      exit 2
      ;;
  esac
fi

if [[ "$DISK_REPR_SET" -eq 1 ]]; then
  if [[ "$DISK_REPR_VALUE" == "2d" ]]; then
    if [[ "$DISK_MODE_ARG_PRESENT" -eq 1 && ( "$DISK_PHYSICS_MODE_VALUE" == "precision" || "$DISK_PHYSICS_MODE_VALUE" == "analysis" || "$DISK_PHYSICS_MODE_VALUE" == "pt" ) ]]; then
      echo "error: --disk-repr 2d cannot be combined with precision disk mode." >&2
      echo "hint: use --disk-repr 3d or switch --disk-mode to thin/thick." >&2
      exit 2
    fi
    if [[ "$DISK_MODE_ARG_PRESENT" -eq 0 ]]; then
      DISK_PHYSICS_MODE_VALUE="thin"
      SWIFT_ARGS+=(--disk-mode thin)
    fi
  else
    if [[ "$DISK_MODE_ARG_PRESENT" -eq 1 ]]; then
      case "$DISK_PHYSICS_MODE_VALUE" in
        precision|analysis|pt) ;;
        *)
          echo "error: --disk-repr 3d requires precision disk mode." >&2
          echo "hint: use --disk-mode precision (or remove --disk-mode thin/thick)." >&2
          exit 2
          ;;
      esac
    else
      DISK_PHYSICS_MODE_VALUE="precision"
      SWIFT_ARGS+=(--disk-mode precision)
    fi

    if [[ "$PIPELINE_ARG_PRESENT" -eq 1 && "$PIPELINE_MODE" != "gpu-only" ]]; then
      echo "error: --disk-repr 3d requires --pipeline gpu-only." >&2
      echo "hint: remove --pipeline cpu-mixed (or use --gpu-only)." >&2
      exit 2
    fi
    if [[ "$PIPELINE_ARG_PRESENT" -eq 0 ]]; then
      PIPELINE_MODE="gpu-only"
    fi
  fi
fi

EFFECTIVE_DISK_REPR="2d"
if [[ "$DISK_REPR_SET" -eq 1 ]]; then
  EFFECTIVE_DISK_REPR="$DISK_REPR_VALUE"
elif [[ "$DISK_PHYSICS_MODE_VALUE" == "precision" || "$DISK_PHYSICS_MODE_VALUE" == "analysis" || "$DISK_PHYSICS_MODE_VALUE" == "pt" ]]; then
  EFFECTIVE_DISK_REPR="3d"
fi

REQUESTED_DISK_MODEL=""
if [[ "$DISK_SOURCE_SET" -eq 1 ]]; then
  case "$DISK_SOURCE_VALUE" in
    flow)
      REQUESTED_DISK_MODEL="flow"
      ;;
    perlin)
      if [[ "$EFFECTIVE_DISK_REPR" == "3d" ]]; then
        echo "error: --disk-source perlin is a 2d path and cannot be combined with 3d representation." >&2
        echo "hint: use --disk-repr 2d or switch source to flow/hdf5/pluto." >&2
        exit 2
      fi
      REQUESTED_DISK_MODEL="perlin"
      ;;
    atlas)
      if [[ "$EFFECTIVE_DISK_REPR" == "3d" ]]; then
        echo "error: --disk-source atlas is a 2d path and cannot be combined with 3d representation." >&2
        echo "hint: use --disk-repr 2d or switch source to flow/hdf5/pluto." >&2
        exit 2
      fi
      REQUESTED_DISK_MODEL="atlas"
      ;;
    hdf5)
      if [[ -z "$DISK_HDF5_PATH" && "$DISK_PLUTO_MODE" -eq 0 && "$DISK_HDF5_SAMPLE" -eq 0 ]]; then
        DISK_HDF5_SAMPLE=1
        echo "info: --disk-source hdf5 requested without input, enabling --disk-hdf5-sample." >&2
      fi
      if [[ "$EFFECTIVE_DISK_REPR" == "3d" ]]; then
        DISK_HDF5_FLOW=1
        REQUESTED_DISK_MODEL="flow"
      else
        REQUESTED_DISK_MODEL="atlas"
      fi
      ;;
    pluto)
      DISK_PLUTO_MODE=1
      if [[ "$EFFECTIVE_DISK_REPR" == "3d" ]]; then
        DISK_HDF5_FLOW=1
        REQUESTED_DISK_MODEL="flow"
      else
        REQUESTED_DISK_MODEL="atlas"
      fi
      ;;
  esac
fi

# If PLUTO/HDF5 is selected by direct flags in 3d mode, route to flow profile bridge.
if [[ "$EFFECTIVE_DISK_REPR" == "3d" && ( "$DISK_PLUTO_MODE" -eq 1 || -n "$DISK_HDF5_PATH" || "$DISK_HDF5_SAMPLE" -eq 1 ) ]]; then
  DISK_HDF5_FLOW=1
  if [[ -z "$REQUESTED_DISK_MODEL" ]]; then
    REQUESTED_DISK_MODEL="flow"
  fi
fi

if [[ -n "$REQUESTED_DISK_MODEL" ]]; then
  REQUESTED_DISK_MODEL_CANON="$(canonical_disk_model "$REQUESTED_DISK_MODEL")"
  if [[ "$DISK_MODEL_SET" -eq 1 ]]; then
    EXPLICIT_DISK_MODEL_CANON="$(canonical_disk_model "$DISK_MODEL_VALUE")"
    if [[ "$EXPLICIT_DISK_MODEL_CANON" != "$REQUESTED_DISK_MODEL_CANON" ]]; then
      echo "error: --disk-source $DISK_SOURCE_VALUE conflicts with explicit --disk-model $DISK_MODEL_VALUE." >&2
      echo "hint: remove one of them, or use --disk-source that matches the chosen model." >&2
      exit 2
    fi
  else
    DISK_MODEL_VALUE="$REQUESTED_DISK_MODEL_CANON"
    SWIFT_ARGS+=(--disk-model "$REQUESTED_DISK_MODEL_CANON")
  fi
fi

if [[ "$LOOK_SET" -eq 0 && -n "$PRESET_VALUE" && "$DISK_PHYSICS_MODE_VALUE" != "precision" && "$DISK_PHYSICS_MODE_VALUE" != "analysis" && "$DISK_PHYSICS_MODE_VALUE" != "pt" ]]; then
  SWIFT_ARGS+=(--look "$PRESET_VALUE")
  PY_ARGS+=(--look "$PRESET_VALUE")
fi

is_precision_mode=0
if [[ "$DISK_PHYSICS_MODE_VALUE" == "precision" || "$DISK_PHYSICS_MODE_VALUE" == "analysis" || "$DISK_PHYSICS_MODE_VALUE" == "pt" ]]; then
  is_precision_mode=1
fi

if [[ "$DISK_HDF5_SAMPLE" -eq 1 ]]; then
  if [[ -n "$DISK_HDF5_PATH" ]]; then
    echo "error: use either --disk-hdf5 or --disk-hdf5-sample, not both." >&2
    exit 2
  fi
  ensure_h5py_python
  HDF5_SAMPLE_SCRIPT="$ROOT_DIR/scripts/build_sample_hdf5.py"
  if [[ ! -f "$HDF5_SAMPLE_SCRIPT" ]]; then
    echo "error: HDF5 sample script not found: $HDF5_SAMPLE_SCRIPT" >&2
    exit 2
  fi
  if [[ "$DISK_HDF5_SAMPLE_OUT_EXPLICIT" -eq 1 ]]; then
    DISK_HDF5_PATH="$DISK_HDF5_SAMPLE_OUT"
  else
    TEMP_HDF5_SAMPLE="$(mktemp /tmp/blackhole_hdf5_sample.XXXXXX).h5"
    DISK_HDF5_PATH="$TEMP_HDF5_SAMPLE"
  fi

  log_section "Preprocess - HDF5 Sample"
  log_item "output" "$DISK_HDF5_PATH"
  log_item "nr,nphi" "${DISK_HDF5_SAMPLE_NR},${DISK_HDF5_SAMPLE_NPHI}"
  "$PYTHON_BIN" "$HDF5_SAMPLE_SCRIPT" \
    --output "$DISK_HDF5_PATH" \
    --nr "$DISK_HDF5_SAMPLE_NR" \
    --nphi "$DISK_HDF5_SAMPLE_NPHI"
  if [[ ! -f "$DISK_HDF5_PATH" ]]; then
    echo "error: sample HDF5 was not created: $DISK_HDF5_PATH" >&2
    exit 2
  fi
fi

if [[ "$DISK_PLUTO_MODE" -eq 1 ]]; then
  DISK_HDF5_PRESET="pluto"
  if [[ -z "$DISK_HDF5_PATH" ]]; then
    DISK_HDF5_PATH="$(resolve_pluto_hdf5 "$ROOT_DIR")"
  fi
  if [[ -z "$DISK_HDF5_PATH" || ! -f "$DISK_HDF5_PATH" ]]; then
    ensure_h5py_python
    HDF5_SAMPLE_SCRIPT="$ROOT_DIR/scripts/build_sample_hdf5.py"
    if [[ ! -f "$HDF5_SAMPLE_SCRIPT" ]]; then
      echo "error: failed to resolve PLUTO HDF5 snapshot, and sample script is missing: $HDF5_SAMPLE_SCRIPT" >&2
      echo "hint: pass --disk-pluto-path <snapshot.h5> or set BH_PLUTO_HDF5." >&2
      exit 2
    fi
    TEMP_HDF5_SAMPLE="$(mktemp /tmp/blackhole_pluto_sample.XXXXXX).h5"
    DISK_HDF5_PATH="$TEMP_HDF5_SAMPLE"
    "$PYTHON_BIN" "$HDF5_SAMPLE_SCRIPT" --output "$DISK_HDF5_PATH" --nr "$DISK_HDF5_SAMPLE_NR" --nphi "$DISK_HDF5_SAMPLE_NPHI"
    if [[ ! -f "$DISK_HDF5_PATH" ]]; then
      echo "error: failed to resolve PLUTO HDF5 snapshot and auto sample generation failed." >&2
      exit 2
    fi
    echo "warn: no PLUTO HDF5 snapshot found. using auto-generated sample: $DISK_HDF5_PATH" >&2
  fi
fi

if [[ -n "$DISK_HDF5_PATH" ]]; then
  case "$DISK_HDF5_PRESET" in
    auto|"")
      ;;
    pluto)
      [[ -z "$DISK_HDF5_R_KEY" ]] && DISK_HDF5_R_KEY="x1v"
      [[ -z "$DISK_HDF5_PHI_KEY" ]] && DISK_HDF5_PHI_KEY="x3v"
      [[ -z "$DISK_HDF5_RHO_KEY" ]] && DISK_HDF5_RHO_KEY="rho"
      [[ -z "$DISK_HDF5_TEMP_KEY" ]] && DISK_HDF5_TEMP_KEY="prs"
      [[ -z "$DISK_HDF5_VR_KEY" ]] && DISK_HDF5_VR_KEY="vx1"
      [[ -z "$DISK_HDF5_VPHI_KEY" ]] && DISK_HDF5_VPHI_KEY="vx3"
      ;;
    *)
      echo "error: --disk-hdf5-preset must be one of auto, pluto" >&2
      exit 2
      ;;
  esac
fi

USE_HDF5_FLOW_BRIDGE=0
if [[ -n "$DISK_HDF5_PATH" ]]; then
  if [[ "$DISK_HDF5_FLOW" -eq 1 || "$is_precision_mode" -eq 1 ]]; then
    USE_HDF5_FLOW_BRIDGE=1
  fi
fi

if [[ "$USE_HDF5_FLOW_BRIDGE" -eq 1 ]]; then
  if [[ "$DISK_ATLAS_SET" -eq 1 ]]; then
    echo "error: --disk-atlas cannot be combined with HDF5 flow bridge (--disk-hdf5-flow or precision+--disk-hdf5)." >&2
    exit 2
  fi
  case "$DISK_MODEL_VALUE" in
    auto|flow|procedural|legacy|noise) ;;
    *)
      echo "error: HDF5 flow bridge requires flow/auto disk model. remove --disk-model $DISK_MODEL_VALUE or use --disk-model flow." >&2
      exit 2
      ;;
  esac

  HDF5_FLOW_SCRIPT="$ROOT_DIR/scripts/build_hdf5_flow_profile.py"
  if [[ ! -f "$HDF5_FLOW_SCRIPT" ]]; then
    echo "error: HDF5 flow profile script not found: $HDF5_FLOW_SCRIPT" >&2
    exit 2
  fi
  ensure_h5py_python
  TEMP_HDF5_FLOW_PROFILE="$(mktemp /tmp/blackhole_hdf5_flow.XXXXXX).json"
  HDF5_FLOW_CMD=(
    "$PYTHON_BIN" "$HDF5_FLOW_SCRIPT"
    --input "$DISK_HDF5_PATH"
    --output "$TEMP_HDF5_FLOW_PROFILE"
  )
  if [[ -n "$DISK_HDF5_R_TO_RS" ]]; then
    HDF5_FLOW_CMD+=(--r-to-rs "$DISK_HDF5_R_TO_RS")
  fi
  if [[ -n "$DISK_HDF5_KEPLER_GM" ]]; then
    HDF5_FLOW_CMD+=(--kepler-gm "$DISK_HDF5_KEPLER_GM")
  fi
  if [[ -n "$DISK_HDF5_R_KEY" ]]; then
    HDF5_FLOW_CMD+=(--r-key "$DISK_HDF5_R_KEY")
  fi
  if [[ -n "$DISK_HDF5_PHI_KEY" ]]; then
    HDF5_FLOW_CMD+=(--phi-key "$DISK_HDF5_PHI_KEY")
  fi
  if [[ -n "$DISK_HDF5_RHO_KEY" ]]; then
    HDF5_FLOW_CMD+=(--rho-key "$DISK_HDF5_RHO_KEY")
  fi
  if [[ -n "$DISK_HDF5_VR_KEY" ]]; then
    HDF5_FLOW_CMD+=(--vr-key "$DISK_HDF5_VR_KEY")
  fi
  if [[ -n "$DISK_HDF5_VPHI_KEY" ]]; then
    HDF5_FLOW_CMD+=(--vphi-key "$DISK_HDF5_VPHI_KEY")
  fi
  if [[ -n "$DISK_HDF5_THETA_INDEX" ]]; then
    HDF5_FLOW_CMD+=(--theta-index "$DISK_HDF5_THETA_INDEX")
  fi
  if [[ "$DISK_HDF5_THETA_AVERAGE" -eq 1 ]]; then
    HDF5_FLOW_CMD+=(--theta-average)
  fi

  log_section "Preprocess - HDF5 Flow"
  log_item "input" "$DISK_HDF5_PATH"
  log_item "preset" "$DISK_HDF5_PRESET"
  log_item "profile" "$TEMP_HDF5_FLOW_PROFILE"
  if [[ -n "$DISK_HDF5_R_KEY" || -n "$DISK_HDF5_PHI_KEY" || -n "$DISK_HDF5_RHO_KEY" || -n "$DISK_HDF5_VR_KEY" || -n "$DISK_HDF5_VPHI_KEY" ]]; then
    log_item "keys" "r=${DISK_HDF5_R_KEY:-auto},phi=${DISK_HDF5_PHI_KEY:-auto},rho=${DISK_HDF5_RHO_KEY:-auto},vr=${DISK_HDF5_VR_KEY:-auto},vphi=${DISK_HDF5_VPHI_KEY:-auto}"
  fi
  "${HDF5_FLOW_CMD[@]}"
  if [[ ! -f "$TEMP_HDF5_FLOW_PROFILE" ]]; then
    echo "error: HDF5 flow bridge did not produce profile: $TEMP_HDF5_FLOW_PROFILE" >&2
    exit 2
  fi

  FLOW_RECO_LINE="$("$PYTHON_BIN" - "$TEMP_HDF5_FLOW_PROFILE" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], "r", encoding="utf-8"))
r = p.get("recommend", {})
orbital = float(r.get("disk_orbital_boost", 1.0))
radial = float(r.get("disk_radial_drift", 0.02))
turb = float(r.get("disk_turbulence", 0.30))
step = float(r.get("disk_flow_step", 0.22))
steps = int(r.get("disk_flow_steps", 8))
print(
    f"{orbital:.8f} "
    f"{radial:.8f} "
    f"{turb:.8f} "
    f"{step:.8f} "
    f"{steps} "
    f"{float(r.get('disk_orbital_boost_inner', orbital)):.8f} "
    f"{float(r.get('disk_orbital_boost_outer', orbital)):.8f} "
    f"{float(r.get('disk_radial_drift_inner', radial)):.8f} "
    f"{float(r.get('disk_radial_drift_outer', radial)):.8f} "
    f"{float(r.get('disk_turbulence_inner', turb)):.8f} "
    f"{float(r.get('disk_turbulence_outer', turb)):.8f}"
)
PY
)"
  read -r FLOW_ORBITAL FLOW_RADIAL FLOW_TURB FLOW_STEP FLOW_STEPS \
    FLOW_ORBITAL_INNER FLOW_ORBITAL_OUTER FLOW_RADIAL_INNER FLOW_RADIAL_OUTER FLOW_TURB_INNER FLOW_TURB_OUTER <<< "$FLOW_RECO_LINE"

  if [[ "$DISK_ORBITAL_BOOST_SET" -eq 0 ]]; then
    SWIFT_ARGS+=(--disk-orbital-boost "$FLOW_ORBITAL")
  fi
  if [[ "$DISK_RADIAL_DRIFT_SET" -eq 0 ]]; then
    SWIFT_ARGS+=(--disk-radial-drift "$FLOW_RADIAL")
  fi
  if [[ "$DISK_TURBULENCE_SET" -eq 0 ]]; then
    SWIFT_ARGS+=(--disk-turbulence "$FLOW_TURB")
  fi
  if [[ "$DISK_ORBITAL_BOOST_INNER_SET" -eq 0 ]]; then
    SWIFT_ARGS+=(--disk-orbital-boost-inner "$FLOW_ORBITAL_INNER")
  fi
  if [[ "$DISK_ORBITAL_BOOST_OUTER_SET" -eq 0 ]]; then
    SWIFT_ARGS+=(--disk-orbital-boost-outer "$FLOW_ORBITAL_OUTER")
  fi
  if [[ "$DISK_RADIAL_DRIFT_INNER_SET" -eq 0 ]]; then
    SWIFT_ARGS+=(--disk-radial-drift-inner "$FLOW_RADIAL_INNER")
  fi
  if [[ "$DISK_RADIAL_DRIFT_OUTER_SET" -eq 0 ]]; then
    SWIFT_ARGS+=(--disk-radial-drift-outer "$FLOW_RADIAL_OUTER")
  fi
  if [[ "$DISK_TURBULENCE_INNER_SET" -eq 0 ]]; then
    SWIFT_ARGS+=(--disk-turbulence-inner "$FLOW_TURB_INNER")
  fi
  if [[ "$DISK_TURBULENCE_OUTER_SET" -eq 0 ]]; then
    SWIFT_ARGS+=(--disk-turbulence-outer "$FLOW_TURB_OUTER")
  fi
  if [[ "$DISK_FLOW_STEP_SET" -eq 0 ]]; then
    SWIFT_ARGS+=(--disk-flow-step "$FLOW_STEP")
  fi
  if [[ "$DISK_FLOW_STEPS_SET" -eq 0 ]]; then
    SWIFT_ARGS+=(--disk-flow-steps "$FLOW_STEPS")
  fi

  log_item "flow_orbital" "$FLOW_ORBITAL"
  log_item "flow_radial" "$FLOW_RADIAL"
  log_item "flow_turb" "$FLOW_TURB"
  log_item "flow_orbital_io" "$FLOW_ORBITAL_INNER / $FLOW_ORBITAL_OUTER"
  log_item "flow_radial_io" "$FLOW_RADIAL_INNER / $FLOW_RADIAL_OUTER"
  log_item "flow_turb_io" "$FLOW_TURB_INNER / $FLOW_TURB_OUTER"
  log_item "flow_step" "$FLOW_STEP"
  log_item "flow_steps" "$FLOW_STEPS"
fi

if [[ -n "$DISK_HDF5_PATH" && "$USE_HDF5_FLOW_BRIDGE" -eq 0 ]]; then
  HDF5_BUILD_SCRIPT="$ROOT_DIR/scripts/build_grmhd_atlas.py"
  if [[ ! -f "$HDF5_BUILD_SCRIPT" ]]; then
    echo "error: HDF5 bridge script not found: $HDF5_BUILD_SCRIPT" >&2
    exit 2
  fi
  ensure_h5py_python
  if [[ ! -f "$DISK_HDF5_PATH" ]]; then
    echo "error: --disk-hdf5 input not found: $DISK_HDF5_PATH" >&2
    exit 2
  fi

  if [[ "$DISK_HDF5_OUT_EXPLICIT" -eq 0 ]]; then
    TEMP_HDF5_ATLAS="$(mktemp /tmp/blackhole_hdf5_atlas.XXXXXX).bin"
    DISK_HDF5_OUT="$TEMP_HDF5_ATLAS"
  fi

  HDF5_ATLAS_W="${DISK_ATLAS_WIDTH_VALUE:-1024}"
  HDF5_ATLAS_H="${DISK_ATLAS_HEIGHT_VALUE:-512}"
  HDF5_R_MIN="${DISK_ATLAS_R_MIN_VALUE:-1.0}"
  HDF5_R_MAX="${DISK_ATLAS_R_MAX_VALUE:-9.0}"
  HDF5_R_WARP="${DISK_ATLAS_R_WARP_VALUE:-0.65}"

  HDF5_CMD=(
    "$PYTHON_BIN" "$HDF5_BUILD_SCRIPT"
    --input "$DISK_HDF5_PATH"
    --output "$DISK_HDF5_OUT"
    --width "$HDF5_ATLAS_W"
    --height "$HDF5_ATLAS_H"
    --r-min "$HDF5_R_MIN"
    --r-max "$HDF5_R_MAX"
    --r-warp "$HDF5_R_WARP"
  )
  if [[ -n "$DISK_HDF5_R_TO_RS" ]]; then
    HDF5_CMD+=(--r-to-rs "$DISK_HDF5_R_TO_RS")
  fi
  if [[ -n "$DISK_HDF5_KEPLER_GM" ]]; then
    HDF5_CMD+=(--kepler-gm "$DISK_HDF5_KEPLER_GM")
  fi
  if [[ -n "$DISK_HDF5_R_KEY" ]]; then
    HDF5_CMD+=(--r-key "$DISK_HDF5_R_KEY")
  fi
  if [[ -n "$DISK_HDF5_PHI_KEY" ]]; then
    HDF5_CMD+=(--phi-key "$DISK_HDF5_PHI_KEY")
  fi
  if [[ -n "$DISK_HDF5_RHO_KEY" ]]; then
    HDF5_CMD+=(--rho-key "$DISK_HDF5_RHO_KEY")
  fi
  if [[ -n "$DISK_HDF5_TEMP_KEY" ]]; then
    HDF5_CMD+=(--temp-key "$DISK_HDF5_TEMP_KEY")
  fi
  if [[ -n "$DISK_HDF5_VR_KEY" ]]; then
    HDF5_CMD+=(--vr-key "$DISK_HDF5_VR_KEY")
  fi
  if [[ -n "$DISK_HDF5_VPHI_KEY" ]]; then
    HDF5_CMD+=(--vphi-key "$DISK_HDF5_VPHI_KEY")
  fi
  if [[ -n "$DISK_HDF5_THETA_INDEX" ]]; then
    HDF5_CMD+=(--theta-index "$DISK_HDF5_THETA_INDEX")
  fi
  if [[ "$DISK_HDF5_THETA_AVERAGE" -eq 1 ]]; then
    HDF5_CMD+=(--theta-average)
  fi
  if [[ "$DISK_HDF5_DENSITY_LOG" -eq 1 ]]; then
    HDF5_CMD+=(--density-log)
  fi
  if [[ "$DISK_HDF5_TEMP_IS_SCALE" -eq 1 ]]; then
    HDF5_CMD+=(--temp-is-scale)
  fi
  if [[ "$DISK_HDF5_VR_IS_RATIO" -eq 1 ]]; then
    HDF5_CMD+=(--vr-is-ratio)
  fi
  if [[ "$DISK_HDF5_VPHI_IS_SCALE" -eq 1 ]]; then
    HDF5_CMD+=(--vphi-is-scale)
  fi
  if [[ -n "$DISK_HDF5_DENSITY_P_LO" ]]; then
    HDF5_CMD+=(--density-p-lo "$DISK_HDF5_DENSITY_P_LO")
  fi
  if [[ -n "$DISK_HDF5_DENSITY_P_HI" ]]; then
    HDF5_CMD+=(--density-p-hi "$DISK_HDF5_DENSITY_P_HI")
  fi

  log_section "Preprocess - HDF5"
  log_item "input" "$DISK_HDF5_PATH"
  log_item "preset" "$DISK_HDF5_PRESET"
  log_item "atlas_out" "$DISK_HDF5_OUT"
  if [[ -n "$DISK_HDF5_R_KEY" || -n "$DISK_HDF5_PHI_KEY" || -n "$DISK_HDF5_RHO_KEY" || -n "$DISK_HDF5_TEMP_KEY" || -n "$DISK_HDF5_VR_KEY" || -n "$DISK_HDF5_VPHI_KEY" ]]; then
    log_item "keys" "r=${DISK_HDF5_R_KEY:-auto},phi=${DISK_HDF5_PHI_KEY:-auto},rho=${DISK_HDF5_RHO_KEY:-auto},temp=${DISK_HDF5_TEMP_KEY:-auto},vr=${DISK_HDF5_VR_KEY:-auto},vphi=${DISK_HDF5_VPHI_KEY:-auto}"
  fi
  "${HDF5_CMD[@]}"
  if [[ ! -f "$DISK_HDF5_OUT" ]]; then
    echo "error: HDF5 bridge did not produce atlas: $DISK_HDF5_OUT" >&2
    exit 2
  fi
  if [[ "$DISK_ATLAS_SET" -eq 1 && "$DISK_ATLAS_VALUE" != "$DISK_HDF5_OUT" ]]; then
    echo "warn: --disk-hdf5 overrides existing --disk-atlas ($DISK_ATLAS_VALUE -> $DISK_HDF5_OUT)" >&2
  fi
  SWIFT_ARGS+=(--disk-atlas "$DISK_HDF5_OUT")
  DISK_ATLAS_SET=1
  DISK_ATLAS_VALUE="$DISK_HDF5_OUT"
fi

# Atlas auto-discovery: when atlas is requested but path is omitted.
if [[ "$is_precision_mode" -eq 1 ]]; then
  if [[ "$DISK_MODEL_VALUE" == "atlas" || "$DISK_ATLAS_SET" -eq 1 ]]; then
    echo "warn: precision mode renders with flow disk model; atlas inputs are ignored at render stage." >&2
  fi
elif [[ "$DISK_ATLAS_SET" -eq 0 ]]; then
  case "$DISK_MODEL_VALUE" in
    atlas)
      AUTO_ATLAS_CANDIDATES=()
      if [[ -n "${BH_DISK_ATLAS:-}" ]]; then
        AUTO_ATLAS_CANDIDATES+=("$BH_DISK_ATLAS")
      fi
      AUTO_ATLAS_CANDIDATES+=(
        "$ROOT_DIR/disk_atlas.bin"
        "/tmp/stage3_ab/disk_atlas.bin"
      )
      AUTO_ATLAS_FOUND=""
      for p in "${AUTO_ATLAS_CANDIDATES[@]}"; do
        if [[ -n "$p" && -f "$p" ]]; then
          AUTO_ATLAS_FOUND="$p"
          break
        fi
      done
      if [[ -n "$AUTO_ATLAS_FOUND" ]]; then
        SWIFT_ARGS+=(--disk-atlas "$AUTO_ATLAS_FOUND")
        DISK_ATLAS_SET=1
        DISK_ATLAS_VALUE="$AUTO_ATLAS_FOUND"
        echo "info: auto-selected atlas: $AUTO_ATLAS_FOUND" >&2
      elif [[ "$DISK_MODEL_VALUE" == "atlas" ]]; then
        echo "error: --disk-model atlas requested but no --disk-atlas provided and no auto atlas found." >&2
        echo "hint: set BH_DISK_ATLAS or place atlas at $ROOT_DIR/disk_atlas.bin" >&2
        exit 2
      fi
      ;;
  esac
fi

# Canonical routing: compose backend is implied by pipeline mode.
if [[ -n "$LEGACY_COMPOSE_OVERRIDE" ]]; then
  if [[ "$LEGACY_COMPOSE_OVERRIDE" == "python" ]]; then
    PIPELINE_MODE="cpu-mixed"
  elif [[ "$LEGACY_COMPOSE_OVERRIDE" == "gpu" && "$PIPELINE_MODE" == "cpu-mixed" ]]; then
    echo "warn: --compose gpu is ignored in cpu-mixed mode (cpu-mixed now composes via python)." >&2
  fi
fi

# Collisions mode may constrain pipeline route.
if [[ "$PIPELINE_MODE" == "cpu-mixed" && ( "$COLLISIONS_MODE" == "auto" || "$COLLISIONS_MODE" == "linear32" || "$COLLISIONS_MODE" == "none" ) ]]; then
  echo "warn: --collisions $COLLISIONS_MODE requires gpu-only. switching pipeline to gpu-only." >&2
  PIPELINE_MODE="gpu-only"
fi

case "$PIPELINE_MODE" in
  cpu-mixed)
    COMPOSE_BACKEND="python"
    MATCH_CPU=1
    GPU_FULL_COMPOSE=0
    GPU_STREAM_LINEAR32=0
    ;;
  gpu-only)
    COMPOSE_BACKEND="gpu"
    MATCH_CPU=0
    GPU_FULL_COMPOSE=1
    GPU_STREAM_LINEAR32=0
    ;;
  *)
    echo "error: internal invalid pipeline mode: $PIPELINE_MODE" >&2
    exit 2
    ;;
esac

if [[ "$COMPOSE_BACKEND" == "python" && ( "$DISK_PHYSICS_MODE_VALUE" == "precision" || "$DISK_PHYSICS_MODE_VALUE" == "analysis" || "$DISK_PHYSICS_MODE_VALUE" == "pt" ) ]]; then
  echo "error: precision disk physics requires gpu-only compose path." >&2
  echo "hint: rerun with --pipeline gpu-only (or --gpu-only)." >&2
  exit 2
fi

case "$COLLISIONS_MODE" in
  debug)
    COLLISIONS_POLICY="keep"
    GPU_FULL_COMPOSE=1
    GPU_STREAM_LINEAR32=0
    ;;
  auto)
    COLLISIONS_POLICY="temp"
    GPU_FULL_COMPOSE=1
    GPU_STREAM_LINEAR32=0
    ;;
  linear32)
    COLLISIONS_POLICY="keep"
    GPU_FULL_COMPOSE=0
    GPU_STREAM_LINEAR32=1
    ;;
  none)
    COLLISIONS_POLICY="temp"
    GPU_FULL_COMPOSE=1
    GPU_STREAM_LINEAR32=0
    ;;
  *)
    echo "error: internal invalid collisions mode: $COLLISIONS_MODE" >&2
    exit 2
    ;;
esac

if [[ "$WIDTH_SET" -eq 1 ]]; then
  if ! [[ "$WIDTH_VALUE" =~ ^[0-9]+$ ]] || [[ "$WIDTH_VALUE" -le 0 ]]; then
    echo "error: --width must be a positive integer" >&2
    exit 2
  fi
  TARGET_WIDTH="$WIDTH_VALUE"
else
  TARGET_WIDTH=1200
fi

if [[ "$HEIGHT_SET" -eq 1 ]]; then
  if ! [[ "$HEIGHT_VALUE" =~ ^[0-9]+$ ]] || [[ "$HEIGHT_VALUE" -le 0 ]]; then
    echo "error: --height must be a positive integer" >&2
    exit 2
  fi
  TARGET_HEIGHT="$HEIGHT_VALUE"
else
  TARGET_HEIGHT=1200
fi

RENDER_WIDTH=$((TARGET_WIDTH * SSAA))
RENDER_HEIGHT=$((TARGET_HEIGHT * SSAA))
SWIFT_ARGS+=(--width "$RENDER_WIDTH" --height "$RENDER_HEIGHT")
PY_ARGS+=(--width "$RENDER_WIDTH" --height "$RENDER_HEIGHT")
if [[ "$SSAA" -gt 1 ]]; then
  PY_ARGS+=(--downsample "$SSAA")
fi
if [[ "$COMPOSE_BACKEND" == "gpu" && "$SSAA" -gt 1 ]]; then
  SWIFT_ARGS+=(--downsample "$SSAA")
fi
if [[ -z "$TILE_SIZE_VALUE" ]]; then
  if (( RENDER_WIDTH * RENDER_HEIGHT > 8000000 )); then
    TILE_SIZE_VALUE=1024
    TILE_SIZE_EXPLICIT=1
  fi
fi
if [[ "$TILE_SIZE_EXPLICIT" -eq 1 && -n "$TILE_SIZE_VALUE" ]]; then
  SWIFT_ARGS+=(--tile-size "$TILE_SIZE_VALUE")
fi
if [[ -n "$TILE_SIZE_VALUE" ]]; then
  TILE_INFO="$TILE_SIZE_VALUE"
else
  TILE_INFO="full-frame"
fi

if [[ "$COMPOSE_BACKEND" == "gpu" && "$MATCH_CPU" -eq 0 && "$GPU_FULL_COMPOSE" -eq 1 && "$COLLISIONS_MODE" == "auto" ]]; then
  PIXELS=$((RENDER_WIDTH * RENDER_HEIGHT))
  COLLISION_BYTES=$((PIXELS * 64))
  NEED_LINEAR=1
  if [[ -n "$EXPOSURE_VALUE" ]]; then
    if awk -v x="$EXPOSURE_VALUE" 'BEGIN { exit !(x > 0) }'; then
      NEED_LINEAR=0
    fi
  fi
  LINEAR_BYTES=$((NEED_LINEAR * PIXELS * 16))
  EST_TOTAL_BYTES=$((COLLISION_BYTES + LINEAR_BYTES))

  PHYS_MEM_BYTES="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
  if [[ "$PHYS_MEM_BYTES" =~ ^[0-9]+$ ]] && (( PHYS_MEM_BYTES > 0 )); then
    SAFE_BUDGET_BYTES=$((PHYS_MEM_BYTES * 80 / 100))
    if (( EST_TOTAL_BYTES > SAFE_BUDGET_BYTES )); then
      EST_GIB="$(to_gib "$EST_TOTAL_BYTES")"
      MEM_GIB="$(to_gib "$PHYS_MEM_BYTES")"
      echo "warn: gpu-only estimated memory ${EST_GIB} GiB exceeds safe budget on this machine (${MEM_GIB} GiB physical)." >&2
      echo "warn: auto mode switched to streamed linear32 due to memory budget." >&2
      MATCH_CPU=0
      GPU_FULL_COMPOSE=0
      GPU_STREAM_LINEAR32=1
    fi
  fi
fi

IMAGE_BASE="$IMAGE_OUT"
if [[ "$IMAGE_BASE" == *.* ]]; then
  IMAGE_BASE="${IMAGE_BASE%.*}"
fi
if [[ "$COLLISIONS_OUT_EXPLICIT" -eq 0 && "$COLLISIONS_POLICY" == "keep" ]]; then
  COLLISIONS_OUT="${IMAGE_BASE}.collisions.bin"
fi

TEMP_COLLISIONS=""
if [[ "$COLLISIONS_POLICY" == "temp" && "$COLLISIONS_OUT_EXPLICIT" -eq 0 ]]; then
  if [[ ( "$COLLISIONS_MODE" == "none" || "$COLLISIONS_MODE" == "auto" ) && "$COMPOSE_BACKEND" == "gpu" && "$GPU_FULL_COMPOSE" -eq 1 ]]; then
    # Even discard-mode uses a unique temporary path so no stale fixed /tmp file remains.
    TEMP_COLLISIONS="$(mktemp /tmp/blackhole_discard.XXXXXX)"
    COLLISIONS_OUT="$TEMP_COLLISIONS"
  else
    TEMP_COLLISIONS="$(mktemp /tmp/blackhole_collisions.XXXXXX)"
    COLLISIONS_OUT="$TEMP_COLLISIONS"
  fi
fi
if [[ "$GPU_STREAM_LINEAR32" -eq 1 ]]; then
  if [[ "$COLLISIONS_POLICY" == "keep" && "$COLLISIONS_OUT_EXPLICIT" -eq 0 ]]; then
    LINEAR32_OUT="${IMAGE_BASE}.linear32f32"
  else
    LINEAR32_OUT="${COLLISIONS_OUT}.linear32f32"
  fi
fi

log_section "Pipeline"
log_item "metric" "$METRIC_VALUE"
if [[ "$MATCH_CPU" -eq 0 ]]; then
  PIPELINE_MODE_LABEL="gpu-only"
else
  PIPELINE_MODE_LABEL="cpu-mixed"
fi
log_item "pipeline_mode" "$PIPELINE_MODE_LABEL"
if [[ "$MATCH_CPU" -eq 0 ]]; then
  if [[ "$GPU_FULL_COMPOSE" -eq 1 ]]; then
    log_item "gpu_strategy" "in-memory"
  elif [[ "$GPU_STREAM_LINEAR32" -eq 1 ]]; then
    log_item "gpu_strategy" "streamed-linear32"
  else
    log_item "gpu_strategy" "disk-collision"
  fi
fi
log_item "collisions_mode" "$COLLISIONS_MODE"
log_item "collisions_policy" "$COLLISIONS_POLICY"
log_item "compose" "$COMPOSE_BACKEND"
log_item "ssaa" "$SSAA"
log_item "output_size" "${TARGET_WIDTH}x${TARGET_HEIGHT}"
log_item "render_size" "${RENDER_WIDTH}x${RENDER_HEIGHT}"
log_item "tile_size" "$TILE_INFO"
log_item "eta_output" "$ETA_RELAY"
log_item "eta_history" "$ETA_HISTORY"
if [[ -n "$DISK_HDF5_PATH" && "$USE_HDF5_FLOW_BRIDGE" -eq 0 ]]; then
  if [[ "$DISK_HDF5_OUT_EXPLICIT" -eq 1 ]]; then
    log_item "hdf5_atlas" "$DISK_HDF5_OUT"
  else
    log_item "hdf5_atlas" "$DISK_HDF5_OUT (temporary)"
  fi
fi
if [[ "$USE_HDF5_FLOW_BRIDGE" -eq 1 ]]; then
  log_item "hdf5_flow" "$TEMP_HDF5_FLOW_PROFILE (temporary)"
fi
if [[ "$DISK_HDF5_SAMPLE" -eq 1 ]]; then
  if [[ "$DISK_HDF5_SAMPLE_OUT_EXPLICIT" -eq 1 ]]; then
    log_item "hdf5_sample" "$DISK_HDF5_PATH"
  else
    log_item "hdf5_sample" "$DISK_HDF5_PATH (temporary)"
  fi
fi
if [[ "$DISK_PLUTO_MODE" -eq 1 ]]; then
  log_item "pluto_hdf5" "$DISK_HDF5_PATH"
fi
if [[ "$GPU_STREAM_LINEAR32" -eq 1 ]]; then
  if [[ -n "$TEMP_COLLISIONS" ]]; then
    log_item "collisions_out" "$COLLISIONS_OUT (temporary, unused)"
    log_item "linear32_out" "$LINEAR32_OUT (temporary)"
  else
    log_item "collisions_out" "$COLLISIONS_OUT (unused)"
    log_item "linear32_out" "$LINEAR32_OUT"
  fi
else
  if [[ -n "$TEMP_COLLISIONS" ]]; then
    log_item "collisions_out" "$COLLISIONS_OUT (temporary)"
  else
    log_item "collisions_out" "$COLLISIONS_OUT"
  fi
fi
log_item "image_out" "$IMAGE_OUT"
if [[ -n "$VERIFY_REF" ]]; then
  log_item "verify_ref" "$VERIFY_REF"
  if [[ -n "$VERIFY_OUT" ]]; then
    log_item "verify_out" "$VERIFY_OUT"
  fi
fi

if [[ -n "$MAX_STEPS_VALUE" ]]; then
  ETA_MAX_STEPS="$MAX_STEPS_VALUE"
else
  case "${PRESET_VALUE:-balanced}" in
    eht) ETA_MAX_STEPS=2000 ;;
    *) ETA_MAX_STEPS=1600 ;;
  esac
fi

if [[ -n "$KERR_SUBSTEPS_VALUE" ]]; then
  ETA_KERR_SUBSTEPS="$KERR_SUBSTEPS_VALUE"
else
  ETA_KERR_SUBSTEPS=4
fi

if [[ "$NO_BUILD" -eq 0 ]]; then
  log_section "Build"
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build >/dev/null
  log_item "status" "completed"
else
  log_section "Build"
  log_item "status" "skipped (--no-build)"
fi

if [[ ! -x "$BIN_PATH" ]]; then
  echo "binary not found: $BIN_PATH" >&2
  exit 1
fi

RUNNER=("$BIN_PATH")
if [[ -n "${BH_FORCE_ARCH:-}" ]]; then
  RUNNER=(/usr/bin/arch "-$BH_FORCE_ARCH" "$BIN_PATH")
  echo "binary runner arch: $BH_FORCE_ARCH"
fi

if [[ "$COMPOSE_BACKEND" == "gpu" && "$MATCH_CPU" -eq 0 ]]; then
  GPU_COMPOSE_ARGS=(--compose-gpu --image-out "$IMAGE_OUT")
  if [[ "$GPU_FULL_COMPOSE" -eq 1 ]]; then
    GPU_COMPOSE_ARGS+=(--gpu-full-compose)
    if [[ "$COLLISIONS_MODE" == "none" || "$COLLISIONS_MODE" == "auto" || -n "$TEMP_COLLISIONS" ]]; then
      GPU_COMPOSE_ARGS+=(--discard-collisions)
    fi
  elif [[ "$GPU_STREAM_LINEAR32" -eq 1 ]]; then
    GPU_COMPOSE_ARGS+=(--linear32-intermediate --linear32-out "$LINEAR32_OUT" --discard-collisions)
  fi
  if ((${#SWIFT_ARGS[@]})); then
    SWIFT_CMD=("${RUNNER[@]}" --output "$COLLISIONS_OUT" "${GPU_COMPOSE_ARGS[@]}" "${SWIFT_ARGS[@]}")
  else
    SWIFT_CMD=("${RUNNER[@]}" --output "$COLLISIONS_OUT" "${GPU_COMPOSE_ARGS[@]}")
  fi
else
  if ((${#SWIFT_ARGS[@]})); then
    SWIFT_CMD=("${RUNNER[@]}" --output "$COLLISIONS_OUT" "${SWIFT_ARGS[@]}")
  else
    SWIFT_CMD=("${RUNNER[@]}" --output "$COLLISIONS_OUT")
  fi
fi

ETA_VARIANT_SWIFT="swift-trace"
if [[ "$COMPOSE_BACKEND" == "gpu" && "$MATCH_CPU" -eq 0 ]]; then
  if [[ "$GPU_STREAM_LINEAR32" -eq 1 ]]; then
    ETA_VARIANT_SWIFT="swift-gpu-linear32"
  elif [[ "$GPU_FULL_COMPOSE" -eq 1 ]]; then
    ETA_VARIANT_SWIFT="swift-gpu-inmem"
  else
    ETA_VARIANT_SWIFT="swift-gpu"
  fi
fi
ETA_VARIANT_PY="python-compose"

if [[ "$COMPOSE_BACKEND" == "gpu" && "$MATCH_CPU" -eq 0 ]]; then
  log_section "Stage 1/1 - Swift"
elif [[ "$COMPOSE_BACKEND" == "gpu" && "$MATCH_CPU" -eq 1 ]]; then
  log_section "Stage 1/2 - Swift"
else
  log_section "Stage 1/2 - Swift"
fi
if [[ -f "$ETA_SCRIPT" ]]; then
  "$PYTHON_BIN" "$ETA_SCRIPT" \
    --history "$ETA_HISTORY" \
    --stage swift \
    --variant "$ETA_VARIANT_SWIFT" \
    --metric "$METRIC_VALUE" \
    --width "$RENDER_WIDTH" \
    --height "$RENDER_HEIGHT" \
    --max-steps "$ETA_MAX_STEPS" \
    --kerr-substeps "$ETA_KERR_SUBSTEPS" \
    --ssaa "$SSAA" \
    --relay-output "$ETA_RELAY" \
    --cmd "${SWIFT_CMD[@]}"
else
  "${SWIFT_CMD[@]}"
fi

if [[ "$COMPOSE_BACKEND" == "python" || ( "$COMPOSE_BACKEND" == "gpu" && "$MATCH_CPU" -eq 1 ) ]]; then
  if ((${#PY_ARGS[@]})); then
    PY_CMD=("$PYTHON_BIN" "$ROOT_DIR/Blackhole/render_collisions.py" \
      --input "$COLLISIONS_OUT" \
      --meta "$COLLISIONS_OUT.json" \
      --output "$IMAGE_OUT" \
      "${PY_ARGS[@]}")
  else
    PY_CMD=("$PYTHON_BIN" "$ROOT_DIR/Blackhole/render_collisions.py" \
      --input "$COLLISIONS_OUT" \
      --meta "$COLLISIONS_OUT.json" \
      --output "$IMAGE_OUT")
  fi

  if [[ "$COMPOSE_BACKEND" == "gpu" && "$MATCH_CPU" -eq 1 ]]; then
    log_section "Stage 2/2 - Python"
  else
    log_section "Stage 2/2 - Python"
  fi
  if [[ -f "$ETA_SCRIPT" ]]; then
    "$PYTHON_BIN" "$ETA_SCRIPT" \
      --history "$ETA_HISTORY" \
      --stage python \
      --variant "$ETA_VARIANT_PY" \
      --metric "$METRIC_VALUE" \
      --width "$RENDER_WIDTH" \
      --height "$RENDER_HEIGHT" \
      --spectral-step "$SPECTRAL_STEP_VALUE" \
      --ssaa "$SSAA" \
      --relay-output "$ETA_RELAY" \
      --cmd "${PY_CMD[@]}"
  else
    "${PY_CMD[@]}"
  fi
fi

if [[ "$COMPOSE_BACKEND" == "gpu" && ! -f "$IMAGE_OUT" ]]; then
  echo "error: GPU compose did not produce image: $IMAGE_OUT" >&2
  echo "hint: rebuild the Swift binary with the latest source, or use --compose python" >&2
  exit 1
fi

if [[ -n "$VERIFY_REF" ]]; then
  VERIFY_SCRIPT="$ROOT_DIR/scripts/compare_images.py"
  if [[ ! -f "$VERIFY_SCRIPT" ]]; then
    echo "error: verify script not found: $VERIFY_SCRIPT" >&2
    exit 2
  fi
  if [[ ! -f "$VERIFY_REF" ]]; then
    echo "error: --verify-ref not found: $VERIFY_REF" >&2
    exit 2
  fi

  VERIFY_CMD=(
    "$PYTHON_BIN" "$VERIFY_SCRIPT"
    --candidate "$IMAGE_OUT"
    --reference "$VERIFY_REF"
  )
  if [[ -n "$VERIFY_OUT" ]]; then
    VERIFY_CMD+=(--output-json "$VERIFY_OUT")
  fi
  if [[ -n "$VERIFY_MAX_RMSE" ]]; then
    VERIFY_CMD+=(--max-rmse "$VERIFY_MAX_RMSE")
  fi
  if [[ -n "$VERIFY_MAX_REL_L2" ]]; then
    VERIFY_CMD+=(--max-rel-l2 "$VERIFY_MAX_REL_L2")
  fi
  if [[ -n "$VERIFY_MASK_LUMA" ]]; then
    VERIFY_CMD+=(--mask-luma-threshold "$VERIFY_MASK_LUMA")
  fi

  log_section "Stage - Verify"
  "${VERIFY_CMD[@]}"
fi

log_section "Outputs"
log_item "image" "$IMAGE_OUT"
if [[ "$COLLISIONS_MODE" == "none" ]]; then
  :
elif [[ "$GPU_STREAM_LINEAR32" -eq 1 ]]; then
  if [[ "$COLLISIONS_POLICY" == "keep" || "$COLLISIONS_OUT_EXPLICIT" -eq 1 ]]; then
    log_item "linear32" "$LINEAR32_OUT"
    log_item "meta" "$LINEAR32_OUT.json"
  fi
elif [[ "$COLLISIONS_POLICY" == "keep" || "$COLLISIONS_OUT_EXPLICIT" -eq 1 ]]; then
  log_item "collisions" "$COLLISIONS_OUT"
  log_item "meta" "$COLLISIONS_OUT.json"
fi

if [[ -n "$TEMP_COLLISIONS" ]]; then
  rm -f "$TEMP_COLLISIONS" "$TEMP_COLLISIONS.json"
  if [[ "$GPU_STREAM_LINEAR32" -eq 1 ]]; then
    rm -f "$LINEAR32_OUT" "$LINEAR32_OUT.json"
    log_item "cleanup" "temporary linear32/collision artifacts removed"
  else
    log_item "cleanup" "temporary collisions removed"
  fi
fi

if [[ -n "$TEMP_HDF5_ATLAS" ]]; then
  rm -f "$TEMP_HDF5_ATLAS" "${TEMP_HDF5_ATLAS}.json"
  log_item "cleanup" "temporary HDF5 atlas removed"
fi

if [[ -n "$TEMP_HDF5_SAMPLE" ]]; then
  rm -f "$TEMP_HDF5_SAMPLE"
  log_item "cleanup" "temporary HDF5 sample removed"
fi

if [[ -n "$TEMP_HDF5_FLOW_PROFILE" ]]; then
  rm -f "$TEMP_HDF5_FLOW_PROFILE"
  log_item "cleanup" "temporary HDF5 flow profile removed"
fi
