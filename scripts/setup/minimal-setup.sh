#!/usr/bin/env bash
# Minimal setup script — links the minimal shell profile and installs exactly the
# dependency set in [minimal] of scripts/optional-deps.toml.
# Run with: ./scripts/setup/minimal-setup.sh [--dry-run] or oooconf minimal.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export OOODNAKOV_MINIMAL=1
export OOODNAKOV_PROFILE=minimal

install_args=(install --minimal --yes-optional)
for arg in "$@"; do
  case "$arg" in
  --dry-run) install_args+=(--dry-run) ;;
  --yes-optional) ;;
  *) install_args+=("$arg") ;;
  esac
done

exec "$REPO_ROOT/scripts/setup/setup.sh" "${install_args[@]}"
