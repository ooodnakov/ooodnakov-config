#!/usr/bin/env bash
# Minimal setup script — installs core tools from [minimal] in optional-deps.toml.
# Run with: ./scripts/minimal-setup.sh or oooconf minimal (after integration).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPTIONAL_DEPS_SCRIPT="$REPO_ROOT/scripts/read_optional_deps.py"

echo "=== ooodnakov minimal setup ==="
echo "Reading core tools from optional-deps.toml [minimal] section..."

MINIMAL_KEYS=$(uv run "$OPTIONAL_DEPS_SCRIPT" minimal)

if [ -z "$MINIMAL_KEYS" ]; then
  echo "No minimal keys defined. Check [minimal] in optional-deps.toml."
  exit 1
fi

echo "Installing minimal core tools: $MINIMAL_KEYS"
echo "(non-interactive with --yes-optional)"

"$REPO_ROOT/scripts/ooodnakov.sh" deps --yes-optional $MINIMAL_KEYS

echo ""
echo "Minimal setup complete. Run 'oooconf deps' for additional optional tools."
echo "Log: ~/.local/state/ooodnakov-config/logs/setup-*.log"
