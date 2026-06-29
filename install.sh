#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

"$ROOT/scripts/generate-feature-flags.sh"

APP_NAME="handy-menu-dashboard"
APP_BUNDLE="$APP_NAME.app"
DERIVED_DATA="$ROOT/build/DerivedData"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_BUNDLE"
INSTALL_DIRS=(
  "$HOME/Applications"
)

for applications_dir in "${INSTALL_DIRS[@]}"; do
  target_app="$applications_dir/$APP_BUNDLE"
  if [[ -d "$target_app" ]]; then
    read -r -p "$APP_BUNDLE is already installed at $target_app. Replace it? [y/N] " reply
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 1
    fi
  fi
done

xcodebuild \
  -project "handy-menu-dashboard.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Build succeeded, but the app bundle was not found at: $BUILT_APP"
  exit 1
fi

for applications_dir in "${INSTALL_DIRS[@]}"; do
  mkdir -p "$applications_dir"
  ditto "$BUILT_APP" "$applications_dir/$APP_BUNDLE"
  echo "Installed $APP_BUNDLE to $applications_dir"
done

if pgrep -x "$APP_NAME" > /dev/null; then
  echo "Stopping running instance of $APP_NAME..."
  pkill -x "$APP_NAME"
  sleep 1
fi

open -a "${INSTALL_DIRS[0]}/$APP_BUNDLE"
echo "Launched $APP_BUNDLE"
