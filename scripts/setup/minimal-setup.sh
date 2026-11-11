#!/usr/bin/env bash
# Minimal setup script — sparse-checkout friendly install of the minimal shell
# profile. Dependencies are installed only with --min-dep (the [minimal] set from
# scripts/optional-deps.toml).
# Run with: ./scripts/setup/minimal-setup.sh [--min-dep] [--dry-run]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export OOODNAKOV_MINIMAL=1
export OOODNAKOV_PROFILE=minimal

install_args=(install --minimal --yes-optional)
min_dep=0
for arg in "$@"; do
  case "$arg" in
  --dry-run) install_args+=(--dry-run) ;;
  --min-dep) min_dep=1 ;;
  --yes-optional) ;;
  *) install_args+=("$arg") ;;
  esac
done

if [ "$min_dep" -eq 1 ]; then
  install_args+=(--min-dep)
else
  export OOODNAKOV_SKIP_DEPS=1
fi

exec "$REPO_ROOT/scripts/setup/setup.sh" "${install_args[@]}"
