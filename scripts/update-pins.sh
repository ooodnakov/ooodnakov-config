#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/update-pins.py"

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

# Run a Python script, preferring `uv run` when available.
run_python() {
  if command -v uv >/dev/null 2>&1 && [ -f "$REPO_ROOT/pyproject.toml" ]; then
    uv run "$@"
  else
    python3 "$@"
  fi
}

usage() {
  ui_line section "update-pins"
  cat <<'EOF'
Usage: ./scripts/update-pins.sh [--apply]

Checks pinned git refs declared in scripts/setup.sh against remote HEAD commits,
updates the automated pin-check section in docs/imports/upstream-audit.md,
and regenerates lock artifacts.

Options:
  --apply  update *_REF values in scripts/setup.sh to remote HEAD commits
EOF
}

args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply) args+=("--apply") ;;
    -h|--help) usage; exit 0 ;;
    *) ui_line fail "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

run_python "$SCRIPT" "${args[@]}"
