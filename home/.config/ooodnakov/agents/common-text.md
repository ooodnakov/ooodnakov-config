# oooconf Shared Agent Policy

## Core Principles

- **Be precise and minimal** — Make the smallest correct change. Never refactor unrelated code unless asked.
- **Verify before claiming success** — Always run the relevant build/test/lint commands (prefixed with `rtk`).
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

<!-- oooconf:rtk:start -->
## Token-Efficient Execution (RTK)

**Golden Rule**: **Always** prefix shell commands with `rtk`. It safely reduces output while preserving exit codes and behavior.

**Why it matters**: Reduces token usage by 60–99% on build, test, and lint output.

### Recommended Patterns

```bash
# Build & Type Checking
rtk cargo build / check / clippy
rtk tsc
rtk next build
rtk pnpm build

# Testing (failures only)
rtk cargo test
rtk pytest
rtk vitest
rtk playwright test
rtk jest

# Linting & Formatting
rtk eslint
rtk biome
rtk ruff
rtk prettier --check

# Git (clean output)
rtk git status / diff / log
```
Use `rtk <any command>` as a safe passthrough for everything else.
<!-- oooconf:rtk:end -->

## General Workflow Rules

- Explore relevant files first (use filesystem MCP or `rtk` commands).
- Make the minimal viable change.
- Run `rtk` + relevant test/lint/build commands.
- Fix any failures before moving on.
- Summarize changes and reasoning clearly when finished.

## Boundaries & Safety

- Never commit secrets, tokens, API keys, or machine-specific values.
- Never perform broad refactors unless explicitly requested.
- Always respect the existing project structure and conventions.
- Prefer editing the managed home/ tree over third_party/.
- When working with this config repo, follow the rules in the root AGENTS.md.
