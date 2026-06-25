#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT/handy-menu-dashboard/FeatureFlags+Generated.swift"

had_override=false
if [[ -n "${SHOW_GITHUB_SETTINGS+x}" ]]; then
  had_override=true
  override_value="$SHOW_GITHUB_SETTINGS"
fi

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

if $had_override; then
  SHOW_GITHUB_SETTINGS="$override_value"
fi

SHOW_GITHUB_SETTINGS="${SHOW_GITHUB_SETTINGS:-false}"

is_enabled() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    true | 1 | yes | on) return 0 ;;
    *) return 1 ;;
  esac
}

if is_enabled "$SHOW_GITHUB_SETTINGS"; then
  enabled="true"
else
  enabled="false"
fi

cat >"$OUTPUT" <<EOF
enum GeneratedFeatureFlags {
    static let showGitHubSettings = $enabled
}
EOF
