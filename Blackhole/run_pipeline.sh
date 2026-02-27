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
MODE="debug"
SSAA=1
WIDTH_SET=0
HEIGHT_SET=0
WIDTH_VALUE=""
HEIGHT_VALUE=""
TILE_SIZE_VALUE=""
COLLISIONS_OUT_EXPLICIT=0
METRIC_VALUE="schwarzschild"
MAX_STEPS_VALUE=""
KERR_SUBSTEPS_VALUE=""
SPECTRAL_STEP_VALUE="5.0"

SWIFT_ARGS=()
PY_ARGS=()
PY_MODE=0
LOOK_SET=0
PRESET_VALUE=""
ETA_SCRIPT="$ROOT_DIR/scripts/pipeline_eta.py"
ETA_HISTORY="$ROOT_DIR/.pipeline_eta_history.json"
ETA_RELAY="${BH_ETA_RELAY:-errors}"
COMPOSE_BACKEND="${BH_COMPOSE_BACKEND:-gpu}"
MATCH_CPU=1
GPU_FULL_COMPOSE=0

case "$ETA_RELAY" in
  always|errors|none) ;;
  *)
    echo "error: BH_ETA_RELAY must be one of always, errors, none" >&2
    exit 2
    ;;
esac

case "$COMPOSE_BACKEND" in
  gpu|python) ;;
  *)
    echo "error: BH_COMPOSE_BACKEND must be one of gpu, python" >&2
    exit 2
    ;;
esac

log_section() {
  printf "\n== %s ==\n" "$1"
}

log_item() {
  printf "  %-16s %s\n" "$1" "$2"
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

show_help() {
  cat <<'USAGE'
Usage: ./run_pipeline.sh [options]

One-command pipeline:
1) Build and run Swift/Metal renderer
2) Compose final image (GPU Metal or Python)
3) Save final image (PNG default)

Routing rules:
- Shared: --width --height --rcp
- Swift-only: --preset --camX --camY --camZ --fov --roll --diskH --maxSteps --h --metric --spin --kerr-substeps --kerr-tol --kerr-escape-mult --kerr-radial-scale --kerr-azimuth-scale --kerr-impact-scale
- Compose controls: --chunk --spectral-step --exposure --exposure-samples --dither --inner-edge-mult --look
- Pipeline quality: --ssaa {1|2|4} (2=2x2, 4=4x4 supersampling)
- Swift memory: --tile-size <pixels> (optional, e.g. 512/1024)
- Mode: --mode {debug|fast} (debug=keep collisions, fast=temporary collisions)
- Compose backend: --compose {gpu|python}
  - gpu: GPU trace + Python compose (quality-match path)
  - python: Python-only compose path
- GPU precise-match path: --gpu-native (CPU-equivalent stats + precise GPU compose)
- Pure GPU stats path: --gpu-pure (native full GPU prepass + GPU compose)
- Legacy hybrid alias: --gpu-hybrid (same as --gpu-native)
- Unknown options go to Swift by default.
- Use --py to forward the remaining args to Python.

Output controls:
- --output <path>: *.png/*.ppm => image output, *.bin => collisions output
- --collisions-out <path>
- --image-out <path>

Example:
  ./run_pipeline.sh --width 1200 --height 1200 --preset interstellar --output blackhole_gpu.png
USAGE
}

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
        *.png|*.ppm) IMAGE_OUT="$out_path" ;;
        *.bin) COLLISIONS_OUT="$out_path"; COLLISIONS_OUT_EXPLICIT=1 ;;
        *) COLLISIONS_OUT="$out_path"; COLLISIONS_OUT_EXPLICIT=1 ;;
      esac
      continue
      ;;
    --mode)
      need_value "$arg" "$@"
      MODE="$1"
      shift
      case "$MODE" in
        debug|fast) ;;
        *)
          echo "error: --mode must be one of debug, fast" >&2
          exit 2
          ;;
      esac
      continue
      ;;
    --compose)
      need_value "$arg" "$@"
      COMPOSE_BACKEND="$1"
      shift
      case "$COMPOSE_BACKEND" in
        gpu|python) ;;
        *)
          echo "error: --compose must be one of gpu, python" >&2
          exit 2
          ;;
      esac
      continue
      ;;
    --match-cpu)
      # Kept for backward compatibility. GPU backend already runs in match mode.
      COMPOSE_BACKEND="gpu"
      MATCH_CPU=1
      GPU_FULL_COMPOSE=0
      continue
      ;;
    --gpu-native)
      COMPOSE_BACKEND="gpu"
      MATCH_CPU=0
      GPU_FULL_COMPOSE=0
      continue
      ;;
    --gpu-pure)
      COMPOSE_BACKEND="gpu"
      MATCH_CPU=0
      GPU_FULL_COMPOSE=1
      continue
      ;;
    --gpu-hybrid)
      COMPOSE_BACKEND="gpu"
      MATCH_CPU=0
      GPU_FULL_COMPOSE=0
      continue
      ;;
    --fast)
      MODE="fast"
      continue
      ;;
    --debug)
      MODE="debug"
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
    --tile-size)
      need_value "$arg" "$@"
      val="$1"
      shift
      TILE_SIZE_VALUE="$val"
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
    --camX|--camY|--camZ|--fov|--roll|--diskH|--h|--spin|--kerr-tol|--kerr-escape-mult|--kerr-radial-scale|--kerr-azimuth-scale|--kerr-impact-scale)
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
    --exposure|--dither|--inner-edge-mult)
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

if [[ "$LOOK_SET" -eq 0 && -n "$PRESET_VALUE" ]]; then
  SWIFT_ARGS+=(--look "$PRESET_VALUE")
  PY_ARGS+=(--look "$PRESET_VALUE")
fi

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
    SWIFT_ARGS+=(--tile-size "$TILE_SIZE_VALUE")
  fi
fi
if [[ -n "$TILE_SIZE_VALUE" ]]; then
  TILE_INFO="$TILE_SIZE_VALUE"
else
  TILE_INFO="full-frame"
fi

TEMP_COLLISIONS=""
if [[ "$MODE" == "fast" && "$COLLISIONS_OUT_EXPLICIT" -eq 0 ]]; then
  TEMP_COLLISIONS="$(mktemp /tmp/blackhole_collisions.XXXXXX)"
  COLLISIONS_OUT="$TEMP_COLLISIONS"
fi

log_section "Pipeline"
log_item "metric" "$METRIC_VALUE"
log_item "mode" "$MODE"
log_item "compose" "$COMPOSE_BACKEND"
if [[ "$COMPOSE_BACKEND" == "gpu" && "$MATCH_CPU" -eq 1 ]]; then
  log_item "match_cpu" "enabled (GPU trace + Python compose)"
elif [[ "$COMPOSE_BACKEND" == "gpu" && "$GPU_FULL_COMPOSE" -eq 1 ]]; then
  log_item "gpu_mode" "pure-gpu"
elif [[ "$COMPOSE_BACKEND" == "gpu" ]]; then
  log_item "gpu_mode" "precise-match"
fi
log_item "ssaa" "$SSAA"
log_item "output_size" "${TARGET_WIDTH}x${TARGET_HEIGHT}"
log_item "render_size" "${RENDER_WIDTH}x${RENDER_HEIGHT}"
log_item "tile_size" "$TILE_INFO"
log_item "eta_output" "$ETA_RELAY"
if [[ -n "$TEMP_COLLISIONS" ]]; then
  log_item "collisions_out" "$COLLISIONS_OUT (temporary)"
else
  log_item "collisions_out" "$COLLISIONS_OUT"
fi
log_item "image_out" "$IMAGE_OUT"

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
    if [[ -n "$TEMP_COLLISIONS" ]]; then
      GPU_COMPOSE_ARGS+=(--discard-collisions)
    fi
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

if [[ "$COMPOSE_BACKEND" == "gpu" && "$MATCH_CPU" -eq 0 ]]; then
  if [[ "$GPU_FULL_COMPOSE" -eq 1 ]]; then
    log_section "Stage 1/1 - Swift Trace+Compose (GPU Pure)"
  else
    log_section "Stage 1/1 - Swift Trace+Compose (GPU Precise-Match)"
  fi
elif [[ "$COMPOSE_BACKEND" == "gpu" && "$MATCH_CPU" -eq 1 ]]; then
  log_section "Stage 1/2 - Swift Trace (Match CPU)"
else
  log_section "Stage 1/2 - Swift Trace"
fi
if [[ -f "$ETA_SCRIPT" ]]; then
  python3 "$ETA_SCRIPT" \
    --history "$ETA_HISTORY" \
    --stage swift \
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
    PY_CMD=(python3 "$ROOT_DIR/Blackhole/render_collisions.py" \
      --input "$COLLISIONS_OUT" \
      --meta "$COLLISIONS_OUT.json" \
      --output "$IMAGE_OUT" \
      "${PY_ARGS[@]}")
  else
    PY_CMD=(python3 "$ROOT_DIR/Blackhole/render_collisions.py" \
      --input "$COLLISIONS_OUT" \
      --meta "$COLLISIONS_OUT.json" \
      --output "$IMAGE_OUT")
  fi

  if [[ "$COMPOSE_BACKEND" == "gpu" && "$MATCH_CPU" -eq 1 ]]; then
    log_section "Stage 2/2 - Python Compose (Match CPU)"
  else
    log_section "Stage 2/2 - Python Compose"
  fi
  if [[ -f "$ETA_SCRIPT" ]]; then
    python3 "$ETA_SCRIPT" \
      --history "$ETA_HISTORY" \
      --stage python \
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

log_section "Outputs"
log_item "image" "$IMAGE_OUT"
if [[ "$MODE" == "debug" || "$COLLISIONS_OUT_EXPLICIT" -eq 1 ]]; then
  log_item "collisions" "$COLLISIONS_OUT"
  log_item "meta" "$COLLISIONS_OUT.json"
fi

if [[ -n "$TEMP_COLLISIONS" ]]; then
  rm -f "$TEMP_COLLISIONS" "$TEMP_COLLISIONS.json"
  log_item "cleanup" "temporary collisions removed"
fi
