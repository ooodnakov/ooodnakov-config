# Reproducibility

## Goals

This repo should let you make a fresh Linux, Windows, or future macOS machine converge on the same terminal experience with minimal manual edits.

## Design

Tracked files:

- base shell config
- base WezTerm config
- base LazyVim/Neovim config
- PowerShell profile
- Python `uv` environment (`pyproject.toml`, `.python-version`, `uv.lock`)
- prompt config
- shared environment files
- shared SSH host definitions
- install scripts

Ignored files:

- API tokens
- SSH private keys
- host-specific shell paths
- machine-only WezTerm domains
- runtime shell artifacts such as history and completion dumps

## Dependency policy

`zsh` dependencies and other third-party utilities are intentionally not committed into the repo.

See [`dependency-decisions.md`](dependency-decisions.md) for the full list of automated, optional, and manual dependencies and how they are installed per platform.
See [`dependency-lock.md`](dependency-lock.md) for the exact pinned git revisions used by the setup scripts.

This keeps the repo small while still making bootstrap deterministic.

Shell runtime state is kept outside the tracked config tree:

- zsh history: `~/.local/state/ooodnakov-config/zsh/history`
- zsh completion dump: `~/.cache/ooodnakov-config/zsh/.zcompdump-<host>-<zsh-version>`

## SSH policy

The tracked SSH file is an include fragment, not a full private SSH directory. It is safe to version because it contains host aliases only.

Keys remain in:

- `~/.ssh/id_*`
- `%USERPROFILE%\.ssh\id_*`

Local-only additions can go into:

- `~/.ssh/config.local`

## Machine overrides

Use local override files for anything that changes by host:

- shell environment variables
- secrets
- internal hostnames or IPs you do not want tracked
- WezTerm launch commands tied to one machine
- OS package manager tweaks

## Manual prerequisites

The bootstrap scripts intentionally do not install every package manager package for you. They assume the machine already has:

- Linux/macOS: `git`, `zsh`
- Windows: `git`, `pwsh` if you want PowerShell Core
- all platforms: `wezterm`, `oh-my-posh`

Fonts are also manual for now. The tracked defaults assume a Nerd Font is installed, with `MesloLGSDZ Nerd Font Mono` preferred.
This repo bundles the Meslo font files under `fonts/meslo`; the Unix setup script installs them for the current user.

For Neovim, the Unix setup validates `nvim >= 0.11.0` for LazyVim. On Linux, if the distro package manager only provides an older version, setup installs the pinned official Neovim release tarball into the repo-managed XDG data tree and links `nvim` from there.
For `pnpm`, the tracked shell environment reserves `PNPM_HOME`, and setup installs a pinned version through `corepack` when available or through `npm` into that path otherwise.

## Bootstrap trust model

The fastest Unix bootstrap path is still `curl ... | bash`, but that is a trust tradeoff, not the recommended review path.

For a new machine or any time you want to inspect changes first, prefer:

1. clone the repo
2. review `bootstrap.sh`, `scripts/setup.sh`, and the tracked config under `home/`
3. run the repo-local `oooconf` entrypoint directly

That keeps the initial setup auditable while preserving the same install behavior.

## CLI Surface

See [`architecture.md`](architecture.md) for details on the `oooconf` command layout, phases, validation, and ergonomics.
