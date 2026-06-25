#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if command -v swiftlint >/dev/null 2>&1; then
  swiftlint lint --quiet
else
  echo "SwiftLint is not installed. Install with: brew install swiftlint"
  exit 0
fi
