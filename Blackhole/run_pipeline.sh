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

SWIFT_ARGS=()
PY_ARGS=()
PY_MODE=0
LOOK_SET=0
PRESET_VALUE=""

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
2) Read collisions + JSON meta in Python
3) Save final image (PNG default)

Routing rules:
- Shared: --width --height --rcp
- Swift-only: --preset --camX --camY --camZ --fov --roll --diskH --maxSteps --h --metric --spin --kerr-substeps --kerr-tol --kerr-escape-mult --kerr-radial-scale --kerr-azimuth-scale --kerr-impact-scale
- Python-only: --chunk --spectral-step --exposure --dither --inner-edge-mult --look
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
        *.bin) COLLISIONS_OUT="$out_path" ;;
        *) COLLISIONS_OUT="$out_path" ;;
      esac
      continue
      ;;
  esac

  if [[ "$PY_MODE" -eq 1 ]]; then
    PY_ARGS+=("$arg")
    continue
  fi

  case "$arg" in
    --width|--height|--rcp)
      need_value "$arg" "$@"
      val="$1"
      shift
      SWIFT_ARGS+=("$arg" "$val")
      PY_ARGS+=("$arg" "$val")
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
    --camX|--camY|--camZ|--fov|--roll|--diskH|--maxSteps|--h|--metric|--spin|--kerr-substeps|--kerr-tol|--kerr-escape-mult|--kerr-radial-scale|--kerr-azimuth-scale|--kerr-impact-scale)
      need_value "$arg" "$@"
      val="$1"
      shift
      SWIFT_ARGS+=("$arg" "$val")
      ;;
    --chunk|--spectral-step|--exposure|--dither|--inner-edge-mult)
      need_value "$arg" "$@"
      val="$1"
      shift
      PY_ARGS+=("$arg" "$val")
      ;;
    --look)
      need_value "$arg" "$@"
      val="$1"
      shift
      LOOK_SET=1
      PY_ARGS+=("$arg" "$val")
      ;;
    *)
      SWIFT_ARGS+=("$arg")
      ;;
  esac
done

if [[ "$LOOK_SET" -eq 0 && -n "$PRESET_VALUE" ]]; then
  PY_ARGS+=(--look "$PRESET_VALUE")
fi

if [[ "$NO_BUILD" -eq 0 ]]; then
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build >/dev/null
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

if ((${#SWIFT_ARGS[@]})); then
  "${RUNNER[@]}" --output "$COLLISIONS_OUT" "${SWIFT_ARGS[@]}"
else
  "${RUNNER[@]}" --output "$COLLISIONS_OUT"
fi

if ((${#PY_ARGS[@]})); then
  python3 "$ROOT_DIR/Blackhole/render_collisions.py" \
    --input "$COLLISIONS_OUT" \
    --meta "$COLLISIONS_OUT.json" \
    --output "$IMAGE_OUT" \
    "${PY_ARGS[@]}"
else
  python3 "$ROOT_DIR/Blackhole/render_collisions.py" \
    --input "$COLLISIONS_OUT" \
    --meta "$COLLISIONS_OUT.json" \
    --output "$IMAGE_OUT"
fi

echo "Done: $COLLISIONS_OUT"
echo "Done: $COLLISIONS_OUT.json"
echo "Done: $IMAGE_OUT"
