#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT/handy-menu-dashboard/FeatureFlags+Generated.swift"

had_github_override=false
if [[ -n "${SHOW_GITHUB_SETTINGS+x}" ]]; then
  had_github_override=true
  github_override_value="$SHOW_GITHUB_SETTINGS"
fi

had_claude_override=false
if [[ -n "${SHOW_CLAUDE_SETTINGS+x}" ]]; then
  had_claude_override=true
  claude_override_value="$SHOW_CLAUDE_SETTINGS"
fi

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

if $had_github_override; then
  SHOW_GITHUB_SETTINGS="$github_override_value"
fi

if $had_claude_override; then
  SHOW_CLAUDE_SETTINGS="$claude_override_value"
fi

SHOW_GITHUB_SETTINGS="${SHOW_GITHUB_SETTINGS:-false}"
SHOW_CLAUDE_SETTINGS="${SHOW_CLAUDE_SETTINGS:-false}"

is_enabled() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    true | 1 | yes | on) return 0 ;;
    *) return 1 ;;
  esac
}

if is_enabled "$SHOW_GITHUB_SETTINGS"; then
  github_enabled="true"
else
  github_enabled="false"
fi

if is_enabled "$SHOW_CLAUDE_SETTINGS"; then
  claude_enabled="true"
else
  claude_enabled="false"
fi

cat >"$OUTPUT" <<EOF
enum GeneratedFeatureFlags {
    static let showGitHubSettings = $github_enabled
    static let showClaudeSettings = $claude_enabled
}
EOF
