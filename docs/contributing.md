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

## Validations After Shell or Bootstrap Changes

After changing bootstrap logic, helper scripts, or Python configuration, run the relevant validations:

- **Shell scripts (.sh):** Check syntax and lint using `bash -n` and `shellcheck`.

  ```bash
  bash -n scripts/setup/setup.sh
  bash -n scripts/setup/ooodnakov.sh
  bash -n scripts/setup/delete.sh
  bash -n scripts/setup/minimal-setup.sh
  shellcheck scripts/setup/setup.sh scripts/setup/ooodnakov.sh scripts/setup/delete.sh scripts/update/update-pins.sh scripts/setup/minimal-setup.sh bootstrap.sh
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

The `oooconf` completion source of truth is `scripts/cli/oooconf-cli-spec.toml`. It is a recursive command tree: add nested commands under `subcommands`, put each command's options and positional values on that command node, and use `value_set` or `option_value_sets` when values come from a shared definition. Dependency-key completions use the `deps_keys` shared definition hydrated from `scripts/optional-deps.toml`, so do not duplicate the optional dependency catalog in generated shell code.

After changing the CLI spec or completion generator, run:

```bash
uv run python scripts/cli/generate_oooconf_completions.py
uv run pytest tests/test_recursive_completions.py
```

## Keeping README, docs/, and AGENTS.md Aligned

Whenever you make updates to the dotfiles setup, ensure that:

- Changes to dependencies are documented in `docs/dependency-decisions.md`.
- Changes to the dotfiles deployment behavior are described in `docs/architecture.md` and `docs/reproducibility.md`.
- The reference lists in `README.md` and `AGENTS.md` always include all relevant markdown files. If you add a new document, list it in both files.
