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

# Run the isolated host-platform lifecycle test.
integration:
    @uv run pytest tests/test_cross_platform_lifecycle.py

# Enforce the initial Python coverage floor.
coverage:
    @uv run pytest --cov=scripts --cov-report=term --cov-fail-under=50

# Parse or smoke-check tracked structured configuration.
formats:
    @uv run python scripts/validation/validate_tracked_formats.py

# Run cross-platform checks.
check: lint format-check formats test
    @echo Cross-platform checks passed.

# Run Unix shell syntax and smoke tests. Requires Bash.
[unix]
unix:
    @bash tests/test_shell.sh

# Regenerate tracked oooconf shell completions and command reference.
completions:
    @uv run python scripts/cli/generate_oooconf_completions.py
    @uv run python scripts/cli/generate_cli_reference.py

# Regenerate dependency lock artifacts.
lock:
    @uv run python scripts/generate/generate_dependency_lock.py
