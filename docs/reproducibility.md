# Reproducibility

## Goals

This repo should let you make a fresh Linux, Windows, or future macOS machine converge on the same terminal experience with minimal manual edits.

## Design

Tracked files:

- base shell config
- base WezTerm config
- PowerShell profile
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

`zsh` dependencies are not copied into the repo. They are installed into `~/.local/share/ooodnakov-config` on Unix-like systems at pinned commits:

- `oh-my-zsh`
- `powerlevel10k`
- `zsh-autosuggestions`
- `zsh-syntax-highlighting`
- `zsh-history-substring-search`
- `zsh-autocomplete`
- `fzf-tab`
- `auto-uv-env`

This keeps the repo small while still making bootstrap deterministic.
`auto-uv-env` is installed in a user-local layout that mirrors its upstream bin/share model without touching global system directories: a pinned source checkout lives under `~/.local/share/ooodnakov-config/src/auto-uv-env`, the executable is linked into `~/.local/share/ooodnakov-config/bin/auto-uv-env`, and the shell integration files are installed into `~/.local/share/ooodnakov-config/auto-uv-env`.
The Unix setup also normalizes permissions for the installed `oh-my-zsh` tree on every run, keeping directories at `755` and regular files at `644` so `compaudit` accepts the completion paths.

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

- `git`
- `zsh` on Linux/macOS
- `pwsh` on Windows if you want PowerShell Core
- `wezterm`
- `oh-my-posh`

Fonts are also manual for now. The tracked defaults assume a Nerd Font is installed, with `MesloLGS NF` preferred.
This repo bundles the Meslo font files under `fonts/meslo`; the Unix setup script installs them for the current user.

## Unified CLI and validation

The primary entrypoints are:

- `./scripts/ooodnakov.sh` on Unix
- `.\scripts\ooodnakov.ps1` on Windows

Phase-1 setup ergonomics are implemented with:

- `dry-run` command to preview setup actions without mutation
- `doctor` command to validate managed links and key tool presence after install

Phase-2 dependency audit ergonomics are implemented with:

- `./scripts/ooodnakov.sh lock` (or `.\scripts\ooodnakov.ps1 lock`) to regenerate lock artifacts from pinned refs
- `./scripts/ooodnakov.sh update-pins` to compare pinned refs with remote HEAD and append an audit summary
- `./scripts/ooodnakov.sh update-pins --apply` to update pinned refs in `scripts/setup.sh`, then regenerate lock artifacts
- `update-pins` workflows are implemented in Python so both Unix and PowerShell CLIs use the same logic


## Phase-3 ergonomics

- `oooconf` command is linked to `~/.local/bin/oooconf` by Unix setup so the unified CLI can be invoked from any directory.
- WezTerm startup supports `OOODNAKOV_WEZTERM_WORKSPACE` and `OOODNAKOV_WEZTERM_CWD` for project-scoped startup defaults without editing tracked config.
