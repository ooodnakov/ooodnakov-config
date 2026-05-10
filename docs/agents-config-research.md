# Agent configuration research notes

This note captures how the main agent CLIs used by `oooconf` structure configuration for:

- instruction files (`AGENTS.md` / `CLAUDE.md`),
- MCP server wiring,
- skills/extensions.

## OpenAI Codex CLI

Top 3 config settings to care about first:
1. `model` / provider defaults in `~/.codex/config.toml`.
2. `mcp_servers.<name>` blocks (command, args, env).
3. Instruction file discovery via repo/global `AGENTS.md`.

Why this matters for `oooconf`:
- `oooconf agents sync --global` should continue to append TOML `mcp_servers` entries for Codex.
- Global instruction sync should continue to target `~/.codex/AGENTS.md` when present.

## Claude Code

Top 3 config settings to care about first:
1. Settings precedence (`~/.claude/settings.json` -> project -> local override).
2. MCP server maps (`~/.claude.json` / `.mcp.json`) and scope precedence.
3. Instruction files (`~/.claude/CLAUDE.md`, `CLAUDE.md`, `.claude/CLAUDE.md`).

Why this matters for `oooconf`:
- The repo keeps `AGENTS.md` as cross-agent policy source and mirrors policy text into global instruction files where applicable.
- Claude MCP sync remains JSON-based and additive.

## Gemini CLI

Top 3 config settings to care about first:
1. `settings.json` model/provider + behavior defaults.
2. `mcpServers` entries and global `mcp` toggles.
3. `context.fileName` instruction discovery list (`AGENTS.md`, `GEMINI.md`, etc.).

Why this matters for `oooconf`:
- Skill sync remains implemented through `gemini skills install <source>` for declarative `skill_specs`.
- Global JSON MCP sync remains compatible with Gemini's documented `mcpServers` model.

## OpenCode

Top 3 config settings to care about first:
1. Global config file at `~/.config/opencode/opencode.json` (or project `opencode.json` override).
2. Top-level `mcp` object keyed by server name (not `mcpServers`), each with `type`, `command`, and optional `environment`/`headers`.
3. Tool gating via `tools` (global/per-agent enable/disable patterns).

Why this matters for `oooconf`:
- OpenCode MCP sync must write to `mcp.<server>` with OpenCode's schema shape.
- For local MCP servers, generated entries should be `{\"type\":\"local\",\"command\":[...],\"environment\":{...}}`.

## Strengthening decisions applied in this repo

1. Added `oooconf agents skills view` to expose a shared marketplace/catalog view through `pnpm dlx skills view`.
2. Kept `oooconf agents skills sync` as declarative install from `skill_specs` for reproducibility.
3. Fixed OpenCode global sync to use `mcp` object format instead of generic `mcpServers`.
4. Added MCP add workflow safeguards (`--multi`, `--preview`, validation, command normalization) before writing shared data.
5. Extended generated completions/spec so new agent subcommands/options are discoverable in shell completion.

## Reference docs (official)

- OpenAI Codex docs: https://developers.openai.com/codex/
- Claude Code configuration docs: https://code.claude.com/docs/en/configuration
- Claude directory layout: https://code.claude.com/docs/en/claude-directory
- Gemini CLI settings docs: https://geminicli.com/docs/cli/settings/
- Gemini CLI MCP docs: https://github.com/google-gemini/gemini-cli/blob/main/docs/tools/mcp-server.md
- OpenCode provider docs: https://opencode.ai/docs/providers
- MiniMax coding tools guide: https://platform.minimax.io/docs/guides/text-ai-coding-tools

## MiniMax-M2.7 provider backend notes (May 2026)

MiniMax documents MiniMax-M2.7 integrations for multiple coding agents. The managed `oooconf agents provider sync minimax` command covers the agent CLIs currently configured in this repo that support file-based or CLI-provider MiniMax setup:

- Claude Code: writes `env` overrides in `~/.claude/settings.json`, including `ANTHROPIC_BASE_URL` and the MiniMax model aliases expected by Claude Code. Claude Code expects `ANTHROPIC_AUTH_TOKEN` itself to contain the bearer token, so the default mode does not write a literal `{MINIMAX_API_KEY}` placeholder; export `ANTHROPIC_AUTH_TOKEN=$MINIMAX_API_KEY` locally or only use `--materialize-secrets` on private machine config.
- OpenCode: writes a `minimax` provider and selects `minimax/MiniMax-M2.7` in `~/.config/opencode/opencode.json`. OpenCode's own docs also support storing credentials via `opencode auth login --provider minimax`, so `oooconf` does not write the key unless `--materialize-secrets` is requested.
- OpenAI Codex CLI: appends `[model_providers.minimax]` and `[profiles.minimax]` to `~/.codex/config.toml`, loading credentials from `MINIMAX_API_KEY`. The MiniMax guide marks Codex as not recommended and suggests `codex --profile minimax` for this backend.

Other tools listed by MiniMax (Cursor, TRAE, Kilo Code, Cline, Roo Code, Droid, Zed, Grok CLI, Hermes Agent, OpenClaw) are GUI-first, outside the current tracked CLI list, or do not have a stable dotfile target in this repo yet. Add them later only with documented, secret-safe config paths.
