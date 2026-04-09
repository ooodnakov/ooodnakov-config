# ooodnakov-config

Reproducible personal dotfiles for Linux, Windows, and future macOS machines.

This repo tracks the opinionated base config and bootstrap logic only. Secrets, tokens, private keys, and host-specific overrides stay outside git in local files.

## What This Repo Manages

Active tracked config lives under `home/` and includes:

- `zsh` and modular zsh config
- pinned shell dependencies and helpers
- WezTerm config
- PowerShell profile
- `oh-my-posh` config
- shared portable environment files
- shared SSH host include config
- LazyVim starter config under `~/.config/nvim`

Bootstrap and maintenance entrypoints live under `scripts/`:

- `scripts/setup.sh`
- `scripts/setup.ps1`
- `scripts/ooodnakov.sh`
- `scripts/ooodnakov.ps1`

Generated lock artifacts:

- `deps.lock.json`
- `docs/dependency-lock.md`

Reference-only material lives under `third_party/` and `docs/imports/`. It is stored for auditability and extraction work, not as active config.

## Repo Layout

- `home/`: managed config that gets linked into the user profile
- `scripts/`: install, update, doctor, delete, and pin-management commands
- `docs/`: reproducibility notes and import audits
- `third_party/`: upstream and local reference trees
- `fonts/meslo/`: bundled Meslo Nerd Font files used by the prompt and terminal defaults

## Quick Start

### Bootstrap on Unix-like systems

```bash
curl -fsSL https://raw.githubusercontent.com/ooodnakov/ooodnakov-config/main/bootstrap.sh | bash
```

This clones the repo into `~/src/ooodnakov-config` by default, updates it in place if it already exists, and runs the normal Unix install flow.

### Manual install on Linux or macOS

```bash
git clone git@github.com:ooodnakov/ooodnakov-config.git ~/src/ooodnakov-config
cd ~/src/ooodnakov-config
./home/.config/ooodnakov/bin/oooconf install
```

Before first install, the repo-local `oooconf` script is the intended entrypoint. After install, setup links `oooconf` into `~/.local/bin`, so you can run:

```bash
oooconf install
oooconf update
oooconf dry-run
oooconf doctor
```

### Windows PowerShell

```powershell
git clone git@github.com:ooodnakov/ooodnakov-config.git $HOME\src\ooodnakov-config
Set-Location $HOME\src\ooodnakov-config
.\scripts\ooodnakov.ps1 install
```

After setup, `oooconf` is linked into `$HOME\.local\bin`, and the managed PowerShell profile prepends that directory to `PATH`, so the same commands work in new sessions:

```powershell
oooconf install
oooconf update
oooconf dry-run
oooconf doctor
```

## CLI Entry Points

Primary commands:

- `oooconf install`: apply managed config and optional dependency installs
- `oooconf update`: fast-forward pull the repo, then rerun install
- `oooconf dry-run`: preview setup actions without changing the system
- `oooconf doctor`: validate managed links and key tools
- `oooconf delete`: remove managed links and restore latest backups when available
- `oooconf remove`: remove managed links without restoring backups
- `oooconf lock`: regenerate dependency lock artifacts
- `oooconf update-pins`: compare pinned refs with upstream HEAD and refresh lock artifacts
- `oooconf update-pins --apply`: update pinned refs in setup scripts, then regenerate lock artifacts

Useful flags:

- `oooconf --help`
- `oooconf help <command>`
- `oooconf --print-repo-root`
- `oooconf --version`

For unattended runs:

```bash
OOODNAKOV_INTERACTIVE=never oooconf update
```

## Install Behavior

Setup symlinks tracked config into standard locations and preserves replaced files by moving them into timestamped backups:

- Unix: `~/.local/state/ooodnakov-config/backups/`
- Windows: `$HOME\.local\state\ooodnakov-config\backups\`

Each install, update, or doctor run also writes logs under:

- Unix: `~/.local/state/ooodnakov-config/logs/`
- Windows: `$HOME\.local\state\ooodnakov-config\logs\`

`setup-latest.log` points to the latest run.

In interactive terminals, setup can also prompt to install common optional dependencies.

## Pinned Dependencies

The repo aims for deterministic setup by pinning third-party shell dependencies and related tooling.

Unix setup installs pinned copies of:

- `oh-my-zsh`
- `powerlevel10k`
- `zsh-autosuggestions`
- `zsh-syntax-highlighting`
- `zsh-history-substring-search`
- `zsh-autocomplete`
- `fzf-tab`
- `auto-uv-env`
- `nvm`
- `k`
- `marker`
- `todo.txt-cli`

Additional setup behavior:

- `uv` uses Astral's official installer
- `pnpm` uses a pinned version via `corepack`, or falls back to `npm install --global`
- `dua-cli` installs from `byron/dua-cli` via `cargo`
- Linux setup requires `nvim >= 0.11.0` for LazyVim and falls back to a pinned official Neovim tarball if the distro package is too old
- setup normalizes `oh-my-zsh` permissions on every run so `compaudit` and `compinit` do not reject the install

On Windows, setup can prompt to install common tools with `winget` and `choco`, including WezTerm, Node.js LTS, `oh-my-posh`, `ripgrep`, and `fd`. It also offers to install Chocolatey if needed.

## Fonts

Bundled Meslo Nerd Font files live in [`fonts/meslo`](/mnt/c/Users/coolk/src/ooodnakov-config/fonts/meslo).

On Linux, `oooconf install` installs them into `~/.local/share/fonts/ooodnakov` and refreshes the font cache when `fc-cache` is available.

On Windows and macOS, the font files are bundled for manual installation if needed.

## Environment and Local Overrides

Portable tracked environment belongs in:

- `~/.config/ooodnakov/env/common.sh`
- `~/.config/ooodnakov/env/common.ps1`

Machine-specific or secret values belong in ignored files:

- `~/.config/ooodnakov/local/env.zsh`
- `~/.config/ooodnakov/local/env.ps1`
- `~/.ssh/config.local`

Additional local-only files you may create per machine:

- `~/.config/ooodnakov/local/wezterm.lua`

Examples live in [`home/.config/ooodnakov/local`](/mnt/c/Users/coolk/src/ooodnakov-config/home/.config/ooodnakov/local).

Runtime shell state is intentionally untracked:

- zsh history: `~/.local/state/ooodnakov-config/zsh/`
- zsh completion dump: `~/.cache/ooodnakov-config/zsh/`

## WezTerm Workspace Ergonomics

Set these environment variables to control WezTerm startup defaults without editing tracked config:

- `OOODNAKOV_WEZTERM_WORKSPACE`
- `OOODNAKOV_WEZTERM_CWD`

Example:

```bash
OOODNAKOV_WEZTERM_WORKSPACE=project-x OOODNAKOV_WEZTERM_CWD=$HOME/src/project-x wezterm
```

## CI/CD

- CI runs on pushes to `main` and pull requests
- Unix scripts are checked with Bash syntax validation and `shellcheck`
- lock artifacts are validated for reproducibility
- `scripts/setup.ps1` and `scripts/ooodnakov.ps1` are parser-validated
- tags matching `v*` publish `.tar.gz` and `.zip` source archives to GitHub Releases

## Upstream and Audit References

The active config is intentionally smaller than the reference material stored alongside it.

Upstream inspirations:

- [`jotyGill/ezsh`](https://github.com/jotyGill/ezsh)
- [`KevinSilvester/wezterm-config`](https://github.com/KevinSilvester/wezterm-config)

Reference docs:

- reproducibility notes: [`docs/reproducibility.md`](/mnt/c/Users/coolk/src/ooodnakov-config/docs/reproducibility.md)
- import and comparison notes: [`docs/imports/upstream-audit.md`](/mnt/c/Users/coolk/src/ooodnakov-config/docs/imports/upstream-audit.md)
- third-party tree notes: [`third_party/README.md`](/mnt/c/Users/coolk/src/ooodnakov-config/third_party/README.md)
