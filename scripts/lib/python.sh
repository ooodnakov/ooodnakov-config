#!/usr/bin/env bash

# Run a Python script, preferring `uv run` (which uses the pinned
# .python-version and project environment) when uv is available.
oooconf_run_python() {
  if command -v uv >/dev/null 2>&1 && [ -f "$1/pyproject.toml" ]; then
    local repo_root="$1"
    shift
    (cd "$repo_root" && uv run "$@")
  else
    shift
    python3 "$@"
  fi
}
