#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$REPO_ROOT/scripts/setup.sh"
DELETE="$REPO_ROOT/scripts/delete.sh"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"
GEN_LOCK="$REPO_ROOT/scripts/generate-dependency-lock.py"
UPDATE_PINS="$REPO_ROOT/scripts/update-pins.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/ooodnakov.sh <command> [options]

Commands:
  bootstrap         clone/update repo then run install
  install           run setup install
  update            run setup update
  doctor            run setup doctor
  dry-run           run setup install --dry-run
  delete            remove managed links and restore latest backups
  remove            remove managed links only
  lock              regenerate dependency lock artifacts
  update-pins       check/update pinned refs and refresh lock artifacts
EOF
}

command="${1:-}"
shift || true

case "$command" in
  bootstrap) exec "$BOOTSTRAP" "$@" ;;
  install) exec "$SETUP" install "$@" ;;
  update) exec "$SETUP" update "$@" ;;
  doctor) exec "$SETUP" doctor "$@" ;;
  dry-run) exec "$SETUP" install --dry-run "$@" ;;
  delete) exec "$DELETE" restore "$@" ;;
  remove) exec "$DELETE" remove "$@" ;;
  lock) exec python3 "$GEN_LOCK" "$@" ;;
  update-pins) exec "$UPDATE_PINS" "$@" ;;
  -h|--help|"") usage ;;
  *)
    echo "Unknown command: $command" >&2
    usage >&2
    exit 1
    ;;
esac
