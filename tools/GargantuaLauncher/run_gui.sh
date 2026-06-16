#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/gargantua-launcher"
APP_BIN="$BUILD_DIR/GargantuaLauncher"

mkdir -p "$BUILD_DIR"
swiftc -parse-as-library "$ROOT/tools/GargantuaLauncher/GargantuaLauncher.swift" \
  -framework SwiftUI \
  -framework AppKit \
  -o "$APP_BIN"

cd "$ROOT"
"$APP_BIN"
