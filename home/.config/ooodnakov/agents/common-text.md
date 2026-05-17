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
