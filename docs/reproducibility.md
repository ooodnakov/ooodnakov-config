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

## Dependency policy

`zsh` dependencies are not copied into the repo. They are installed into `~/.local/share/ooodnakov-config` on Unix-like systems at pinned commits:

- `oh-my-zsh`
- `powerlevel10k`
- `zsh-autosuggestions`
- `zsh-syntax-highlighting`
- `zsh-history-substring-search`

This keeps the repo small while still making bootstrap deterministic.

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
