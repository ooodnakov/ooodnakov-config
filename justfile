# Project task runner. Run `just --list` for available recipes.

# List available automation recipes.
default:
    @just --list --unsorted

# Run Python lint checks.
lint:
    @uv run ruff check

# Verify Python formatting without changing files.
format-check:
    @uv run ruff format --check

# Apply safe automated Python lint and formatting fixes.
fix:
    @uv run ruff check --select I --fix
    @uv run ruff format

# Run full Python test suite.
test:
    @uv run pytest

# Run cross-platform checks.
check: lint format-check test
    @echo Cross-platform checks passed.

# Run Unix shell syntax and smoke tests. Requires Bash.
[unix]
unix:
    @bash tests/test_shell.sh

# Regenerate tracked oooconf shell completions.
completions:
    @uv run python scripts/cli/generate_oooconf_completions.py

# Regenerate dependency lock artifacts.
lock:
    @uv run python scripts/generate/generate_dependency_lock.py
