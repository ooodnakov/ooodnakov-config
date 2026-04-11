# Reproducibility

## Goals

This repo should let you make a fresh Linux, Windows, or future macOS machine converge on the same terminal experience with minimal manual edits.

## Design

Tracked files:

- base shell config
- base WezTerm config
- base LazyVim/Neovim config
- PowerShell profile
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

`zsh` dependencies are not copied into the repo. They are installed into `~/.local/share/ooodnakov-config` on Unix-like systems at pinned commits:

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

This keeps the repo small while still making bootstrap deterministic.
`auto-uv-env` is installed in a user-local layout that mirrors its upstream bin/share model without touching global system directories: a pinned source checkout lives under `~/.local/share/ooodnakov-config/src/auto-uv-env`, the executable is linked into `~/.local/share/ooodnakov-config/bin/auto-uv-env`, and the shell integration files are installed into `~/.local/share/ooodnakov-config/auto-uv-env`.
`zoxide` is treated as an optional system package rather than a pinned repo checkout; when present, the tracked `zsh` config initializes it as `z` and `zi` so it replaces the older `z` plugin without changing the interactive command.
The Unix setup also normalizes permissions for the installed `oh-my-zsh` tree on every run, keeping directories at `755` and regular files at `644` so `compaudit` accepts the completion paths.
For optional tooling, `bat` is installed via the system package manager when available as a `cat` alternative with syntax highlighting, `delta` is installed via the system package manager when available as a Git diff pager with syntax highlighting, `glow` is installed via the system package manager when available as a terminal Markdown reader, `gum` is installed from Charm's official package sources when needed for the interactive dependency picker, `q` is installed via the upstream natesales APT repo on Debian/Ubuntu and via the system package manager when available elsewhere, `uv` is installed via Astral's official installer, `bw` is installed from Bitwarden's pinned official native CLI archive, and `dua-cli` is installed from `https://github.com/byron/dua-cli` via `cargo`, avoiding distro-specific package naming drift.

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

The bootstrap scripts intentionally do not install every package manager package for you. They assume the machine already has:

- Linux/macOS: `git`, `zsh`
- Windows: `git`, `pwsh` if you want PowerShell Core
- all platforms: `wezterm`, `oh-my-posh`

Fonts are also manual for now. The tracked defaults assume a Nerd Font is installed, with `MesloLGS NF` preferred.
This repo bundles the Meslo font files under `fonts/meslo`; the Unix setup script installs them for the current user.

For Neovim, the Unix setup validates `nvim >= 0.11.0` for LazyVim. On Linux, if the distro package manager only provides an older version, setup installs the pinned official Neovim release tarball into the repo-managed XDG data tree and links `nvim` from there.
For `pnpm`, the tracked shell environment reserves `PNPM_HOME`, and setup installs a pinned version through `corepack` when available or through `npm` into that path otherwise.

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
- `oooconf` after Unix setup links it into `~/.local/bin/oooconf`
- `.\scripts\ooodnakov.ps1` before Windows setup
- `oooconf` after Windows setup links `oooconf.ps1` and `oooconf.cmd` into `~/.local/bin`

On Windows, setup also links the tracked PowerShell profile into both `~/.config/powershell/Microsoft.PowerShell_profile.ps1` and the active `$PROFILE.CurrentUserCurrentHost` path so the managed XDG-style file and the loaded profile stay aligned.

Phase-1 setup ergonomics are implemented with:

- `dry-run` command to preview setup actions without mutation
- `doctor` command to validate managed links and key tool presence after install
- `deps` command to install optional dependencies separately from the full config-linking flow

Phase-2 dependency audit ergonomics are implemented with:

- `oooconf lock` (or `.\scripts\ooodnakov.ps1 lock`) to regenerate lock artifacts from pinned refs
- `oooconf update-pins` to compare pinned refs with remote HEAD and append an audit summary
- `oooconf update-pins --apply` to update pinned refs in `scripts/setup.sh`, then regenerate lock artifacts
- `update-pins` workflows are implemented in Python so both Unix and PowerShell CLIs use the same logic


## Phase-3 ergonomics

- `oooconf` command is linked to `~/.local/bin/oooconf` by Unix setup so the unified CLI can be invoked from any directory.
- `oooconf deps` uses `gum choose --no-limit` when available to provide a terminal multi-select picker for optional dependencies, and it can bootstrap `gum` first when interactive package installation is allowed.
- Unix and PowerShell setup runs write per-run logs under `~/.local/state/ooodnakov-config/logs/`, with `setup-latest.log` copied or linked to the latest run for debugging.
- PowerShell shared environment exports `OOODNAKOV_CONFIG_HOME`, `OOODNAKOV_SHARE_HOME`, `OOODNAKOV_STATE_HOME`, and `OOODNAKOV_CACHE_HOME`, and prepends both `~/.local/bin` and `~/.local/share/ooodnakov-config/bin` when present.
- WezTerm startup supports `OOODNAKOV_WEZTERM_WORKSPACE` and `OOODNAKOV_WEZTERM_CWD` for project-scoped startup defaults without editing tracked config.
