# Dependency Decision Matrix

**Single source of truth**: `scripts/optional-deps.toml` (with `[managed-tools]` section for git-pinned items). All decisions, versions, URLs, and install methods live here. No lists or overrides exist elsewhere.

`oooconf deps` (or `--yes-optional`) offers everything marked optional. Automated items are handled in `install_managed_tools()` via the TOML.

Run `oooconf lock` after TOML changes to update `deps.lock.json` + docs.

| Key | Repository | Reason |
| --- | --- | --- |
| `oh-my-zsh` | ohmyzsh/ohmyzsh | Zsh framework required by tracked `.zshrc` |
| `powerlevel10k` | romkatv/powerlevel10k | Prompt theme required by tracked config |
| `zsh-autosuggestions` | zsh-users/zsh-autosuggestions | Zsh plugin tracked by `.zshrc` |
| `zsh-syntax-highlighting` | zsh-users/zsh-syntax-highlighting | Zsh plugin tracked by `.zshrc` |
| `zsh-history-substring-search` | zsh-users/zsh-history-substring-search | Zsh plugin tracked by `.zshrc` |
| `zsh-autocomplete` | marlonrichert/zsh-autocomplete | Zsh plugin tracked by `.zshrc` |
| `fzf-tab` | Aloxaf/fzf-tab | Zsh plugin tracked by `.zshrc` |
| `forgit` | wfxr/forgit | Zsh plugin tracked by `.zshrc` |
| `you-should-use` | MichaelAquilina/zsh-you-should-use | Zsh plugin tracked by `.zshrc` |
| `auto-uv-env` | ashwch/auto-uv-env | uv environment setup script |
| `k` | supercrabtree/k | Standalone k command for directory jumping |
| `marker` | jotyGill/marker | Git branch management UI |
| `nvm` | nvm-sh/nvm | Node version manager (lazy-loaded) |
| `todo-txt` | todotxt/todo.txt-cli | Plain-text todo manager |
| `croc` | schollz/croc | Secure peer-to-peer file transfer (github-release on Linux, brew on macOS, winget/choco on Windows) |
| `just` | casey/just | Cross-platform task runner for repeatable lint, format, test, completion, and lock commands |


All decisions, categories, versions, install methods, pins, and reasons are **defined exclusively** in `scripts/optional-deps.toml` (see `[managed-tools]` section and per-entry comments).

The current optional dependency catalog includes:

`wget`, `git`, `wezterm`, `oh-my-posh`, `posh-git`, `psfzf`, `choco`, `brew`, `gsudo`, `rg`, `fd`, `zsh`, `direnv`, `fzf`, `bat`, `delta`, `glow`, `gum`, `zoxide`, `q`, `eza`, `yazi`, `ffmpeg`, `jq`, `p7zip`, `poppler`, `fc-cache`, `cargo`, `dua`, `nvim`, `tree-sitter`, `k`, `python3`, `lazygit`, `lazydocker`, `docker`, `impala`, `bluetui`, `just`, `uv`, `bw`, `node`, `pnpm`, `rtk`, `imagemagick`, `ghostscript`, `luarocks`, `tectonic`, `mermaid-cli`, `zig`, `neovim-node`, `neovim-python`, `fastfetch`, `btop`, `cava`, `blackhole-2ch`, `glazewm`, `zebar`, `overline-zebar`, `pandoc`, `pi-coding-agent`, `croc`

Optional UI extras such as `cava` for the SketchyBar audio visualizer, plus `BlackHole 2ch` for macOS loopback capture, also live in that TOML catalog and can be installed through `oooconf deps`. The `docker` entry is intentionally a configuration helper: it does not install Docker Engine, but on systemd Linux it enables and starts existing Docker and containerd units. Window-manager and agent-adjacent optional entries now include GlazeWM, Zebar, Overline Zebar widgets, RTK, and the Pi coding agent.

`brew` is optional on both macOS and Linux. It uses Homebrew's official installer with the non-interactive environment flag after the normal `oooconf deps` confirmation path.

- Automated: handled via `[managed-tools]` + `install_managed_tools()`.
- Optional: offered by `oooconf deps` (interactive picker or `--yes-optional`).
- Manual: not offered by bootstrap (e.g. WezTerm, final editor choice).

Run `oooconf lock` after editing the TOML.

**Rule of thumb:** if the tool is the primary host for tracked config (terminal, editor, IDE), it stays manual. Config *for* the tool can be tracked; the tool itself should not be force-installed.

## Adding a New Optional Dependency

1. Append a `[[deps]]` block to `scripts/optional-deps.toml` with the key, display name, description, and per-platform install info (`linux.manager`, `macos.manager`, `windows.manager`, plus `package`, `command`, `winget_id`, `choco_id`, `url`, or `asset` as needed).
   - For GitHub release archives, use `manager = "github-release"`, `package = "owner/repo"`, `ver`, `bin`, and platform `asset` templates with `${ver}`, `${system}`, and `${arch}` placeholders.
   - If the dependency requires specialized install logic, add `handler = "<name>"` and map that handler in setup dispatchers (`setup.sh` / `setup.ps1`). The `node` and `pnpm` handlers are intentionally paired so a fresh machine with only `nvm` can bootstrap Node.js, npm, and pnpm in one optional dependency run.
2. Add/adjust presence checks:
   - `optional_dependency_present()` in `scripts/setup/setup.sh`
   - `Get-OptionalDependencyCommandNames` / `Test-OptionalDependencyPresent` in `scripts/setup/setup.ps1`
3. Add custom installer handling only when needed:
   - `install_optional_dependency_from_catalog()` in `scripts/setup/setup.sh`
   - `Install-OptionalDependencyFromSpec` in `scripts/setup/setup.ps1`
4. Run `oooconf lock` to regenerate lock artifacts.
5. Regenerate command completions with `uv run python scripts/cli/generate_oooconf_completions.py`; if the dependency adds shell completions, update `scripts/generate/tool-completions.toml` and run `uv run python scripts/generate/generate_tool_completions.py --dry-run`.
6. Run drift checks so generated/consumer metadata stays aligned:
   - `uv run pytest tests/test_optional_deps.py tests/test_optional_deps_drift.py tests/test_static_smoke.py`
   - `bash tests/test_shell.sh`
7. Document the decision in this file under the appropriate table.

## Platform-Specific Installers

| Platform | Primary | Fallback |
| --- | --- | --- |
| Linux (Debian/Ubuntu) | `apt` | manual download / archive |
| Windows | `winget` | `choco` |
| macOS | `brew` | — |

The bootstrap detects the available package manager at install time and uses it. If no package manager is found, the dependency is skipped with a warning.
