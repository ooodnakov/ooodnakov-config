# Contributing Workflow

This short guide covers the common workflows for contributors making changes to this repository.

## Updating Documentation Safely

When making structural or setup behavior changes, it is important to keep the documentation aligned. Follow these rules:

- **Reference Docs:** All overarching reference material belongs in the `docs/` directory.
- **`README.md`:** Core entry points, general setup behavior, and architectural overviews should be summarized in `README.md`.
- **`AGENTS.md`:** Ensure that any behavioral constraints, architecture rules, or automated checks are reflected in `AGENTS.md`.

## Updating Dependency Pins and Regenerating Lock Artifacts

When adding, updating, or removing dependencies, you must regenerate the lock artifacts to maintain cross-platform reproducibility:

1. Use `oooconf lock` to regenerate the lock artifacts (`deps.lock.json`).

   ```bash
   oooconf lock
   ```

2. For interactive dependency updates, you can use `oooconf deps`.

## Project Automation

Use the root `justfile` for common local workflows after installing its optional runner with `oooconf deps just`:

```bash
just check
just fix
just test
just unix          # Unix only
just integration
just coverage
just formats
just completions
just lock
```

`just check` is cross-platform and wraps Ruff plus pytest. `just unix` deliberately remains separate because it requires Bash. Run `just --list` for all recipes; the recipes wrap existing commands and CI remains authoritative.

CI runs the complete Python suite on Python 3.12 and 3.13 with a 50% coverage floor.
The isolated lifecycle test can be run directly without touching the real home or
performing network installation:

```bash
uv run pytest tests/test_cross_platform_lifecycle.py
uv run pytest --cov=scripts --cov-report=term --cov-fail-under=50
uv run python scripts/validation/validate_tracked_formats.py
```

The platform matrix is intentionally asymmetric: Ubuntu and macOS exercise Bash,
Windows exercises PowerShell 7, and the complete Python suite runs on Ubuntu for
Python 3.12 and 3.13. The isolated lifecycle additionally runs once on each OS. Do
not describe an architecture or shell as tested unless a required CI job executes
it; update the [support matrix](reproducibility.md#platform-support-matrix) whenever
the workflow matrix changes.

## Continuous Integration

- CI runs on pushes to `main` and on pull requests.
- Linux and macOS jobs run Python lint/format checks, Bash syntax validation, `shellcheck`, lockfile reproducibility checks, static Neovim/WezTerm/Ghostty smoke checks, and `oooconf` smoke tests (`install --dry-run`, `doctor` expected-failure on a fresh HOME, and `lock`).
- Windows jobs run Python lint/format checks, PowerShell parser validation, static Neovim/WezTerm/Ghostty smoke checks, and the same `oooconf` smoke tests.
- Tags matching `v*` publish `.tar.gz` and `.zip` source archives to GitHub Releases.
- `oooconf fleet sync` pulls repository updates onto SSH hosts, dedupes aliases that reach the same machine, and reports root, missing-checkout, local, and duplicate hosts as `skipped` without running git; see [SSH fleet sync](fleet-automation.md).
- CI exercises the complete plan/apply/doctor/remove/restore/rollback lifecycle in isolated temporary homes on Linux, macOS, and Windows, with network installs disabled and a ratchetable Python coverage floor.

## Pre-commit Hooks

Install `pre-commit` and enable the tracked hooks before committing: they mirror the main local checks (Bash syntax, `shellcheck`, Ruff lint/format, dependency lock reproducibility, and a `gitleaks` scan of staged changes; `just secrets` scans the full git history).

```bash
uv tool install pre-commit
pre-commit install
pre-commit run --all-files
```

## Validations After Shell or Bootstrap Changes

After changing bootstrap logic, setup/CLI helper scripts, or Python configuration, run the relevant validations. Setup and `oooconf` implementation lives in `scripts/setup/lib/`; keep public entrypoints stable and put newly extracted helpers in focused Bash/PowerShell module pairs when practical:

- **Shell scripts (.sh):** Check syntax and lint using `bash -n` and `shellcheck`.

  ```bash
  bash -n scripts/setup/setup.sh
  bash -n scripts/setup/ooodnakov.sh
  bash -n scripts/setup/delete.sh
  bash -n scripts/setup/minimal-setup.sh
  bash -n scripts/setup/lib/*.sh
  shellcheck scripts/setup/setup.sh scripts/setup/ooodnakov.sh scripts/setup/delete.sh scripts/update/update-pins.sh scripts/setup/minimal-setup.sh bootstrap.sh
  # Note: lib modules (scripts/setup/lib/*.sh) are syntax-checked via bash -n above; full shellcheck coverage is pending.
  ```

- **PowerShell scripts (.ps1):** Validate using PSScriptAnalyzer via `pwsh`.

  ```powershell
  Invoke-ScriptAnalyzer -Path scripts/setup/*.ps1, home/.config/ooodnakov/bin/*.ps1, tests/*.ps1
  ```

- **Python scripts and configuration:** Validate via `ruff` and `uv`.

  ```bash
  uv run ruff check --select I --fix
  uv run ruff check
  uv run ruff format
  uv run pytest
  ```

## Updating oooconf Completions

For command design and dispatch details, start with `docs/cli-extension-guide.md`. The `oooconf` completion source of truth is `scripts/cli/oooconf-cli-spec.toml`. It is a recursive command tree: add nested commands under `subcommands`, put each command's options and positional values on that command node, and use `value_set` or `option_value_sets` when values come from a shared definition. Dependency-key completions use the `deps_keys` shared definition hydrated from `scripts/optional-deps.toml`, so do not duplicate the optional dependency catalog in generated shell code.

After changing the CLI spec or completion generator, run:

```bash
uv run python scripts/cli/generate_oooconf_completions.py
uv run python scripts/cli/generate_cli_reference.py
uv run pytest tests/test_cli_contract.py tests/test_recursive_completions.py
```

After changing third-party autogen completion metadata in `scripts/generate/tool-completions.toml`, run:

```bash
uv run python scripts/generate/generate_tool_completions.py --dry-run
uv run pytest tests/test_optional_deps_drift.py -k tool_completion
```

## Keeping README, docs/, and AGENTS.md Aligned

Whenever you make updates to the dotfiles setup, ensure that:

- Changes to dependencies are documented in `docs/dependency-decisions.md`.
- Changes to the dotfiles deployment behavior are described in `docs/architecture.md` and `docs/reproducibility.md`.
- The reference lists in `README.md` and `AGENTS.md` always include all relevant markdown files. If you add a new document, list it in both files.
