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
- AeroSpace, SketchyBar, and Borders config under `~/.config/`

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

Before first install, the repo-local `oooconf` script is the intended entrypoint. After install, setup links both `oooconf` and short alias `o` into `~/.local/bin`, so you can run:

```bash
oooconf install
oooconf deps
oooconf update
oooconf dry-run
oooconf doctor
o doctor
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

After setup, `oooconf` is linked into `$HOME\.local\bin` (plus short alias wrappers `o.ps1`/`o.cmd`), and the managed PowerShell profile prepends that directory to `PATH`, so the same commands work in new sessions:

```powershell
oooconf install
oooconf deps
oooconf update
oooconf dry-run
oooconf doctor
o doctor
```

During `oooconf install` and `oooconf update`, LazyVim plugin sync runs headlessly with progress-only output. Detailed Neovim plugin logs stay hidden unless the sync fails.

## CLI Entry Points

Primary commands:

- `o`: short alias wrapper for `oooconf` with matching completion behavior
- `oooconf install`: apply managed config and optional dependency installs
- `oooconf deps`: install optional dependencies only, with a multi-select picker when `gum` is available
- `oooconf update`: fast-forward pull the repo, then rerun install
- `oooconf dry-run`: preview setup actions without changing the system
- `oooconf doctor`: validate managed links and key tools
- `oooconf delete`: remove managed links and restore latest backups when available
- `oooconf remove`: remove managed links without restoring backups
- `oooconf bootstrap`: clone/update repo then run install (Unix only)
- `oooconf lock`: regenerate dependency lock artifacts
- `oooconf update-pins`: compare pinned refs with upstream HEAD and refresh lock artifacts
- `oooconf update-pins --apply`: update pinned refs in setup scripts, then regenerate lock artifacts
- `oooconf completions`: regenerate tracked completion files (autogen zsh + `oooconf` command completions)
- `oooconf agents detect`: report configured AI agent CLIs available on `PATH`
- `oooconf agents sync`: append/update shared managed AGENTS.md policy sections
- `oooconf agents doctor`: verify AGENTS.md managed sections and common MCP/skills content
- `oooconf agents update`: update installed agent CLIs using their preferred package manager (pnpm-based tools are updated via `pnpm`)

The helper scripts use `uv` for Python version and dependency management. If `uv` is available, scripts will run in the pinned Python environment (defined in `.python-version` and `pyproject.toml`). If `uv` is missing, they fall back to the system `python3`.

Secrets commands:

- `oooconf secrets login`: configure Bitwarden/Vaultwarden server, choose login method, and start login
- `oooconf secrets unlock --shell zsh`: print shell code to export `BW_SESSION`
- `oooconf secrets sync`: render local secret env files from the tracked template, creating missing `env.zsh`/`env.ps1`
- `oooconf secrets sync --dry-run`: preview rendered files without writing
- `oooconf secrets list`: list secrets from the template (add `--resolved` to resolve `bw://` refs)
- `oooconf secrets status`: check sync state and vault status
- `oooconf secrets doctor`: validate prerequisites and rendered files
- `oooconf secrets logout`: lock vault and revoke the Bitwarden session
- `oooconf shell status`: print all managed shell preference modes
- `oooconf shell forgit-aliases [plain|forgit|status]`: choose whether short git aliases stay plain or switch to upstream `forgit` aliases
- `oooconf shell auto-uv-env [enabled|quiet|status]`: control Python virtualenv activation message verbosity

On Windows, setup also links `oooconf` into `$HOME\.local\bin` and the managed PowerShell profile prepends that directory to `PATH`, so `oooconf install`, `oooconf doctor`, and similar commands work directly in new shell sessions. It also links the tracked PowerShell profile into both `$HOME\.config\powershell\Microsoft.PowerShell_profile.ps1` and the active `$PROFILE.CurrentUserCurrentHost` path, so the XDG-style source of truth and the profile PowerShell actually loads stay in sync.
The PowerShell setup can also prompt to install missing optional tools via the catalog in `scripts/optional-deps.toml` (using winget, choco, corepack/pnpm, PowerShell Gallery, or custom methods). It offers to bootstrap Chocolatey if needed. Replaced files are preserved in timestamped backups under `$HOME\.local\state\ooodnakov-config\backups\`.
Windows setup runs also write debug logs under `$HOME\.local\state\ooodnakov-config\logs\`, with `setup-latest.log` updated to the latest run.

Shell completion:

- **PowerShell**: argument completion is automatically loaded by the managed profile
  - Complete commands: `oooconf <Tab>`
  - Alias completions also work: `o <Tab>`
  - Complete options: `oooconf install --<Tab>`
  - Complete secrets subcommands: `oooconf secrets <Tab>`
  - Complete shell values: `oooconf secrets unlock --shell <Tab>`
- **Zsh**: completion is provided via fzf-tab integration
  - Regenerate tracked completions: `oooconf completions`

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
oooconf deps <key>
```

Agent policy management:

```bash
oooconf agents detect
oooconf agents sync
oooconf agents doctor
oooconf agents update
```

The shared AGENTS policy snippets are configured in:

- `home/.config/ooodnakov/agents/config.json`
- `home/.config/ooodnakov/agents/common-text.md`
- `home/.config/ooodnakov/agents/common-data.json` (structured MCP + skills data)

`oooconf agents doctor` also checks common MCP/skills markers against default agent config paths by format (JSON, TOML, YAML). Use `oooconf agents doctor --strict-config-paths` to fail when none of an agent's documented default config paths exist locally.
`oooconf agents update` updates only agent CLIs that are currently installed on `PATH`, and routes all pnpm-preferred agents through `pnpm add -g <package>@latest`.
`oooconf agents sync --global` now understands MCP `env_vars` shorthands and resolves `{env_var}` placeholders from the current environment when generating Codex, Claude, and Gemini MCP configs.

## Prerequisites

The setup scripts intentionally do not try to provision a full workstation from bare metal. Core tools should already exist before first install:

| Platform | Required System Tools | Core Terminal Tools |
|----------|-----------------------|---------------------|
| **Linux** | `git`, `zsh` | `wezterm`, `oh-my-posh` |
| **macOS** | `git`, `zsh` | `wezterm`, `oh-my-posh` |
| **Windows** | `git`, `pwsh` (for PowerShell Core) | `wezterm`, `oh-my-posh` |


See [`docs/reproducibility.md`](docs/reproducibility.md) for the full dependency policy and [`docs/architecture.md`](docs/architecture.md) for the symlink, lockfile, and local-override model.

## Install Behavior

Setup symlinks tracked config into standard locations and preserves replaced files by moving them into timestamped backups:

- Unix: `~/.local/state/ooodnakov-config/backups/`
- Windows: `$HOME\.local\state\ooodnakov-config\backups\`

On Unix, that managed tree includes `~/.config/niri` alongside the existing shell, terminal, editor, and `ooodnakov` config links.

Each install, update, or doctor run also writes logs under:

- Unix: `~/.local/state/ooodnakov-config/logs/`
- Windows: `$HOME\.local\state\ooodnakov-config\logs\`

`setup-latest.log` points to the latest run.

In interactive terminals, setup can also prompt to install common optional dependencies. The full catalog lives in `scripts/optional-deps.toml`, which both Unix and PowerShell setup scripts read. Each entry defines per-platform install methods (apt, brew, choco, winget, cargo, curl, or custom).

### Installing Optional Dependencies

Use `oooconf deps` to install optional tools interactively or specifically:

- `oooconf deps` — Interactive picker (requires `gum`).
- `oooconf deps --minimal` — Install core minimal setup (git, zsh, uv, oh-my-posh, gum, rg, fd, bat).
- `oooconf deps <key...>` — Install specific tools (e.g., `oooconf deps yazi p7zip`).
- `oooconf deps --dry-run` — Preview without installing.

All metadata is in `scripts/optional-deps.toml` (sole source of truth). Run `oooconf lock` after editing.

See [`docs/dependency-decisions.md`](docs/dependency-decisions.md) for the full decision matrix.

## Pinned Dependencies

The repo aims for deterministic setup by pinning third-party shell dependencies and related tooling.

See [`docs/dependency-decisions.md`](docs/dependency-decisions.md) for the full list of automated, optional, and manual dependencies and how they are installed per platform.
See [`docs/dependency-lock.md`](docs/dependency-lock.md) for the exact pinned git revisions used by the setup scripts.

The tracked `oh-my-posh` theme uses its own unified `git` segment in [home/.config/ohmyposh/ooodnakov.omp.json](home/.config/ohmyposh/ooodnakov.omp.json). It provides a clean, single-branch status with detailed working and staging information. The PowerShell profile still imports `posh-git` to provide git command completions, but prompt rendering is handled entirely by Oh My Posh for a consistent look.

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

To sync shared secrets across machines, keep Bitwarden references in the tracked template and render local plaintext files on each machine:

- `oooconf secrets login` (prompts for login type)
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
# or explicitly:
oooconf secrets login --method apikey
eval "$(oooconf secrets unlock --shell zsh)"
oooconf secrets sync
```

Typical PowerShell flow:

```powershell
oooconf install
oooconf secrets login
# or explicitly:
oooconf secrets login --method apikey
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
- Linux and macOS jobs run Bash syntax validation, `shellcheck`, lockfile reproducibility checks, and `oooconf` smoke tests (`install --dry-run`, `doctor` expected-failure on fresh HOME, and `lock`)
- Windows jobs run PowerShell parser validation plus `oooconf` smoke tests (`install --dry-run`, `doctor` expected-failure on fresh HOME, and `lock`)
- tags matching `v*` publish `.tar.gz` and `.zip` source archives to GitHub Releases

## Upstream and Audit References

The active config is intentionally smaller than the reference material stored alongside it.

Upstream inspirations:

- [`jotyGill/ezsh`](https://github.com/jotyGill/ezsh)
- [`KevinSilvester/wezterm-config`](https://github.com/KevinSilvester/wezterm-config)

Reference docs:

- architecture notes: [`docs/architecture.md`](docs/architecture.md)
- contributing workflow: [`docs/contributing.md`](docs/contributing.md)
- reproducibility notes: [`docs/reproducibility.md`](docs/reproducibility.md)
- dependency decisions: [`docs/dependency-decisions.md`](docs/dependency-decisions.md)
- troubleshooting: [`docs/troubleshooting.md`](docs/troubleshooting.md)
- import and comparison notes: [`docs/imports/upstream-audit.md`](docs/imports/upstream-audit.md)
- third-party tree notes: [`third_party/README.md`](third_party/README.md)
- contributor instructions and coding rules: [`AGENTS.md`](AGENTS.md)

## Development

If you'd like to make changes to the configuration, testing your changes against the codebase is recommended.
You can use `pre-commit` to ensure code is formatted properly and passes linting checks before committing.

Install `pre-commit` and run it locally:
```bash
uv tool install pre-commit
pre-commit install
pre-commit run --all-files
```
