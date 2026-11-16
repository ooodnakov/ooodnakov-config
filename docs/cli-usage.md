# oooconf usage

Command-line reference for `oooconf`: managed secrets and shell preferences, window-manager control, shell completion, the help system, unattended and automation-safe runs, transactional link application and rollback, portable profiles, and interactive dependency picks.

The helper scripts use `uv` for Python version and dependency management. If `uv` is available, scripts will run in the pinned Python environment (defined in `.python-version` and `pyproject.toml`). If `uv` is missing, they fall back to the system `python3`.

## Secrets commands

- `oooconf env KEY VALUE`: safely add or update a machine-local value in the preserved blocks of both `env.zsh` and `env.ps1`
- `oooconf env`: prompt for a variable name and hidden value, then offer an optional Bitwarden upload (default: no)
- `oooconf env KEY VALUE --secrets`: update both local files and upload the value to a Bitwarden secure note
- `oooconf secrets login`: configure Bitwarden/Vaultwarden server, choose login method, start login, then prompt for the master password to unlock the vault and save the session
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
- `oooconf shell typo-handling [silent|suggest|help|status]`: control typo suggestions for mistyped commands
- `oooconf shell psfzf-tab [enabled|disabled|status]`: toggle PSFzf tab completion integration
- `oooconf shell psfzf-git [enabled|disabled|status]`: toggle PSFzf Git helper integration
- `oooconf shell poshgit [enabled|disabled|status]`: toggle posh-git auto-import in PowerShell (opt-in; its prompt status duplicates the oh-my-posh git segment)
- `oooconf shell auto-uv-env [disabled|existing|enabled|quiet|status]`: control Python virtualenv auto-activation behavior (`existing` is the default and never creates missing `.venv` directories)
- `oooconf color [status|list|<theme>|dark|light]`: select a unified CLI color theme (`default`, `catppuccin`, `gruvbox`, `nord`, `tokyonight`, `noctalia`) and dark/light mode. When unset, `oooconf` prefers existing tracked tool themes (WezTerm/Neovim) before falling back to `default`; theme changes sync local overrides for Yazi, WezTerm, Komorebi (including bar config), SketchyBar colors, Zebar CSS vars, and a themed Oh My Posh config under `~/.config/ooodnakov/local/ohmyposh/`, and `status` reports detected Neovim/Oh My Posh config state. All command output uses role-colored Nerd Font icons automatically on UTF-8 terminals; redirected output or `OOOCONF_ASCII=1` falls back to ASCII tags. Paths are printed `$HOME`-relative (`~/…`) with muted directories and a highlighted leaf, and long link lists collapse into a grouped tree.

## Window manager commands

- `oooconf wm status`: shows the currently running window manager and bar when detectable
- `oooconf wm set [komorebi|glazewm|aerospace|omniwm]`: selects the default window manager and starts it
- `oooconf wm start`: starts the default window manager
- `oooconf wm stop`: stops the managed window-manager stack for the selected platform
- `oooconf wm reload`: reloads the active/default window manager
- `oooconf wm bar status`: shows the running managed bar when detectable
- `oooconf wm bar set [zebar|yabs|sketchybar]`: sets the default bar in local shell overrides
- `oooconf wm bar [start|stop|reload]`: controls the default managed bar
- `oooconf wm komorebi [status|start|stop|reload]`: low-level Komorebi integration commands

The default window-manager and bar choices are stored in ignored local shell overrides (`OOODNAKOV_DEFAULT_WM` and `OOODNAKOV_DEFAULT_BAR`) so host-specific desktop preferences do not enter tracked config.

## Shell completion

- **PowerShell**: argument completion is automatically loaded by the managed profile
  - Complete commands: `oooconf <Tab>`
  - Alias completions also work: `o <Tab>`
  - Complete options: `oooconf install --<Tab>`
  - Complete secrets subcommands: `oooconf secrets <Tab>`
  - Complete nested agent subcommands: `oooconf agents mcp <Tab>`
  - Complete shell values: `oooconf secrets unlock --shell <Tab>`
- **Zsh**: completion is provided via fzf-tab integration
  - Regenerate completions: `oooconf completions`
  - Third-party tool completions come from `scripts/generate/tool-completions.toml` and are emitted only for binaries available on `PATH`.
  - `oooconf` command metadata comes from the recursive CLI tree in `scripts/cli/oooconf-cli-spec.toml`; shared value sets such as optional dependency keys are referenced by name and expanded by the generator.

## Help system

- `oooconf --help` — shows grouped command categories with common workflow examples
- `oooconf help <command>` — shows command-specific help with examples and environment overrides
- `oooconf --print-repo-root`
- `oooconf --version`

## Unattended runs

```bash
OOODNAKOV_INTERACTIVE=never oooconf update
oooconf update --yes-optional
```

## Automation: plan, apply, rollback

For an automation-safe preview, use the shared planner. `oooconf dry-run` is a
compatibility alias for the default install plan:

```bash
oooconf plan
oooconf plan --scope links
oooconf plan bat zoxide --format json
oooconf dry-run --format json
```

Plan generation validates link sources, duplicate targets, dependency keys, and
target containment before reporting any operation. It does not create directories,
resolve secrets, install packages, or otherwise modify the machine. Setup on both
Unix and Windows consumes the same validated link-plan output.

Managed links are applied as a transaction. Each apply holds an exclusive lock and
atomically journals completed operations under
`$XDG_STATE_HOME/ooodnakov-config/transactions/` (falling back to
`~/.local/state/ooodnakov-config/transactions/`). If a link operation fails, completed
operations are rolled back automatically. `oooconf rollback --last` can reverse the
latest completed or interrupted transaction, but refuses to overwrite or remove a
target changed by the user after apply. Running `oooconf apply` again with an
identical link state is a no-op and creates neither a journal nor a backup.

Transaction journals and their referenced backups are intentionally retained until
rollback is no longer needed. Never delete an incomplete or `rollback_failed`
journal as routine cleanup; follow the
[recovery and retention procedure](troubleshooting.md#transaction-journal-retention-and-cleanup)
before removing terminal journals or backups.

`oooconf install` keeps its existing dependency and setup behavior, but delegates its
managed-link phase to the same transaction engine. Package-manager changes and
external tool/plugin updates remain explicitly non-reversible.

## Portable profiles

Portable profiles can limit managed links to a reusable capability bundle:

```bash
oooconf plan --profile workstation
oooconf apply --profile terminal
oooconf install --profile developer
```

Built-in profiles are `minimal`, `terminal`, `workstation`, and `developer`.
Precedence is explicit `--profile`, then `OOODNAKOV_PROFILE`, then the ignored local
`~/.config/ooodnakov/local/profile.toml`; no selection retains the historical
all-applicable-links behavior. Platform-inapplicable capabilities appear as skipped
in plan output, and profile dependency lists are recommendations rather than
automatic installation requests. See `docs/profiles.md` for the schemas and
extension workflow.

The tested and best-effort operating-system, shell, and architecture combinations
are listed in the [platform support matrix](reproducibility.md#platform-support-matrix).

## Interactive dependency picks

```bash
# interactive multi-select picker (requires gum)
oooconf deps
# without gum: text prompt lists available keys, type to select
oooconf deps
# explicit keys (no prompt)
oooconf deps <key>
```
