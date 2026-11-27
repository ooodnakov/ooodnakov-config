from __future__ import annotations

import difflib
import json
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any

from .config import (
    common_data_path,
    load_common_data,
    prompt_yes_no,
    read_json,
    write_common_data,
)
from .models import (
    _JSON_TRAILING_COMMA_PATTERN,
    ENV_PLACEHOLDER_PATTERN,
    ENV_REFERENCE_PATTERN,
    AgentConfigTarget,
    interactive_select,
    is_interactive,
    print_error_line,
    print_path,
    print_section,
    print_spacer,
    print_status_line,
    resolve_collab,
)


def normalize_mcp_command(config: dict[str, Any]) -> dict[str, Any]:
    """Normalize npx/npm exec MCP commands to ``pnpm dlx``."""
    updated = dict(config)
    command = str(updated.get("command", "")).strip()
    args = [str(arg) for arg in (updated.get("args") or [])]
    if command == "npx":
        if args[:1] in (["-y"], ["--yes"]):
            args = args[1:]
        updated["command"] = "pnpm"
        updated["args"] = ["dlx", *args]
    elif command == "npm" and args[:1] == ["exec"]:
        updated["command"] = "pnpm"
        updated["args"] = ["dlx", *args[1:]]
    return updated


def is_remote_mcp(config: dict[str, Any]) -> bool:
    """Return True if the MCP definition uses a remote URL."""
    return bool(str(config.get("url", "")).strip())


def is_valid_mcp_definition(config: dict[str, Any]) -> bool:
    """Return True if the MCP definition has either a remote URL or a stdio command."""
    return is_remote_mcp(config) or bool(str(config.get("command", "")).strip())


def _strip_trailing_commas(text: str) -> str:
    return _JSON_TRAILING_COMMA_PATTERN.sub(r"\1", text).rstrip().removesuffix(",")


def _json_object_candidates(payload: str) -> list[str]:
    raw = payload.strip()
    if not raw:
        return []

    # Heuristics for common paste mistakes:
    # 1) User pastes `"name": {...}` without outer braces.
    # 2) User pastes object with a trailing comma.
    # 3) User pastes a single-quoted JSON-like dict.
    variants = [raw, _strip_trailing_commas(raw)]
    if "'" in raw and '"' not in raw:
        fixed = raw.replace("'", '"')
        variants.extend([fixed, _strip_trailing_commas(fixed)])

    candidates: list[str] = []
    for variant in variants:
        candidates.append(variant)
        if not variant.startswith("{") and ":" in variant:
            candidates.append("{" + variant + "}")
    return list(dict.fromkeys(candidates))


def _load_json_object(payload: str) -> dict[str, Any]:
    parse_errors: list[str] = []
    for candidate in _json_object_candidates(payload):
        try:
            parsed = json.loads(candidate)
        except json.JSONDecodeError as exc:
            parse_errors.append(str(exc))
            continue
        if isinstance(parsed, dict):
            return parsed
    hint = 'Ensure the input is a JSON object, e.g. {"name": {"command": "pnpm", "args": ["dlx", "pkg"]}}.'
    details = parse_errors[0] if parse_errors else "Invalid JSON payload."
    raise ValueError(f"{details}. {hint}")


def parse_mcp_json_input(payload: str) -> tuple[str, dict[str, Any]]:
    """Parse a single MCP server JSON object into ``(name, config)``."""
    obj = _load_json_object(payload)
    if len(obj) != 1:
        raise ValueError("MCP JSON input must contain exactly one top-level server entry.")
    name, cfg = next(iter(obj.items()))
    if not isinstance(cfg, dict):
        raise ValueError("MCP server config must be a JSON object.")
    if not is_valid_mcp_definition(cfg):
        raise ValueError("MCP server config must include 'command' (stdio) or 'url' (remote HTTP).")
    return str(name), cfg


def parse_mcp_json_inputs(payload: str, *, allow_multi: bool = False) -> dict[str, dict[str, Any]]:
    """Parse one or more MCP server JSON entries."""
    if not allow_multi:
        name, cfg = parse_mcp_json_input(payload)
        return {name: cfg}
    obj = _load_json_object(payload)
    normalized: dict[str, dict[str, Any]] = {}
    for key, value in obj.items():
        if not isinstance(value, dict):
            raise ValueError(f"MCP entry '{key}' must be an object.")
        if not is_valid_mcp_definition(value):
            raise ValueError(f"MCP entry '{key}' must include 'command' (stdio) or 'url' (remote HTTP).")
        normalized[str(key)] = value
    return normalized


def validate_mcp_entry(name: str, entry: dict[str, Any]) -> None:
    """Validate an MCP server definition, raising ``ValueError`` on invalid fields."""
    remote = is_remote_mcp(entry)
    if remote:
        url = str(entry["url"]).strip()
        if not url.startswith(("http://", "https://")):
            raise ValueError(f"MCP entry '{name}' url must be an http(s) URL.")
        transport = entry.get("type", "http")
        if not isinstance(transport, str) or transport not in {"http", "sse", "remote"}:
            raise ValueError(f"MCP entry '{name}' type must be 'http' or 'sse'.")
        headers = entry.get("headers", {})
        if headers is not None and not isinstance(headers, dict):
            raise ValueError(f"MCP entry '{name}' headers must be an object.")
        if "command" in entry:
            raise ValueError(f"MCP entry '{name}' cannot combine 'url' with 'command'.")
    elif not isinstance(entry.get("command"), str) or not entry["command"].strip():
        raise ValueError(f"MCP entry '{name}' must include 'command' (stdio) or 'url' (remote HTTP).")
    args = entry.get("args", [])
    if args is not None and not isinstance(args, list):
        raise ValueError(f"MCP entry '{name}' args must be a list.")
    if "env" in entry and not isinstance(entry["env"], dict):
        raise ValueError(f"MCP entry '{name}' env must be an object.")


def resolve_mcp_path(repo_root: Path, name: str) -> Path:
    """Resolve and validate the managed checkout directory for an MCP server."""
    del repo_root
    if not name or not name.strip() or name in {".", ".."} or "/" in name or "\\" in name or "\x00" in name:
        raise ValueError(f"invalid MCP server name: {name!r}")
    base = Path("~/.local/share/ooodnakov-config/mcp").expanduser().resolve()
    resolved = (base / name).resolve()
    if resolved == base or not resolved.is_relative_to(base):
        raise ValueError(f"MCP server path escapes managed directory: {name!r}")
    return resolved


def expand_mcp_vars(text: str, mcp_dir: Path, repo_root: Path) -> str:
    """Expand ``~``, ``{mcp_dir}``, and ``{repo_root}`` placeholders."""
    expanded = str(Path(text).expanduser()) if text.startswith("~") else text
    return expanded.replace("{mcp_dir}", str(mcp_dir)).replace("{repo_root}", str(repo_root))


def resolve_env_reference(var_name: str) -> str | None:
    """Look up an environment variable value for MCP secret materialization."""
    import os

    return os.environ.get(var_name)


def replace_env_references(text: str) -> str:
    """Replace ``${VAR}``, ``$VAR``, and ``{VAR}`` references when set in environment."""

    def replace_with_value(match: Any) -> str:
        name = next(group for group in match.groups() if group)
        value = resolve_env_reference(name)
        return value if value is not None else match.group(0)

    return ENV_REFERENCE_PATTERN.sub(replace_with_value, text)


def render_mcp_value(
    value: str,
    *,
    mcp_dir: Path,
    repo_root: Path,
    materialize_secrets: bool = False,
) -> str:
    """Render a string value for an MCP server config."""
    rendered = expand_mcp_vars(value, mcp_dir, repo_root)
    return replace_env_references(rendered) if materialize_secrets else rendered


def build_mcp_env(
    config: dict[str, Any],
    *,
    mcp_dir: Path,
    repo_root: Path,
    materialize_secrets: bool = False,
) -> dict[str, Any]:
    """Build the rendered ``env`` dictionary for a stdio MCP server."""
    env: dict[str, Any] = {}

    for name in config.get("env_vars", []):
        value = resolve_env_reference(name)
        env[name] = value if (value is not None and materialize_secrets) else f"{{{name}}}"

    for key, value in config.get("env", {}).items():
        if isinstance(value, str):
            env[key] = render_mcp_value(
                value,
                mcp_dir=mcp_dir,
                repo_root=repo_root,
                materialize_secrets=materialize_secrets,
            )
        else:
            env[key] = value

    return env


def render_mcp_headers(
    config: dict[str, Any], *, mcp_dir: Path, repo_root: Path, materialize_secrets: bool = False
) -> dict[str, Any]:
    """Render HTTP headers for a remote MCP server."""
    headers: dict[str, Any] = {}
    for key, value in (config.get("headers") or {}).items():
        headers[str(key)] = (
            render_mcp_value(value, mcp_dir=mcp_dir, repo_root=repo_root, materialize_secrets=materialize_secrets)
            if isinstance(value, str)
            else value
        )
    return headers


def render_remote_mcp_entry(
    target: AgentConfigTarget,
    name: str,
    config: dict[str, Any],
    repo_root: Path,
    *,
    materialize_secrets: bool = False,
) -> dict[str, Any]:
    """Render a remote HTTP/SSE MCP server entry for a specific agent target."""
    mcp_dir = resolve_collab("resolve_mcp_path", resolve_mcp_path)(repo_root, name)
    url = render_mcp_value(
        str(config["url"]), mcp_dir=mcp_dir, repo_root=repo_root, materialize_secrets=materialize_secrets
    )
    transport = str(config.get("type") or "http").strip() or "http"
    if transport == "remote":
        transport = "http"
    headers = render_mcp_headers(config, mcp_dir=mcp_dir, repo_root=repo_root, materialize_secrets=materialize_secrets)

    if target.name == "Pi Agent":
        # Pi expands ${VAR} at runtime; keep unresolved placeholders expandable there.
        headers = {
            key: ENV_PLACEHOLDER_PATTERN.sub(lambda m: "${" + m.group(1) + "}", value)
            if isinstance(value, str)
            else value
            for key, value in headers.items()
        }

    if target.name == "Gemini CLI":
        # Gemini distinguishes streamable HTTP (httpUrl) from legacy SSE (url).
        entry: dict[str, Any] = {"httpUrl": url} if transport == "http" else {"url": url}
    elif target.name == "Antigravity":
        # Antigravity Streamable HTTP uses serverUrl without a transport type field.
        entry = {"serverUrl": url}
    elif target.name == "Pi Agent":
        # Pi infers the remote transport from url; it has no separate type field.
        entry = {"url": url}
    else:
        entry = {"type": transport, "url": url}

    if headers:
        entry["headers"] = headers
    return entry


def render_mcp_server_entry(
    target: AgentConfigTarget,
    name: str,
    config: dict[str, Any],
    repo_root: Path,
    *,
    materialize_secrets: bool = False,
) -> dict[str, Any]:
    """Render a stdio or remote MCP server entry for a target."""
    if is_remote_mcp(config):
        return render_remote_mcp_entry(target, name, config, repo_root, materialize_secrets=materialize_secrets)

    mcp_dir = resolve_collab("resolve_mcp_path", resolve_mcp_path)(repo_root, name)
    entry: dict[str, Any] = {
        "command": render_mcp_value(
            config["command"],
            mcp_dir=mcp_dir,
            repo_root=repo_root,
            materialize_secrets=materialize_secrets,
        ),
        "args": [
            render_mcp_value(arg, mcp_dir=mcp_dir, repo_root=repo_root, materialize_secrets=materialize_secrets)
            for arg in (config.get("args") or [])
        ],
    }

    env = build_mcp_env(config, mcp_dir=mcp_dir, repo_root=repo_root, materialize_secrets=materialize_secrets)
    if env:
        entry["env"] = env

    return entry


def render_opencode_mcp_entry(
    target: AgentConfigTarget,
    name: str,
    config: dict[str, Any],
    repo_root: Path,
    *,
    materialize_secrets: bool = False,
) -> dict[str, Any]:
    """Render an OpenCode-formatted MCP entry."""
    entry = render_mcp_server_entry(target, name, config, repo_root, materialize_secrets=materialize_secrets)
    if is_remote_mcp(config):
        mapped: dict[str, Any] = {
            "type": "remote",
            "url": entry["url"],
            "enabled": True,
        }
        if "headers" in entry:
            mapped["headers"] = entry["headers"]
        return mapped

    mapped = {
        "type": "local",
        "command": [entry["command"], *entry.get("args", [])],
        "enabled": True,
    }
    if "env" in entry and isinstance(entry["env"], dict) and entry["env"]:
        mapped["environment"] = entry["env"]
    return mapped


def cmd_mcp_add(
    repo_root: Path,
    config: dict[str, Any],
    name: str | None,
    json_payload: str | None,
    check_only: bool,
    sync_now: bool,
    allow_multi: bool = False,
    preview: bool = False,
) -> int:
    """Add one or more MCP server entries to ``common-data.json``."""
    if json_payload:
        payload = json_payload
    elif not sys.stdin.isatty():
        payload = sys.stdin.read()
    else:
        prompt = "multiple MCP JSON entries" if allow_multi else "single MCP JSON object"
        print_error_line("hint", f"Paste {prompt} and press Ctrl-D:")
        payload = sys.stdin.read()
    if not payload.strip():
        print_status_line("fail", "No MCP JSON payload provided.")
        return 1
    if allow_multi and name:
        print_status_line("fail", "--name cannot be combined with --multi.")
        return 1

    single_named_payload = payload
    if not allow_multi and name:
        try:
            parsed_payload = json.loads(payload)
            if isinstance(parsed_payload, dict) and is_valid_mcp_definition(parsed_payload):
                single_named_payload = json.dumps({name: parsed_payload})
        except json.JSONDecodeError:
            pass

    try:
        parsed_entries = parse_mcp_json_inputs(single_named_payload, allow_multi=allow_multi)
        normalized_entries: dict[str, dict[str, Any]] = {}
        for parsed_name, entry in parsed_entries.items():
            key = name or parsed_name
            normalized = normalize_mcp_command(entry)
            validate_mcp_entry(key, normalized)
            normalized_entries[key] = normalized
    except ValueError as exc:
        print_status_line("fail", str(exc))
        return 1

    data = read_json(repo_root, config["common_data_file"])
    mcp_servers = data.setdefault("mcp_servers", {})
    planned: list[str] = []
    for key, normalized in normalized_entries.items():
        mcp_servers[key] = normalized
        planned.append(key)
    if check_only:
        print_status_line("ok", f"Plan: add MCP(s) {', '.join(planned)} to {config['common_data_file']}")
        return 0
    if preview:
        path = common_data_path(repo_root, config)
        before = path.read_text(encoding="utf-8")
        after = json.dumps(data, indent=2, sort_keys=True) + "\n"
        diff = "\n".join(
            difflib.unified_diff(
                before.splitlines(), after.splitlines(), fromfile="before", tofile="after", lineterm=""
            )
        )
        if diff:
            print(diff)
    write_common_data(repo_root, config, data)
    print_status_line("ok", f"Added MCP(s) {', '.join(planned)} to {config['common_data_file']}")
    prompt_fn = resolve_collab("prompt_yes_no", prompt_yes_no)
    should_sync = sync_now or prompt_fn("Sync global agent configs now?")
    if should_sync:
        sync_fn = resolve_collab("cmd_sync", None)
        if sync_fn is None:
            from .sync import cmd_sync as sync_fn
        return sync_fn(repo_root, config, check_only=False)
    return 0


def cmd_mcp_sync(
    repo_root: Path,
    config: dict[str, Any],
    check_only: bool,
    servers: list[str] | None = None,
    dry_run: bool = False,
    select: bool = False,
) -> int:
    """Clone/pull and install managed MCP servers that declare a ``source`` repo."""
    common_data = resolve_collab("load_common_data", load_common_data)(repo_root, config, include_local=True)
    mcp_servers = common_data.get("mcp_servers", {})
    managed_mcps = {name: cfg for name, cfg in mcp_servers.items() if "source" in cfg}

    if not managed_mcps:
        print_status_line("info", "No managed MCP servers (with 'source') configured.")
        return 0

    if select and servers is not None:
        print_status_line("fail", "--select cannot be combined with --servers.")
        return 1
    if select:
        if not resolve_collab("is_interactive", is_interactive)():
            print_status_line("fail", "--select requires an interactive terminal.")
            return 1
        selected = resolve_collab("interactive_select", interactive_select)(
            sorted(managed_mcps), title="Select MCP servers to sync"
        )
        if selected is None:
            print_status_line("info", "Cancelled.")
            return 1
        if not selected:
            print_status_line("info", "No MCP servers selected.")
            return 0
        servers = selected

    if servers:
        wanted = set(servers)
        unmatched = sorted(wanted - set(managed_mcps))
        for server in unmatched:
            print_status_line("warn", f"No managed MCP server named '{server}'.")
        managed_mcps = {name: cfg for name, cfg in managed_mcps.items() if name in wanted}
        if not managed_mcps:
            print_status_line("warn", f"No managed MCP servers match: {', '.join(servers)}")
            return 1

    print_section("MCP Sync (dry-run)" if dry_run else "MCP Sync")
    print_status_line("hint", f"Mode: {'dry-run' if dry_run else 'check' if check_only else 'sync'}")
    if servers:
        print_status_line("hint", f"Servers: {', '.join(servers)}")

    attempted = 0
    failed = 0
    synced = 0
    subprocess_mod = resolve_collab("subprocess", subprocess)
    resolve_path_fn = resolve_collab("resolve_mcp_path", resolve_mcp_path)

    for name, cfg in managed_mcps.items():
        source = cfg["source"]
        mcp_dir = resolve_path_fn(repo_root, name)
        install_cmd = cfg.get("install")

        attempted += 1
        print_status_line("info", f"Syncing {name} ({source})")

        if not isinstance(source, str) or not source.strip() or source.lstrip().startswith("-"):
            print_status_line("fail", f"Refusing unsafe MCP source for {name}: {source!r}")
            failed += 1
            continue

        if dry_run:
            if not mcp_dir.exists():
                print_status_line("hint", f"  Would clone into {print_path(mcp_dir)}")
            else:
                print_status_line("hint", f"  Would pull latest changes in {print_path(mcp_dir)}")
            if install_cmd:
                print_status_line("hint", f"  Would run install: {install_cmd}")
            else:
                print_status_line("hint", "  No install needed")
            continue

        if not mcp_dir.parent.exists() and not check_only:
            mcp_dir.parent.mkdir(parents=True, exist_ok=True)

        if not mcp_dir.exists():
            print_status_line("hint", f"  Cloning into {print_path(mcp_dir)}...")
            if check_only:
                synced += 1
                continue
            try:
                subprocess_mod.run(["git", "clone", "--", source, str(mcp_dir)], check=True)
            except subprocess.CalledProcessError as exc:
                print_status_line("fail", f"Failed to clone {name}: {exc}")
                failed += 1
                continue
        else:
            print_status_line("hint", f"  Pulling latest changes in {print_path(mcp_dir)}...")
            if not check_only:
                try:
                    subprocess_mod.run(["git", "-C", str(mcp_dir), "pull", "--ff-only"], check=True)
                except subprocess.CalledProcessError as exc:
                    print_status_line("warn", f"Failed to pull {name} (continuing): {exc}")

        if install_cmd:
            print_status_line("hint", f"  Running install: {install_cmd}")
            if check_only:
                synced += 1
                continue

            try:
                cmd_parts = shlex.split(install_cmd)
                if not cmd_parts:
                    continue
                subprocess_mod.run(cmd_parts, check=True, cwd=str(mcp_dir))
                print_status_line("ok", f"Successfully installed {name}")
                synced += 1
            except subprocess.CalledProcessError as exc:
                print_status_line("fail", f"Install failed for {name}: {exc}")
                failed += 1
                continue
        else:
            print_status_line("ok", f"Synced {name} (no install needed)")
            synced += 1

    print_spacer()
    print_status_line("info", f"Summary: synced {synced}/{attempted} managed MCPs; failed {failed}.")
    return 1 if failed else 0


def cmd_mcp_status(repo_root: Path, config: dict[str, Any]) -> int:
    """Display the status of managed and static MCP servers."""
    common_data = resolve_collab("load_common_data", load_common_data)(repo_root, config, include_local=True)
    mcp_servers = common_data.get("mcp_servers", {})
    resolve_path_fn = resolve_collab("resolve_mcp_path", resolve_mcp_path)

    print_section("MCP Status")

    for name, cfg in sorted(mcp_servers.items()):
        source = cfg.get("source")
        if source:
            mcp_dir = resolve_path_fn(repo_root, name)
            if mcp_dir.exists():
                print_status_line("ok", f"{name} (managed): {mcp_dir}")
            else:
                print_status_line("missing", f"{name} (managed): {mcp_dir} NOT CLONED")
        else:
            if is_remote_mcp(cfg):
                print_status_line("ok", f"{name} (static): {cfg.get('type', 'http')} {cfg.get('url')}")
            else:
                print_status_line("ok", f"{name} (static): {cfg.get('command')} {shlex.join(cfg.get('args') or [])}")

    return 0
