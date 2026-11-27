from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
from pathlib import Path
from typing import Any

from .config import (
    detect_clis,
    ensure_parent,
    existing_default_path,
    get_platform_common_text,
    load_common_data,
    parse_agent_clis,
    parse_agent_targets,
    parse_agent_update_specs,
    read_json_file_or_empty,
    read_text,
    replace_or_append_toml_table,
    select_agent_targets,
    toml_key,
    toml_table_exists,
    upsert_nested_dict,
    write_json_atomic,
    write_text_atomic,
)
from .mcp import is_valid_mcp_definition, render_mcp_server_entry, render_opencode_mcp_entry
from .models import (
    AGENT_EXTRA_HEADING,
    MANAGED_BEGIN,
    MANAGED_END,
    AgentConfigTarget,
    interactive_select,
    is_interactive,
    print_bullet,
    print_error_line,
    print_path,
    print_section,
    print_spacer,
    print_status_line,
    resolve_collab,
)

MINIMAX_MODEL = "MiniMax-M2.7"
MINIMAX_CODEX_MODEL = "codex-MiniMax-M2.7"
MINIMAX_ENV_KEY = "MINIMAX_API_KEY"


def apply_agent_extra(managed_block: str, extra_text: str) -> str:
    """Insert per-agent instructions directly before ``MANAGED_END``."""
    body = extra_text.strip()
    if not body or MANAGED_END not in managed_block:
        return managed_block
    marker_index = managed_block.rindex(MANAGED_END)
    prefix = managed_block[:marker_index].rstrip("\n")
    suffix = managed_block[marker_index:]
    section = f"{AGENT_EXTRA_HEADING}\n\n{body}"
    return f"{prefix}\n\n{section}\n\n{suffix}"


def render_frontmatter(frontmatter: dict[str, str] | None) -> str:
    """Render YAML frontmatter for modular rule files such as Antigravity rules."""
    if not frontmatter:
        return ""
    lines = ["---"]
    for key, value in frontmatter.items():
        text = str(value)
        rendered_val = text if key == "trigger" else json.dumps(text)
        lines.append(f"{key}: {rendered_val}")
    lines.append("---")
    return "\n".join(lines) + "\n"


def render_extra_only_block(extra_text: str) -> str:
    """Render a standalone managed block containing only per-agent instructions."""
    body = extra_text.strip()
    if not body:
        return ""
    return f"{MANAGED_BEGIN}\n{AGENT_EXTRA_HEADING}\n\n{body}\n\n{MANAGED_END}\n"


def ensure_frontmatter(content: str, frontmatter: dict[str, str] | None) -> str:
    """Prepend YAML frontmatter if configured and not already present."""
    rendered = render_frontmatter(frontmatter)
    if not rendered:
        return content
    if content.startswith(("---\n", "---\r\n")):
        return content
    stripped = content.lstrip("\r\n")
    if not stripped:
        return rendered
    return f"{rendered}\n{stripped}"


def render_markdown_block(common_text: str, common_data: dict[str, Any], extra_text: str = "") -> str:
    """Render the shared AGENTS.md managed block."""
    mcp_servers: dict[str, dict[str, Any]] = common_data.get("mcp_servers", {})
    skills_entries: list[str] = sorted(common_data.get("skills", []))

    lines = [
        MANAGED_BEGIN,
        "## oooconf shared agent policy",
        "",
        common_text.rstrip(),
        "",
        "## Common MCP servers",
        "<!-- oooconf:mcp-servers:start -->",
    ]
    for name, config in sorted(mcp_servers.items()):
        desc = config.get("description", "No description")
        lines.append(f"- `{name}`: {desc}")
    lines.append("<!-- oooconf:mcp-servers:end -->")

    lines.extend(["", "## Common Skills", "<!-- oooconf:skills:start -->"])
    lines.extend([f"- {skill}" for skill in skills_entries])
    lines.extend(["<!-- oooconf:skills:end -->", MANAGED_END, ""])
    return apply_agent_extra("\n".join(lines), extra_text)


def upsert_managed_block(existing: str, managed_block: str) -> str:
    """Insert or replace the managed block inside an existing markdown file."""
    if MANAGED_BEGIN in existing and MANAGED_END in existing:
        start = existing.index(MANAGED_BEGIN)
        end = existing.rindex(MANAGED_END) + len(MANAGED_END)
        prefix = existing[:start]
        suffix = existing[end:].lstrip("\n")
        if not prefix.strip():
            return managed_block + suffix
        return prefix.rstrip() + "\n\n" + managed_block + suffix
    if not existing.strip():
        return managed_block
    return existing.rstrip() + "\n\n" + managed_block


def _sync_mcp_file_target(
    repo_root: Path,
    target: AgentConfigTarget,
    common_data: dict[str, Any],
    check_only: bool,
    materialize_secrets: bool,
) -> Path | None:
    mcp_file: Path | None = None
    for mp in target.mcp_paths or ():
        candidate = Path(mp).expanduser()
        if candidate.exists() or candidate.parent.exists():
            mcp_file = candidate
            break
    if not mcp_file:
        return None
    render_entry = resolve_collab("render_mcp_server_entry", render_mcp_server_entry)
    try:
        mcp_data = json.loads(mcp_file.read_text(encoding="utf-8")) if mcp_file.exists() else {}
        mcp_servers = common_data.get("mcp_servers", {})
        mcp_key = "mcpServers"
        if mcp_key not in mcp_data:
            mcp_data[mcp_key] = {}
        needs_update = False
        for name, config in mcp_servers.items():
            if name not in mcp_data[mcp_key]:
                if not is_valid_mcp_definition(config):
                    continue
                mcp_data[mcp_key][name] = render_entry(
                    target, name, config, repo_root, materialize_secrets=materialize_secrets
                )
                needs_update = True
        if needs_update:
            if not check_only:
                write_json_atomic(mcp_file, mcp_data)
            return mcp_file
    except Exception as exc:
        print_error_line("warn", f"failed to sync mcp file {mcp_file}: {exc}")
    return None


def _sync_markdown_target(
    existing: Path,
    target: AgentConfigTarget,
    managed_block: str,
    check_only: bool,
    extras: dict[str, str] | None,
) -> Path | None:
    extra_text = (extras or {}).get(target.name, "")
    if target.extra_only:
        block = render_extra_only_block(extra_text)
        if not block:
            return None
    else:
        block = apply_agent_extra(managed_block, extra_text)
    try:
        if not existing.exists():
            rendered = ensure_frontmatter(block, target.frontmatter)
            if not check_only:
                write_text_atomic(existing, rendered)
            return existing

        current = existing.read_text(encoding="utf-8")
        updated = ensure_frontmatter(upsert_managed_block(current, block), target.frontmatter)
        if updated != current:
            if not check_only:
                write_text_atomic(existing, updated)
            return existing
    except Exception as exc:
        print_error_line("warn", f"failed to sync global markdown {existing}: {exc}")
    return None


def _sync_toml_target(
    repo_root: Path,
    existing: Path,
    target: AgentConfigTarget,
    common_data: dict[str, Any],
    check_only: bool,
    materialize_secrets: bool,
) -> Path | None:
    render_entry = resolve_collab("render_mcp_server_entry", render_mcp_server_entry)
    try:
        current = existing.read_text(encoding="utf-8")
        updated = current
        needs_update = False
        mcp_servers = common_data.get("mcp_servers", {})
        for name, config in mcp_servers.items():
            table = f"mcp_servers.{toml_key(name)}"
            if toml_table_exists(updated, table) or not is_valid_mcp_definition(config):
                continue

            entry = render_entry(target, name, config, repo_root, materialize_secrets=materialize_secrets)
            if "url" in entry:
                block = (
                    f"\n[{table}]\ntype = {json.dumps(entry.get('type', 'http'))}\nurl = {json.dumps(entry['url'])}\n"
                )
                headers = entry.get("headers")
                if isinstance(headers, dict) and headers:
                    block += f"\n[{table}.http_headers]\n"
                    for key, value in headers.items():
                        block += f"{toml_key(key)} = {json.dumps(value)}\n"
            else:
                block = f"\n[{table}]\ncommand = {json.dumps(entry['command'])}\nargs = {json.dumps(entry['args'])}\n"
                if "env" in entry:
                    block += f"[{table}.env]\n"
                    for key, value in entry["env"].items():
                        block += f"{toml_key(key)} = {json.dumps(value)}\n"

            updated += block
            needs_update = True

        if needs_update:
            if not check_only:
                write_text_atomic(existing, updated)
            return existing
    except Exception as exc:
        print_error_line("warn", f"failed to sync global toml {existing}: {exc}")
    return None


def _sync_json_target(
    repo_root: Path,
    existing: Path,
    target: AgentConfigTarget,
    common_data: dict[str, Any],
    check_only: bool,
    materialize_secrets: bool,
) -> Path | None:
    render_entry = resolve_collab("render_mcp_server_entry", render_mcp_server_entry)
    render_opencode = resolve_collab("render_opencode_mcp_entry", render_opencode_mcp_entry)
    try:
        data = json.loads(existing.read_text(encoding="utf-8"))
        needs_update = False
        mcp_servers = common_data.get("mcp_servers", {})

        if mcp_servers and target.name != "OpenCode":
            if "mcpServers" not in data:
                data["mcpServers"] = {}
            for name, config in mcp_servers.items():
                if name not in data["mcpServers"] and is_valid_mcp_definition(config):
                    data["mcpServers"][name] = render_entry(
                        target, name, config, repo_root, materialize_secrets=materialize_secrets
                    )
                    needs_update = True

        if mcp_servers and target.name == "OpenCode":
            if "mcp" not in data or not isinstance(data.get("mcp"), dict):
                data["mcp"] = {}
                needs_update = True
            for name, config in mcp_servers.items():
                if name not in data["mcp"] and is_valid_mcp_definition(config):
                    data["mcp"][name] = render_opencode(
                        target, name, config, repo_root, materialize_secrets=materialize_secrets
                    )
                    needs_update = True

        if target.name == "Gemini CLI":
            if "context" not in data:
                data["context"] = {}
                needs_update = True
            required_files = ["AGENTS.md", "GEMINI.md"]
            current_files = data["context"].get("fileName", [])
            if not isinstance(current_files, list):
                current_files = [current_files] if current_files else []
            updated_files = list(current_files)
            file_needs_update = False
            for fname in required_files:
                if fname not in updated_files:
                    updated_files.append(fname)
                    file_needs_update = True
            if file_needs_update:
                data["context"]["fileName"] = updated_files
                needs_update = True

        if needs_update:
            if not check_only:
                write_json_atomic(existing, data)
            return existing
    except Exception as exc:
        print_error_line("warn", f"failed to sync global config {existing}: {exc}")
    return None


def sync_global_configs(
    repo_root: Path,
    targets: list[AgentConfigTarget],
    common_data: dict[str, Any],
    managed_block: str,
    check_only: bool,
    materialize_secrets: bool = False,
    extras: dict[str, str] | None = None,
) -> tuple[int, list[Path]]:
    """Sync managed instructions and MCP server definitions into global agent configs."""
    changed: list[Path] = []

    for target in targets:
        existing = existing_default_path(target.default_paths)

        if existing is None and target.format == "markdown":
            anchor = Path(target.create_if_dir_exists).expanduser() if target.create_if_dir_exists else None
            for p in target.default_paths:
                candidate = Path(p).expanduser()
                if candidate.parent.exists() or (anchor is not None and anchor.is_dir()):
                    existing = candidate
                    break

        if existing is None:
            continue

        if target.mcp_paths and not target.mcp_skip:
            updated_path = _sync_mcp_file_target(repo_root, target, common_data, check_only, materialize_secrets)
            if updated_path is not None:
                changed.append(updated_path)
            continue

        if target.mcp_skip and target.format != "markdown":
            continue

        if target.format == "markdown":
            updated_path = _sync_markdown_target(existing, target, managed_block, check_only, extras)
        elif target.format == "toml":
            updated_path = _sync_toml_target(repo_root, existing, target, common_data, check_only, materialize_secrets)
        elif target.format == "json":
            updated_path = _sync_json_target(repo_root, existing, target, common_data, check_only, materialize_secrets)
        else:
            updated_path = None

        if updated_path is not None:
            changed.append(updated_path)

    return len(changed), changed


def cmd_sync(
    repo_root: Path,
    config: dict[str, Any],
    check_only: bool,
    materialize_secrets: bool = False,
    agents: list[str] | None = None,
    select: bool = False,
    dry_run: bool = False,
) -> int:
    """Sync shared AGENTS.md instructions and MCP entries into global agent configs."""
    read_only = check_only or dry_run
    common_text = get_platform_common_text(repo_root, config)
    merged_data = resolve_collab("load_common_data", load_common_data)(repo_root, config, include_local=True)
    managed_block = resolve_collab("render_markdown_block", render_markdown_block)(common_text, merged_data)
    all_targets = parse_agent_targets(config["agent_configs"])
    update_specs = parse_agent_update_specs(config.get("agent_updates", []))

    print_section("AGENTS Sync (dry-run)" if dry_run else "AGENTS Sync")
    print_status_line("hint", f"Mode: {'dry-run' if dry_run else 'check' if check_only else 'sync'}")

    if select and agents is not None:
        print_status_line("fail", "--select cannot be combined with --agents.")
        return 1

    if select:
        if not resolve_collab("is_interactive", is_interactive)():
            print_status_line("fail", "--select requires an interactive terminal.")
            return 1
        selected_names = resolve_collab("interactive_select", interactive_select)(
            [target.name for target in all_targets],
            title="Select agents to sync",
            instructions="SPACE toggle  ENTER confirm  A all  N none  Q quit",
        )
        if selected_names is None:
            print_status_line("info", "Cancelled.")
            return 1
        if not selected_names:
            print_status_line("info", "No agents selected.")
            return 0
        targets = [target for target in all_targets if target.name in selected_names]
    else:
        targets, unmatched = select_agent_targets(all_targets, update_specs, agents)
        for query in unmatched:
            print_status_line("warn", f"No global config target matches agent '{query}'.")

    if not targets:
        print_status_line("warn", "No agent config targets selected.")
        return 1 if agents or select else 0

    extras: dict[str, str] = {}
    extra_paths: dict[str, str] = {}
    for target in targets:
        if target.format != "markdown" or not target.extra_text_file:
            continue
        try:
            extras[target.name] = read_text(repo_root, target.extra_text_file)
            extra_paths[target.name] = target.extra_text_file
        except Exception as exc:
            print_error_line("warn", f"failed to read extra text for {target.name}: {exc}")

    if dry_run:
        print_status_line("hint", f"Targets: {len(targets)}")
        print_status_line("hint", "Managed block preview:")
        preview = managed_block.split("\n")
        for line in preview[:20]:
            print_status_line("hint", f"  {line}")
        if len(preview) > 20:
            print_status_line("hint", "  ...")
        for name, relative_path in extra_paths.items():
            print_status_line("hint", f"Extras: {name} -> {relative_path}")
            print_status_line("hint", f"  {AGENT_EXTRA_HEADING}")
            extra_lines = extras[name].strip().split("\n") if extras[name].strip() else []
            for line in extra_lines[:5]:
                print_status_line("hint", f"  {line}")
            if len(extra_lines) > 5:
                print_status_line("hint", "  ...")

    sync_fn = resolve_collab("sync_global_configs", sync_global_configs)
    g_count, g_files = sync_fn(
        repo_root,
        targets,
        merged_data,
        managed_block,
        read_only,
        materialize_secrets=materialize_secrets,
        extras=extras,
    )
    print_status_line("hint", f"Global configs scanned: {len(targets)}")
    print_status_line("hint", f"Global configs needing updates: {g_count}")
    if g_files:
        for file_path in g_files:
            print_bullet(str(file_path))
    if g_count == 0:
        print_spacer()
        print_status_line("ok", "All target files are up to date.")

    return 1 if check_only and g_count > 0 else 0


def minimax_endpoints(region: str) -> dict[str, str]:
    """Return MiniMax API endpoints for ``global`` or ``china`` regions."""
    if region == "china":
        return {
            "openai_base_url": "https://api.minimaxi.com/v1",
            "anthropic_base_url": "https://api.minimaxi.com/anthropic",
            "opencode_anthropic_base_url": "https://api.minimaxi.com/anthropic/v1",
        }
    return {
        "openai_base_url": "https://api.minimax.io/v1",
        "anthropic_base_url": "https://api.minimax.io/anthropic",
        "opencode_anthropic_base_url": "https://api.minimax.io/anthropic/v1",
    }


def upsert_claude_minimax_config(path: Path, region: str, materialize_secrets: bool, check_only: bool) -> bool:
    """Update Claude Code settings JSON with MiniMax provider settings."""
    data = read_json_file_or_empty(path)
    endpoints = minimax_endpoints(region)
    api_key = os.environ.get(MINIMAX_ENV_KEY)
    env_updates = {
        "ANTHROPIC_BASE_URL": endpoints["anthropic_base_url"],
        "API_TIMEOUT_MS": "3000000",
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
        "ANTHROPIC_MODEL": MINIMAX_MODEL,
        "ANTHROPIC_DEFAULT_SONNET_MODEL": MINIMAX_MODEL,
        "ANTHROPIC_DEFAULT_OPUS_MODEL": MINIMAX_MODEL,
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": MINIMAX_MODEL,
    }
    if materialize_secrets and api_key is not None:
        env_updates["ANTHROPIC_AUTH_TOKEN"] = api_key
    changed = upsert_nested_dict(data, {"env": env_updates})
    env = data.get("env")
    if not materialize_secrets and isinstance(env, dict):
        token = env.get("ANTHROPIC_AUTH_TOKEN")
        if token is not None and (token == f"{{{MINIMAX_ENV_KEY}}}" or (api_key is not None and token == api_key)):
            del env["ANTHROPIC_AUTH_TOKEN"]
            changed = True
    if changed:
        ensure_parent(path, check_only)
        if not check_only:
            write_json_atomic(path, data)
    return changed


def upsert_opencode_minimax_config(path: Path, region: str, materialize_secrets: bool, check_only: bool) -> bool:
    """Update OpenCode config JSON with MiniMax provider settings."""
    data = read_json_file_or_empty(path)
    endpoints = minimax_endpoints(region)
    provider_options: dict[str, Any] = {"baseURL": endpoints["opencode_anthropic_base_url"]}
    api_key = os.environ.get(MINIMAX_ENV_KEY)
    if materialize_secrets and api_key is not None:
        provider_options["apiKey"] = api_key
    updates = {
        "$schema": "https://opencode.ai/config.json",
        "model": f"minimax/{MINIMAX_MODEL}",
        "provider": {
            "minimax": {
                "npm": "@ai-sdk/anthropic",
                "options": provider_options,
                "models": {MINIMAX_MODEL: {"name": MINIMAX_MODEL}},
            }
        },
    }
    changed = upsert_nested_dict(data, updates)
    if changed:
        ensure_parent(path, check_only)
        if not check_only:
            write_json_atomic(path, data)
    return changed


def render_codex_minimax_profile() -> str:
    """Render the Codex CLI ``[profiles.minimax]`` TOML section."""
    return f'[profiles.minimax]\nmodel = "{MINIMAX_CODEX_MODEL}"\nmodel_provider = "minimax"\n'


def render_codex_minimax_provider(region: str, materialize_secrets: bool = False, api_key: str | None = None) -> str:
    """Render the Codex CLI ``[model_providers.minimax]`` TOML section."""
    endpoints = minimax_endpoints(region)
    del materialize_secrets, api_key
    return (
        "[model_providers.minimax]\n"
        'name = "MiniMax Chat Completions API"\n'
        f'base_url = "{endpoints["openai_base_url"]}"\n'
        f'env_key = "{MINIMAX_ENV_KEY}"\n'
        'env_key_instructions = "Export MINIMAX_API_KEY before starting Codex."\n'
        'wire_api = "chat"\n'
        "requires_openai_auth = false\n"
        "request_max_retries = 4\n"
        "stream_max_retries = 10\n"
        "stream_idle_timeout_ms = 300000\n"
    )


def append_codex_minimax_config(path: Path, region: str, materialize_secrets: bool, check_only: bool) -> bool:
    """Update Codex CLI TOML config with MiniMax provider and profile tables."""
    current = path.read_text(encoding="utf-8") if path.exists() else ""
    api_key = os.environ.get(MINIMAX_ENV_KEY)
    updated, provider_changed = replace_or_append_toml_table(
        current,
        "model_providers.minimax",
        render_codex_minimax_provider(region, materialize_secrets and api_key is not None, api_key),
    )
    updated, profile_changed = replace_or_append_toml_table(updated, "profiles.minimax", render_codex_minimax_profile())
    changed = provider_changed or profile_changed
    if changed:
        ensure_parent(path, check_only)
        if not check_only:
            write_text_atomic(path, updated)
    return changed


def cmd_provider_sync(
    config: dict[str, Any],
    provider: str,
    check_only: bool,
    materialize_secrets: bool,
    region: str,
    agents: list[str] | None = None,
    dry_run: bool = False,
    select: bool = False,
) -> int:
    """Sync a model/API provider backend into supported agent configs."""
    if provider != "minimax":
        print_status_line("fail", f"Unsupported provider: {provider}")
        return 1

    read_only = check_only or dry_run
    all_targets = parse_agent_targets(config["agent_configs"])
    update_specs = parse_agent_update_specs(config.get("agent_updates", []))
    supported = {
        "Claude Code": upsert_claude_minimax_config,
        "OpenCode": upsert_opencode_minimax_config,
        "OpenAI Codex CLI": append_codex_minimax_config,
    }

    if select and agents is not None:
        print_status_line("fail", "--select cannot be combined with --agents.")
        return 1
    if select:
        if not resolve_collab("is_interactive", is_interactive)():
            print_status_line("fail", "--select requires an interactive terminal.")
            return 1
        supported_names = [target.name for target in all_targets if target.name in supported]
        agents = resolve_collab("interactive_select", interactive_select)(
            supported_names, title="Select agents to configure provider"
        )
        if agents is None:
            print_status_line("info", "Cancelled.")
            return 1
        if not agents:
            print_status_line("info", "No agents selected.")
            return 0
        targets = [target for target in all_targets if target.name in agents]
    else:
        targets, unmatched = select_agent_targets(all_targets, update_specs, agents)
        for query in unmatched:
            print_status_line("warn", f"No agent config target matches agent '{query}'.")

    print_section("Agent Provider Sync (dry-run)" if dry_run else "Agent Provider Sync")
    print_status_line("hint", f"Provider: {provider}")
    print_status_line("hint", f"Region: {region}")
    print_status_line("hint", f"Mode: {'dry-run' if dry_run else 'check' if check_only else 'sync'}")
    if agents:
        print_status_line("hint", f"Agents: {', '.join(agents)}")

    if materialize_secrets and not os.environ.get(MINIMAX_ENV_KEY):
        print_status_line("fail", f"{MINIMAX_ENV_KEY} is not set; refusing to materialize an empty API key.")
        return 1

    changed_paths: list[Path] = []
    supported_targets = 0

    for target in targets:
        updater = supported.get(target.name)
        if updater is None or not target.default_paths:
            continue
        supported_targets += 1
        path = existing_default_path(target.default_paths) or Path(target.default_paths[0]).expanduser()
        try:
            changed = updater(path, region, materialize_secrets, read_only)
        except Exception as exc:
            print_status_line("fail", f"{target.name}: failed to update {print_path(path)}: {exc}")
            return 1
        status = "ok" if changed else "info"
        action = "would update" if read_only and changed else "updated" if changed else "already configured"
        print_status_line(status, f"{target.name}: {action} {print_path(path)}")
        if changed:
            changed_paths.append(path)

    if supported_targets == 0:
        print_status_line("warn", "No supported provider targets selected (supported: Claude Code, OpenCode, Codex).")
        return 1 if agents or select else 0

    print_spacer()
    print_status_line(
        "info",
        f"Summary: {len(changed_paths)} supported provider config(s) {'would change' if read_only else 'changed'}.",
    )
    if not materialize_secrets:
        print_status_line("hint", f"Hint: export {MINIMAX_ENV_KEY} in your local env before launching Codex.")
        print_status_line(
            "hint",
            "Hint: Claude Code requires ANTHROPIC_AUTH_TOKEN to contain the MiniMax key; export "
            f"ANTHROPIC_AUTH_TOKEN=${MINIMAX_ENV_KEY} before launching Claude or rerun with --materialize-secrets.",
        )
        print_status_line(
            "hint",
            "Hint: OpenCode stores provider credentials via `opencode auth login --provider minimax`; rerun with "
            "--materialize-secrets only if you intentionally want the key written to opencode.json.",
        )
    return 1 if check_only and changed_paths else 0


def cmd_rtk_init(repo_root: Path, config: dict[str, Any], check_only: bool, dry_run: bool = False) -> int:
    """Initialize RTK (Rust Token Killer) global hooks for detected agents."""
    del repo_root
    if os.name == "nt":
        print_status_line("fail", "RTK hook-based initialization is not supported on Windows.")
        return 0

    shutil_mod = resolve_collab("shutil", shutil)
    subprocess_mod = resolve_collab("subprocess", subprocess)

    if not shutil_mod.which("rtk"):
        print_status_line("fail", "rtk command not found. Install it first (e.g., via 'oooconf deps rtk').")
        return 1

    rows = resolve_collab("detect_clis", detect_clis)(parse_agent_clis(config["agent_clis"]))
    installed_agents = {row["command"] for row in rows if row["installed"]}

    if not installed_agents:
        print_status_line("info", "No agents detected; nothing to initialize.")
        return 0

    print_section("RTK Init (dry-run)" if dry_run else "RTK Init")
    print_status_line("hint", f"Mode: {'dry-run' if dry_run else 'check' if check_only else 'init'}")

    agent_map = {
        "claude": ["--auto-patch", "--agent", "claude"],
        "gemini": ["--auto-patch", "--gemini"],
        "codex": ["--codex"],
        "opencode": ["--auto-patch", "--opencode"],
        "cursor-agent": ["--auto-patch", "--agent", "cursor"],
    }

    attempted = 0
    synced = 0
    failed = 0

    for agent_cmd, flags in agent_map.items():
        if agent_cmd in installed_agents:
            attempted += 1
            cmd = ["rtk", "init", "--global", *flags]
            cmd_display = shlex.join(cmd)
            print_status_line("info", f"Initializing RTK for {agent_cmd}")
            print_status_line("hint", f"  command: {cmd_display}")

            if check_only or dry_run:
                synced += 1
                continue

            try:
                subprocess_mod.run(cmd, check=True)
                print_status_line("ok", f"Successfully initialized {agent_cmd}")
                synced += 1
            except subprocess.CalledProcessError as exc:
                print_status_line("fail", f"Failed to initialize {agent_cmd}: {exc}")
                failed += 1

    print_spacer()
    print_status_line("info", f"Summary: initialized RTK for {synced}/{attempted} detected agents; failed {failed}.")
    return 1 if failed else 0
