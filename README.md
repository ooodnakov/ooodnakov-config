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

### Preferred install path on Linux or macOS

```bash
git clone git@github.com:ooodnakov/ooodnakov-config.git ~/src/ooodnakov-config
cd ~/src/ooodnakov-config
./home/.config/ooodnakov/bin/oooconf install
```

This is the recommended path because it lets you inspect the tracked config and setup scripts before they make changes on the machine.

Before first install, the repo-local `oooconf` script is the intended entrypoint. After install, setup links `oooconf` into `~/.local/bin`, so you can run:

```bash
oooconf install
oooconf deps
oooconf update
oooconf dry-run
oooconf doctor
```

### Bootstrap shortcut on Unix-like systems

```bash
curl -fsSLo /tmp/ooodnakov-bootstrap.sh https://raw.githubusercontent.com/ooodnakov/ooodnakov-config/main/bootstrap.sh
less /tmp/ooodnakov-bootstrap.sh
bash /tmp/ooodnakov-bootstrap.sh
```

If you already trust the repo and want the one-liner, this also works:

```bash
curl -fsSL https://raw.githubusercontent.com/ooodnakov/ooodnakov-config/main/bootstrap.sh | bash
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
oooconf deps
oooconf update
oooconf dry-run
oooconf doctor
```

## CLI Entry Points

Primary commands:

- `oooconf install`: apply managed config and optional dependency installs
- `oooconf deps`: install optional dependencies only, with a multi-select picker when `gum` is available
- `oooconf update`: fast-forward pull the repo, then rerun install
- `oooconf dry-run`: preview setup actions without changing the system
- `oooconf doctor`: validate managed links and key tools
- `oooconf delete`: remove managed links and restore latest backups when available (Unix only)
- `oooconf remove`: remove managed links without restoring backups (Unix only)
- `oooconf bootstrap`: clone/update repo then run install (Unix only)
- `oooconf lock`: regenerate dependency lock artifacts
- `oooconf update-pins`: compare pinned refs with upstream HEAD and refresh lock artifacts
- `oooconf update-pins --apply`: update pinned refs in setup scripts, then regenerate lock artifacts
- `oooconf agents detect`: report configured AI agent CLIs available on `PATH`
- `oooconf agents sync`: append/update shared managed AGENTS.md policy sections
- `oooconf agents doctor`: verify AGENTS.md managed sections and common MCP/skills content

The helper scripts use `uv` for Python version and dependency management. If `uv` is available, scripts will run in the pinned Python environment (defined in `.python-version` and `pyproject.toml`). If `uv` is missing, they fall back to the system `python3`.

Secrets commands:

- `oooconf secrets login`: configure Bitwarden/Vaultwarden server and start login
- `oooconf secrets unlock --shell zsh`: print shell code to export `BW_SESSION`
- `oooconf secrets sync`: render local secret env files from the tracked template, creating missing `env.zsh`/`env.ps1`
- `oooconf secrets sync --dry-run`: preview rendered files without writing
- `oooconf secrets list`: list secrets from the template (add `--resolved` to resolve `bw://` refs)
- `oooconf secrets status`: check sync state and vault status
- `oooconf secrets doctor`: validate prerequisites and rendered files
- `oooconf secrets logout`: lock vault and revoke the Bitwarden session
- `oooconf shell forgit-aliases [plain|forgit|status]`: choose whether short git aliases stay plain or switch to upstream `forgit` aliases

On Windows, setup also links `oooconf` into `$HOME\.local\bin` and the managed PowerShell profile prepends that directory to `PATH`, so `oooconf install`, `oooconf doctor`, and similar commands work directly in new shell sessions. It also links the tracked PowerShell profile into both `$HOME\.config\powershell\Microsoft.PowerShell_profile.ps1` and the active `$PROFILE.CurrentUserCurrentHost` path, so the XDG-style source of truth and the profile PowerShell actually loads stay in sync.
The PowerShell setup can also prompt to install missing core tools with `winget` (like WezTerm, Node.js LTS, `git`, `nvim`, `oh-my-posh`, `gum`, `yazi`, `ffmpeg`, `jq`, `7zip`, and `poppler`) and `choco` (like `gsudo`, `ripgrep`, `fd`, `direnv`, `fzf`, `bat`, `delta`, `glow`, `q`, `eza`, `uv`, and `python`). It also offers to install `pnpm`, preferring `corepack` and falling back to `npm`. If Chocolatey is missing, setup will offer to install it. Replaced files are now also preserved by moving them into timestamped backups under `$HOME\.local\state\ooodnakov-config\backups\`.
Windows setup runs also write debug logs under `$HOME\.local\state\ooodnakov-config\logs\`, with `setup-latest.log` updated to the latest run.

Shell completion:

- **PowerShell**: argument completion is automatically loaded by the managed profile
  - Complete commands: `oooconf <Tab>`
  - Complete options: `oooconf install --<Tab>`
  - Complete secrets subcommands: `oooconf secrets <Tab>`
  - Complete shell values: `oooconf secrets unlock --shell <Tab>`
- **Zsh**: completion is provided via fzf-tab integration

Help system:

- `oooconf --help` — shows grouped command categories with common workflow examples
- `oooconf help <command>` — shows command-specific help with examples and environment overrides
- `oooconf --print-repo-root`
- `oooconf --version`

For unattended runs:

```bash
OOODNAKOV_INTERACTIVE=never oooconf update
oooconf update --yes-optional
```

Interactive dependency picks:

```bash
# interactive multi-select picker (requires gum)
oooconf deps
# without gum: text prompt lists available keys, type to select
oooconf deps
# explicit keys (no prompt)
oooconf deps bat delta glow
```

Agent policy management:

```bash
oooconf agents detect
oooconf agents sync
oooconf agents doctor
```

The shared AGENTS policy snippets are configured in:

- `home/.config/ooodnakov/agents/config.json`
- `home/.config/ooodnakov/agents/common-text.md`
- `home/.config/ooodnakov/agents/common-data.json` (structured MCP + skills data)

`oooconf agents doctor` also checks common MCP/skills markers against default agent config paths by format (JSON, TOML, YAML). Use `oooconf agents doctor --strict-config-paths` to fail when none of an agent's documented default config paths exist locally.

## Prerequisites

The setup scripts intentionally do not try to provision a full workstation from bare metal. Core tools should already exist before first install:

- Linux/macOS: `git`, `zsh`
- Windows: `git`, `pwsh` if PowerShell Core is desired
- all platforms: `wezterm`, `oh-my-posh`

See [`docs/reproducibility.md`](docs/reproducibility.md) for the full dependency policy and [`docs/architecture.md`](docs/architecture.md) for the symlink, lockfile, and local-override model.

## Install Behavior

Setup symlinks tracked config into standard locations and preserves replaced files by moving them into timestamped backups:

- Unix: `~/.local/state/ooodnakov-config/backups/`
- Windows: `$HOME\.local\state\ooodnakov-config\backups\`

Each install, update, or doctor run also writes logs under:

- Unix: `~/.local/state/ooodnakov-config/logs/`
- Windows: `$HOME\.local\state\ooodnakov-config\logs\`

`setup-latest.log` points to the latest run.

In interactive terminals, setup can also prompt to install common optional dependencies. The full catalog lives in `scripts/optional-deps.toml`, which both Unix and PowerShell setup scripts read. Each entry defines per-platform install methods (apt, brew, choco, winget, cargo, curl, or custom).

To add or remove an optional dependency, edit the TOML file and run `oooconf lock`. See [`docs/dependency-decisions.md`](docs/dependency-decisions.md) for the full decision matrix.

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
- `forgit`
- `zsh-you-should-use`
- `auto-uv-env`
- `nvm`
- `k`
- `marker`
- `todo.txt-cli`

Additional setup behavior:

- `zoxide` is installed via the system package manager when available and initialized as `z`/`zi` in `zsh`
- `bat` is installed via the system package manager when available as a `cat` alternative with syntax highlighting
- `delta` is installed via the system package manager when available as a Git diff pager with syntax highlighting
- `glow` is installed via the system package manager when available as a terminal Markdown reader
- `gum` is installed via the official Charm package source when needed for the interactive dependency picker, or via the system package manager where available
- `q` is installed via the upstream natesales APT repo on Debian/Ubuntu, or via the system package manager when available elsewhere
- `yazi` is available as an optional terminal file manager
- `ffmpeg`, `jq`, `p7zip`, and `poppler` are available as optional companion tools for richer Yazi previews/plugins
- `uv` uses Astral's official installer
- `bw` uses Bitwarden's official native CLI release archive
- `pnpm` uses a pinned version via `corepack`, or falls back to `npm install --global`
- `dua-cli` installs from `byron/dua-cli` via `cargo`
- Linux setup requires `nvim >= 0.11.0` for LazyVim and falls back to a pinned official Neovim tarball if the distro package is too old
- setup normalizes `oh-my-zsh` permissions on every run so `compaudit` and `compinit` do not reject the install

On Windows, setup can prompt to install common tools with `winget` and `choco`, including WezTerm, Node.js LTS, `oh-my-posh`, `gum`, `ripgrep`, `fd`, `bat`, `delta`, `glow`, `q`, `yazi`, `ffmpeg`, `jq`, `7zip`, and `poppler`. It also offers to install Chocolatey if needed. `bw` is installed from Bitwarden's official Windows zip into `~/.local/bin`.

## Fonts

Bundled Meslo Nerd Font files live in [`fonts/meslo`](fonts/meslo).

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

Tracked secret references belong in:

- `~/.config/ooodnakov/secrets/env.template`

Tracked shared environment currently covers:

- editor and pager defaults
- `OOODNAKOV_CONFIG_HOME`
- `OOODNAKOV_SHARE_HOME`
- `OOODNAKOV_STATE_HOME`
- `OOODNAKOV_CACHE_HOME`
- `NVM_DIR`
- `PNPM_HOME`
- `~/.local/bin`
- `~/.local/share/ooodnakov-config/bin`
- `~/.cargo/bin`
- optional `~/.local/bin/env` sourcing when present

Runtime shell artifacts are intentionally not tracked. Zsh history is written under `~/.local/state/ooodnakov-config/zsh/` and the completion dump under `~/.cache/ooodnakov-config/zsh/`.

Additional local-only files you may create per machine:

- `~/.config/ooodnakov/local/env.zsh`
- `~/.config/ooodnakov/local/env.ps1`
- `~/.config/ooodnakov/local/wezterm.lua`

Examples live in [`home/.config/ooodnakov/local`](home/.config/ooodnakov/local).

Runtime shell state is intentionally untracked:

- zsh history: `~/.local/state/ooodnakov-config/zsh/`
- zsh completion dump: `~/.cache/ooodnakov-config/zsh/`

To sync shared secrets across machines, keep Bitwarden references in the tracked template and render local plaintext files on each machine:

- `oooconf secrets login`
- `eval "$(oooconf secrets unlock --shell zsh)"`
- `oooconf secrets sync`
- `oooconf secrets sync --dry-run`
- `oooconf secrets doctor`

The generated files stay local and ignored:

- `~/.config/ooodnakov/local/env.zsh`
- `~/.config/ooodnakov/local/env.ps1`

The tracked template supports plain shared values and `bw://item/<item-id>/...` references. The current backend is `Bitwarden CLI` via `bw`, intended for a self-hosted Vaultwarden server such as `https://vaultwarden.ooodnakov.ru`.

Typical Unix flow:

```bash
oooconf install
oooconf secrets login
eval "$(oooconf secrets unlock --shell zsh)"
oooconf secrets sync
```

Typical PowerShell flow:

```powershell
oooconf install
oooconf secrets login
oooconf secrets unlock --shell pwsh | Invoke-Expression
oooconf secrets sync
```

For non-interactive or automated setups, you can skip the login/unlock step entirely by setting these environment variables before running `oooconf secrets sync`:

```bash
export BW_CLIENTID="user.xxx"
export BW_CLIENTSECRET="xxx"
export BW_PASSWORD="your-vault-password"
oooconf secrets sync
```

The sync will auto-unlock the vault, create missing local env files if needed, and render them without any manual interaction.

**LOCAL OVERRIDES**: rendered files (`~/.config/ooodnakov/local/env.zsh`, `env.ps1`) contain a `# --- LOCAL OVERRIDES START/END ---` block. Lines inside this section survive every `oooconf secrets sync`, making it safe to add machine-specific env vars that are not tracked in the template. Anything outside the markers is overwritten on each sync.

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

- architecture notes: [`docs/architecture.md`](docs/architecture.md)
- reproducibility notes: [`docs/reproducibility.md`](docs/reproducibility.md)
- dependency decisions: [`docs/dependency-decisions.md`](docs/dependency-decisions.md)
- troubleshooting: [`docs/troubleshooting.md`](docs/troubleshooting.md)
- import and comparison notes: [`docs/imports/upstream-audit.md`](docs/imports/upstream-audit.md)
- third-party tree notes: [`third_party/README.md`](third_party/README.md)
