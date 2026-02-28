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

case "$ETA_RELAY" in
  always|errors|none) ;;
  *)
    echo "error: BH_ETA_RELAY must be one of always, errors, none" >&2
    exit 2
    ;;
esac

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

show_help() {
  cat <<'USAGE'
Usage: ./run_pipeline.sh [options]

One-command pipeline:
1) Build and run Swift/Metal renderer
2) Compose final image (GPU Metal or Python)
3) Save final image (PNG default)

Routing rules:
- Shared: --width --height --rcp
- Swift-only: --preset --camX --camY --camZ --fov --roll --diskH --maxSteps --h --metric --spin --kerr-substeps --kerr-tol --kerr-escape-mult --kerr-radial-scale --kerr-azimuth-scale --kerr-impact-scale --disk-time --disk-orbital-boost --disk-radial-drift --disk-turbulence --disk-flow-step --disk-flow-steps --disk-model --disk-atlas --disk-atlas-width --disk-atlas-height --disk-atlas-temp-scale --disk-atlas-density-blend --disk-atlas-vr-scale --disk-atlas-vphi-scale --disk-atlas-r-min --disk-atlas-r-max --disk-atlas-r-warp
- Disk model values: --disk-model {procedural|perlin|atlas|auto}
- Atlas auto path: when --disk-model atlas is set and --disk-atlas is omitted, auto-search order is BH_DISK_ATLAS, ./disk_atlas.bin, /tmp/stage3_ab/disk_atlas.bin
- Compose controls: --chunk --spectral-step --exposure --exposure-samples --dither --inner-edge-mult --look
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
- Unknown options go to Swift by default.
- Use --py to forward the remaining args to Python.

Output controls:
- --output <path>: final image output path (PNG/PPM)
- --image-out <path>: alias of --output
- --collisions-out <path>: optional explicit intermediate path (advanced)

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
  python3 "$COMPARE_STAGE3_SCRIPT" --run-pipeline "$ROOT_DIR/Blackhole/run_pipeline.sh" "${STAGE3_AB_ARGS[@]}"
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
      continue
      ;;
    --gpu-only)
      PIPELINE_MODE="gpu-only"
      continue
      ;;
    --pipeline)
      need_value "$arg" "$@"
      pipeline_mode="$1"
      shift
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
      continue
      ;;
    --gpu-native)
      # Kept for backward compatibility: map to cpu-mixed terminology.
      PIPELINE_MODE="cpu-mixed"
      continue
      ;;
    --gpu-pure)
      # Kept for backward compatibility: map to gpu-only terminology.
      PIPELINE_MODE="gpu-only"
      continue
      ;;
    --gpu-hybrid)
      # Kept for backward compatibility: map to cpu-mixed terminology.
      PIPELINE_MODE="cpu-mixed"
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
    --disk-atlas)
      need_value "$arg" "$@"
      val="$1"
      shift
      DISK_ATLAS_VALUE="$val"
      DISK_ATLAS_SET=1
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
    --camX|--camY|--camZ|--fov|--roll|--diskH|--h|--spin|--kerr-tol|--kerr-escape-mult|--kerr-radial-scale|--kerr-azimuth-scale|--kerr-impact-scale|--disk-time|--disk-orbital-boost|--disk-radial-drift|--disk-turbulence|--disk-flow-step|--disk-flow-steps|--disk-model|--disk-atlas|--disk-atlas-width|--disk-atlas-height|--disk-atlas-temp-scale|--disk-atlas-density-blend|--disk-atlas-vr-scale|--disk-atlas-vphi-scale|--disk-atlas-r-min|--disk-atlas-r-max|--disk-atlas-r-warp)
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

if [[ "$LOOK_SET" -eq 0 && -n "$PRESET_VALUE" ]]; then
  SWIFT_ARGS+=(--look "$PRESET_VALUE")
  PY_ARGS+=(--look "$PRESET_VALUE")
fi

# Atlas auto-discovery: when atlas is requested but path is omitted.
if [[ "$DISK_ATLAS_SET" -eq 0 ]]; then
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
    COLLISIONS_OUT="/tmp/blackhole_discard.bin"
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
  python3 "$ETA_SCRIPT" \
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
    log_section "Stage 2/2 - Python"
  else
    log_section "Stage 2/2 - Python"
  fi
  if [[ -f "$ETA_SCRIPT" ]]; then
    python3 "$ETA_SCRIPT" \
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
