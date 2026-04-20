# Reproducibility

## Goals

This repo should let you make a fresh Linux, Windows, or future macOS machine converge on the same terminal experience with minimal manual edits.

## Design

Tracked files:

- base shell config
- base WezTerm config
- base LazyVim/Neovim config
- PowerShell profile
- Python `uv` environment (`pyproject.toml`, `.python-version`, `uv.lock`)
- prompt config
- shared environment files
- shared SSH host definitions
- install scripts

Ignored files:

- API tokens
- SSH private keys
- host-specific shell paths
- machine-only WezTerm domains
- runtime shell artifacts such as history and completion dumps

## Dependency policy

`zsh` dependencies and other third-party utilities are intentionally not committed into the repo.

See [`dependency-decisions.md`](dependency-decisions.md) for the full list of automated, optional, and manual dependencies and how they are installed per platform.
See [`dependency-lock.md`](dependency-lock.md) for the exact pinned git revisions used by the setup scripts.

This keeps the repo small while still making bootstrap deterministic.

Shell runtime state is kept outside the tracked config tree:

- zsh history: `~/.local/state/ooodnakov-config/zsh/history`
- zsh completion dump: `~/.cache/ooodnakov-config/zsh/.zcompdump-<host>-<zsh-version>`

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

The bootstrap scripts intentionally do not install every package manager package for you. See the [Prerequisites table in the README](../README.md#prerequisites) for the required bare-metal tools per platform.

Fonts are also manual for now. The tracked defaults assume a Nerd Font is installed, with `MesloLGSDZ Nerd Font Mono` preferred.
This repo bundles the Meslo font files under `fonts/meslo`; the Unix setup script installs them for the current user.

For Neovim, the Unix setup validates `nvim >= 0.11.0` for LazyVim. On Linux, if the distro package manager only provides an older version, setup installs the pinned official Neovim release tarball into the repo-managed XDG data tree and links `nvim` from there.
For `pnpm`, the tracked shell environment reserves `PNPM_HOME`, and setup installs a pinned version through `corepack` when available or through `pnpm` into that path otherwise.

## Bootstrap trust model

The fastest Unix bootstrap path is still `curl ... | bash`, but that is a trust tradeoff, not the recommended review path.

For a new machine or any time you want to inspect changes first, prefer:

1. clone the repo
2. review `bootstrap.sh`, `scripts/setup.sh`, and the tracked config under `home/`
3. run the repo-local `oooconf` entrypoint directly

That keeps the initial setup auditable while preserving the same install behavior.

## Unified CLI and validation

The primary entrypoints are:

- repo-local `./home/.config/ooodnakov/bin/oooconf` before first install on Unix
- `oooconf` (and alias `o`) after Unix setup links them into `~/.local/bin/oooconf` and `~/.local/bin/o`
- `.\scripts\ooodnakov.ps1` before Windows setup
- `oooconf` (and alias `o`) after Windows setup links `oooconf.ps1`/`oooconf.cmd` and `o.ps1`/`o.cmd` into `~/.local/bin`

On Windows, setup also links the tracked PowerShell profile into both `~/.config/powershell/Microsoft.PowerShell_profile.ps1` and the active `$PROFILE.CurrentUserCurrentHost` path so the managed XDG-style file and the loaded profile stay aligned.

Phase-1 setup ergonomics are implemented with:

- `dry-run` command to preview setup actions without mutation
- `doctor` command to validate managed links and key tool presence after install
- `deps` command to install optional dependencies separately from the full config-linking flow
- `completions` command to regenerate tracked completion files (autogen zsh + oooconf command completions)

Phase-2 dependency audit ergonomics are implemented with:

- `oooconf lock` (or `.\scripts\ooodnakov.ps1 lock`) to regenerate lock artifacts from pinned refs
- `oooconf update-pins` to compare pinned refs with remote HEAD and append an audit summary
- `oooconf update-pins --apply` to update pinned refs in `scripts/setup.sh`, then regenerate lock artifacts
- `oooconf agents detect` to detect configured AI coding agent CLIs available on `PATH`
- `oooconf agents sync` to update managed shared AGENTS.md policy sections from tracked snippets
- `oooconf agents doctor` to verify AGENTS.md managed sections and check common MCP/skills markers in default agent config paths
- `oooconf agents update` to update installed agent CLIs; pnpm-preferred agents are updated through `pnpm`
- `oooconf agents doctor --strict-config-paths` to fail when expected agent default config files are missing
- `oooconf agents sync --global` to sync MCP configs with environment-backed secret rendering, including `env_vars` passthrough and `{env_var}` placeholders resolved from the current shell environment
- `update-pins` workflows are implemented in Python so both Unix and PowerShell CLIs use the same logic. Helper scripts use `uv run` if `uv` is available to ensure they run with the pinned Python version and a consistent environment. If `uv` is not present, they fall back to the system `python3`.
- autogen completion specs are sourced from `scripts/autogen-completions.txt` for both Bash and PowerShell setup flows.
- `oooconf` command completions are generated from tracked command/dependency catalogs by `scripts/generate_oooconf_completions.py`.


## Phase-3 ergonomics

- `oooconf` command (plus alias `o`) is linked by Unix setup so the unified CLI can be invoked from any directory.
- `oooconf deps` uses `gum choose --no-limit` when available to provide a terminal multi-select picker for optional dependencies, and it can bootstrap `gum` first when interactive package installation is allowed. In the current picker, use arrow keys to move, `x` to toggle items, and `Enter` to continue.
- Unix and PowerShell setup runs write per-run logs under `~/.local/state/ooodnakov-config/logs/`, with `setup-latest.log` copied or linked to the latest run for debugging.
- PowerShell shared environment exports `OOODNAKOV_CONFIG_HOME`, `OOODNAKOV_SHARE_HOME`, `OOODNAKOV_STATE_HOME`, and `OOODNAKOV_CACHE_HOME`, and prepends both `~/.local/bin` and `~/.local/share/ooodnakov-config/bin` when present.
- WezTerm startup supports `OOODNAKOV_WEZTERM_WORKSPACE` and `OOODNAKOV_WEZTERM_CWD` for project-scoped startup defaults without editing tracked config.
