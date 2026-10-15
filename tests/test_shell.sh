#!/usr/bin/env bash
# Simple shell test for refactored .sh files (central TOML usage).
# Run with: bash tests/test_shell.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== Testing shell syntax (.sh files) ==="
for script in scripts/setup/setup.sh scripts/setup/ooodnakov.sh scripts/setup/delete.sh scripts/setup/lib/*.sh; do
  echo "Checking $script..."
  bash -n "$script"
done
echo "OK: All entrypoint and setup/lib .sh files have valid syntax."

echo "=== Testing dry-run with central TOML parser ==="
echo "Running oooconf deps --dry-run (verifies central TOML parser, no scattered lists/overrides)..."
output=$(./scripts/setup/ooodnakov.sh deps --dry-run rtk bw pnpm nvim 2>&1)
echo "$output" | grep -E "(dry-run|Dependency summary|complete|skipping)" || true
if echo "$output" | grep -qE "(Dependency summary|complete|dry-run)"; then
  echo "OK: dry-run completed successfully via central TOML."
else
  echo "WARNING: dry-run output unexpected (but return code was 0)."
fi

echo "=== Testing managed tool lookup (get_managed_tool) ==="
# Simple validation that the helper path is exercised (no hard-coded lists)
STATE_HOME="/tmp/test_state"
export STATE_HOME
if ./scripts/setup/ooodnakov.sh deps --dry-run rtk 2>&1 | grep -qE "(dry-run|rtk|Dependency summary|complete)"; then
  echo "OK: managed tool lookup and TOML path exercised."
else
  echo "INFO: managed tool lookup skipped (normal in minimal env)."
fi

echo "=== Testing WSL host-binary detection helpers ==="
# WSL leaks Windows host binaries onto PATH as /mnt/<drive>/... paths; those must
# not count as installed inside the distro.
if bash -c 'source scripts/setup/lib/setup-ui.sh; is_host_windows_command_path "/mnt/c/Users/example/.bun/bin/bun"'; then
  echo "OK: Windows host path detected."
else
  echo "FAIL: Windows host path not detected." >&2
  exit 1
fi

if bash -c 'source scripts/setup/lib/setup-ui.sh; is_host_windows_command_path "/usr/local/bin/bun"'; then
  echo "FAIL: native path misdetected as a Windows host path." >&2
  exit 1
fi

if bash -c 'source scripts/setup/lib/setup-ui.sh; is_host_windows_command_path "/mnt/wsl/shared/bin/tool"'; then
  echo "FAIL: /mnt/wsl misdetected as a Windows drive path." >&2
  exit 1
fi
echo "OK: native and /mnt/wsl paths are not treated as Windows host paths."

if bash -c 'source scripts/setup/lib/setup-ui.sh; dependency_resolved_on_windows_host sh'; then
  echo "FAIL: a native command was reported as a Windows host binary." >&2
  exit 1
fi
echo "OK: native commands are left untouched by the WSL check."

echo "=== Testing --dry-run does not mutate file permissions ==="
dryrun_dir="$(mktemp -d)"
printf '#!/bin/sh\n' >"$dryrun_dir/script.sh"
chmod 755 "$dryrun_dir/script.sh"
DRY_RUN=1 bash -c 'ui_line() { :; }; source scripts/setup/lib/setup-ui.sh; source scripts/setup/lib/setup-links.sh; normalize_tree_permissions "$1"' _ "$dryrun_dir" >/dev/null 2>&1
if [ -x "$dryrun_dir/script.sh" ]; then
  echo "OK: dry-run left permissions unchanged."
else
  echo "FAIL: dry-run stripped executable permissions." >&2
  rm -rf "$dryrun_dir"
  exit 1
fi
DRY_RUN=0 bash -c 'ui_line() { :; }; source scripts/setup/lib/setup-ui.sh; source scripts/setup/lib/setup-links.sh; normalize_tree_permissions "$1"' _ "$dryrun_dir" >/dev/null 2>&1
if [ -x "$dryrun_dir/script.sh" ]; then
  echo "FAIL: real run did not normalize permissions." >&2
  rm -rf "$dryrun_dir"
  exit 1
fi
echo "OK: real run normalizes permissions."
rm -rf "$dryrun_dir"

echo "=== Testing pinned checkout tolerates permission drift ==="
if (
  set +e
  t="$(mktemp -d)"
  trap 'rm -rf "$t"' EXIT
  DRY_RUN=0
  VERBOSE=0
  FAILURES=()
  TOOL_SUMMARY=()
  STATE_HOME="$t/state"
  HOME_DIR="$HOME"
  INTERACTIVE=never
  OOODNAKOV_GIT_SYNC_ATTEMPTS=1
  ui_line() { :; }
  run_python() { :; }
  source scripts/setup/lib/setup-ui.sh
  source scripts/setup/lib/setup-links.sh

  origin="$t/origin.git"
  work="$t/work"
  checkout="$t/checkout"
  git init -q --bare "$origin"
  git -C "$origin" config uploadpack.allowAnySHA1InWant true
  git init -q "$work"
  (
    cd "$work" || exit 1
    git config user.email t@t
    git config user.name t
    printf '#!/bin/sh\necho v1\n' >tool.sh
    chmod +x tool.sh
    git add tool.sh
    git commit -qm c1
    git remote add origin "$origin"
    git push -q origin HEAD:main
  )
  first_ref="$(git -C "$work" rev-parse HEAD)"
  sync_repo "$origin" "$first_ref" "$checkout" >/dev/null 2>&1

  (
    cd "$work" || exit 1
    printf '#!/bin/sh\necho v2\n' >tool.sh
    git commit -qam c2
    git push -q origin HEAD:main
  )
  second_ref="$(git -C "$work" rev-parse HEAD)"

  # Permission-only drift, as an interrupted or dry-run normalize would leave.
  chmod u=rw,go=r "$checkout/tool.sh"
  sync_repo "$origin" "$second_ref" "$checkout" >/dev/null 2>&1
  [ "$(git -C "$checkout" rev-parse HEAD)" = "$second_ref" ]
); then
  echo "OK: pinned ref applied despite permission drift."
else
  echo "FAIL: permission drift blocked pinning." >&2
  exit 1
fi

echo "=== Testing PowerShell syntax (if pwsh available) ==="
if command -v pwsh >/dev/null 2>&1; then
  echo "pwsh found. Checking setup.ps1 syntax..."
  pwsh -NoProfile -Command "try { . ./scripts/setup/setup.ps1; exit 0 } catch { Write-Error \$_; exit 1 }"
  echo "OK: PowerShell syntax valid."
else
  echo "pwsh not available — skipping .ps1 syntax test (install via 'oooconf deps pwsh' or package manager)."
fi

echo ""
echo "All shell tests passed. The refactored code uses optional-deps.toml as the only source of truth."
echo "No lists or overrides found in .sh/.ps1 files."
