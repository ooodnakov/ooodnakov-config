# AGENTS.md

## Scope

These instructions apply to the repository rooted at this directory.

## Purpose

This repo is a reproducible cross-platform dotfiles repository for Linux, Windows, and future macOS machines.

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
- `home/.config/powershell/`
- `home/.config/ohmyposh/`
- `home/.config/ooodnakov/`

Bootstrap behavior lives in:

- `scripts/setup.sh`
- `scripts/setup.ps1`

The unified CLI entrypoint lives in:

- `scripts/ooodnakov.sh` (Unix)
- `scripts/ooodnakov.ps1` (PowerShell)

Shell completions live in:

- `home/.config/ooodnakov/completions/oooconf-completions.ps1` (PowerShell, auto-loaded)

Reference-only material lives in:

- `third_party/upstream/ezsh`
- `third_party/local-snapshots/wezterm-current`

Do not treat `third_party/` as active config unless the user explicitly asks to extract or merge something from it.

## Editing rules

- Prefer changing active config in `home/` rather than editing files in `third_party/`.
- Keep secrets out of git. Tokens, private keys, and machine-only values belong in local ignored files only.
- Preserve reproducibility. Prefer pinned versions, deterministic paths, and explicit setup steps.
- Keep cross-platform behavior in shared config only when it is safe on Linux, Windows, and macOS.
- Put host-specific behavior in local override examples or documented local files, not in tracked base config.

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

- `pyproject.toml`: Defines project metadata and (currently empty) dependencies.
- `.python-version`: Pins the Python version (e.g., 3.12).
- `uv.lock`: Ensures deterministic environment state.
- Helper scripts (`scripts/*.sh`, `scripts/*.ps1`) use a `run_python` / `Run-Python` function that prefers `uv run` if available, ensuring they run with the correct Python version and environment.
- The virtual environment `.venv/` is ignored by git.

When adding new Python dependencies:
- Use `uv add <package>` to update `pyproject.toml` and `uv.lock`.
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
- `third_party/README.md`

## Validation

After changing shell bootstrap logic, validate:

```bash
bash -n scripts/setup.sh
```

If PowerShell setup changes and `pwsh` is available, validate those scripts too.

After changing CLI help output or completions:

- Verify `oooconf --help` renders cleanly on both Unix and PowerShell
- Verify `oooconf help <command>` shows examples for each command
- Test PowerShell completions load without errors
- Confirm completions work for commands, options, and secrets subcommands

## Task Completion and Commits

- After finishing a requested task, the agent MUST organize, stage, and commit the changes to the current branch.
- Propose a clear and concise commit message following the existing style (e.g., `feat(scope): ...`, `fix(scope): ...`).
- Only push to the remote repository if specifically asked by the user or if it is the natural conclusion of the task (e.g., "organize, commit and push").

<!-- oooconf:agents-common:start -->
## oooconf shared agent policy

- Keep responses concise and action-oriented.
- Favor reproducible commands and explicit file paths.
- Prefer tracked shared config over machine-specific local overrides.
- Never include secrets, private keys, or access tokens in tracked files.

## Common MCP servers

- `filesystem`: local repository and home config trees
- `git`: commit history, diff summaries, and branch status
- `shell`: deterministic local inspection commands (rg, fd, git, python3)

## Common Skills

- Dotfiles portability review (Linux + Windows + macOS safety)
- Secrets hygiene review (template references vs local plaintext files)
- Shell bootstrap audit (idempotency and dry-run behavior)
<!-- oooconf:agents-common:end -->
