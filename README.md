# ooodnakov-config

Reproducible personal dotfiles for:

- Linux
- Windows
- macOS

The repo keeps only opinionated config and bootstrap logic. Secrets, tokens, keys, and machine-specific overrides stay outside git in local override files.

## What is managed

- `zsh` with `oh-my-zsh`, pinned plugin/theme checkouts, built-in `direnv` plugin support, and pinned `auto-uv-env`
- pinned Zsh completion stack including `fzf-tab`
- managed shell helpers: `nvm`, `k`, `marker`, `todo.txt-cli`
- `LazyVim` starter config (managed in `~/.config/nvim`)
- optional CLI tools prompted during setup: `fzf`, `eza`, `dua-cli`
- dependency lock artifacts (`deps.lock.json`, `docs/dependency-lock.md`) generated from pinned setup refs
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
When run in a real terminal, bootstrap/setup also prompt for missing dependencies based on the `ezsh` workflow, including `git`, `zsh`, `wget`, `fzf`, `eza`, `dua-cli`, `node`, `npm`, `python3`, `uv`, `cargo`, `autoconf`, `fontconfig`, and `neovim` (`nvim`). Prompts read from `/dev/tty`, so they work correctly even with `curl | bash`.
For `eza`, setup only auto-installs on package-manager paths that match upstream guidance directly; Debian/Ubuntu and some Fedora setups are left as manual installs instead of guessing.
The Unix setup also installs pinned copies of `fzf-tab`, `auto-uv-env`, `nvm`, `k`, `marker`, and `todo.txt-cli`.
For `auto-uv-env`, setup keeps a pinned source checkout under the repo-managed XDG data tree, links the executable into `~/.local/share/ooodnakov-config/bin`, and installs the shell integration files into `~/.local/share/ooodnakov-config/auto-uv-env`.
It also normalizes the installed `oh-my-zsh` tree permissions on every run so `compaudit` and `compinit` do not abort on group-writable plugin directories.

### Linux or macOS

```bash
git clone git@github.com:ooodnakov/ooodnakov-config.git ~/src/ooodnakov-config
cd ~/src/ooodnakov-config
chmod +x ./scripts/setup.sh
./scripts/setup.sh
```

Unified CLI (recommended):

```bash
chmod +x ./scripts/ooodnakov.sh
./scripts/ooodnakov.sh install
```

Setup now also links a convenience command into `~/.local/bin/oooconf`, so you can run `oooconf install`, `oooconf doctor`, etc. directly from your terminal.

To update an existing machine from the repo and reapply the managed config:

```bash
cd ~/src/ooodnakov-config
./scripts/setup.sh update
```

or:

```bash
./scripts/ooodnakov.sh update
```

This also preserves replaced files by moving them into timestamped backups under `~/.local/state/ooodnakov-config/backups/`.
In interactive terminals it also offers to install common optional dependencies via the detected package manager.
It also reapplies safe `oh-my-zsh` directory and file modes on every run.
At the end of setup it also sources `~/.zshrc` inside the installer process, but you may still want to open a fresh shell session for a fully clean environment.

You can also rerun the bootstrap:

```bash
curl -fsSL https://raw.githubusercontent.com/ooodnakov/ooodnakov-config/main/bootstrap.sh | bash
```

For unattended runs, disable prompts:

```bash
OOODNAKOV_INTERACTIVE=never ./scripts/setup.sh update
```

Preview setup actions without changing the system:

```bash
./scripts/ooodnakov.sh dry-run
```

Run post-install checks:

```bash
./scripts/ooodnakov.sh doctor
```

Run dependency lock generation and pin audit helpers:

```bash
./scripts/ooodnakov.sh lock
./scripts/ooodnakov.sh update-pins
# optional: apply latest HEAD refs into scripts/setup.sh
./scripts/ooodnakov.sh update-pins --apply
```

Workspace ergonomics (Phase 3):

- set `OOODNAKOV_WEZTERM_WORKSPACE` to choose startup workspace name
- set `OOODNAKOV_WEZTERM_CWD` to choose startup working directory

Example:

```bash
OOODNAKOV_WEZTERM_WORKSPACE=project-x OOODNAKOV_WEZTERM_CWD=$HOME/src/project-x wezterm
```

### Windows PowerShell

```powershell
git clone git@github.com:ooodnakov/ooodnakov-config.git $HOME\src\ooodnakov-config
Set-Location $HOME\src\ooodnakov-config
.\scripts\setup.ps1
```

Unified PowerShell CLI (recommended):

```powershell
.\scripts\ooodnakov.ps1 install
.\scripts\ooodnakov.ps1 dry-run
.\scripts\ooodnakov.ps1 doctor
```

Dependency lock and pin update helpers are also exposed in PowerShell:

```powershell
.\scripts\ooodnakov.ps1 lock
.\scripts\ooodnakov.ps1 update-pins
.\scripts\ooodnakov.ps1 update-pins -Apply
```

Both commands require `python3` to be available on `PATH`.

On Windows, the PowerShell setup can also prompt to install missing core tools with `winget` (like WezTerm and `oh-my-posh`) and `choco` (like `gsudo`, `ripgrep`, and `fd`). If Chocolatey is missing, setup will offer to install it. Replaced files are now also preserved by moving them into timestamped backups under `$HOME\.local\state\ooodnakov-config\backups\`.

## Removal

To remove the managed Unix symlinks and restore the latest backups when available:

```bash
cd ~/src/ooodnakov-config
chmod +x ./scripts/delete.sh
./scripts/delete.sh
```

or via unified CLI:

```bash
./scripts/ooodnakov.sh delete
```

To remove only the managed links without restoring backups:

```bash
./scripts/delete.sh remove
```

or:

```bash
./scripts/ooodnakov.sh remove
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

Runtime shell artifacts are intentionally not tracked. Zsh history is written under `~/.local/state/ooodnakov-config/zsh/` and the completion dump under `~/.cache/ooodnakov-config/zsh/`.

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
