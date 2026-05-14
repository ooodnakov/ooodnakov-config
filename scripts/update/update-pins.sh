#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON_LIB="$REPO_ROOT/scripts/lib/python.sh"
SCRIPT="$REPO_ROOT/scripts/update/update_pins.py"

ui_is_interactive() {
  [ -t 1 ]
}

ui_line() {
  local role="$1"
  shift
  local icon='[info]'
  local color='38;5;117'
  case "$role" in
    fail) icon='[fail]'; color='1;38;5;203' ;;
    section) icon='=='; color='1;38;5;111' ;;
  esac
  if [ -z "${NO_COLOR:-}" ] && ui_is_interactive; then
    printf '\033[%sm%s\033[0m %s\n' "$color" "$icon" "$*"
  else
    printf '%s %s\n' "$icon" "$*"
  fi
}

# shellcheck source=/dev/null
source "$PYTHON_LIB"

run_python() {
  oooconf_run_python "$REPO_ROOT" "$@"
}

usage() {
  ui_line section "update-pins"
  cat <<'EOF'
Usage: ./scripts/update/update-pins.sh [--apply] [--offline] [--dry-run]

Checks pinned git refs declared in scripts/optional-deps.toml against remote HEAD commits,
updates the automated pin-check section in docs/imports/upstream-audit.md,
and regenerates lock artifacts.

Options:
  --apply    update refs in scripts/optional-deps.toml to remote HEAD commits
  --offline  parse pins without resolving remote HEAD commits
  --dry-run  do not write report or lock artifacts
EOF
}

args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply) args+=("--apply") ;;
    --offline) args+=("--offline") ;;
    --dry-run) args+=("--dry-run") ;;
    -h|--help) usage; exit 0 ;;
    *) ui_line fail "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

run_python "$SCRIPT" "${args[@]}"
