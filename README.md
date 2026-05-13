# ooodnakov-config

Reproducible personal dotfiles for Linux, Windows, and future macOS machines.

This repo tracks the opinionated base config and bootstrap logic only. Secrets, tokens, private keys, and host-specific overrides stay outside git in local files.

## What This Repo Manages

Active tracked config lives under `home/` and includes:

- `zsh` and modular zsh config
- pinned shell dependencies and helpers
- WezTerm config
- Yazi config
- Niri config under `~/.config/niri`
- Noctalia config under `~/.config/noctalia`
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
- `oooconf agents mcp sync|status`: manage tracked MCP server clones/install state
- `oooconf agents mcp add`: add one or many MCP JSON entries to shared common-data (`--multi`), with optional `--preview`, and normalize `npx -y` to `pnpm dlx`
- `oooconf agents rtk init`: run RTK global init for detected agents
- `oooconf agents provider sync minimax`: configure MiniMax-M2.7 provider backends for Claude Code, OpenCode, and Codex CLI
- `oooconf agents skills sync`: synchronize configured agent skill specs
- `oooconf agents skills view`: list the global shared skills catalog via `pnpm dlx skills ls -g` (add `--json` for machine output)
- `oooconf agents skills add <source>`: add one shared skill source (e.g. `vercel-labs/agent-skills`) and optionally sync
- `oooconf agents update`: update installed agent CLIs using their preferred package manager (pnpm-based tools are updated via `pnpm`)
- `oooconf agents install <agent>`: install one specific agent CLI
- `oooconf agents install-scripts-build`: rebuild standalone install scripts for agents

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
- `oooconf shell prompt [p10k|ohmyposh|status]`: switch only the zsh prompt engine between Powerlevel10k and Oh My Posh
- `oooconf shell prompt-style [verbose|concise|status]`: switch all managed prompts between the full multi-segment layout and a compact layout
- `oooconf shell forgit-aliases [plain|forgit|status]`: choose whether short git aliases stay plain or switch to upstream `forgit` aliases
- `oooconf shell auto-uv-env [enabled|quiet|status]`: control Python virtualenv activation message verbosity
- `oooconf color [status|list|<theme>|dark|light]`: select a unified CLI color theme (`default`, `catppuccin`, `gruvbox`, `nord`, `tokyonight`, `noctalia`) and dark/light mode. When unset, `oooconf` prefers existing tracked tool themes (WezTerm/Neovim) before falling back to `default`; theme changes sync local overrides for Yazi, WezTerm, Komorebi (including bar config), SketchyBar colors, Zebar CSS vars, and a themed Oh My Posh config under `~/.config/ooodnakov/local/ohmyposh/`, and `status` reports detected Neovim/Oh My Posh config state.

Window manager commands (Windows):

- `oooconf wm status`: shows the currently running window manager (komorebi or glazewm)
- `oooconf wm set [komorebi|glazewm]`: stops the current WM and starts the specified one
- `oooconf wm start`: starts the default WM (komorebi with whkd)
- `oooconf wm stop`: stops any running WM stack (komorebi, whkd, komorebi-bar, glazewm)
- `oooconf wm reload`: reloads the configuration of the active WM
- `oooconf wm bar set [zebar|yabs]`: set or show the default bar type used on WM start
- `oooconf wm bar zebar-config [status|list|set <name>|install <source>]`: manage zebar widget configs
- `oooconf wm bar [stop|start|reload]`: stop, start, or restart the zebar bar (keeps komorebi running)
- `oooconf wm komorebi [reload|start|stop] [--bar]`: low-level komorebi control with optional bar flag

The `default_bar_type` setting in `home/.glzr/zebar/config.yaml` controls whether `oooconf wm start` or `oooconf wm set komorebi` also launches the bar. Use `oooconf wm bar set zebar` or `oooconf wm bar set yabs` to change it.

On Windows, setup also links `oooconf` into `$HOME\.local\bin` and the managed PowerShell profile prepends that directory to `PATH`, so `oooconf install`, `oooconf doctor`, and similar commands work directly in new shell sessions. It also links the tracked PowerShell profile into both `$HOME\.config\powershell\Microsoft.PowerShell_profile.ps1` and the active `$PROFILE.CurrentUserCurrentHost` path, so the XDG-style source of truth and the profile PowerShell actually loads stay in sync.
The PowerShell setup can also prompt to install missing optional tools via the catalog in `scripts/optional-deps.toml` (using winget, choco, nvm-backed Node.js, corepack/pnpm, PowerShell Gallery, or custom methods). It offers to bootstrap Chocolatey if needed. Replaced files are preserved in timestamped backups under `$HOME\.local\state\ooodnakov-config\backups\`.
Windows setup runs also write debug logs under `$HOME\.local\state\ooodnakov-config\logs\`, with `setup-latest.log` updated to the latest run.

Shell completion:

- **PowerShell**: argument completion is automatically loaded by the managed profile
  - Complete commands: `oooconf <Tab>`
  - Alias completions also work: `o <Tab>`
  - Complete options: `oooconf install --<Tab>`
  - Complete secrets subcommands: `oooconf secrets <Tab>`
  - Complete nested agent subcommands: `oooconf agents mcp <Tab>`
  - Complete shell values: `oooconf secrets unlock --shell <Tab>`
- **Zsh**: completion is provided via fzf-tab integration
  - Regenerate tracked completions: `oooconf completions`
  - Command metadata comes from the recursive CLI tree in `scripts/oooconf-cli-spec.toml`; shared value sets such as optional dependency keys are referenced by name and expanded by the generator.

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
oooconf agents mcp sync
oooconf agents mcp status
oooconf agents rtk init
oooconf agents provider sync minimax
oooconf agents skills sync
oooconf agents skills view
oooconf agents install --check
oooconf agents install
oooconf agents install codex gemini
oooconf agents install --all
oooconf agents update
oooconf agents install-scripts-build
```

The shared AGENTS policy snippets are configured in:

- `home/.config/ooodnakov/agents/config.json`
- `home/.config/ooodnakov/agents/common-text.md`
- `home/.config/ooodnakov/agents/common-data.json` (structured MCP + skills data)
- `docs/agents-config-research.md` (cross-agent config model comparison and rationale)

`oooconf agents doctor` also checks common MCP/skills markers against default agent config paths by format (JSON, TOML, YAML). Use `oooconf agents doctor --strict-config-paths` to fail when none of an agent's documented default config paths exist locally.
`oooconf agents install` installs missing configured agent CLIs by default. Pass one or more agent keys such as `codex gemini`, `--missing` for explicit missing-only mode, or `--all` to install or upgrade every configured agent CLI. `--check` previews the installer commands without running them.
`oooconf agents update` updates only agent CLIs that are currently installed on `PATH`, and routes all pnpm-preferred agents through `pnpm add -g <package>@latest`.
`oooconf agents sync --global` now understands MCP `env_vars` shorthands and resolves `{env_var}` placeholders from the current environment when generating Codex, Claude, and Gemini MCP configs. `oooconf agents provider sync minimax` configures MiniMax-M2.7 backends for Claude Code (`~/.claude/settings.json`), OpenCode (`~/.config/opencode/opencode.json`), and Codex CLI (`~/.codex/config.toml`) while keeping `MINIMAX_API_KEY` in local environment by default for Codex/OpenCode; Claude Code also needs `ANTHROPIC_AUTH_TOKEN` exported to the MiniMax key unless `--materialize-secrets` is intentionally used on private machine config.

## Prerequisites

The setup scripts intentionally do not try to provision a full workstation from bare metal. Core tools should already exist before first install:

| Platform    | Required System Tools               | Core Terminal Tools     |
|-------------|-------------------------------------|-------------------------|
| **Linux**   | `git`, `zsh`                        | `wezterm`, `oh-my-posh` |
| **macOS**   | `git`, `zsh`                        | `wezterm`, `oh-my-posh` |
| **Windows** | `git`, `pwsh` (for PowerShell Core) | `wezterm`, `oh-my-posh` |


See [`docs/reproducibility.md`](docs/reproducibility.md) for the full dependency policy and [`docs/architecture.md`](docs/architecture.md) for the symlink, lockfile, and local-override model.

## Install Behavior

Setup symlinks tracked config into standard locations and preserves replaced files by moving them into timestamped backups:

- Unix: `~/.local/state/ooodnakov-config/backups/`
- Windows: `$HOME\.local\state\ooodnakov-config\backups\`

On Unix, that managed tree includes `~/.config/niri` linked from [`home/.config/niri`](home/.config/niri) and `~/.config/noctalia` linked from [`home/.config/noctalia`](home/.config/noctalia) alongside the existing shell, terminal, editor, and `ooodnakov` config links.

Each install, update, or doctor run also writes logs under:

- Unix: `~/.local/state/ooodnakov-config/logs/`
- Windows: `$HOME\.local\state\ooodnakov-config\logs\`

`setup-latest.log` points to the latest run.

In interactive terminals, setup can also prompt to install common optional dependencies. The full catalog lives in `scripts/optional-deps.toml`, which both Unix and PowerShell setup scripts read. Each entry defines per-platform install methods (apt, brew, choco, winget, cargo, curl, GitHub release archive, or custom).

### Installing Optional Dependencies

Use `oooconf deps` to install optional tools interactively or specifically:

- `oooconf deps` — Interactive picker (requires `gum`).
- `oooconf deps --minimal` — Install core minimal setup (git, zsh, uv, oh-my-posh, gum, rg, fd, bat).
- `oooconf deps <key...>` — Install specific tools (e.g., `oooconf deps yazi p7zip`).
- `oooconf deps docker` — On systemd Linux, enable and start existing Docker/containerd units at boot.
- `oooconf deps --dry-run` — Preview without installing.

All metadata is in `scripts/optional-deps.toml` (sole source of truth). Run `oooconf lock` after editing.

See [`docs/dependency-decisions.md`](docs/dependency-decisions.md) for the full decision matrix.

## Pinned Dependencies

The repo aims for deterministic setup by pinning third-party shell dependencies and related tooling.

See [`docs/dependency-decisions.md`](docs/dependency-decisions.md) for the full list of automated, optional, and manual dependencies and how they are installed per platform.
See [`docs/dependency-lock.md`](docs/dependency-lock.md) for the exact pinned git revisions used by the setup scripts.

The tracked `oh-my-posh` theme honors `OOOCONF_PROMPT_STYLE` and is regenerated by `oooconf color` with the selected oooconf palette. It uses its own unified `git` segment in [home/.config/ohmyposh/ooodnakov.omp.json](home/.config/ohmyposh/ooodnakov.omp.json). It provides a clean, single-branch status with detailed working and staging information. The PowerShell profile still imports `posh-git` to provide git command completions, but prompt rendering is handled entirely by Oh My Posh for a consistent look.

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

The managed WezTerm setup also loads a small, cross-platform plugin layer:

- `LEADER Space`: searchable command picker for managed keybindings
- `LEADER s` / `LEADER S`: smart workspace switching and previous-workspace toggle with zoxide-backed project discovery
- `LEADER r` / `LEADER R` / `LEADER D`: restore, save, and delete resurrected WezTerm workspace state
- `LEADER d` / `LEADER v` / `LEADER h`: quick domain attach, vertical split attach, and horizontal split attach
- pane navigation keeps the existing platform `SUPER+h/j/k/l` shortcuts but routes them through `smart-splits.nvim` so they can cross Neovim and WezTerm pane boundaries; `SUPER_REV+h/j/k/l` resizes panes the same way

The tab/status bar remains local to this repo rather than replacing it wholesale with an external tab plugin. It borrows the useful pieces from the retro/tabline ecosystem: workspace and leader/mode cells, zoom indicators, tab indexes, pane counts, host/current-directory context, battery, and clock.

## CI/CD

- CI runs on pushes to `main` and pull requests
- Linux and macOS jobs run Python lint/format checks, Bash syntax validation, `shellcheck`, lockfile reproducibility checks, static Neovim/WezTerm smoke checks, and `oooconf` smoke tests (`install --dry-run`, `doctor` expected-failure on fresh HOME, and `lock`)
- Windows jobs run Python lint/format checks, PowerShell parser validation, static Neovim/WezTerm smoke checks, and `oooconf` smoke tests (`install --dry-run`, `doctor` expected-failure on fresh HOME, and `lock`)
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

The pre-commit hooks mirror the main local checks: Bash syntax, `shellcheck`, Ruff lint/format checks, and dependency lock reproducibility.
