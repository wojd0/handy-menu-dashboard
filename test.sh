#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

RESULT_BUNDLE="$ROOT/build/TestResults.xcresult"
rm -rf "$RESULT_BUNDLE"

SHOW_GITHUB_SETTINGS=true xcodebuild \
  -project "handy-menu-dashboard.xcodeproj" \
  -scheme "handy-menu-dashboard" \
  -configuration Debug \
  -destination "platform=macOS" \
  -resultBundlePath "$RESULT_BUNDLE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  test

"$ROOT/scripts/generate-feature-flags.sh"
