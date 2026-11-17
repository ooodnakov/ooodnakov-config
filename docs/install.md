# Installing ooodnakov-config

This page covers install prerequisites, install behavior, pinned dependencies, and bundled fonts for this repo.

## Prerequisites

The setup scripts intentionally do not try to provision a full workstation from bare metal: core tools must already exist before first install. The required system and terminal tools per platform are in the [Prerequisites table in the README](../README.md#prerequisites).

On Windows, `oooconf deps zsh` (from PowerShell) installs the pinned MSYS2 zsh package into the Git for Windows directory and Git Bash windows then start the managed zsh automatically. The bundled Meslo Nerd Font is installed per-user by setup and a managed `~/.minttyrc` pins mintty's `Font=`, so Git Bash windows render the same prompt icons as WezTerm. Set `OOODNAKOV_GITBASH_ZSH=0` to keep plain bash for a session. Ghostty is optional; when installed, its managed config mirrors the WezTerm theme and keybindings.

See [`reproducibility.md`](reproducibility.md) for the full dependency policy and [`architecture.md`](architecture.md) for the symlink, lockfile, and local-override model.

## Minimal Sparse Checkout

`bootstrap.sh minimal` performs the sparse checkout and links the minimal shell profile; `minimal` alone installs no packages, and `OOODNAKOV_SKIP_DEPS=1` is the explicit environment form of that behavior for direct `setup.sh` runs. To reproduce the checkout by hand, run:

```bash
git clone --filter=blob:none --no-checkout https://github.com/ooodnakov/ooodnakov-config.git ~/src/ooodnakov-config
git -C ~/src/ooodnakov-config sparse-checkout init --cone
git -C ~/src/ooodnakov-config sparse-checkout set scripts home/.zshrc home/.config/zsh home/.config/ooodnakov home/.config/ohmyposh home/.config/powershell bootstrap.sh LICENSE
git -C ~/src/ooodnakov-config checkout main
cd ~/src/ooodnakov-config
./scripts/setup/minimal-setup.sh
```

The partial checkout omits the reference snapshots, bundled fonts, and editor/desktop configs. Git, Bash, and Zsh are required; Python 3 is used by the link planner, with no `uv` environment or repository packages installed.

Release archives include `SHA256SUMS`. Verify an archive before extracting it; do not pipe a newly downloaded bootstrap script directly into a shell.

## Install Behavior

Setup symlinks tracked config into standard locations and preserves replaced files by moving them into timestamped backups:

- Unix: `~/.local/state/ooodnakov-config/backups/`
- Windows: `$HOME\.local\state\ooodnakov-config\backups\`

On Unix, that managed tree includes `~/.config/niri` linked from [`home/.config/niri`](../home/.config/niri), `~/.config/umbriel` linked from [`home/.config/umbriel`](../home/.config/umbriel), `~/.config/hypr` linked from [`home/.config/hypr`](../home/.config/hypr), `~/.config/pypr` linked from [`home/.config/pypr`](../home/.config/pypr), and `~/.config/noctalia` linked from [`home/.config/noctalia`](../home/.config/noctalia) alongside the existing shell, terminal, editor, and `ooodnakov` config links.

Each install, update, or doctor run also writes logs under:

- Unix: `~/.local/state/ooodnakov-config/logs/`
- Windows: `$HOME\.local\state\ooodnakov-config\logs\`

`setup-latest.log` points to the latest run.

In interactive terminals, setup can also prompt to install common optional dependencies. The full catalog lives in `scripts/optional-deps.toml`, which both Unix and PowerShell setup scripts read. Each entry defines per-platform install methods (apt, brew, choco, winget, cargo, curl, GitHub release archive, or custom).

### Installing Optional Dependencies

Use `oooconf deps` to install optional tools interactively or specifically:

- `oooconf deps` — Interactive picker (requires `gum`).
- `oooconf deps --min-dep` — Install only the `[minimal]` dependency set (git, zsh, uv, gum, rg, fd, bat, delta, jq, unzip, bin, topgrade, brew, node, pnpm, bun, eza, zoxide, lazydocker, lazygit, oh-my-pi; `oh-my-posh` on Windows only). `--minimal` remains accepted as an alias for this command.
- `oooconf deps <key...>` — Install specific tools (e.g., `oooconf deps yazi p7zip`).
- `oooconf deps --latest <key...>` — Install missing selections, then run Topgrade with bounded retries; its native `bin` step updates tracked GitHub releases. `GITHUB_AUTH_TOKEN` (or `GITHUB_TOKEN`) is forwarded to GitHub release updates.
- `oooconf deps bin topgrade` — Explicitly install the two primary dependency-management tools; they are also part of the minimal/install bootstrap flow.
- `oooconf deps docker` — Install Docker Engine on Linux with the distribution's official procedure (apt repo on Ubuntu/Debian, pacman on Arch, dnf repo on Fedora), then enable the Docker/containerd units. macOS/Windows need Docker Desktop; manual steps and fallbacks live in [`docker-install.md`](docker-install.md).
- `oooconf deps brew` — Install Homebrew on macOS or Linux with Homebrew's official installer.
- `oooconf deps taskwarrior` — Install Taskwarrior through Homebrew (`task`) on Linux and macOS; Linux apt packages are intentionally avoided. Install Homebrew first if needed.
- `oooconf deps worktrunk` — Install Worktrunk for parallel Git worktrees (Homebrew on Linux/macOS, winget on Windows). Managed Zsh and PowerShell profiles enable its shell integration when installed; use `git-wt` on Windows to avoid Windows Terminal's `wt` alias.
- `oooconf deps docker` — On systemd Linux, enable and start existing Docker/containerd units at boot.
- `oooconf deps --dry-run` — Preview without installing.

All metadata is in `scripts/optional-deps.toml` (sole source of truth). Run `oooconf lock` after editing.
GitHub release installs select the catalog's platform asset explicitly, avoiding interactive asset-selection prompts from `bin`.
After dependency setup on Unix and PowerShell, catalog GitHub release binaries in the managed install directories are adopted into `bin` tracking without re-downloading, including tools omitted from the selection. Run `oooconf deps bin` to pick up earlier installs. Adoption reads their installed versions, preserves existing tracking records, and respects `--dry-run`.
Topgrade runs in the foreground so upgrade progress and prompts remain visible. `--latest` disables Topgrade self-update, retries failed steps twice, and reports remaining manager failures as warnings so completed dependency installs are not discarded. Set `OOODNAKOV_DEPS_LATEST_STRICT=1` to make those orchestration failures fatal.

See [`dependency-decisions.md`](dependency-decisions.md) for the full decision matrix.

During `oooconf install` and `oooconf update`, LazyVim plugin sync runs headlessly with progress-only output. Detailed Neovim plugin logs stay hidden unless the sync fails.

### Windows setup details

On Windows, setup also links `oooconf` into `$HOME\.local\bin` and the managed PowerShell profile prepends that directory to `PATH`, so `oooconf install`, `oooconf doctor`, and similar commands work directly in new shell sessions. It also links the tracked PowerShell profile into both `$HOME\.config\powershell\Microsoft.PowerShell_profile.ps1` and the active `$PROFILE.CurrentUserCurrentHost` path, so the XDG-style source of truth and the profile PowerShell actually loads stay in sync.
The PowerShell setup can also prompt to install missing optional tools via the catalog in `scripts/optional-deps.toml` (using winget, choco, official nodejs.org Node.js archives, corepack/pnpm, PowerShell Gallery, or custom methods). It offers to bootstrap Chocolatey if needed. Replaced files are preserved in timestamped backups under `$HOME\.local\state\ooodnakov-config\backups\`.
Windows setup runs also write debug logs under `$HOME\.local\state\ooodnakov-config\logs\`, with `setup-latest.log` updated to the latest run.

## Pinned Dependencies

The repo aims for deterministic setup by pinning third-party shell dependencies and related tooling.

See [`dependency-decisions.md`](dependency-decisions.md) for the full list of automated, optional, and manual dependencies and how they are installed per platform.
See `deps.lock.json` for the exact pinned git revisions used by the setup scripts.
Unix setup installs the configured custom Zsh plugins, including `zsh-fzf-unified` and `s3cmd`; `oooconf doctor` checks their OMZ entrypoints. Autocomplete loads before OMZ completion initialization, and syntax highlighting loads last.

The tracked `oh-my-posh` theme honors `OOOCONF_PROMPT_STYLE` and is regenerated by `oooconf color` with the selected oooconf palette. It uses its own unified `git` segment in [home/.config/ohmyposh/ooodnakov.omp.json](../home/.config/ohmyposh/ooodnakov.omp.json). It provides a clean, single-branch status with detailed working and staging information. The PowerShell profile still imports `posh-git` to provide git command completions, but prompt rendering is handled entirely by Oh My Posh for a consistent look.

## Fonts

Bundled Meslo Nerd Font files live in [`fonts/meslo`](../fonts/meslo).

On Linux, `oooconf install` installs them into `~/.local/share/fonts/ooodnakov` and refreshes the font cache when `fc-cache` is available.

On Windows, setup installs them per-user and registers them in the Windows font store. `install --dry-run` previews this step without copying fonts, writing registry entries, or notifying applications. On macOS, the bundled font files remain available for manual installation.
