#!/usr/bin/env bash
# Minimal setup script — links the shell profile and installs only Oh My Zsh.
# Run with: ./scripts/setup/minimal-setup.sh or oooconf minimal (after integration).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export OOODNAKOV_MINIMAL=1
export OOODNAKOV_PROFILE=minimal
export OOODNAKOV_SKIP_DEPS=1

if [[ "${1:-}" == "--dry-run" ]]; then
  exec "$REPO_ROOT/scripts/setup/setup.sh" install --dry-run
fi

exec "$REPO_ROOT/scripts/setup/setup.sh" install
