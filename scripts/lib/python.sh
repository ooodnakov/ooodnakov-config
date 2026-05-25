#!/usr/bin/env bash

# Run a Python script, preferring `uv run` (which uses the pinned
# .python-version and project environment) when uv is available.
oooconf_run_python() {
  local repo_root="$1"
  shift

  if command -v uv >/dev/null 2>&1 && [ -f "$repo_root/pyproject.toml" ] && [ -z "${UV_RUN_RECURSION_DEPTH:-}" ]; then
    if [ "${MINIMAL:-0}" = "1" ] || [ "${OOODNAKOV_MINIMAL:-0}" = "1" ]; then
      (cd "$repo_root" && uv run --no-sync "$@")
    else
      (cd "$repo_root" && uv run "$@")
    fi
  else
    (cd "$repo_root" && python3 "$@")
  fi
}
