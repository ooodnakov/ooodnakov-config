# Dependency Decision Matrix

**Single source of truth**: `scripts/optional-deps.toml` (with `[managed-tools]` section for git-pinned items). All decisions, versions, URLs, and install methods live here. No lists or overrides exist elsewhere.

`oooconf deps` (or `--yes-optional`) offers everything marked optional. Automated items are handled in `install_managed_tools()` via the TOML.

Run `oooconf lock` after TOML changes to update `deps.lock.json` + docs.

| Key | Repository | Reason |
| --- | --- | --- |
| `oh_my_zsh` | ohmyzsh/ohmyzsh | Zsh framework required by tracked `.zshrc` |
| `p10k` | romkatv/powerlevel10k | Prompt theme required by tracked config |
| `zsh_autosuggestions` | zsh-users/zsh-autosuggestions | Zsh plugin tracked by `.zshrc` |
| `zsh_highlighting` | zsh-users/zsh-syntax-highlighting | Zsh plugin tracked by `.zshrc` |
| `zsh_history` | zsh-users/zsh-history-substring-search | Zsh plugin tracked by `.zshrc` |
| `zsh_autocomplete` | marlonrichert/zsh-autocomplete | Zsh plugin tracked by `.zshrc` |
| `fzf_tab` | Aloxaf/fzf-tab | Zsh plugin tracked by `.zshrc` |
| `forgit` | wfxr/forgit | Zsh plugin tracked by `.zshrc` |
| `zsh_you_should_use` | MichaelAquilina/zsh-you-should-use | Zsh plugin tracked by `.zshrc` |
| `auto_uv_env` | ashwch/auto-uv-env | uv environment setup script |
| `k` | supercrabtree/k | Standalone k command for directory jumping |

All decisions, categories, versions, install methods, pins, and reasons are **defined exclusively** in `scripts/optional-deps.toml` (see `[managed-tools]` section and per-entry comments).

- Automated: handled via `[managed-tools]` + `install_managed_tools()`.
- Optional: offered by `oooconf deps` (interactive picker or `--yes-optional`).
- Manual: not offered by bootstrap (e.g. WezTerm, final editor choice).

Run `oooconf lock` after editing the TOML.

**Rule of thumb:** if the tool is the primary host for tracked config (terminal, editor, IDE), it stays manual. Config *for* the tool can be tracked; the tool itself should not be force-installed.

## Adding a New Optional Dependency

1. Append a `[[deps]]` block to `scripts/optional-deps.toml` with the key, display name, description, and per-platform install info (`linux.manager`, `macos.manager`, `windows.manager`, plus `package`, `command`, `winget_id`, or `choco_id` as needed).
2. Add/adjust presence checks:
   - `optional_dependency_present()` in `scripts/setup.sh`
   - `Get-OptionalDependencyCommandNames` / `Test-OptionalDependencyPresent` in `scripts/setup.ps1`
3. Add custom installer handling only when needed:
   - `install_optional_dependency_from_catalog()` in `scripts/setup.sh`
   - `Install-OptionalDependencyFromSpec` in `scripts/setup.ps1`
4. Run `oooconf lock` to regenerate lock artifacts.
5. Document the decision in this file under the appropriate table.

## Platform-Specific Installers

| Platform | Primary | Fallback |
| --- | --- | --- |
| Linux (Debian/Ubuntu) | `apt` | manual download / archive |
| Windows | `winget` | `choco` |
| macOS | `brew` (planned) | — |

The bootstrap detects the available package manager at install time and uses it. If no package manager is found, the dependency is skipped with a warning.
