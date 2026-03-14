# ooodnakov-config

Reproducible personal dotfiles for:

- Linux
- Windows
- macOS

The repo keeps only opinionated config and bootstrap logic. Secrets, tokens, keys, and machine-specific overrides stay outside git in local override files.

## What is managed

- `zsh` with `oh-my-zsh` and pinned plugin/theme checkouts
- managed shell helpers: `k`, `marker`, `todo.txt-cli`
- `wezterm`
- PowerShell profile
- `oh-my-posh`
- shared SSH host include config

## What is also stored

- subtree-managed upstream copy of `ezsh`
- snapshot of the current local WezTerm fork from this machine
- bundled `MesloLGS NF` font files used by the shell and WezTerm defaults
- audit notes from inspecting local config and remote hosts `orange` and `site`

These live under [`third_party`](/mnt/d/stufffromC/user/Documents/Gits/ooodnakov-config/third_party) and [`docs/imports`](/mnt/d/stufffromC/user/Documents/Gits/ooodnakov-config/docs/imports). They are not installed by the setup scripts.

## Upstream references

- [`jotyGill/ezsh`](https://github.com/jotyGill/ezsh) for the modular zsh layout idea
- [`KevinSilvester/wezterm-config`](https://github.com/KevinSilvester/wezterm-config) for the modular WezTerm structure

This repo keeps a smaller active config inspired by them, plus a few upstream/reference trees for audit and future extraction work.

## Quick start

### One-line bootstrap

```bash
curl -fsSL https://raw.githubusercontent.com/ooodnakov/ooodnakov-config/main/bootstrap.sh | bash
```

This clones the repo into `~/src/ooodnakov-config` by default and runs the normal Unix setup.
If the repo is already present there, it is updated in place first.
If managed target files already exist, they are moved into timestamped backups under `~/.local/state/ooodnakov-config/backups/`.
When run in a real terminal, bootstrap/setup also prompt for missing dependencies based on the `ezsh` workflow, including `git`, `zsh`, `wget`, `fzf`, `eza`, `autoconf`, `python3`, and `fontconfig`. Prompts read from `/dev/tty`, so they work correctly even with `curl | bash`.
The Unix setup also installs pinned copies of `k`, `marker`, and `todo.txt-cli`.

### Linux or macOS

```bash
git clone git@github.com:ooodnakov/ooodnakov-config.git ~/src/ooodnakov-config
cd ~/src/ooodnakov-config
chmod +x ./scripts/setup.sh
./scripts/setup.sh
```

To update an existing machine from the repo and reapply the managed config:

```bash
cd ~/src/ooodnakov-config
./scripts/setup.sh update
```

This also preserves replaced files by moving them into timestamped backups under `~/.local/state/ooodnakov-config/backups/`.
In interactive terminals it also offers to install common optional dependencies via the detected package manager.
At the end of setup it also sources `~/.zshrc` inside the installer process, but you may still want to open a fresh shell session for a fully clean environment.

You can also rerun the bootstrap:

```bash
curl -fsSL https://raw.githubusercontent.com/ooodnakov/ooodnakov-config/main/bootstrap.sh | bash
```

For unattended runs, disable prompts:

```bash
OOODNAKOV_INTERACTIVE=never ./scripts/setup.sh update
```

### Windows PowerShell

```powershell
git clone git@github.com:ooodnakov/ooodnakov-config.git $HOME\src\ooodnakov-config
Set-Location $HOME\src\ooodnakov-config
.\scripts\setup.ps1
```

On Windows, the PowerShell setup can also prompt to install missing core tools with `winget`, including WezTerm and `oh-my-posh`.

## Removal

To remove the managed Unix symlinks and restore the latest backups when available:

```bash
cd ~/src/ooodnakov-config
chmod +x ./scripts/delete.sh
./scripts/delete.sh
```

To remove only the managed links without restoring backups:

```bash
./scripts/delete.sh remove
```

## Fonts

The repo now includes the Meslo Nerd Font files used by the tracked prompt and WezTerm config:

- [`fonts/meslo`](/mnt/d/stufffromC/user/Documents/Gits/ooodnakov-config/fonts/meslo)

On Linux, `./scripts/setup.sh` installs these into `~/.local/share/fonts/ooodnakov` and refreshes the font cache when `fc-cache` is available.

On Windows and macOS, the files are bundled here for manual installation if needed.

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
