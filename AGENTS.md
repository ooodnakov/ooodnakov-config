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

<!-- context7 -->
Use Context7 MCP to fetch current documentation whenever the user asks about a library, framework, SDK, API, CLI tool, or cloud service -- even well-known ones like React, Next.js, Prisma, Express, Tailwind, Django, or Spring Boot. This includes API syntax, configuration, version migration, library-specific debugging, setup instructions, and CLI tool usage. Use even when you think you know the answer -- your training data may not reflect recent changes. Prefer this over web search for library docs.

Do not use for: refactoring, writing scripts from scratch, debugging business logic, code review, or general programming concepts.

## Steps

1. Always start with `resolve-library-id` using the library name and the user's question, unless the user provides an exact library ID in `/org/project` format
2. Pick the best match (ID format: `/org/project`) by: exact name match, description relevance, code snippet count, source reputation (High/Medium preferred), and benchmark score (higher is better). If results don't look right, try alternate names or queries (e.g., "next.js" not "nextjs", or rephrase the question). Use version-specific IDs when the user mentions a version
3. `query-docs` with the selected library ID and the user's full question (not single words)
4. Answer using the fetched docs
<!-- context7 -->


<!-- grok-mcp -->
  Use Grok MCP when the task specifically benefits from xAI/Grok capabilities that are exposed as MCP tools: agentic web
  research, X/Twitter search, code execution, vision, document chat, or Grok image/video generation.

  ## When to use Grok MCP
  - Use `grok_agent` for multi-tool tasks that may need web search, X search, code execution, files, or images in one
  request.
  - Use `web_search` for agentic web research, especially when domain filters, citations, or multi-step search are
  useful.
  - Use `x_search` for X/Twitter-specific research, handle filtering, or date-bounded social search.
  - Use `chat` or `stateful_chat` for plain Grok text generation when Grok itself is the target model.
  - Use `chat_with_vision` when the user wants Grok to analyze images.
  - Use `chat_with_files`, `upload_file`, and related file tools when the user wants Grok to read or reason over
  documents.
  - Use `generate_image` or `generate_video` only when the user explicitly wants media generation or editing.

  ## Operating notes
  - `grok_agent` is the highest-level Grok tool. Enable only the capabilities needed for the task: `use_web_search`,
  `use_x_search`, and/or `use_code_execution`.
  - Prefer narrower tools over `grok_agent` when the task is single-purpose.
  - For local images/files, pass file paths only if the environment exposes them to the MCP server. In some clients this
  requires a Filesystem MCP server or equivalent file access.
  - Use `stateful_chat` with `response_id` only when continuing the same Grok conversation across turns is actually
  useful.
  - If the user needs citations from Grok web/X research, set `include_inline_citations=true` when supported.

  ## Tool map
  - Text chat: `chat`, `stateful_chat`, `retrieve_stateful_response`, `delete_stateful_response`
  - Vision: `chat_with_vision`
  - Research: `web_search`, `x_search`, `grok_agent`
  - Code execution: `code_executor`, or `grok_agent` with `use_code_execution=true`
  - Files: `upload_file`, `list_files`, `get_file`, `get_file_content`, `delete_file`, `chat_with_files`
  - Media generation: `generate_image`, `generate_video`
  - Local session history: `list_chat_sessions`, `get_chat_history`, `clear_chat_history`
  <!-- grok-mcp -->

<!-- rtk-instructions v2 -->
# RTK (Rust Token Killer) - Token-Optimized Commands

## Golden Rule

**Always prefix commands with `rtk`**. If RTK has a dedicated filter, it uses it. If not, it passes through unchanged. This means RTK is always safe to use.

**Important**: Even in command chains with `&&`, use `rtk`:
```bash
# ❌ Wrong
git add . && git commit -m "msg" && git push

# ✅ Correct
rtk git add . && rtk git commit -m "msg" && rtk git push
```

## RTK Commands by Workflow

### Build & Compile (80-90% savings)
```bash
rtk cargo build         # Cargo build output
rtk cargo check         # Cargo check output
rtk cargo clippy        # Clippy warnings grouped by file (80%)
rtk tsc                 # TypeScript errors grouped by file/code (83%)
rtk lint                # ESLint/Biome violations grouped (84%)
rtk prettier --check    # Files needing format only (70%)
rtk next build          # Next.js build with route metrics (87%)
```

### Test (60-99% savings)
```bash
rtk cargo test          # Cargo test failures only (90%)
rtk go test             # Go test failures only (90%)
rtk jest                # Jest failures only (99.5%)
rtk vitest              # Vitest failures only (99.5%)
rtk playwright test     # Playwright failures only (94%)
rtk pytest              # Python test failures only (90%)
rtk rake test           # Ruby test failures only (90%)
rtk rspec               # RSpec test failures only (60%)
rtk test <cmd>          # Generic test wrapper - failures only
```

### Git (59-80% savings)
```bash
rtk git status          # Compact status
rtk git log             # Compact log (works with all git flags)
rtk git diff            # Compact diff (80%)
rtk git show            # Compact show (80%)
rtk git add             # Ultra-compact confirmations (59%)
rtk git commit          # Ultra-compact confirmations (59%)
rtk git push            # Ultra-compact confirmations
rtk git pull            # Ultra-compact confirmations
rtk git branch          # Compact branch list
rtk git fetch           # Compact fetch
rtk git stash           # Compact stash
rtk git worktree        # Compact worktree
```

Note: Git passthrough works for ALL subcommands, even those not explicitly listed.

### GitHub (26-87% savings)
```bash
rtk gh pr view <num>    # Compact PR view (87%)
rtk gh pr checks        # Compact PR checks (79%)
rtk gh run list         # Compact workflow runs (82%)
rtk gh issue list       # Compact issue list (80%)
rtk gh api              # Compact API responses (26%)
```

### JavaScript/TypeScript Tooling (70-90% savings)
```bash
rtk pnpm list           # Compact dependency tree (70%)
rtk pnpm outdated       # Compact outdated packages (80%)
rtk pnpm install        # Compact install output (90%)
rtk npm run <script>    # Compact npm script output
rtk npx <cmd>           # Compact npx command output
rtk prisma              # Prisma without ASCII art (88%)
```

### Files & Search (60-75% savings)
```bash
rtk ls <path>           # Tree format, compact (65%)
rtk read <file>         # Code reading with filtering (60%)
rtk grep <pattern>      # Search grouped by file (75%)
rtk find <pattern>      # Find grouped by directory (70%)
```

### Analysis & Debug (70-90% savings)
```bash
rtk err <cmd>           # Filter errors only from any command
rtk log <file>          # Deduplicated logs with counts
rtk json <file>         # JSON structure without values
rtk deps                # Dependency overview
rtk env                 # Environment variables compact
rtk summary <cmd>       # Smart summary of command output
rtk diff                # Ultra-compact diffs
```

### Infrastructure (85% savings)
```bash
rtk docker ps           # Compact container list
rtk docker images       # Compact image list
rtk docker logs <c>     # Deduplicated logs
rtk kubectl get         # Compact resource list
rtk kubectl logs        # Deduplicated pod logs
```

### Network (65-70% savings)
```bash
rtk curl <url>          # Compact HTTP responses (70%)
rtk wget <url>          # Compact download output (65%)
```

### Meta Commands
```bash
rtk gain                # View token savings statistics
rtk gain --history      # View command history with savings
rtk discover            # Analyze Claude Code sessions for missed RTK usage
rtk proxy <cmd>         # Run command without filtering (for debugging)
rtk init                # Add RTK instructions to CLAUDE.md
rtk init --global       # Add RTK to ~/.claude/CLAUDE.md
```

## Token Savings Overview

| Category | Commands | Typical Savings |
|----------|----------|-----------------|
| Tests | vitest, playwright, cargo test | 90-99% |
| Build | next, tsc, lint, prettier | 70-87% |
| Git | status, log, diff, add, commit | 59-80% |
| GitHub | gh pr, gh run, gh issue | 26-87% |
| Package Managers | pnpm, npm, npx | 70-90% |
| Files | ls, read, grep, find | 60-75% |
| Infrastructure | docker, kubectl | 85% |
| Network | curl, wget | 65-70% |

Overall average: **60-90% token reduction** on common development operations.
<!-- /rtk-instructions -->

<!-- common -->
## MCP Management

Managed MCP servers (with a `source` repository) can be synchronized and installed across machines.

```bash
oooconf agents mcp status  # check status of all MCP servers
oooconf agents mcp sync    # clone/pull and run install commands for managed MCPs
```

## Python projects
If you are working in python project, use `uv` for dependency management and `ruff` for linting.

After changing Python helper scripts or Python project configuration, validate:

```bash
uv run ruff check --select I --fix
uv run ruff check
uv run ruff format
``` 

## Task Completion and Commits in Git Repositories

- After finishing a requested task, the agent MUST organize, stage, and commit the changes to the current branch.
- Propose a clear and concise commit message following the existing style (e.g., `feat(scope): ...`, `fix(scope): ...`).
- Only push to the remote repository if specifically asked by the user or if it is the natural conclusion of the task (e.g., "organize, commit and push").

<!-- /common -->

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
