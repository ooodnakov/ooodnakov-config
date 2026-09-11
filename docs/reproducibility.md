# Reproducibility

## Goals

This repo should let you make a fresh Linux, Windows, or macOS machine converge on the same terminal experience with minimal manual edits.

## Platform Support Matrix

“Tested” means the lifecycle and relevant native-script checks run in GitHub Actions.
“Best effort” means the configuration is designed to work but is not exercised by
the complete CI lifecycle. “Unsupported” means no compatibility guarantee is made.

| Operating system / shell / architecture | Level | Validation and limits |
|---|---|---|
| Ubuntu GitHub runner, Bash, runner-native architecture | Tested | Full Python suite, Bash syntax/ShellCheck, dry-run smoke test, and isolated lifecycle. |
| macOS GitHub runner, Bash, runner-native architecture | Tested | Bash syntax/ShellCheck, dry-run smoke test, and isolated lifecycle; GUI desktop startup is not exercised. |
| Windows GitHub runner, PowerShell 7, x64 | Tested | PowerShell parsing, dry-run smoke test, structured files, and isolated lifecycle. |
| Zsh interactive configuration on Linux/macOS | Best effort | Generated completion syntax is tested when Zsh is available; terminal and plugin behavior depends on installed tools. |
| Linux ARM64, macOS ARM64 outside the hosted runner, and WSL | Best effort | Shared config is portable, but every release artifact and desktop integration is not covered. Preview with `oooconf plan`. |
| Other Unix variants, 32-bit systems, Windows PowerShell 5.1, and unlisted shells | Unsupported | Add local overrides or a tested platform implementation before relying on setup automation. |

The runner labels are the durable promise; hosted-runner images and hardware can
change. CI workflow files are authoritative for the currently exercised images and
Python versions.

## Design

Tracked files:

- base shell config
- base WezTerm config
- base LazyVim/Neovim config
- PowerShell profile
- Python `uv` environment metadata (`pyproject.toml`, `.python-version`, tracked `uv.lock`; `.venv/` is an ignored local artifact)
- prompt config
- shared environment files
- shared SSH host definitions
- install scripts and sourced/dot-sourced setup/CLI helper modules under `scripts/setup/lib/`

Ignored files:

- API tokens
- SSH private keys
- host-specific shell paths
- machine-only WezTerm domains
- runtime shell artifacts such as history and completion dumps

## Dependency policy

`zsh` dependencies and other third-party utilities are intentionally not committed into the repo.

See [`dependency-decisions.md`](dependency-decisions.md) for the full list of automated, optional, and manual dependencies and how they are installed per platform.
See `deps.lock.json` for the exact pinned git revisions used by the setup scripts.

This keeps the repo small while still making bootstrap deterministic. The refactored setup entrypoints keep dependency metadata centralized in `scripts/optional-deps.toml`; the extracted helper modules only organize implementation details and do not introduce new dependency lists or machine-local state.

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
- env (machine-local values only; optional Bitwarden upload)
- internal hostnames or IPs you do not want tracked
- WezTerm launch commands tied to one machine
- OS package manager tweaks

The machine-local default capability profile belongs in
`~/.config/ooodnakov/local/profile.toml`. It contains only a built-in profile name
and is ignored by git. Tracked profile definitions select portable capabilities;
platform-inapplicable capabilities are reported as skipped, and dependency lists are
recommendations that do not bypass the existing install-consent flow. See
`docs/profiles.md` for precedence and examples.

## Manual prerequisites

The bootstrap scripts intentionally do not install every package manager package for you. See the [Prerequisites table in the README](../README.md#prerequisites) for the required bare-metal tools per platform.

Fonts are also manual for now. The tracked defaults assume a Nerd Font is installed, with `MesloLGSDZ Nerd Font Mono` preferred.
This repo bundles the Meslo font files under `fonts/meslo`; the Unix setup script installs them for the current user.

For Neovim, setup validates `nvim >= 0.10.0` for LazyVim. If Neovim is missing or too old, setup installs the pinned official Neovim GitHub release archive into the repo-managed data tree and links or copies `nvim` from there instead of using an OS package manager.
For Node.js, setup can install the pinned Node.js LTS version through an available `nvm` checkout, including the bundled `npm`. On Unix, the bootstrap can sync the managed `nvm` checkout first when only the repository-managed `nvm` tree is missing.
For `pnpm`, the tracked shell environment reserves `PNPM_HOME`; setup first ensures Node.js/npm are available, then installs the pinned pnpm version through `corepack` when available or through `npm` into that path otherwise.

## Bootstrap trust model

Do not pipe the Unix bootstrap directly into a shell. Download it to a temporary
file, inspect it, and execute that reviewed file. For a release archive, download
the accompanying `SHA256SUMS` file and verify it before extraction, for example
with `sha256sum --check SHA256SUMS` from the directory containing the archives.

Direct dependency archives are pinned by version and SHA-256 in
`scripts/optional-deps.toml`. The shared secure extractor rejects absolute paths,
parent traversal, devices, and archive links. Upstreams offering only mutable
installer scripts are explicit checksum exceptions in `deps.lock.json` and
`docs/dependency-lock.md`; those scripts are downloaded before execution and
package-manager routes remain preferred.

For a new machine or any time you want to inspect changes first, prefer:

1. clone the repo
2. review `bootstrap.sh`, `scripts/setup/setup.sh`, and the tracked config under `home/`
3. run the repo-local `oooconf` entrypoint directly

That keeps the initial setup auditable while preserving the same install behavior.

## Unified CLI and validation

The primary entrypoints are:

- repo-local `./home/.config/ooodnakov/bin/oooconf` before first install on Unix
- `oooconf` (and alias `o`) after Unix setup links them into `~/.local/bin/oooconf` and `~/.local/bin/o`
- `.\home\.config\ooodnakov\bin\oooconf.ps1` before Windows setup
- `oooconf` (and alias `o`) after Windows setup links `oooconf.ps1`/`oooconf.cmd` and `o.ps1`/`o.cmd` into `~/.local/bin`

On Windows, setup also links the tracked PowerShell profile into both `~/.config/powershell/Microsoft.PowerShell_profile.ps1` and the active `$PROFILE.CurrentUserCurrentHost` path so the managed XDG-style file and the loaded profile stay aligned.

Phase-1 setup ergonomics are implemented with:

- `dry-run` command to preview setup actions without mutation
- `doctor` command to validate managed links and key tool presence after install
- `deps` command to install optional dependencies separately from the full config-linking flow
- `completions` command to regenerate tracked completion files (autogen zsh + oooconf command completions)
- `doctor --format json` and `status --format json` for a stable, secret-free
  inventory contract with explicit health-check exit semantics
- `snapshot export|inspect|apply` for portable profile and allowlisted preference
  transfer; snapshots intentionally contain no arbitrary environment values,
  credentials, machine paths, histories, logs, or caches

Phase-2 dependency audit ergonomics are implemented with:

- `oooconf lock` (or `.\home\.config\ooodnakov\bin\oooconf.ps1 lock`) to regenerate lock artifacts from pinned refs
- `oooconf update-pins` to compare pinned refs with remote HEAD and append an audit summary
- `oooconf update-pins --apply` to update pinned refs in `scripts/optional-deps.toml`, then regenerate lock artifacts
- `oooconf agents detect` to detect configured AI coding agent CLIs available on `PATH`
- `oooconf agents sync` to update managed shared AGENTS.md policy sections from tracked snippets
- `oooconf agents doctor` to verify AGENTS.md managed sections and check common MCP/skills markers in default agent config paths
- `oooconf agents install [<agent> ...] [--all|--missing] [--check]` to install missing, selected, or all configured agent CLIs through their preferred package managers
- `oooconf agents update` to update installed agent CLIs; pnpm-preferred agents are updated through `pnpm`
- `oooconf agents provider sync minimax` to configure MiniMax-M2.7 provider backends for Claude Code, OpenCode, and Codex CLI without committing API keys
- `oooconf agents doctor --strict-config-paths` to fail when expected agent default config files are missing
- `oooconf agents sync --global` to sync MCP configs with environment-backed secret rendering, including `env_vars` passthrough and `{env_var}` placeholders resolved from the current shell environment
- MiniMax provider sync uses `MINIMAX_API_KEY` from machine-local environment for Codex/OpenCode; Claude Code also needs `ANTHROPIC_AUTH_TOKEN` exported to the MiniMax key unless `--materialize-secrets` is used, which should be avoided in tracked or shared files
- `update-pins` workflows are implemented in Python so both Unix and PowerShell CLIs use the same logic. Helper scripts use `uv run` if `uv` is available to ensure they run with the pinned Python version and a consistent environment. If `uv` is not present, they fall back to the system `python3`.
- autogen third-party zsh completion specs are sourced from `scripts/generate/tool-completions.toml` and generated by `scripts/generate/generate_tool_completions.py` for both Bash and PowerShell setup flows.
- `oooconf` command completions are generated from the canonical recursive CLI spec (`scripts/cli/oooconf-cli-spec.toml`), tracked command list, and optional dependency catalog by `scripts/cli/generate_oooconf_completions.py`. Shared completion definitions, such as dependency keys and provider regions, are referenced by name from command nodes instead of hardcoded in shell-specific generators.

The root `justfile` exposes repeatable developer automation without replacing the underlying commands: `just check` runs Ruff, structured-file validation, and pytest on every platform; `just integration` runs the isolated lifecycle, `just coverage` enforces the current floor, and `just unix` adds Bash syntax and smoke checks on Unix. `just completions` and `just lock` regenerate tracked artifacts. Install the optional task runner with `oooconf deps just`.

Fleet automation uses exact package versions and a tracked `scripts/fleet/bun.lock`.
CI and both Fleet workflows install with `bun install --frozen-lockfile`, then run
Biome lint, TypeScript checking, and offline Bun tests. Merge automation defaults to
preview and requires an explicit manual `apply` input before any repository mutation.
See [Fleet automation](fleet-automation.md) for its trust and eligibility model.

Transactional journals and their backup files are deliberately outside the tracked
repository and are not automatically expired. Retain a completed journal for as long
as rollback may be needed, then follow the guarded cleanup procedure in
[Troubleshooting](troubleshooting.md#transaction-journal-retention-and-cleanup).

## Phase-3 ergonomics

- `oooconf` command (plus alias `o`) is linked by Unix setup so the unified CLI can be invoked from any directory.
- `oooconf deps` uses `gum choose --no-limit` when available to provide a terminal multi-select picker for optional dependencies, and it can bootstrap `gum` first when interactive package installation is allowed. In the current picker, use arrow keys to move, `x` to toggle items, and `Enter` to continue.
- `marcosnils/bin` is the primary installer and tracker for GitHub release binaries, while Topgrade is the primary upgrade orchestrator. `oooconf deps --latest <key...>` installs missing selections and then runs Topgrade; Topgrade's native `bin` step executes `bin update`. The managers themselves are bootstrapped from catalog pins (or native Windows/macOS package managers), and both are included in the minimal/install flow.
- GitHub release installs pass the expanded catalog asset to `bin install --name`, so pinned installs do not prompt between variants such as GNU and musl.
- Unix and PowerShell setup runs write per-run logs under `~/.local/state/ooodnakov-config/logs/`, with `setup-latest.log` copied or linked to the latest run for debugging.
- PowerShell shared environment exports `OOODNAKOV_CONFIG_HOME`, `OOODNAKOV_SHARE_HOME`, `OOODNAKOV_STATE_HOME`, and `OOODNAKOV_CACHE_HOME`, and prepends both `~/.local/bin` and `~/.local/share/ooodnakov-config/bin` when present.
- WezTerm startup supports `OOODNAKOV_WEZTERM_WORKSPACE` and `OOODNAKOV_WEZTERM_CWD` for project-scoped startup defaults without editing tracked config. The managed plugin layer is declared in `home/.config/wezterm/config/plugins.lua`; WezTerm clones those HTTPS plugins into its runtime plugin cache on first launch, while repo-local tab/status rendering stays tracked under `home/.config/wezterm/events/` for deterministic cross-platform behavior. AI Commander is configured without tracked secrets and reads provider credentials from `ANTHROPIC_API_KEY` and `OPENAI_API_KEY`; `WEZTERM_AI_COMMANDER_RENDERER` can override the ask-pane renderer, otherwise WezTerm uses `streamdown` when available and falls back to `cat`.
