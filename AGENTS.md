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
- `third_party/README.md`

## Validation

After changing shell bootstrap logic, validate:

```bash
bash -n scripts/setup.sh
```

If PowerShell setup changes and `pwsh` is available, validate those scripts too.

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

- After finishing a requested task, the agent MUST organize, stage, and commit the changes to the current branch.
- Propose a clear and concise commit message following the existing style (e.g., `feat(scope): ...`, `fix(scope): ...`).
- Only push to the remote repository if specifically asked by the user or if it is the natural conclusion of the task (e.g., "organize, commit and push").


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

<!-- oooconf:agents-common:start -->
## oooconf shared agent policy

# oooconf Shared Agent Policy

## Core Principles

- **Be precise and minimal** — Make the smallest correct change. Never refactor unrelated code unless asked.
- **Verify before claiming success** — Always run the relevant build/test/lint commands.
- **Use Context7 for anything technical** — Never rely on training data for libraries, APIs, CLIs, or frameworks.
- **Prefer modern, idiomatic solutions** — Follow current best practices for the language and ecosystem.
- **Ask when uncertain** — If requirements are ambiguous, ask for clarification rather than guessing.
- **Document your reasoning** — Briefly explain *why* you made each change.

## Documentation & Research (Context7)

Use Context7 MCP to fetch current documentation whenever the user asks about a library, framework, SDK, API, CLI tool, or cloud service — even well-known ones (React, Next.js, Prisma, Express, Tailwind, Django, Spring Boot, etc.).

**Do not use Context7 for**: refactoring, writing scripts from scratch, debugging business logic, code review, or general programming concepts.

### Steps (always follow this order)

1. Start with `resolve-library-id` using the library name and the user's full question (unless they already gave an exact `/org/project` ID).
2. Pick the best match by: exact name match, description relevance, code snippet count, source reputation (High/Medium preferred), and benchmark score.
3. Use `query-docs` with the selected library ID and the user's complete question.
4. Answer using only the freshly fetched documentation.

**Tip**: Use version-specific IDs when the user mentions a version.

## Advanced Capabilities (Grok MCP)

Use Grok tools when the task benefits from real-time research, code execution, vision, or media generation.

| Task                              | Recommended Tool                     | Notes |
|-----------------------------------|--------------------------------------|-------|
| General research / unknown topics | `web_search` or `grok_agent`         | Start here for most technical questions |
| X/Twitter research                | `x_search`                           | Use date filters and relevance scoring |
| Code execution                    | `code_executor` or `grok_agent`      | Enable with `use_code_execution=true` |
| Image / vision analysis           | `chat_with_vision`                   | Pass local file paths when available |
| Large document / file review      | `chat_with_files` + `upload_file`    | Best for reviewing codebases or specs |
| Ongoing conversation              | `stateful_chat`                      | Use only when maintaining context across turns |
| Simple text generation            | `chat`                               | Default for straightforward requests |

**Operating notes**:
- `grok_agent` is the highest-level tool — only enable the capabilities you actually need.
- Prefer narrower tools (`web_search`, `code_executor`, etc.) when the task is focused.
- For citations, set `include_inline_citations=true` when supported.

## General Workflow Rules

- Explore relevant files first.
- Make the minimal viable change.
- Run relevant test/lint/build commands.
- Fix any failures before moving on.
- Summarize changes and reasoning clearly when finished.

## Boundaries & Safety 

- Never commit secrets, tokens, API keys, or machine-specific values.
- Never perform broad refactors unless explicitly requested.
- Always respect the existing project structure and conventions.
- Prefer editing the managed home/ tree over third_party/.
- When working with this config repo, follow the rules in the root AGENTS.md.

## Common MCP servers
<!-- oooconf:mcp-servers:start -->
- `context7`: documentation search and code examples for thousands of libraries
- `filesystem`: local repository and home config trees
- `gemini-webapi`: Unofficial Gemini Web API access
- `git`: commit history, diff summaries, and branch status
- `github`: GitHub API access (repositories, issues, PRs)
- `godot`: Godot engine editor interaction
- `grok_mcp`: xAI Grok API access
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
