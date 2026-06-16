#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="GargantuaLauncher"
BUNDLE_ID="com.gargantua.launcher"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${BH_GUI_DERIVED_DATA:-/private/tmp/bh_gargantua_launcher_run/DerivedData}"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"

usage() {
  echo "usage: $0 [run|--verify|--logs|--telemetry|--debug]" >&2
}

kill_existing() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_app() {
  xcodebuild \
    -project "$ROOT_DIR/Blackhole.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    build \
    -quiet
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_app() {
  open_app
  sleep 2
  pgrep -x "$APP_NAME" >/dev/null
  echo "$APP_NAME is running"
}

kill_existing
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --verify|verify)
    verify_app
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  *)
    usage
    exit 2
    ;;
esac
