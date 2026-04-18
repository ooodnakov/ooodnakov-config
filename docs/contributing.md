# Contributing Workflow

This short guide covers the common workflows for contributors making changes to this repository.

## Updating Documentation Safely

When making structural or setup behavior changes, it is important to keep the documentation aligned. Follow these rules:
- **Reference Docs:** All overarching reference material belongs in the `docs/` directory.
- **`README.md`:** Core entry points, general setup behavior, and architectural overviews should be summarized in `README.md`.
- **`AGENTS.md`:** Ensure that any behavioral constraints, architecture rules, or automated checks are reflected in `AGENTS.md`.

## Updating Dependency Pins and Regenerating Lock Artifacts

When adding, updating, or removing dependencies, you must regenerate the lock artifacts to maintain cross-platform reproducibility:

1. Use the helper script to regenerate the lock artifacts (`deps.lock.json` and `docs/dependency-lock.md`).
   ```bash
   uv run scripts/generate-dependency-lock.py
   ```
2. For interactive dependency updates, you can use `oooconf deps` or `oooconf lock`.

## Validations After Shell or Bootstrap Changes

After changing bootstrap logic, helper scripts, or Python configuration, run the relevant validations:

- **Shell scripts (.sh):** Check syntax and lint using `bash -n` and `shellcheck`.
  ```bash
  bash -n scripts/setup.sh
  shellcheck scripts/*.sh
  ```
- **PowerShell scripts (.ps1):** Validate using PSScriptAnalyzer via `pwsh`.
  ```powershell
  Invoke-ScriptAnalyzer -Path scripts/*.ps1
  ```
- **Python scripts and configuration:** Validate via `ruff` and `uv`.
  ```bash
  uv run ruff check --select I --fix
  uv run ruff check
  uv run ruff format
  ```

## Keeping README, docs/, and AGENTS.md Aligned

Whenever you make updates to the dotfiles setup, ensure that:
- Changes to dependencies are documented in `docs/dependency-decisions.md`.
- Changes to the dotfiles deployment behavior are described in `docs/architecture.md` and `docs/reproducibility.md`.
- The reference lists in `README.md` and `AGENTS.md` always include all relevant markdown files. If you add a new document, list it in both files.
