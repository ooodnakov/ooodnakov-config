# Agent policy management

The `oooconf agents` command family detects, renders, and keeps shared agent policy, MCP servers, skills, and provider settings in sync across the configured agent CLIs.

## Commands

```bash
oooconf agents detect
oooconf agents sync
oooconf agents sync --check
oooconf agents sync --agents claude
oooconf agents doctor
oooconf agents mcp sync
oooconf agents mcp sync --servers context7
oooconf agents mcp status
oooconf agents rtk init
oooconf agents provider sync minimax
oooconf agents provider sync minimax --agents codex
oooconf agents skills sync
oooconf agents skills view
oooconf agents install --check
oooconf agents install
oooconf agents install codex gemini
oooconf agents install --all
oooconf agents update
oooconf agents install-scripts-build
```

## Shared policy sources

The shared AGENTS policy snippets are configured in:

- `home/.config/ooodnakov/agents/config.json`
- `home/.config/ooodnakov/agents/common-text.md`
- `home/.config/ooodnakov/agents/common-data.json` (structured MCP + skills data)
- `home/.config/ooodnakov/agents/extras/<agent>.md` (per-agent inserts, referenced by `extra_text_file`)
- `docs/agents-config-research.md` (cross-agent config model comparison and rationale)

An `agent_configs` entry may set `extra_text_file`, a repo-relative Markdown file whose contents are appended inside that target's managed block under `## Agent-specific instructions`. Extras stay inside the `oooconf:agents-common` markers, so they are replaced on every sync and never accumulate; targets without the key render the shared block unchanged. Currently only the Oh My Pi global instructions target carries an extra (`extras/omp.md`: independent batching, scoped delegation, native tooling, evidence-based recovery, asynchronous execution, persistent state, and focused output).

## Sync behavior

`oooconf agents doctor` also checks common MCP/skills markers against default agent config paths by format (JSON, TOML, YAML). Use `oooconf agents doctor --strict-config-paths` to fail when none of an agent's documented default config paths exist locally.
`oooconf agents sync` targets every configured global agent config by default and is idempotent. Pass agent keys such as `--agents claude codex` to narrow it, or `--select` to choose interactively. `--check` exits non-zero when any target is stale; `--dry-run` prints the same plan without writing.
`oooconf agents install` installs missing configured agent CLIs by default. Pass one or more agent keys such as `codex gemini`, `--missing` for explicit missing-only mode, or `--all` to install or upgrade every configured agent CLI. `--check` and `--dry-run` preview the installer commands and post-install steps without running them.
`oooconf agents update` updates only agent CLIs that are currently installed on `PATH`, routes pnpm-preferred agents through `pnpm add -g <package>@latest` (falling back to `npm install -g` when pnpm is unavailable), and reruns configured post-install steps.

## Providers

`oooconf agents sync` understands both stdio entries (`command`/`args`) and remote HTTP entries (`type`/`url`/`headers`) in `common-data.json`, rendering each agent's native shape: `type`+`url` for Claude Code, Oh My Pi, and Pi, `httpUrl` for Gemini CLI, `type = "remote"` for OpenCode, and `[mcp_servers.<name>]` with `http_headers` tables for Codex. MCP `env_vars` shorthands resolve. `{env_var}`/`$env_var` placeholders are kept verbatim unless `--materialize-secrets` is passed, so generated configs stay secret-free by default.
`oooconf agents provider sync minimax` configures MiniMax-M2.7 backends for Claude Code (`~/.claude/settings.json`), OpenCode (`~/.config/opencode/opencode.json`), and Codex CLI (`~/.codex/config.toml`) while keeping `MINIMAX_API_KEY` in the local environment by default for Codex/OpenCode; Claude Code also needs `ANTHROPIC_AUTH_TOKEN` exported to the MiniMax key unless `--materialize-secrets` is intentionally used on private machine config.
