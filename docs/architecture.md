# Architecture

## Goals

This repo keeps the active tracked config small, reproducible, and portable across Linux, Windows, and future macOS machines.

The tracked base config is intended to be safe to clone onto a new machine without carrying over secrets, host-specific paths, or runtime state.

## Layout

- `home/`: active tracked config that gets linked into the user profile
- `scripts/`: install, update, doctor, delete, and dependency pin management entrypoints
- `docs/`: reproducibility notes, architecture, and import audit records
- `fonts/meslo/`: bundled prompt and terminal fonts used by the tracked defaults
- `third_party/`: reference-only upstream trees and local snapshots for audit or extraction work

Only `home/` is treated as managed active config. `third_party/` is kept for comparison and targeted imports, not as a live runtime tree.

## Install Model

The repo uses a symlink-first install model.

On Unix-like systems:

- `scripts/setup.sh` links tracked files from `home/` into XDG and home-directory targets
- `home/.config/ooodnakov/bin/oooconf` is linked into `~/.local/bin/oooconf`
- replaced files are moved into timestamped backups under `~/.local/state/ooodnakov-config/backups/`
- logs are written to `~/.local/state/ooodnakov-config/logs/`

On Windows:

- `scripts/setup.ps1` creates the corresponding managed links
- `oooconf.ps1` and `oooconf.cmd` are linked into `$HOME\.local\bin`
- backups and logs live under `$HOME\.local\state\ooodnakov-config\`

The install flow is intentionally idempotent. Re-running `oooconf install` should converge the machine back to the tracked state without duplicating managed artifacts.

## CLI Surface

There are two phase-1 entrypoints before install:

- Unix: `./home/.config/ooodnakov/bin/oooconf`
- Windows: `.\scripts\ooodnakov.ps1`

After install, the unified `oooconf` command is available from `~/.local/bin` on both platforms.

Primary commands:

- `install`: apply managed config and optional dependency installs
- `update`: fast-forward the repo and rerun install
- `dry-run`: preview planned changes without mutating the system
- `doctor`: validate managed links and key tools
- `delete` and `remove`: remove managed links, optionally restoring backups
- `lock`: regenerate dependency lock artifacts
- `update-pins`: audit pinned refs against upstream and optionally apply updates

## Dependency Model

Pinned third-party shell dependencies are installed outside the repo into user-local state instead of being committed into the active tracked tree.

Optional dependencies are defined in `scripts/optional-deps.toml` — a single TOML file that both Unix and PowerShell setup scripts read through `scripts/read_optional_deps.py`. Each entry specifies per-platform install methods (apt, brew, choco, winget, cargo, curl, or custom), so adding or removing an optional dep is a one-file change with platform install info ready for reuse.

This gives two properties:

- the working config remains small and readable
- installs stay reproducible because setup pins upstream refs and regenerates `deps.lock.json` plus `docs/dependency-lock.md`

Python scripts under `scripts/` own the lockfile generation and pin-update workflow so Unix and PowerShell entrypoints share the same implementation.

## Local Override Precedence

Tracked portable environment belongs in:

- `home/.config/ooodnakov/env/common.sh`
- `home/.config/ooodnakov/env/common.ps1`

Machine-specific or secret values belong in ignored local files such as:

- `~/.config/ooodnakov/local/env.zsh`
- `~/.config/ooodnakov/local/env.ps1`
- `~/.config/ooodnakov/local/wezterm.lua`
- `~/.ssh/config.local`

Tracked secret references belong in:

- `home/.config/ooodnakov/secrets/env.template`

The design rule is simple: if a value is secret, internal, machine-only, or not safe across Linux, Windows, and macOS, it belongs in a local override instead of tracked base config.

`oooconf secrets login` configures the CLI against the intended Bitwarden-compatible server. `oooconf secrets unlock` prints shell code that exports `BW_SESSION` in the caller's shell, and `oooconf secrets sync` then resolves the tracked template into local plaintext env files for Zsh and PowerShell. The initial backend is `Bitwarden CLI` with `bw://item/<item-id>/...` references, which keeps the source of truth outside git while preserving reproducible local file locations.

## Runtime State

Runtime state is intentionally untracked.

Examples:

- zsh history under `~/.local/state/ooodnakov-config/zsh/`
- zsh completion dumps under `~/.cache/ooodnakov-config/zsh/`
- setup logs under the repo-managed state directory

This prevents mutable local artifacts from leaking back into the reproducible source tree.

## Third-Party Reference Trees

`third_party/` exists for two reasons:

- upstream auditability
- selective extraction of ideas from larger external trees

Changes should normally land in `home/` or `scripts/`, not by replacing active config with reference snapshots.

## Validation

Current validation focuses on:

- shell syntax checks
- `shellcheck`
- PowerShell parser validation
- lock artifact reproducibility

When bootstrap or setup behavior changes, these checks should be updated alongside the relevant docs so the repo stays reproducible and explainable.
