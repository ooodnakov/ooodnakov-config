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

## What is also stored

- reference snapshot of upstream `ezsh`
- snapshot of the current local WezTerm fork from this machine
- audit notes from inspecting local config and remote hosts `orange` and `site`

These live under [`third_party`](/mnt/d/stufffromC/user/Documents/Gits/ooodnakov-config/third_party) and [`docs/imports`](/mnt/d/stufffromC/user/Documents/Gits/ooodnakov-config/docs/imports). They are not installed by the setup scripts.

## Upstream references

- [`jotyGill/ezsh`](https://github.com/jotyGill/ezsh) for the modular zsh layout idea
- [`KevinSilvester/wezterm-config`](https://github.com/KevinSilvester/wezterm-config) for the modular WezTerm structure

This repo keeps a smaller active config inspired by them, plus a few reference snapshots for audit and future extraction work.

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

These are loaded automatically by zsh and PowerShell and are meant for values you want to copy across machines.

Machine-only or secret values live in ignored files:

- `~/.config/ooodnakov/local/env.zsh`
- `~/.config/ooodnakov/local/env.ps1`
- `~/.ssh/config.local`

The shell and PowerShell profiles load both automatically.

Tracked shared environment currently covers:

- editor and pager defaults
- `NVM_DIR`
- `PNPM_HOME`
- `~/.local/bin`
- `~/.cargo/bin`
- optional `~/.local/bin/env` sourcing when present

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

## Audit notes

- import and comparison notes: [`docs/imports/upstream-audit.md`](/mnt/d/stufffromC/user/Documents/Gits/ooodnakov-config/docs/imports/upstream-audit.md)
- third-party reference trees: [`third_party/README.md`](/mnt/d/stufffromC/user/Documents/Gits/ooodnakov-config/third_party/README.md)
