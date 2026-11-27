# Agent configuration research notes

This note captures how the main agent CLIs used by `oooconf` structure configuration for:

- instruction files (`AGENTS.md` / `CLAUDE.md`),
- MCP server wiring,
- skills/extensions.

## OpenAI Codex CLI

Top 3 config settings to care about first:

1. `model` / provider defaults in `~/.codex/config.toml`.
2. `mcp_servers.<name>` blocks (stdio `command`/`args`/`env`, or remote `type`/`url` with `http_headers`).
3. Instruction file discovery via repo/global `AGENTS.md`.

Why this matters for `oooconf`:

- `oooconf agents sync` appends TOML `mcp_servers` entries for Codex (global configs are the default target).
- Global instruction sync should continue to target `~/.codex/AGENTS.md` when present.

## Claude Code

Top 3 config settings to care about first:

1. Settings precedence (`~/.claude/settings.json` -> project -> local override).
2. MCP server maps (`~/.claude.json` / `.mcp.json`) and scope precedence.
3. Instruction files (`~/.claude/CLAUDE.md`, `CLAUDE.md`, `.claude/CLAUDE.md`).

Why this matters for `oooconf`:

- The repo keeps `AGENTS.md` as cross-agent policy source and mirrors policy text into global instruction files where applicable.
- Claude MCP sync remains JSON-based and additive.

## Antigravity (App / CLI / IDE)

Top 3 config settings to care about first:

1. Global rules are loaded **cumulatively** from `~/.gemini/AGENTS.md`, `~/.gemini/GEMINI.md`, and modular `~/.gemini/config/rules/*.md` (which require YAML frontmatter with `trigger: always_on | model_decision | glob | manual`).
2. Global MCP servers live in `~/.gemini/config/mcp_config.json` under `mcpServers` (`command`/`args`/`env` for stdio, `serverUrl`/`headers` for Streamable HTTP — no `type` or `httpUrl`).
3. Personal skills live in `~/.gemini/config/skills/<name>/SKILL.md` (and `skills` CLI targets `-a antigravity`).

Why this matters for `oooconf`:

- Because Antigravity cumulatively loads `~/.gemini/AGENTS.md` alongside `~/.gemini/config/rules/*.md`, keeping the shared policy in `~/.gemini/AGENTS.md` and syncing `extras/antigravity.md` as an `extra_only` modular rule in `~/.gemini/config/rules/antigravity.md` (with `trigger: always_on` frontmatter) avoids duplicating the ~300-line shared block while keeping Antigravity-only rules separate.
- `agy` is detected via `agent_clis`, but installs and self-updates via Google's native installer (`agy update`), not npm/uv `agent_updates`.

## OpenCode

Top 3 config settings to care about first:

1. Global config file at `~/.config/opencode/opencode.json` (or project `opencode.json` override).
2. Top-level `mcp` object keyed by server name (not `mcpServers`), each with `type` (`local` or `remote`), plus `command`/`environment` for stdio or `url`/`headers` for remote HTTP.
3. Tool gating via `tools` (global/per-agent enable/disable patterns).

Why this matters for `oooconf`:

- OpenCode MCP sync must write to `mcp.<server>` with OpenCode's schema shape.
- For local MCP servers, generated entries should be `{\"type\":\"local\",\"command\":[...],\"environment\":{...}}`.
- For remote HTTP servers, generated entries should be `{\"type\":\"remote\",\"url\":\"https://...\",\"headers\":{...},\"enabled\":true}`.

## Strengthening decisions applied in this repo

1. Added `oooconf agents skills view` to expose a shared marketplace/catalog listing through `pnpm dlx skills ls -g`.
2. Kept `oooconf agents skills sync` as declarative install from `skill_specs` for reproducibility.
3. Fixed OpenCode global sync to use `mcp` object format instead of generic `mcpServers`.
4. Added MCP add workflow safeguards (`--multi`, `--preview`, validation, command normalization) before writing shared data.
5. Extended generated completions/spec so new agent subcommands/options are discoverable in shell completion.
6. Added remote MCP support (`type`/`url`/`headers`) to `common-data.json` entries and per-agent rendering: Codex `http_headers` tables, OpenCode `type: "remote"`, Antigravity `serverUrl`, Pi `url` with `${VAR}` interpolation, Claude/Oh My Pi `type` + `url`.
7. Moved the graphify skill out of the OMP-only tree into the shared `~/.agents/skills` registry (the skills CLI / Agent Skills location read by OMP, Claude Code, Codex, and Pi) and added Worktrunk as a managed skill installed via `pnpm dlx skills add -g` (`installer: "skills"` specs).
8. Removed Gemini CLI support: the CLI is deprecated upstream, and the declarative `agent` skill-spec installer existed only to run `gemini skills install`, so `skill_specs` now require `installer: "skills"` or `installer: "local"` and `oooconf agents skills add` writes skills-CLI specs.

## Reference docs (official)

- OpenAI Codex docs: https://developers.openai.com/codex/
- Claude Code configuration docs: https://code.claude.com/docs/en/configuration
- Claude directory layout: https://code.claude.com/docs/en/claude-directory
- Antigravity rules docs: https://antigravity.google/docs/rules
- Antigravity MCP docs: https://antigravity.google/docs/mcp
- Antigravity customization discovery docs: https://antigravity.google/docs/customization-discovery
- OpenCode provider docs: https://opencode.ai/docs/providers
- MiniMax coding tools guide: https://platform.minimax.io/docs/guides/text-ai-coding-tools

## MiniMax-M2.7 provider backend notes (May 2026)

MiniMax documents MiniMax-M2.7 integrations for multiple coding agents. The managed `oooconf agents provider sync minimax` command covers the agent CLIs currently configured in this repo that support file-based or CLI-provider MiniMax setup:

- Claude Code: writes `env` overrides in `~/.claude/settings.json`, including `ANTHROPIC_BASE_URL` and the MiniMax model aliases expected by Claude Code. Claude Code expects `ANTHROPIC_AUTH_TOKEN` itself to contain the bearer token, so the default mode does not write a literal `{MINIMAX_API_KEY}` placeholder; export `ANTHROPIC_AUTH_TOKEN=$MINIMAX_API_KEY` locally or only use `--materialize-secrets` on private machine config.
- OpenCode: writes a `minimax` provider and selects `minimax/MiniMax-M2.7` in `~/.config/opencode/opencode.json`. OpenCode's own docs also support storing credentials via `opencode auth login --provider minimax`, so `oooconf` does not write the key unless `--materialize-secrets` is requested.
- OpenAI Codex CLI: appends `[model_providers.minimax]` and `[profiles.minimax]` to `~/.codex/config.toml`, loading credentials from `MINIMAX_API_KEY`. The MiniMax guide marks Codex as not recommended and suggests `codex --profile minimax` for this backend.

Other tools listed by MiniMax (Cursor, TRAE, Kilo Code, Cline, Roo Code, Droid, Zed, Grok CLI, Hermes Agent, OpenClaw) are GUI-first, outside the current tracked CLI list, or do not have a stable dotfile target in this repo yet. Add them later only with documented, secret-safe config paths.
