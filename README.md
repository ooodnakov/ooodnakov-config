# ooodnakov-config

Reproducible personal dotfiles for:

- Linux
- Windows
- macOS

The repo keeps only opinionated config and bootstrap logic. Secrets, tokens, keys, and machine-specific overrides stay outside git in local override files.

## What is managed

- `zsh` with `oh-my-zsh` and pinned plugin/theme checkouts
- `wezterm`
- PowerShell profile
- `oh-my-posh`
- shared SSH host include config

## Upstream references

- [`jotyGill/ezsh`](https://github.com/jotyGill/ezsh) for the modular zsh layout idea
- [`KevinSilvester/wezterm-config`](https://github.com/KevinSilvester/wezterm-config) for the modular WezTerm structure

This repo does not vendor those projects. It keeps a smaller, reproducible setup inspired by them.

## Quick start

### Linux or macOS

```bash
git clone git@github.com:ooodnakov/ooodnakov-config.git ~/src/ooodnakov-config
cd ~/src/ooodnakov-config
./scripts/setup.sh
```

### Windows PowerShell

```powershell
git clone git@github.com:ooodnakov/ooodnakov-config.git $HOME\src\ooodnakov-config
Set-Location $HOME\src\ooodnakov-config
.\scripts\setup.ps1
```

## Environment layout

Portable environment variables live in tracked files:

- `~/.config/ooodnakov/env/common.sh`
- `~/.config/ooodnakov/env/common.ps1`

Machine-only or secret values live in ignored files:

- `~/.config/ooodnakov/local/env.zsh`
- `~/.config/ooodnakov/local/env.ps1`
- `~/.ssh/config.local`

The shell and PowerShell profiles load both automatically.

## Local-only files

Create these on each machine as needed:

- `~/.config/ooodnakov/local/env.zsh`
- `~/.config/ooodnakov/local/env.ps1`
- `~/.config/ooodnakov/local/wezterm.lua`
- `~/.ssh/config.local`

Examples are tracked in [`home/.config/ooodnakov/local`](/mnt/d/stufffromC/user/Documents/Gits/ooodnakov-config/home/.config/ooodnakov/local).

## Reproducibility rules

- Third-party shell dependencies are installed at pinned commits by the setup script.
- Tracked config is symlinked into standard OS locations.
- Shared environment is tracked and loaded automatically.
- Local secrets are sourced from ignored files only.
- Machine-specific shell paths and hostnames belong in local override files, not tracked config.

More detail: [`docs/reproducibility.md`](/mnt/d/stufffromC/user/Documents/Gits/ooodnakov-config/docs/reproducibility.md)
