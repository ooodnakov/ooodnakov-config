# AGENTS.md

## Scope

These instructions apply to the repository rooted at this directory.

## Purpose

This repo is a reproducible cross-platform dotfiles repository for Linux, Windows, and macOS machines.

The repo contains:

- active managed config under `home/`
- bootstrap scripts under `scripts/`
- documentation under `docs/`
- reference/upstream trees under `third_party/`
- bundled fonts under `fonts/`

## Source of truth

Authoritative managed config lives in:

- `home/.zshrc`
- `home/.config/zsh/`
- `home/.config/wezterm/`
- `home/.config/yazi/`
- `home/.config/nvim/`
- `home/.config/powershell/`
- `home/.config/ohmyposh/`
- `home/.config/ooodnakov/`
- desktop/window-manager trees under `home/.config/{niri,noctalia,komorebi,aerospace,omniwm,sketchybar,borders}/` and `home/.glzr/`

Bootstrap behavior lives in:

- `scripts/setup/setup.sh`
- `scripts/setup/setup.ps1`

The unified CLI entrypoint lives in:

- `scripts/setup/ooodnakov.sh` (Unix)
- `scripts/setup/ooodnakov.ps1` (PowerShell)

Shell completions live in:

- `home/.config/ooodnakov/completions/oooconf-completions.ps1` (PowerShell, auto-loaded)

Reference-only material lives in:

- `third_party/upstream/ezsh`
- `third_party/local-snapshots/wezterm-current`

Do not treat `third_party/` as active config unless the user explicitly asks to extract or merge something from it.

## Editing rules

- Prefer changing active config in `home/` rather than editing files in `third_party/`.
- Keep secrets out of git. Tokens, private keys, and machine-specific values belong in local ignored files only.
- Preserve reproducibility. Prefer pinned versions, deterministic paths, and explicit setup steps.
- Keep cross-platform behavior in shared config only when it is safe on Linux, Windows, and macOS.
- Put host-specific behavior in local override examples or documented local files, not in tracked base config.

## Symlink manifest

When adding or modifying symlinks, relevant files are:

| File | Role |
|------|------|
| `scripts/link_manager.py` | Engine: manifest parsing, auto-discovery, platform filtering, local override merging |
| `scripts/links.toml` | Canonical manifest of all managed symlinks |
| `scripts/setup/setup.sh` / `scripts/setup/setup.ps1` | Consumers: call `link_manager.py` to get link list, then create symlinks |

**Adding a new config folder:**

The preferred approach is to create the directory under `home/.config/` (or `home/.local/` or `home/.glzr/`). Auto-discovery handles it automatically — no manifest edit needed.

Only add an explicit `[[links]]` entry in `scripts/links.toml` for:
- Files (not directories), e.g., `home/.zshrc`
- Platform-specific links (`only` or `except` tags)
- Non-standard targets that do not follow the `{CONFIG_HOME}/<key>` convention

**Machine-local overrides:**

The local overrides file is at `home/.config/ooodnakov/local/links.local.toml` (i.e., `{CONFIG_HOME}/ooodnakov/local/links.local.toml`). This file is never tracked in git. It supports target overrides and new `[links.<key>]` entries; platform tag filtering belongs in `scripts/links.toml`. See `docs/symlink-manifest.md` for the full current format and examples.

## Shell config policy

- Shared portable environment belongs in:
  - `home/.config/ooodnakov/env/common.sh`
  - `home/.config/ooodnakov/env/common.ps1`
- Machine-specific or secret environment belongs in:
  - `~/.config/ooodnakov/local/env.zsh`
  - `~/.config/ooodnakov/local/env.ps1`
- Shell completions belong in:
  - `home/.config/ooodnakov/completions/` (auto-loaded by managed profiles)
- These local files contain a `# --- LOCAL OVERRIDES START/END ---` section that survives `oooconf secrets sync`. User-added lines inside the markers are preserved across renders; everything outside is overwritten.
- `oooconf secrets sync` can auto-unlock the vault if `BW_CLIENTID`, `BW_CLIENTSECRET`, and `BW_PASSWORD` are exported, avoiding interactive prompts.
- If importing behavior from real machines, keep only portable parts in tracked config.

## WezTerm policy

- Active WezTerm config is the smaller reproducible setup in `home/.config/wezterm/`.
- The large local fork snapshot in `third_party/local-snapshots/wezterm-current` is for audit/reference only.
- If borrowing features from the snapshot, port them intentionally into the active config instead of replacing the active tree wholesale.

## Python and uv

The project uses `uv` for Python version and dependency management.

- `pyproject.toml`: Defines project metadata, dev tooling, and lint configuration.
- `.python-version`: Pins the Python version (e.g., 3.12).
- Helper scripts (`scripts/*.sh`, `scripts/*.ps1`) use a `run_python` / `Run-Python` function that prefers `uv run` if available, ensuring they run with the correct Python version and environment.
- `ruff` is configured in `pyproject.toml` and should be run via `uv run ruff check .`.
- The virtual environment `.venv/` is ignored by git.

When adding new Python dependencies:

- Use `uv add <package>` to update `pyproject.toml`.
- Ensure scripts remain compatible with the pinned Python version.

## Upstream tracking

- `third_party/upstream/ezsh` is managed as a git subtree.
- If updating it, prefer:

```bash
git subtree pull --prefix=third_party/upstream/ezsh https://github.com/jotyGill/ezsh.git master --squash
```

- Document meaningful imports from upstream or remote machines in `docs/imports/upstream-audit.md`.

## Fonts

- Bundled Meslo Nerd Font files live in `fonts/meslo/`.
- Keep font filenames stable unless there is a deliberate migration.
- If setup behavior changes, update both `README.md` and `docs/reproducibility.md`.

## Documentation

When structure or setup behavior changes, update the relevant docs:

- `README.md`
- `docs/reproducibility.md`
- `docs/imports/upstream-audit.md`
- `docs/troubleshooting.md`
- `docs/dependency-decisions.md`
- `docs/architecture.md`
- `docs/contributing.md`
- `docs/cli-extension-guide.md`
- `docs/ci-smoke-checks-terminal.md`
- `third_party/README.md`

## Validation

After changing shell bootstrap logic, validate:

```bash
bash -n scripts/setup/setup.sh
bash -n scripts/setup/ooodnakov.sh
bash -n scripts/setup/delete.sh
bash -n scripts/setup/minimal-setup.sh
```

If PowerShell setup changes and `pwsh` is available, validate active PowerShell scripts under `scripts/setup/*.ps1`, wrappers under `home/.config/ooodnakov/bin/*.ps1`, and maintained PowerShell tests under `tests/*.ps1`.

After changing Python helper scripts or Python project configuration, validate:

```bash
uv run ruff check --select I --fix
uv run ruff check
uv run ruff format
uv run pytest
```

After changing CLI help output or completions:

- Verify `oooconf --help` renders cleanly on both Unix and PowerShell
- Verify `oooconf help <command>` shows examples for each command
- Test PowerShell completions load without errors
- Confirm completions work for commands, options, and secrets subcommands

## Task Completion and Commits

Follow this policy when finishing a requested task:

- Organize, stage, and commit changes to the current branch.
- Write a clear, concise commit message following the existing style (e.g., `feat(scope): ...`, `fix(scope): ...`).
- Only push to the remote repository if specifically asked by the user or if it is the natural conclusion of the task.

## Common MCP servers
<!-- oooconf:mcp-servers:start -->
- `context7`: documentation search and code examples for thousands of libraries
- `filesystem`: local repository and home config trees
- `git`: commit history, diff summaries, and branch status
- `github`: GitHub API access (repositories, issues, PRs)
- `playwright`: headless browser automation and web testing
- `shell`: deterministic local inspection commands (rg, fd, git, python3)
- `windows-mcp`: Windows system inspection and automation (processes, windows, registry)
<!-- oooconf:mcp-servers:end -->

## Common Skills
<!-- oooconf:skills:start -->
- Cross-agent MCP server bridging (Codex + Claude + Gemini compatibility)
- Dotfiles portability review (Linux + Windows + macOS safety)
- Full-control sandbox management (system-level Danger Mode)
- Manual approval flow orchestration (safety-first review policy)
- Secrets hygiene review (template references vs local plaintext files)
- Shell bootstrap audit (idempotency and dry-run behavior)
<!-- oooconf:skills:end -->
<!-- oooconf:agents-common:end -->