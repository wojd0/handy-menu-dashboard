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
  "/Applications"
  "$HOME/Applications"
)

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
  target_app="$applications_dir/$APP_BUNDLE"
  staged_app="$applications_dir/.$APP_BUNDLE.installing"

  mkdir -p "$applications_dir"
  rm -rf "$staged_app"
  ditto "$BUILT_APP" "$staged_app"
  rm -rf "$target_app"
  mv "$staged_app" "$target_app"

  echo "Installed $APP_BUNDLE to $applications_dir"
done

if pgrep -xq "$APP_NAME"; then
  osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
  sleep 1
fi

open -a "${INSTALL_DIRS[0]}/$APP_BUNDLE"
