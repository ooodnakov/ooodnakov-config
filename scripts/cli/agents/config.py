from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from .models import (
    DEFAULT_CONFIG_PATH,
    REPO_ROOT_DEFAULT,
    RTK_BEGIN,
    RTK_END,
    TOML_BARE_KEY_PATTERN,
    AgentCli,
    AgentConfigTarget,
    AgentUpdateSpec,
    print_error_line,
    resolve_collab,
)


def resolve_repo_root(repo_root: str | None) -> Path:
    """Resolve the repository root from CLI arg, env var, or package location."""
    if repo_root:
        return Path(repo_root).expanduser().resolve()
    env_root = os.environ.get("OOODNAKOV_REPO_ROOT")
    if env_root:
        return Path(env_root).expanduser().resolve()
    return REPO_ROOT_DEFAULT


def resolve_config_path(repo_root: Path, config_override: str | None) -> Path:
    """Resolve the agent config JSON path."""
    return (
        Path(config_override).expanduser().resolve() if config_override else (repo_root / DEFAULT_CONFIG_PATH).resolve()
    )


def load_config(path: Path) -> dict[str, Any]:
    """Load and validate the top-level agents configuration JSON."""
    if not path.exists():
        raise FileNotFoundError(f"agent config not found: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    required = {"agent_files", "common_text_file", "common_data_file", "agent_clis", "agent_configs"}
    missing = sorted(required - set(data.keys()))
    if missing:
        raise ValueError(f"agent config missing keys: {', '.join(missing)}")
    return data


def read_text(repo_root: Path, relative_path: str) -> str:
    """Read a repo-relative UTF-8 text file normalized with a single trailing newline."""
    path = (repo_root / relative_path).resolve()
    if not path.exists():
        raise FileNotFoundError(f"missing configured file: {path}")
    return path.read_text(encoding="utf-8").rstrip() + "\n"


def write_text_atomic(path: Path, text: str, *, mode: int | None = None) -> None:
    """Replace ``path`` atomically so a failed write cannot truncate a live config."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        if mode is not None:
            os.chmod(tmp_name, mode)
        os.replace(tmp_name, path)
    except BaseException:
        from contextlib import suppress

        with suppress(OSError):
            os.unlink(tmp_name)
        raise


def write_json_atomic(path: Path, data: Any, *, sort_keys: bool = False) -> None:
    """Atomically write formatted JSON to ``path``."""
    write_text_atomic(path, json.dumps(data, indent=2, sort_keys=sort_keys) + "\n")


def read_json(repo_root: Path, relative_path: str) -> dict[str, Any]:
    """Read a repo-relative JSON file."""
    path = (repo_root / relative_path).resolve()
    if not path.exists():
        raise FileNotFoundError(f"missing configured JSON file: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def read_json_file_or_empty(path: Path) -> dict[str, Any]:
    """Read a JSON object from ``path``, returning ``{}`` when absent."""
    if not path.exists():
        return {}
    parsed = json.loads(path.read_text(encoding="utf-8").strip() or "{}")
    if not isinstance(parsed, dict):
        raise ValueError(f"expected JSON object in {path}")
    return parsed


def upsert_nested_dict(target: dict[str, Any], updates: dict[str, Any]) -> bool:
    """Recursively merge ``updates`` into ``target``, returning whether any value changed."""
    changed = False
    for key, value in updates.items():
        if isinstance(value, dict):
            current = target.get(key)
            if not isinstance(current, dict):
                target[key] = {}
                current = target[key]
                changed = True
            if upsert_nested_dict(current, value):
                changed = True
        elif target.get(key) != value:
            target[key] = value
            changed = True
    return changed


def ensure_parent(path: Path, check_only: bool) -> None:
    """Create parent directories for ``path`` unless running in check mode."""
    if not check_only:
        path.parent.mkdir(parents=True, exist_ok=True)


def load_common_data(repo_root: Path, config: dict[str, Any], include_local: bool = True) -> dict[str, Any]:
    """Load shared agent data and optionally merge machine-local overrides."""
    common_data = read_json(repo_root, config["common_data_file"])

    if not include_local:
        return common_data

    local_data_path = Path("~/.config/ooodnakov/local/agents/data.json").expanduser()
    if local_data_path.exists():
        try:
            local_data = json.loads(local_data_path.read_text(encoding="utf-8"))
            if "skills" in local_data:
                current_skills = common_data.get("skills", [])
                for skill in local_data["skills"]:
                    if skill not in current_skills:
                        current_skills.append(skill)
                common_data["skills"] = current_skills
            if "mcp_servers" in local_data:
                local_mcps = local_data["mcp_servers"]
                for name, local_cfg in local_mcps.items():
                    if name in common_data.get("mcp_servers", {}):
                        common_data["mcp_servers"][name].update(local_cfg)
                    else:
                        common_data.setdefault("mcp_servers", {})[name] = local_cfg
            if "extensions" in local_data:
                current_exts = common_data.get("extensions", [])
                for ext in local_data["extensions"]:
                    if ext not in current_exts:
                        current_exts.append(ext)
                common_data["extensions"] = current_exts
        except Exception as exc:
            print_error_line("warn", f"failed to load local agent data: {exc}")

    return common_data


def common_data_path(repo_root: Path, config: dict[str, Any]) -> Path:
    """Return the resolved path to ``common_data_file``."""
    return (repo_root / config["common_data_file"]).resolve()


def write_common_data(repo_root: Path, config: dict[str, Any], data: dict[str, Any]) -> None:
    """Write ``common_data_file`` atomically with sorted keys."""
    write_json_atomic(common_data_path(repo_root, config), data, sort_keys=True)


def toml_key(key: str) -> str:
    """Format a key as a bare TOML key when valid or a quoted TOML string otherwise."""
    return key if TOML_BARE_KEY_PATTERN.match(key) else json.dumps(key)


def toml_table_exists(content: str, table: str) -> bool:
    """Return True if a ``[table]`` header exists in TOML text."""
    return bool(re.search(rf"^\s*\[\s*{re.escape(table)}\s*\]\s*$", content, flags=re.MULTILINE))


def replace_or_append_toml_table(content: str, table: str, rendered: str) -> tuple[str, bool]:
    """Replace an existing TOML ``[table]`` section or append it if missing."""
    table_pattern = rf"^\s*\[\s*{re.escape(table)}\s*\]\s*$"
    pattern = re.compile(rf"{table_pattern}.*?(?=^\s*\[|\Z)", flags=re.MULTILINE | re.DOTALL)
    match = pattern.search(content)
    rendered = rendered.strip() + "\n"
    if match is None:
        prefix = content.rstrip()
        updated = f"{prefix}\n\n{rendered}" if prefix else rendered
        return updated, True
    if match.group(0).strip() == rendered.strip():
        return content, False
    updated = f"{content[: match.start()]}{rendered}{content[match.end() :].lstrip(chr(10))}"
    return updated, True


def parse_agent_clis(raw: list[dict[str, str]]) -> list[AgentCli]:
    """Parse ``agent_clis`` entries into ``AgentCli`` instances."""
    return [AgentCli(name=entry["name"], command=entry["command"]) for entry in raw]


def parse_agent_targets(raw: list[dict[str, Any]]) -> list[AgentConfigTarget]:
    """Parse ``agent_configs`` entries into ``AgentConfigTarget`` instances."""
    targets: list[AgentConfigTarget] = []
    for entry in raw:
        raw_agents = entry.get("agents") or ()
        if isinstance(raw_agents, str):
            raw_agents = [raw_agents]
        raw_frontmatter = entry.get("frontmatter")
        frontmatter = (
            {str(k): str(v) for k, v in raw_frontmatter.items()} if isinstance(raw_frontmatter, dict) else None
        )
        targets.append(
            AgentConfigTarget(
                name=entry["name"],
                format=entry["format"],
                default_paths=list(entry.get("default_paths", [])),
                docs_url=entry.get("docs_url", ""),
                mcp_paths=entry.get("mcp_paths"),
                mcp_skip=entry.get("mcp_skip", False),
                agents=tuple(raw_agents),
                extra_text_file=entry.get("extra_text_file", "") or "",
                extra_only=bool(entry.get("extra_only", False)),
                create_if_dir_exists=str(entry.get("create_if_dir_exists", "") or ""),
                frontmatter=frontmatter,
            )
        )
    return targets


def parse_agent_update_specs(raw: list[dict[str, str]]) -> list[AgentUpdateSpec]:
    """Parse ``agent_updates`` entries into ``AgentUpdateSpec`` instances."""
    return [
        AgentUpdateSpec(
            name=entry["name"],
            command=entry["command"],
            preferred=entry.get("preferred", ""),
            package=entry.get("package", ""),
            install_script=entry.get("install_script") or None,
            install_script_ps=entry.get("install_script_ps") or None,
        )
        for entry in raw
    ]


def _target_aliases(target: AgentConfigTarget, update_specs: list[AgentUpdateSpec]) -> set[str]:
    aliases = {
        target.name.lower(),
        target.name.lower().replace(" ", "-"),
        target.name.lower().replace(" ", ""),
    }
    aliases.update(alias.lower() for alias in target.agents)
    if not target.agents:
        aliases.add(re.split(r"[^a-z0-9]+", target.name.lower())[0])
    for spec in update_specs:
        if spec.command.lower() in aliases or spec.name.lower() in aliases:
            aliases.update({spec.command.lower(), spec.name.lower(), spec.name.lower().replace(" ", "-")})
    return aliases


def select_agent_targets(
    targets: list[AgentConfigTarget],
    update_specs: list[AgentUpdateSpec],
    queries: list[str] | None,
) -> tuple[list[AgentConfigTarget], list[str]]:
    """Filter targets by agent key or name. Returns (selected, unmatched_queries)."""
    if queries is None:
        return list(targets), []
    selected: list[AgentConfigTarget] = []
    unmatched: list[str] = []
    for query in queries:
        normalized = query.strip().lower()
        matches = [target for target in targets if normalized in _target_aliases(target, update_specs)]
        if not matches:
            unmatched.append(query)
            continue
        for target in matches:
            if target not in selected:
                selected.append(target)
    return selected, unmatched


def detect_clis(agent_clis: list[AgentCli]) -> list[dict[str, str | bool]]:
    """Detect configured agent CLIs on PATH."""
    shutil_mod = resolve_collab("shutil", shutil)
    rows: list[dict[str, str | bool]] = []
    for cli in agent_clis:
        resolved = shutil_mod.which(cli.command)
        rows.append({"name": cli.name, "command": cli.command, "installed": bool(resolved), "path": resolved or ""})
    return rows


def existing_default_path(paths: list[str]) -> Path | None:
    """Return the first existing file among candidate config paths."""
    for path in paths:
        candidate = Path(path).expanduser()
        if candidate.exists() and candidate.is_file():
            return candidate
    return None


def get_platform_common_text(repo_root: Path, config: dict[str, Any]) -> str:
    """Load shared instruction text, stripping Windows-only RTK notes off Windows."""
    common_text = read_text(repo_root, config["common_text_file"])

    if os.name != "nt" and RTK_BEGIN in common_text and RTK_END in common_text:
        start = common_text.index(RTK_BEGIN)
        end = common_text.index(RTK_END) + len(RTK_END)
        common_text = common_text[:start].rstrip() + "\n" + common_text[end:].lstrip()
    return common_text


def prompt_yes_no(question: str) -> bool:
    """Ask a yes/no confirmation question when running interactively."""
    if not sys.stdin.isatty():
        return False
    shutil_mod = resolve_collab("shutil", shutil)
    subprocess_mod = resolve_collab("subprocess", subprocess)
    if shutil_mod.which("gum"):
        result = subprocess_mod.run(["gum", "confirm", question], check=False)
        return result.returncode == 0
    try:
        answer = input(f"{question} [y/N] ").strip().lower()
    except (EOFError, KeyboardInterrupt):
        return False
    return answer in {"y", "yes"}
