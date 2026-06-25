#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

APP_NAME="handy-menu-dashboard"
APP_BUNDLE="$APP_NAME.app"
DERIVED_DATA="$ROOT/build/DerivedData"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_BUNDLE"
APPLICATIONS_DIR="$HOME/Applications"
TARGET_APP="$APPLICATIONS_DIR/$APP_BUNDLE"
STAGED_APP="$APPLICATIONS_DIR/.$APP_BUNDLE.installing"

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

mkdir -p "$APPLICATIONS_DIR"
rm -rf "$STAGED_APP"
ditto "$BUILT_APP" "$STAGED_APP"
rm -rf "$TARGET_APP"
mv "$STAGED_APP" "$TARGET_APP"

echo "Installed $APP_BUNDLE to $APPLICATIONS_DIR"
