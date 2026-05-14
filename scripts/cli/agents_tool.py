#!/usr/bin/env python3
from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    tomllib = None

from tui import is_interactive, interactive_select

MANAGED_BEGIN = "<!-- oooconf:agents-common:start -->"
MANAGED_END = "<!-- oooconf:agents-common:end -->"
RTK_BEGIN = "<!-- oooconf:rtk:start -->"
RTK_END = "<!-- oooconf:rtk:end -->"
DEFAULT_CONFIG_PATH = Path("home/.config/ooodnakov/agents/config.json")
ASCII_ICONS = {
    "section": "==",
    "ok": "[ok]",
    "warn": "[warn]",
    "fail": "[fail]",
    "missing": "[missing]",
    "outdated": "[outdated]",
    "info": "[info]",
    "bullet": "-",
}
NERD_FONT_ICONS = {
    "section": "▸",
    "ok": "✓",
    "warn": "⚠",
    "fail": "✗",
    "missing": "✗",
    "outdated": "󰏫",
    "info": "ℹ",
    "bullet": "•",
}
ANSI_RESET = "\033[0m"
ANSI_BOLD = "\033[1m"
THEME_COLORS = {
    "default": {
        "section": 111,
        "ok": 78,
        "warn": 221,
        "fail": 203,
        "missing": 203,
        "outdated": 215,
        "info": 117,
        "muted": 245,
    },
    "catppuccin": {
        "section": 111,
        "ok": 150,
        "warn": 223,
        "fail": 203,
        "missing": 203,
        "outdated": 181,
        "info": 117,
        "muted": 145,
    },
    "gruvbox": {
        "section": 214,
        "ok": 142,
        "warn": 214,
        "fail": 167,
        "missing": 167,
        "outdated": 214,
        "info": 109,
        "muted": 248,
    },
    "nord": {
        "section": 110,
        "ok": 108,
        "warn": 180,
        "fail": 174,
        "missing": 174,
        "outdated": 109,
        "info": 110,
        "muted": 146,
    },
    "tokyonight": {
        "section": 111,
        "ok": 114,
        "warn": 221,
        "fail": 203,
        "missing": 203,
        "outdated": 180,
        "info": 117,
        "muted": 146,
    },
    "noctalia": {
        "section": 141,
        "ok": 110,
        "warn": 180,
        "fail": 174,
        "missing": 174,
        "outdated": 109,
        "info": 117,
        "muted": 146,
    },
}
ENV_PLACEHOLDER_PATTERN = re.compile(r"\{([A-Za-z_][A-Za-z0-9_]*)\}")
BRACED_ENV_REF_PATTERN = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")
SIMPLE_ENV_REF_PATTERN = re.compile(r"(?<!\$)\$([A-Za-z_][A-Za-z0-9_]*)")


@dataclass(frozen=True)
class AgentCli:
    name: str
    command: str


@dataclass(frozen=True)
class AgentConfigTarget:
    name: str
    format: str
    default_paths: list[str]
    docs_url: str


@dataclass(frozen=True)
class DoctorConfigResult:
    target: AgentConfigTarget
    existing_path: Path | None
    missing_mcp: list[str]
    missing_skills: list[str]
    parse_error: str = ""
    shape_issues: list[str] | None = None


@dataclass(frozen=True)
class AgentUpdateSpec:
    name: str
    command: str
    preferred: str
    package: str
    install_script: str | None = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="oooconf agents",
        description="Detect AI agent CLIs and manage shared AGENTS.md instructions.",
    )
    parser.add_argument("--repo-root", default=None, help="Repo root containing oooconf agent config.")
    parser.add_argument("--config", default=None, help="Override agent config JSON path.")

    subparsers = parser.add_subparsers(dest="command", required=True)

    detect_parser = subparsers.add_parser("detect", help="Detect known agent CLIs available on PATH.")
    detect_parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON output.")

    sync_parser = subparsers.add_parser("sync", help="Append/update a managed common block in AGENTS.md files.")
    sync_parser.add_argument("--check", action="store_true", help="Validate only; do not write files.")
    sync_parser.add_argument(
        "--materialize-secrets",
        action="store_true",
        help="Materialize env vars into generated global MCP configs (otherwise keep placeholders).",
    )
    sync_parser.add_argument(
        "--global", dest="global_sync", action="store_true", help="Also sync MCP servers to global agent configs."
    )
    sync_parser.add_argument(
        "--agents",
        nargs="*",
        help="Filter sync to specific agents by name or key.",
    )

    doctor_parser = subparsers.add_parser(
        "doctor", help="Validate AGENTS.md managed block and check common MCP/skills in agent config paths."
    )
    doctor_parser.add_argument(
        "--strict-config-paths",
        action="store_true",
        help="Fail if no default config path exists for an agent target.",
    )

    mcp_parser = subparsers.add_parser("mcp", help="Manage Model Context Protocol (MCP) servers.")
    mcp_subparsers = mcp_parser.add_subparsers(dest="subcommand", required=True)
    mcp_sync_parser = mcp_subparsers.add_parser("sync", help="Synchronize (clone/pull/install) managed MCP servers.")
    mcp_sync_parser.add_argument("--check", action="store_true", help="Print planned actions without executing.")
    mcp_sync_parser.add_argument(
        "--agents",
        metavar="AGENT",
        nargs="*",
        default=None,
        help="Restrict sync to specific agents. If omitted, interactive mode.",
    )
    mcp_add_parser = mcp_subparsers.add_parser("add", help="Add an MCP server entry to common-data.json.")
    mcp_add_parser.add_argument("--name", help="Optional MCP server name (otherwise inferred from JSON key).")
    mcp_add_parser.add_argument(
        "--json",
        dest="json_payload",
        help="MCP JSON object payload. If omitted, read from stdin or interactive prompt.",
    )
    mcp_add_parser.add_argument("--sync-now", action="store_true", help="Run agents sync --global after adding.")
    mcp_add_parser.add_argument("--multi", action="store_true", help="Allow multiple MCP entries in one JSON payload.")
    mcp_add_parser.add_argument("--preview", action="store_true", help="Show diff preview before writing.")
    mcp_add_parser.add_argument("--check", action="store_true", help="Validate and print changes without writing.")
    subparsers.add_parser("status", help="Show status of managed MCP servers.")

    rtk_parser = subparsers.add_parser("rtk", help="Manage RTK (Rust Token Killer) integration.")
    rtk_subparsers = rtk_parser.add_subparsers(dest="subcommand", required=True)
    rtk_init_parser = rtk_subparsers.add_parser("init", help="Run 'rtk init --global' for all detected agents.")
    rtk_init_parser.add_argument("--check", action="store_true", help="Print planned actions without executing.")

    update_parser = subparsers.add_parser(
        "update",
        help="Update installed agent CLIs and rebuild install scripts.",
    )
    update_parser.add_argument(
        "--check",
        action="store_true",
        help="Print planned update commands without executing them.",
    )

    install_parser = subparsers.add_parser(
        "install",
        help="Install configured agent CLIs.",
    )
    install_parser.add_argument(
        "agents",
        nargs="*",
        help="Agent keys or names to install (e.g., claude, gemini, aider). Defaults to missing agents.",
    )
    install_parser.add_argument(
        "--all",
        action="store_true",
        help="Install or upgrade every configured agent CLI.",
    )
    install_parser.add_argument(
        "--missing",
        action="store_true",
        help="Install only configured agent CLIs that are missing from PATH (default when no agent is given).",
    )
    install_parser.add_argument(
        "--check",
        action="store_true",
        help="Print planned install commands without executing them.",
    )

    subparsers.add_parser(
        "install-scripts-build",
        help="Build standalone install.sh and install.ps1 scripts for agents.",
    )

    provider_parser = subparsers.add_parser("provider", help="Configure shared model/API providers for agent CLIs.")
    provider_subparsers = provider_parser.add_subparsers(dest="subcommand", required=True)
    provider_sync_parser = provider_subparsers.add_parser(
        "sync", help="Sync a provider backend into supported agent configs."
    )
    provider_sync_parser.add_argument("provider", choices=["minimax"], help="Provider backend to configure.")
    provider_sync_parser.add_argument(
        "--check", action="store_true", help="Print planned config changes without writing."
    )
    provider_sync_parser.add_argument(
        "--materialize-secrets",
        action="store_true",
        help="Write MINIMAX_API_KEY's current value into configs that cannot read env refs.",
    )
    provider_sync_parser.add_argument(
        "--region",
        choices=["global", "china"],
        default="global",
        help="MiniMax endpoint region to configure (default: global).",
    )
    provider_sync_parser.add_argument(
        "--agents",
        metavar="AGENT",
        nargs="*",
        default=None,
        help="Restrict sync to specific agents (e.g., claude codex opencode). If omitted, interactive mode.",
    )

    skills_parser = subparsers.add_parser(
        "skills",
        help="Manage agent skills and extensions across different agent ecosystems.",
    )
    skills_subparsers = skills_parser.add_subparsers(dest="subcommand", required=True)
    skills_sync_parser = skills_subparsers.add_parser("sync", help="Synchronize configured skill_specs across agents.")
    skills_sync_parser.add_argument(
        "--check", action="store_true", help="Print planned skill installs without executing."
    )
    skills_sync_parser.add_argument(
        "--agents",
        metavar="AGENT",
        nargs="*",
        default=None,
        help="Restrict sync to specific agents. If omitted, interactive mode.",
    )
    skills_view_parser = skills_subparsers.add_parser(
        "view",
        help="List globally available skills through the shared pnpm skills catalog.",
    )
    skills_view_parser.add_argument("--json", action="store_true", help="Request JSON output from the skills catalog.")
    skills_view_parser.add_argument("--check", action="store_true", help="Print planned command without executing.")
    skills_add_parser = skills_subparsers.add_parser("add", help="Add a shared skill source to common-data.json.")
    skills_add_parser.add_argument("source", help="Skill source (e.g. vercel-labs/agent-skills).")
    skills_add_parser.add_argument("--agent", default="gemini", help="Agent sync target for this skill spec.")
    skills_add_parser.add_argument("--sync-now", action="store_true", help="Run agents skills sync after adding.")
    skills_add_parser.add_argument("--check", action="store_true", help="Validate and print changes without writing.")

    return parser.parse_args()


def resolve_repo_root(repo_root: str | None) -> Path:
    return Path(repo_root).expanduser().resolve() if repo_root else Path(__file__).resolve().parent.parent


def resolve_config_path(repo_root: Path, config_override: str | None) -> Path:
    return (
        Path(config_override).expanduser().resolve() if config_override else (repo_root / DEFAULT_CONFIG_PATH).resolve()
    )


def load_config(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(f"agent config not found: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    required = {"agent_files", "common_text_file", "common_data_file", "agent_clis", "agent_configs"}
    missing = sorted(required - set(data.keys()))
    if missing:
        raise ValueError(f"agent config missing keys: {', '.join(missing)}")
    return data


def read_text(repo_root: Path, relative_path: str) -> str:
    path = (repo_root / relative_path).resolve()
    if not path.exists():
        raise FileNotFoundError(f"missing configured file: {path}")
    return path.read_text(encoding="utf-8").rstrip() + "\n"


def read_json(repo_root: Path, relative_path: str) -> dict[str, Any]:
    path = (repo_root / relative_path).resolve()
    if not path.exists():
        raise FileNotFoundError(f"missing configured JSON file: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def load_common_data(repo_root: Path, config: dict[str, Any], include_local: bool = True) -> dict[str, Any]:
    common_data = read_json(repo_root, config["common_data_file"])

    if not include_local:
        return common_data

    # Merge local data if it exists
    local_data_path = Path("~/.config/ooodnakov/local/agents/data.json").expanduser()
    if local_data_path.exists():
        try:
            local_data = json.loads(local_data_path.read_text(encoding="utf-8"))
            if "skills" in local_data:
                # Use a list to preserve order, but set for uniqueness
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
            print(f"warning: failed to load local agent data: {exc}", file=sys.stderr)

    return common_data


def common_data_path(repo_root: Path, config: dict[str, Any]) -> Path:
    return (repo_root / config["common_data_file"]).resolve()


def write_common_data(repo_root: Path, config: dict[str, Any], data: dict[str, Any]) -> None:
    path = common_data_path(repo_root, config)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def normalize_mcp_command(config: dict[str, Any]) -> dict[str, Any]:
    updated = dict(config)
    command = str(updated.get("command", "")).strip()
    args = [str(arg) for arg in updated.get("args", [])]
    if command in {"npx", "npm"} and args[:1] == ["-y"]:
        updated["command"] = "pnpm"
        updated["args"] = ["dlx", *args[1:]]
    return updated


def parse_mcp_json_input(payload: str) -> tuple[str, dict[str, Any]]:
    raw = payload.strip()
    candidates = [raw]

    # Heuristics for common paste mistakes:
    # 1) User pastes `"name": {...}` without outer braces.
    # 2) User pastes object with trailing comma.
    # 3) User pastes single-quoted JSON-like dict.
    if raw and not raw.startswith("{") and ":" in raw:
        candidates.append("{" + raw + "}")
    if raw.endswith(","):
        candidates.append(raw[:-1])
    if "'" in raw and '"' not in raw:
        candidates.append(raw.replace("'", '"'))
        if not raw.startswith("{") and ":" in raw:
            candidates.append("{" + raw.replace("'", '"') + "}")

    parse_errors: list[str] = []
    obj: dict[str, Any] | None = None
    for candidate in candidates:
        try:
            parsed = json.loads(candidate)
            if isinstance(parsed, dict):
                obj = parsed
                break
        except json.JSONDecodeError as exc:
            parse_errors.append(str(exc))

    if obj is None:
        hint = 'Ensure the input is a JSON object, e.g. {"name": {"command": "pnpm", "args": ["dlx", "pkg"]}}.'
        details = parse_errors[0] if parse_errors else "Invalid JSON payload."
        raise ValueError(f"{details} {hint}")

    if len(obj) != 1:
        raise ValueError("MCP JSON input must contain exactly one top-level server entry.")
    name, cfg = next(iter(obj.items()))
    if not isinstance(cfg, dict):
        raise ValueError("MCP server config must be a JSON object.")
    if "command" not in cfg:
        raise ValueError("MCP server config must include 'command'.")
    return str(name), cfg


def parse_mcp_json_inputs(payload: str, *, allow_multi: bool = False) -> dict[str, dict[str, Any]]:
    if not allow_multi:
        name, cfg = parse_mcp_json_input(payload)
        return {name: cfg}
    raw = payload.strip()
    try:
        obj = json.loads(raw if raw.startswith("{") else "{" + raw + "}")
    except json.JSONDecodeError:
        fixed = raw.replace("'", '"') if "'" in raw and '"' not in raw else raw
        obj = json.loads(fixed if fixed.startswith("{") else "{" + fixed + "}")
    if not isinstance(obj, dict):
        raise ValueError("MCP payload must be a JSON object.")
    normalized: dict[str, dict[str, Any]] = {}
    for key, value in obj.items():
        if not isinstance(value, dict):
            raise ValueError(f"MCP entry '{key}' must be an object.")
        if "command" not in value:
            raise ValueError(f"MCP entry '{key}' must include 'command'.")
        normalized[str(key)] = value
    return normalized


def validate_mcp_entry(name: str, entry: dict[str, Any]) -> None:
    if not isinstance(entry.get("command"), str) or not entry["command"].strip():
        raise ValueError(f"MCP entry '{name}' has invalid command.")
    args = entry.get("args", [])
    if args is not None and not isinstance(args, list):
        raise ValueError(f"MCP entry '{name}' args must be a list.")
    if "env" in entry and not isinstance(entry["env"], dict):
        raise ValueError(f"MCP entry '{name}' env must be an object.")


def canonicalize_skill_source(source: str) -> str:
    src = source.strip()
    if src.startswith("https://github.com/"):
        src = src.rstrip("/")
        if src.endswith(".git"):
            src = src[:-4]
        return src
    if "://" in src:
        return src.rstrip("/")
    return f"https://github.com/{src.rstrip('/')}"


def discover_agent_files(repo_root: Path, configured_files: list[str], include_missing: bool = False) -> list[Path]:
    discovered: set[Path] = set()
    for rel in configured_files:
        candidate = (repo_root / rel).resolve()
        if candidate.exists() and candidate.is_file():
            discovered.add(candidate)
        elif include_missing and candidate.parent.exists():
            discovered.add(candidate)
    return sorted(list(discovered))


def parse_agent_clis(raw: list[dict[str, str]]) -> list[AgentCli]:

    return [AgentCli(name=entry["name"], command=entry["command"]) for entry in raw]


def parse_agent_targets(raw: list[dict[str, Any]]) -> list[AgentConfigTarget]:
    targets: list[AgentConfigTarget] = []
    for entry in raw:
        targets.append(
            AgentConfigTarget(
                name=entry["name"],
                format=entry["format"],
                default_paths=list(entry.get("default_paths", [])),
                docs_url=entry.get("docs_url", ""),
            )
        )
    return targets


def parse_agent_update_specs(raw: list[dict[str, str]]) -> list[AgentUpdateSpec]:
    return [
        AgentUpdateSpec(
            name=entry["name"],
            command=entry["command"],
            preferred=entry.get("preferred", ""),
            package=entry.get("package", ""),
            install_script=entry.get("install_script") or None,
        )
        for entry in raw
    ]


def supports_nerd_font_output() -> bool:
    if os.environ.get("OOOCONF_ASCII") == "1":
        return False
    if not sys.stdout.isatty():
        return False
    encoding = (sys.stdout.encoding or "").lower()
    return "utf" in encoding


def supports_color_output() -> bool:
    mode = os.environ.get("OOOCONF_COLOR", "").lower()
    if mode in {"0", "false", "never"} or os.environ.get("NO_COLOR") is not None:
        return False
    if mode in {"1", "true", "always"} or os.environ.get("FORCE_COLOR") is not None:
        return True
    return sys.stdout.isatty()


def _theme_palette() -> dict[str, int]:
    return THEME_COLORS.get(os.environ.get("OOOCONF_THEME", "default").lower(), THEME_COLORS["default"])


def colorize(text: str, role: str, *, bold: bool = False) -> str:
    if not supports_color_output():
        return text
    palette = _theme_palette()
    color_num = palette.get(role)
    color = f"\033[38;5;{color_num}m" if color_num is not None else ""
    weight = ANSI_BOLD if bold else ""
    return f"{weight}{color}{text}{ANSI_RESET}"


def icon(name: str) -> str:
    palette = NERD_FONT_ICONS if supports_nerd_font_output() else ASCII_ICONS
    return palette[name]


def print_section(title: str) -> None:
    prefix = icon("section")
    print(f"{colorize(prefix, 'section', bold=True)} {colorize(title, 'section', bold=True)}")
    line = "─" * (len(title) + 2) if prefix != ASCII_ICONS["section"] else "-" * (len(title) + 3)
    print(colorize(line, "muted"))


def print_status_line(status: str, message: str) -> None:
    print(f"{colorize(icon(status), status, bold=True)} {message}")


def detect_clis(agent_clis: list[AgentCli]) -> list[dict[str, str | bool]]:
    rows: list[dict[str, str | bool]] = []
    for cli in agent_clis:
        resolved = shutil.which(cli.command)
        rows.append({"name": cli.name, "command": cli.command, "installed": bool(resolved), "path": resolved or ""})
    return rows


def render_markdown_block(common_text: str, common_data: dict[str, Any]) -> str:
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
    return "\n".join(lines)


def upsert_managed_block(existing: str, managed_block: str) -> str:
    if MANAGED_BEGIN in existing and MANAGED_END in existing:
        start = existing.index(MANAGED_BEGIN)
        end = existing.rindex(MANAGED_END) + len(MANAGED_END)
        return existing[:start].rstrip() + "\n\n" + managed_block + existing[end:].lstrip("\n")
    return existing.rstrip() + "\n\n" + managed_block


def sync_files(agent_files: list[Path], managed_block: str, check_only: bool) -> tuple[int, list[Path]]:
    changed: list[Path] = []
    for path in agent_files:
        if not path.exists():
            changed.append(path)
            if not check_only:
                # For new files, the managed block is the entire content
                path.write_text(managed_block, encoding="utf-8")
            continue

        current = path.read_text(encoding="utf-8")
        updated = upsert_managed_block(current, managed_block)
        if updated != current:
            changed.append(path)
            if not check_only:
                path.write_text(updated, encoding="utf-8")
    return len(changed), changed


def extract_search_space(path: Path, fmt: str) -> str:
    raw = path.read_text(encoding="utf-8")
    if fmt == "json":
        obj = json.loads(raw)
        return json.dumps(obj, sort_keys=True)
    if fmt == "toml":
        if tomllib is None:
            return raw
        obj = tomllib.loads(raw)
        return json.dumps(obj, sort_keys=True)
    if fmt in {"yaml", "yml"}:
        return raw
    return raw


def existing_default_path(paths: list[str]) -> Path | None:
    for path in paths:
        candidate = Path(path).expanduser()
        if candidate.exists() and candidate.is_file():
            return candidate
    return None


def check_common_entries(content: str, common_data: dict[str, Any], fmt: str) -> tuple[list[str], list[str]]:
    lowered = content.lower()
    missing_mcp: list[str] = []
    missing_skills: list[str] = []

    mcp_servers = common_data.get("mcp_servers", {})
    for name in mcp_servers:
        if name.lower() not in lowered:
            missing_mcp.append(name)

    # Skills are only expected in Markdown instruction files, not JSON/TOML configs
    if fmt == "markdown":
        for skill in common_data.get("skills", []):
            # lightweight fuzzy check: require at least one distinct token for each skill phrase
            tokens = [token for token in skill.lower().replace("(", " ").replace(")", " ").split() if len(token) >= 5]
            if not tokens:
                if skill.lower() not in lowered:
                    missing_skills.append(skill)
            elif not any(token in lowered for token in tokens):
                missing_skills.append(skill)

    return missing_mcp, missing_skills


def check_config_shape(target: AgentConfigTarget, content: str, parsed_obj: dict[str, Any] | None = None) -> list[str]:
    issues: list[str] = []

    def has_top_level_key(key: str) -> bool:
        if parsed_obj is not None:
            return key in parsed_obj
        lowered = content.lower()
        key_lower = re.escape(key.lower())
        return bool(re.search(rf'["\']{key_lower}["\']\s*:', lowered) or re.search(rf"\[{key_lower}(?:[.\]])", lowered))

    if target.name == "OpenCode" and not has_top_level_key("mcp"):
        issues.append('expected top-level "mcp" object')
    if target.name in {"Gemini CLI", "Claude Code"} and not has_top_level_key("mcpServers"):
        issues.append('expected "mcpServers" object')
    if target.name == "OpenAI Codex CLI" and not has_top_level_key("mcp_servers"):
        issues.append('expected "mcp_servers" tables')
    return issues


def inspect_agent_configs(
    targets: list[AgentConfigTarget], common_data: dict[str, Any]
) -> tuple[list[DoctorConfigResult], bool]:
    results: list[DoctorConfigResult] = []
    has_failures = False

    for target in targets:
        existing = existing_default_path(target.default_paths)
        if existing is None:
            results.append(
                DoctorConfigResult(
                    target=target,
                    existing_path=None,
                    missing_mcp=[],
                    missing_skills=[],
                )
            )
            continue

        try:
            search_space = extract_search_space(existing, target.format)
        except Exception as exc:
            results.append(
                DoctorConfigResult(
                    target=target,
                    existing_path=existing,
                    missing_mcp=[],
                    missing_skills=[],
                    parse_error=str(exc),
                )
            )
            has_failures = True
            continue

        missing_mcp, missing_skills = check_common_entries(search_space, common_data, target.format)
        parsed_obj: dict[str, Any] | None = None
        if target.format == "json":
            try:
                parsed = json.loads(existing.read_text(encoding="utf-8"))
                if isinstance(parsed, dict):
                    parsed_obj = parsed
            except Exception:
                parsed_obj = None
        shape_issues = check_config_shape(target, search_space, parsed_obj)
        if missing_mcp or missing_skills:
            has_failures = True
        if shape_issues:
            has_failures = True

        results.append(
            DoctorConfigResult(
                target=target,
                existing_path=existing,
                missing_mcp=missing_mcp,
                missing_skills=missing_skills,
                shape_issues=shape_issues,
            )
        )

    return results, has_failures


def sync_global_configs(
    repo_root: Path,
    targets: list[AgentConfigTarget],
    common_data: dict[str, Any],
    managed_block: str,
    check_only: bool,
    materialize_secrets: bool = False,
) -> tuple[int, list[Path]]:
    changed: list[Path] = []

    for target in targets:
        existing = existing_default_path(target.default_paths)

        if existing is None and target.format == "markdown":
            # If no file exists, try to create the first path if its parent exists
            for p in target.default_paths:
                candidate = Path(p).expanduser()
                if candidate.parent.exists():
                    existing = candidate
                    break

        if existing is None:
            continue

        if target.format == "markdown":
            try:
                if not existing.exists():
                    changed.append(existing)
                    if not check_only:
                        existing.write_text(managed_block, encoding="utf-8")
                    continue

                current = existing.read_text(encoding="utf-8")
                updated = upsert_managed_block(current, managed_block)
                if updated != current:
                    changed.append(existing)
                    if not check_only:
                        existing.write_text(updated, encoding="utf-8")
            except Exception as exc:
                print(f"warning: failed to sync global markdown {existing}: {exc}", file=sys.stderr)
            continue

        if target.format == "toml":
            try:
                current = existing.read_text(encoding="utf-8")
                updated = current
                needs_update = False
                mcp_servers = common_data.get("mcp_servers", {})
                for name, config in mcp_servers.items():
                    # Check for [mcp_servers.name] or [mcp_servers."name"]
                    if f"[mcp_servers.{name}]" not in updated and f'[mcp_servers."{name}"]' not in updated:
                        if "command" not in config:
                            continue

                        entry = render_mcp_server_entry(
                            target, name, config, repo_root, materialize_secrets=materialize_secrets
                        )

                        # Basic TOML injection (appending to end of file)
                        block = (
                            f"\n[mcp_servers.{name}]\n"
                            f"command = {json.dumps(entry['command'])}\n"
                            f"args = {json.dumps(entry['args'])}\n"
                        )
                        if "env" in entry:
                            block += f"[mcp_servers.{name}.env]\n"
                            for key, value in entry["env"].items():
                                block += f"{key} = {json.dumps(value)}\n"

                        updated += block
                        needs_update = True

                if needs_update:
                    changed.append(existing)
                    if not check_only:
                        existing.write_text(updated, encoding="utf-8")
            except Exception as exc:
                print(f"warning: failed to sync global toml {existing}: {exc}", file=sys.stderr)
            continue

        if target.format != "json":
            continue

        try:
            data = json.loads(existing.read_text(encoding="utf-8"))
            needs_update = False

            # Standard MCP injection (Claude/Gemini format)
            mcp_servers = common_data.get("mcp_servers", {})
            if mcp_servers and target.name != "OpenCode":
                if "mcpServers" not in data:
                    data["mcpServers"] = {}

                for name, config in mcp_servers.items():
                    if name not in data["mcpServers"]:
                        if "command" not in config:
                            continue

                        data["mcpServers"][name] = render_mcp_server_entry(
                            target, name, config, repo_root, materialize_secrets=materialize_secrets
                        )
                        needs_update = True

            # OpenCode uses a top-level "mcp" object keyed by server name.
            if mcp_servers and target.name == "OpenCode":
                if "mcp" not in data or not isinstance(data.get("mcp"), dict):
                    data["mcp"] = {}
                    needs_update = True

                for name, config in mcp_servers.items():
                    if name not in data["mcp"]:
                        if "command" not in config:
                            continue
                        data["mcp"][name] = render_opencode_mcp_entry(
                            target, name, config, repo_root, materialize_secrets=materialize_secrets
                        )
                        needs_update = True

            # Gemini-specific context config sync
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
                for f in required_files:
                    if f not in updated_files:
                        updated_files.append(f)
                        file_needs_update = True

                if file_needs_update:
                    data["context"]["fileName"] = updated_files
                    needs_update = True

            if needs_update:
                changed.append(existing)
                if not check_only:
                    existing.write_text(json.dumps(data, indent=2), encoding="utf-8")
        except Exception as exc:
            print(f"warning: failed to sync global config {existing}: {exc}", file=sys.stderr)

    return len(changed), changed


def cmd_detect(config: dict[str, Any], json_output: bool) -> int:
    rows = detect_clis(parse_agent_clis(config["agent_clis"]))
    installed = sum(1 for row in rows if row["installed"])

    if json_output:
        print(json.dumps({"detected": rows}, indent=2))
    else:
        print_section("Agent CLI Detection")
        for row in rows:
            status = "ok" if row["installed"] else "missing"
            location = row["path"] or "-"
            print_status_line(status, f"{row['name']} ({row['command']})")
            print(f"  path: {location}")
        print("")
        print(f"Summary: detected {installed}/{len(rows)} configured agent CLIs.")
    return 0


def get_platform_common_text(repo_root: Path, config: dict[str, Any]) -> str:
    common_text = read_text(repo_root, config["common_text_file"])

    # Strip RTK part if not on Windows
    if os.name != "nt":
        if RTK_BEGIN in common_text and RTK_END in common_text:
            start = common_text.index(RTK_BEGIN)
            end = common_text.index(RTK_END) + len(RTK_END)
            common_text = common_text[:start].rstrip() + "\n" + common_text[end:].lstrip()
    return common_text


def cmd_sync(
    repo_root: Path,
    config: dict[str, Any],
    check_only: bool,
    global_sync: bool,
    materialize_secrets: bool = False,
    agents: list[str] | None = None,
) -> int:
    common_text = get_platform_common_text(repo_root, config)

    print_section("AGENTS Sync")
    print(f"Mode: {'check' if check_only else 'sync'}")

    g_count = 0
    g_files = []
    if global_sync:
        merged_data = load_common_data(repo_root, config, include_local=True)
        managed_block_global = render_markdown_block(common_text, merged_data)
        config_targets = parse_agent_targets(config["agent_configs"])

        # Filter to selected agents if not all specified
        if agents is None and not check_only and is_interactive():
            agent_names = [t.name for t in config_targets]
            selected = interactive_select(
                agent_names,
                title="Select agents to sync",
                instructions="SPACE toggle  ENTER confirm  A all  N none  Q quit",
            )
            if selected is None:
                print("Aborted.")
                return 1
            agents = selected

        if agents is not None:
            config_targets = [t for t in config_targets if t.name in agents]

        g_count, g_files = sync_global_configs(
            repo_root,
            config_targets,
            merged_data,
            managed_block_global,
            check_only,
            materialize_secrets=materialize_secrets,
        )
        print(f"Global configs scanned: {len(config_targets)}")
        print(f"Global configs needing updates: {g_count}")
        if g_files:
            for file_path in g_files:
                print(f"{icon('bullet')} {file_path}")
    else:
        print("Repo-specific sync is disabled. Use --global to sync global agent configs.")

    if global_sync and g_count == 0:
        print("")
        print("All target files are up to date.")

    return 1 if check_only and global_sync and g_count > 0 else 0


def cmd_doctor(repo_root: Path, config: dict[str, Any], strict_paths: bool) -> int:
    # merged_data for global agent configs (includes local overrides)
    merged_data = load_common_data(repo_root, config, include_local=True)

    config_targets = parse_agent_targets(config["agent_configs"])
    config_results, config_failures = inspect_agent_configs(config_targets, merged_data)
    rows = detect_clis(parse_agent_clis(config["agent_clis"]))

    failed = False

    print_section("AGENTS Doctor")

    print("Agent Configs")
    print("-------------")
    for result in config_results:
        target = result.target
        if result.existing_path is None:
            message = f"{target.name}: config path not found ({', '.join(target.default_paths)})"
            if target.docs_url:
                message += f" | docs: {target.docs_url}"
            print_status_line("warn", message)
            if strict_paths:
                failed = True
            continue

        if result.parse_error:
            print_status_line("fail", f"{target.name}: failed parsing {result.existing_path}")
            print(f"  error: {result.parse_error}")
            continue

        if result.missing_mcp or result.missing_skills:
            print_status_line("fail", f"{target.name}: missing required markers in {result.existing_path}")
            if result.missing_mcp:
                print(f"  missing MCPs: {', '.join(result.missing_mcp)}")
            if result.missing_skills:
                print(f"  missing skills: {', '.join(result.missing_skills)}")
            continue
        if result.shape_issues:
            print_status_line("fail", f"{target.name}: config shape mismatch in {result.existing_path}")
            print(f"  issues: {', '.join(result.shape_issues)}")
            continue

        print_status_line("ok", f"{target.name}: required MCP/skills markers found in {result.existing_path}")

    print("")
    print("Agent CLIs")
    print("----------")
    missing_clis = [row for row in rows if not row["installed"]]
    installed_clis = [row for row in rows if row["installed"]]
    for row in installed_clis:
        print_status_line("ok", f"{row['name']} ({row['command']})")
    for row in missing_clis:
        print_status_line("missing", f"{row['name']} ({row['command']})")

    print("")
    strict_note = "strict config paths enabled" if strict_paths else "missing config paths are warnings"
    print(f"Summary: {len(installed_clis)}/{len(rows)} CLIs installed, {strict_note}.")

    failed = failed or config_failures

    return 1 if failed else 0


def resolve_update_command(spec: AgentUpdateSpec) -> tuple[list[str], str]:
    preferred = spec.preferred.strip().lower()
    package = spec.package.strip() or spec.command
    if preferred in {"npm", "pnpm"}:
        return ["pnpm", "add", "-g", f"{package}@latest"], "pnpm"
    if preferred == "uv":
        return ["uv", "tool", "install", "--upgrade", package], "uv"
    if preferred == "pipx":
        return ["pipx", "upgrade", package], "pipx"
    raise RuntimeError(f"unsupported preferred update manager: {spec.preferred!r}")


def cmd_install_scripts_build(repo_root: Path, config: dict[str, Any]) -> int:
    specs = parse_agent_update_specs(config.get("agent_updates", []))
    if not specs:
        print("No agent_updates configured.", file=sys.stderr)
        return 1

    install_dir = repo_root / "home" / ".config" / "ooodnakov" / "agents" / "install"
    install_dir.mkdir(parents=True, exist_ok=True)

    print_section("Building Agent Install Scripts")
    print(f"Target: {install_dir}")

    count = 0
    for spec in specs:
        cmd_list, runner = resolve_update_command(spec)
        cmd_str = shlex.join(cmd_list)

        # Build Unix .sh script
        sh_path = install_dir / f"install-{spec.command}.sh"
        sh_lines = [
            f'#!/bin/sh\n# Generated by oooconf agents install-scripts-build\necho "Installing {spec.name} via {runner}..."\n{cmd_str}\n'
        ]

        # Append post-install script if configured (supports multiline via \n or &&)
        if spec.install_script:
            script = spec.install_script
            # Normalize: allow \n or && as separators, collapse excess whitespace
            script = script.replace("&&", "\n").replace("\r\n", "\n")
            for line in script.split("\n"):
                line = line.strip()
                if line:
                    sh_lines.append(f"{line}\n")

        sh_content = "".join(sh_lines)
        sh_path.write_text(sh_content, encoding="utf-8")
        sh_path.chmod(0o755)

        # Build PowerShell .ps1 script
        ps1_path = install_dir / f"install-{spec.command}.ps1"
        ps1_lines = [
            f'# Generated by oooconf agents install-scripts-build\nWrite-Host "Installing {spec.name} via {runner}..."\n{cmd_str}\n'
        ]

        if spec.install_script:
            script = spec.install_script
            script = script.replace("&&", "\n").replace("\r\n", "\n")
            for line in script.split("\n"):
                line = line.strip()
                if line:
                    ps1_lines.append(f"{line}\n")

        ps1_content = "".join(ps1_lines)
        ps1_path.write_text(ps1_content, encoding="utf-8")

        print_status_line("ok", f"{spec.name} ({spec.command})")
        count += 1

    print(f"\nSummary: built install scripts for {count} agents.")
    return 0


def agent_matches_query(spec: AgentUpdateSpec, query: str) -> bool:
    normalized_query = query.strip().lower()
    aliases = {
        spec.command.lower(),
        spec.name.lower(),
        spec.name.lower().replace(" ", "-"),
        spec.name.lower().replace(" ", ""),
        spec.package.lower(),
    }
    return normalized_query in aliases


def select_install_specs(
    specs: list[AgentUpdateSpec],
    queries: list[str],
    *,
    install_all: bool,
    missing_only: bool,
) -> tuple[list[AgentUpdateSpec], list[str]]:
    if install_all and queries:
        return [], ["--all cannot be combined with explicit agent names."]
    if install_all and missing_only:
        return [], ["--all and --missing are mutually exclusive."]

    if install_all:
        return specs, []

    if queries:
        selected: list[AgentUpdateSpec] = []
        errors: list[str] = []
        for query in queries:
            matches = [spec for spec in specs if agent_matches_query(spec, query)]
            if not matches:
                errors.append(f"No agent update/install spec found for '{query}'.")
                continue
            selected.extend(matches)

        deduped: list[AgentUpdateSpec] = []
        seen: set[str] = set()
        for spec in selected:
            if spec.command in seen:
                continue
            seen.add(spec.command)
            deduped.append(spec)
        if missing_only:
            deduped = [spec for spec in deduped if not shutil.which(spec.command)]
        return deduped, errors

    return [spec for spec in specs if not shutil.which(spec.command)], []


def run_install_spec(spec: AgentUpdateSpec, check_only: bool) -> tuple[bool, bool]:
    try:
        command, runner = resolve_update_command(spec)
    except RuntimeError as exc:
        print_status_line("fail", f"{spec.name}: {exc}")
        return False, False

    command_display = shlex.join(command)
    if check_only:
        print_status_line("ok", f"Plan: install {spec.name} via {runner}")
        print(f"  command: {command_display}")
        if spec.install_script:
            print(f"  post-install: {spec.install_script}")
        return True, False

    resolved_runner = shutil.which(command[0])
    if not resolved_runner:
        print_status_line("fail", f"{spec.name}: required installer '{command[0]}' is not installed.")
        return False, False

    command_exec = [resolved_runner, *command[1:]]
    print_status_line("info", f"Installing {spec.name} via {runner}")
    print(f"  command: {command_display}")
    try:
        subprocess.run(command_exec, check=True)
        print_status_line("ok", f"Successfully installed {spec.name}")
    except subprocess.CalledProcessError as exc:
        print_status_line("fail", f"Failed to install {spec.name}: {exc}")
        return False, False

    # Run post-install script if configured
    if spec.install_script:
        script = spec.install_script
        script = script.replace("&&", "\n").replace("\r\n", "\n")
        for line in script.split("\n"):
            line = line.strip()
            if not line:
                continue
            print_status_line("info", f"Running post-install step: {line}")
            try:
                cmd_parts = shlex.split(line)
                if not cmd_parts:
                    continue
                subprocess.run(cmd_parts, check=True)
                print_status_line("ok", "Post-install step succeeded")
            except ValueError as exc:
                print_status_line("fail", f"Post-install step failed to parse: {exc}")
                return False, False
            except subprocess.CalledProcessError as exc:
                print_status_line("fail", f"Post-install step failed: {exc}")
                return False, False

    return True, True


def cmd_install(
    repo_root: Path,
    config: dict[str, Any],
    agent_queries: list[str],
    *,
    check_only: bool,
    install_all: bool,
    missing_only: bool,
) -> int:
    specs = parse_agent_update_specs(config.get("agent_updates", []))
    if not specs:
        print("No agent_updates configured.", file=sys.stderr)
        return 1

    selected, errors = select_install_specs(specs, agent_queries, install_all=install_all, missing_only=missing_only)
    for error in errors:
        print_status_line("fail", error)
    if errors:
        return 1

    print_section("Agent CLI Installation")
    if install_all:
        scope = "all configured agents"
    elif agent_queries:
        scope = ", ".join(agent_queries)
        if missing_only:
            scope = f"missing selected agents ({scope})"
    else:
        scope = "missing configured agents"
    print(f"Mode: {'check' if check_only else 'install'}")
    print(f"Scope: {scope}")

    if not selected:
        print_status_line("ok", "No matching agents require installation.")
        return 0

    attempted = 0
    planned_or_installed = 0
    failed = 0
    for spec in selected:
        attempted += 1
        ok, installed = run_install_spec(spec, check_only)
        if ok:
            planned_or_installed += 1
        else:
            failed += 1

    print("")
    action = "planned" if check_only else "installed"
    print(f"Summary: {action} {planned_or_installed}/{attempted} agents; failed {failed}.")
    return 1 if failed else 0


def get_command_version(command: str) -> str | None:
    try:
        # Most agent CLIs support --version
        result = subprocess.run(
            [command, "--version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            timeout=5,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (subprocess.SubprocessError, FileNotFoundError):
        pass
    return None


def get_runner_bin_dir(runner: str) -> str | None:
    if runner == "pnpm":
        try:
            result = subprocess.run(
                ["pnpm", "bin", "-g"],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                timeout=5,
            )
            if result.returncode == 0:
                return result.stdout.strip()
        except (subprocess.SubprocessError, FileNotFoundError):
            pass
    return None


def cmd_update(repo_root: Path, config: dict[str, Any], check_only: bool) -> int:
    # First, autobuild install scripts
    if not check_only:
        cmd_install_scripts_build(repo_root, config)

    specs = parse_agent_update_specs(config.get("agent_updates", []))
    if not specs:
        print("No agent_updates configured.", file=sys.stderr)
        return 1

    print_section("Agent CLI Updates")
    print(f"Mode: {'check' if check_only else 'update'}")

    attempted = 0
    failed = 0
    skipped = 0
    updated = 0
    for spec in specs:
        installed_path = shutil.which(spec.command)
        if not installed_path:
            print_status_line("missing", f"{spec.name} ({spec.command}) not found on PATH; skipping.")
            skipped += 1
            continue

        # Check version before update
        version_before = get_command_version(spec.command)

        try:
            command, runner = resolve_update_command(spec)
        except RuntimeError as exc:
            print_status_line("fail", f"{spec.name}: {exc}")
            failed += 1
            continue
        attempted += 1
        command_display = shlex.join(command)
        if check_only:
            print_status_line("ok", f"{spec.name} via {runner}")
            if version_before:
                print(f"  current version: {version_before}")
            print(f"  command: {command_display}")
            continue
        resolved_runner = shutil.which(command[0])
        if not resolved_runner:
            print_status_line("fail", f"{spec.name}: required updater '{command[0]}' is not installed.")
            failed += 1
            continue

        command_exec = [resolved_runner, *command[1:]]
        print_status_line("info", f"Updating {spec.name} via {runner}")
        print(f"  command: {command_display}")

        output_lines: list[str] = []
        process = subprocess.Popen(
            command_exec,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
        )
        assert process.stdout is not None
        for raw_line in process.stdout:
            line = raw_line.rstrip()
            output_lines.append(line)
            if line:
                print(f"  {line}")
        return_code = process.wait()
        if return_code == 0:
            version_after = get_command_version(spec.command)
            runner_bin_dir = get_runner_bin_dir(runner)

            is_shadowed = False
            if installed_path and runner_bin_dir:
                # Normalizing paths for comparison
                p_installed = Path(installed_path).resolve()
                p_runner_bin = Path(runner_bin_dir).resolve()
                if p_runner_bin not in p_installed.parents:
                    is_shadowed = True

            if version_before and version_after and version_before == version_after:
                output_str = "\n".join(output_lines)
                if "Already up to date" not in output_str and "is up to date" not in output_str:
                    print_status_line("warn", f"{spec.name} version did not change ({version_after}).")
                    if is_shadowed:
                        print(
                            f"  {colorize('Note:', 'warn')} active binary '{installed_path}' is SHADOWING the {runner} version."
                        )
                        print(f"  Expected in: {runner_bin_dir}")
                else:
                    if is_shadowed:
                        print_status_line("warn", f"{spec.name} is up to date in {runner}, but SHADOWED on PATH.")
                        print(f"  Active: {installed_path}")
                        print(f"  Try: pnpm remove -g {spec.package} (if installed via pnpm)")
                    else:
                        print_status_line("ok", f"{spec.name} is already up to date ({version_after})")
            else:
                if is_shadowed:
                    print_status_line("warn", f"{spec.name} updated, but still SHADOWED on PATH.")
                    print(f"  Active version: {version_after}")
                    print(f"  Active path: {installed_path}")
                else:
                    print_status_line(
                        "ok", f"{spec.name} updated: {version_before or 'unknown'} -> {version_after or 'unknown'}"
                    )
            updated += 1
        else:
            print_status_line("fail", f"{spec.name} update failed via {runner}")
            if output_lines:
                print("  (combined stdout/stderr shown above)")
            failed += 1
    print("")
    print(f"Summary: updated {updated}/{attempted} attempted; skipped {skipped} missing; failed {failed}.")
    return 1 if failed else 0


def cmd_skills_sync(repo_root: Path, config: dict[str, Any], check_only: bool, agents: list[str] | None = None) -> int:
    common_data = load_common_data(repo_root, config, include_local=True)
    skill_specs = common_data.get("skill_specs", [])
    if not skill_specs:
        print("No skill_specs configured.", file=sys.stderr)
        return 0

    # Get unique agent keys from skill specs
    spec_agents = sorted(set(s.get("agent", "").lower() for s in skill_specs if s.get("agent")))
    if agents is None and not check_only and is_interactive():
        agents = interactive_select(spec_agents, title="Select agents to sync skills for")
        if agents is None:
            print_status_line("info", "Cancelled.")
            return 0
        if not agents:
            print_status_line("info", "No agents selected.")
            return 0

    if agents:
        skill_specs = [s for s in skill_specs if s.get("agent", "").lower() in [a.lower() for a in agents]]
        if not skill_specs:
            print_status_line("warn", f"No skill specs match agents: {', '.join(agents)}")
            return 0

    print_section("Agent Skills Sync")
    print(f"Mode: {'check' if check_only else 'sync'}")
    if agents:
        print(f"Agents: {', '.join(agents)}")

    attempted = 0
    failed = 0
    skipped = 0
    synced = 0

    for spec in skill_specs:
        name = spec.get("name", "unknown")
        agent_key = spec.get("agent", "").lower()
        source = spec.get("source", "")
        if not agent_key or not source:
            print_status_line("fail", f"Invalid skill spec: {name} (missing agent or source)")
            failed += 1
            continue

        agent_cli = next(
            (
                a
                for a in parse_agent_clis(config["agent_clis"])
                if a.command == agent_key or a.name.lower() == agent_key
            ),
            None,
        )
        if not agent_cli:
            # Try direct command match
            agent_cli = AgentCli(name=agent_key.capitalize(), command=agent_key)

        installed_path = shutil.which(agent_cli.command)
        if not installed_path:
            print_status_line("missing", f"{agent_cli.name} ({agent_cli.command}) not found; skipping skill {name}.")
            skipped += 1
            continue

        command: list[str] = []
        if agent_cli.command == "gemini":
            command = ["gemini", "skills", "install", source]
        elif agent_cli.command == "claude":
            # Claude Code uses /plugin install in-session, but for CLI automation we might need another way or just skip
            # If there's no CLI flag for plugins, we skip for now.
            print_status_line("warn", f"Automated plugin install for {agent_cli.name} not yet supported; skip {name}.")
            skipped += 1
            continue
        else:
            print_status_line("warn", f"Skill sync for {agent_cli.name} not yet implemented; skip {name}.")
            skipped += 1
            continue

        attempted += 1
        command_display = shlex.join(command)
        if check_only:
            print_status_line("ok", f"Plan: {name} for {agent_cli.name}")
            print(f"  command: {command_display}")
            continue

        print_status_line("ok", f"Syncing {name} for {agent_cli.name}...")
        print(f"  command: {command_display}")
        try:
            subprocess.run(command, check=True, shell=os.name == "nt")
            print_status_line("ok", f"Successfully synced {name}")
            synced += 1
        except subprocess.CalledProcessError as exc:
            print_status_line("fail", f"Failed to sync {name}: {exc}")
            failed += 1

    print("")
    print(f"Summary: synced {synced}/{attempted} attempted; skipped {skipped}; failed {failed}.")
    return 1 if failed else 0


def cmd_skills_view(json_output: bool, check_only: bool) -> int:
    command = ["pnpm", "dlx", "skills", "ls", "-g"]
    if json_output:
        command.append("--json")
    command_display = shlex.join(command)
    print_section("Agent Skills View")
    if check_only:
        print_status_line("ok", "Plan: list global shared skills catalog")
        print(f"  command: {command_display}")
        return 0

    if not shutil.which("pnpm"):
        print_status_line("missing", "pnpm not found; cannot run skills catalog view.")
        print("  install pnpm first, then rerun: oooconf agents skills view")
        return 1

    print_status_line("info", "Listing global shared skills catalog via pnpm dlx")
    print(f"  command: {command_display}")
    result = subprocess.run(command, shell=os.name == "nt")
    if result.returncode != 0:
        print_status_line("fail", "skills list command failed.")
        print("  ensure the `skills` package is reachable from pnpm dlx in your environment.")
        return result.returncode
    return 0


def prompt_yes_no(question: str) -> bool:
    if shutil.which("gum") and sys.stdin.isatty():
        result = subprocess.run(["gum", "confirm", question], shell=False)
        return result.returncode == 0
    return False


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
    if json_payload:
        payload = json_payload
    elif not sys.stdin.isatty():
        payload = sys.stdin.read()
    else:
        prompt = "multiple MCP JSON entries" if allow_multi else "single MCP JSON object"
        print(f"Paste {prompt} and press Ctrl-D:", file=sys.stderr)
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
            if isinstance(parsed_payload, dict) and "command" in parsed_payload:
                single_named_payload = json.dumps({name: parsed_payload})
        except json.JSONDecodeError:
            pass

    parsed_entries = parse_mcp_json_inputs(single_named_payload, allow_multi=allow_multi)
    data = read_json(repo_root, config["common_data_file"])
    mcp_servers = data.setdefault("mcp_servers", {})
    planned: list[str] = []
    for parsed_name, entry in parsed_entries.items():
        key = name or parsed_name
        normalized = normalize_mcp_command(entry)
        validate_mcp_entry(key, normalized)
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
    should_sync = sync_now or prompt_yes_no("Sync global agent configs now?")
    if should_sync:
        return cmd_sync(repo_root, config, check_only=False, global_sync=True)
    return 0


def cmd_skills_add(
    repo_root: Path, config: dict[str, Any], source: str, agent: str, check_only: bool, sync_now: bool
) -> int:
    data = read_json(repo_root, config["common_data_file"])
    skill_specs = data.setdefault("skill_specs", [])
    source_url = canonicalize_skill_source(source)
    name = source.rstrip("/").split("/")[-1]
    spec = {
        "name": name,
        "agent": agent,
        "source": source_url,
        "description": f"Added via oooconf agents skills add ({source})",
    }
    exists = any(
        canonicalize_skill_source(str(s.get("source", ""))) == source_url and s.get("agent") == agent
        for s in skill_specs
    )
    if not exists:
        skill_specs.append(spec)
    skills = data.setdefault("skills", [])
    label = f"{name} ({agent})"
    if label not in skills:
        skills.append(label)
    if check_only:
        print_status_line("ok", f"Plan: add skill spec '{source_url}' for {agent}")
        return 0
    write_common_data(repo_root, config, data)
    print_status_line("ok", f"Added skill spec '{source_url}' for {agent}")
    should_sync = sync_now or prompt_yes_no("Sync skills to local agents now?")
    if should_sync:
        return cmd_skills_sync(repo_root, config, check_only=False)
    return 0


def resolve_mcp_path(repo_root: Path, name: str) -> Path:
    base = Path("~/.local/share/ooodnakov-config/mcp").expanduser()
    return (base / name).resolve()


def expand_mcp_vars(text: str, mcp_dir: Path, repo_root: Path) -> str:
    # Use ~ expansion first
    expanded = str(Path(text).expanduser()) if text.startswith("~") else text
    return expanded.replace("{mcp_dir}", str(mcp_dir)).replace("{repo_root}", str(repo_root))


def resolve_env_reference(var_name: str) -> str | None:
    return os.environ.get(var_name)


def replace_env_references(text: str) -> str:
    def replace_with_value(match: re.Match[str]) -> str:
        name = match.group(1)
        value = resolve_env_reference(name)
        return value if value is not None else match.group(0)

    rewritten = BRACED_ENV_REF_PATTERN.sub(replace_with_value, text)
    rewritten = SIMPLE_ENV_REF_PATTERN.sub(replace_with_value, rewritten)
    return ENV_PLACEHOLDER_PATTERN.sub(replace_with_value, rewritten)


def render_mcp_value(
    value: str,
    *,
    mcp_dir: Path,
    repo_root: Path,
) -> str:
    rendered = expand_mcp_vars(value, mcp_dir, repo_root)
    return replace_env_references(rendered)


def build_mcp_env(
    config: dict[str, Any],
    *,
    mcp_dir: Path,
    repo_root: Path,
    materialize_secrets: bool = False,
) -> dict[str, Any]:
    env: dict[str, Any] = {}

    for name in config.get("env_vars", []):
        value = resolve_env_reference(name)
        env[name] = value if (value is not None and materialize_secrets) else f"{{{name}}}"

    for key, value in config.get("env", {}).items():
        if isinstance(value, str):
            env[key] = render_mcp_value(value, mcp_dir=mcp_dir, repo_root=repo_root) if materialize_secrets else value
        else:
            env[key] = value

    return env


def render_mcp_server_entry(
    _target: AgentConfigTarget,
    name: str,
    config: dict[str, Any],
    repo_root: Path,
    *,
    materialize_secrets: bool = False,
) -> dict[str, Any]:
    mcp_dir = resolve_mcp_path(repo_root, name)
    entry = {
        "command": render_mcp_value(
            config["command"],
            mcp_dir=mcp_dir,
            repo_root=repo_root,
        ),
        "args": [render_mcp_value(arg, mcp_dir=mcp_dir, repo_root=repo_root) for arg in config.get("args", [])],
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
    entry = render_mcp_server_entry(target, name, config, repo_root, materialize_secrets=materialize_secrets)
    mapped: dict[str, Any] = {
        "type": "local",
        "command": [entry["command"], *entry.get("args", [])],
        "enabled": True,
    }
    if "env" in entry and isinstance(entry["env"], dict) and entry["env"]:
        mapped["environment"] = entry["env"]
    return mapped


MINIMAX_MODEL = "MiniMax-M2.7"
MINIMAX_CODEX_MODEL = "codex-MiniMax-M2.7"
MINIMAX_ENV_KEY = "MINIMAX_API_KEY"


def minimax_endpoints(region: str) -> dict[str, str]:
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


def read_json_file_or_empty(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    parsed = json.loads(path.read_text(encoding="utf-8").strip() or "{}")
    if not isinstance(parsed, dict):
        raise ValueError(f"expected JSON object in {path}")
    return parsed


def upsert_nested_dict(target: dict[str, Any], updates: dict[str, Any]) -> bool:
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
    if not check_only:
        path.parent.mkdir(parents=True, exist_ok=True)


def upsert_claude_minimax_config(path: Path, region: str, materialize_secrets: bool, check_only: bool) -> bool:
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
    if (
        not materialize_secrets
        and isinstance(env, dict)
        and env.get("ANTHROPIC_AUTH_TOKEN") == f"{{{MINIMAX_ENV_KEY}}}"
    ):
        del env["ANTHROPIC_AUTH_TOKEN"]
        changed = True
    if changed:
        ensure_parent(path, check_only)
        if not check_only:
            path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return changed


def upsert_opencode_minimax_config(path: Path, region: str, materialize_secrets: bool, check_only: bool) -> bool:
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
            path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return changed


def toml_table_exists(content: str, table: str) -> bool:
    return bool(re.search(rf"^\s*\[\s*{re.escape(table)}\s*\]\s*$", content, flags=re.MULTILINE))


def replace_or_append_toml_table(content: str, table: str, rendered: str) -> tuple[str, bool]:
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


def render_codex_minimax_profile() -> str:
    return f'[profiles.minimax]\nmodel = "{MINIMAX_CODEX_MODEL}"\nmodel_provider = "minimax"\n'


def append_codex_minimax_config(path: Path, region: str, materialize_secrets: bool, check_only: bool) -> bool:
    current = path.read_text(encoding="utf-8") if path.exists() else ""
    api_key = os.environ.get(MINIMAX_ENV_KEY)
    updated, provider_changed = replace_or_append_toml_table(
        current, "model_providers.minimax", render_codex_minimax_provider(region, materialize_secrets and api_key is not None, api_key)
    )
    updated, profile_changed = replace_or_append_toml_table(updated, "profiles.minimax", render_codex_minimax_profile())
    changed = provider_changed or profile_changed
    if changed:
        ensure_parent(path, check_only)
        if not check_only:
            path.write_text(updated, encoding="utf-8")
    return changed


def render_codex_minimax_provider(region: str, materialize_secrets: bool = False, api_key: str | None = None) -> str:
    endpoints = minimax_endpoints(region)
    key_value = api_key if materialize_secrets and api_key is not None else MINIMAX_ENV_KEY
    return (
        "[model_providers.minimax]\n"
        'name = "MiniMax Chat Completions API"\n'
        f'base_url = "{endpoints["openai_base_url"]}"\n'
        f'env_key = "{key_value}"\n'
        'env_key_instructions = "Export MINIMAX_API_KEY before starting Codex."\n'
        'wire_api = "chat"\n'
        "requires_openai_auth = false\n"
        "request_max_retries = 4\n"
        "stream_max_retries = 10\n"
        "stream_idle_timeout_ms = 300000\n"
    )


def cmd_provider_sync(
    config: dict[str, Any], provider: str, check_only: bool, materialize_secrets: bool, region: str, agents: list[str] | None = None
) -> int:
    if provider != "minimax":
        print_status_line("fail", f"Unsupported provider: {provider}")
        return 1

    targets = parse_agent_targets(config["agent_configs"])
    supported = {
        "Claude Code": upsert_claude_minimax_config,
        "OpenCode": upsert_opencode_minimax_config,
        "OpenAI Codex CLI": append_codex_minimax_config,
    }

    # Filter to only supported agents
    supported_names = sorted(supported.keys())
    if agents is None and not check_only and is_interactive():
        agents = interactive_select(supported_names, title="Select agents to configure provider")
        if agents is None:
            print_status_line("info", "Cancelled.")
            return 0
        if not agents:
            print_status_line("info", "No agents selected.")
            return 0

    print_section("Agent Provider Sync")
    print(f"Provider: {provider}")
    print(f"Region: {region}")
    print(f"Mode: {'check' if check_only else 'sync'}")
    if agents:
        print(f"Agents: {', '.join(agents)}")

    if materialize_secrets and not os.environ.get(MINIMAX_ENV_KEY):
        print_status_line("fail", f"{MINIMAX_ENV_KEY} is not set; refusing to materialize an empty API key.")
        return 1

    changed_paths: list[Path] = []

    for target in targets:
        updater = supported.get(target.name)
        if updater is None or not target.default_paths:
            continue
        if agents is not None and target.name not in agents:
            continue
        path = existing_default_path(target.default_paths) or Path(target.default_paths[0]).expanduser()
        try:
            changed = updater(path, region, materialize_secrets, check_only)  # type: ignore[misc]
        except Exception as exc:
            print_status_line("fail", f"{target.name}: failed to update {path}: {exc}")
            return 1
        status = "ok" if changed else "info"
        action = "would update" if check_only and changed else "updated" if changed else "already configured"
        print_status_line(status, f"{target.name}: {action} {path}")
        if changed:
            changed_paths.append(path)

    print("")
    print(f"Summary: {len(changed_paths)} supported provider config(s) {'would change' if check_only else 'changed'}.")
    if not materialize_secrets:
        print(f"Hint: export {MINIMAX_ENV_KEY} in your local env before launching Codex.")
        print(
            f"Hint: Claude Code requires ANTHROPIC_AUTH_TOKEN to contain the MiniMax key; export ANTHROPIC_AUTH_TOKEN=${MINIMAX_ENV_KEY} before launching Claude or rerun with --materialize-secrets."
        )
        print(
            "Hint: OpenCode stores provider credentials via `opencode auth login --provider minimax`; rerun with --materialize-secrets only if you intentionally want the key written to opencode.json."
        )
    return 1 if check_only and changed_paths else 0


def cmd_mcp_sync(repo_root: Path, config: dict[str, Any], check_only: bool, agents: list[str] | None = None) -> int:
    common_data = load_common_data(repo_root, config, include_local=True)
    mcp_servers = common_data.get("mcp_servers", {})
    managed_mcps = {name: cfg for name, cfg in mcp_servers.items() if "source" in cfg}

    if not managed_mcps:
        print("No managed MCP servers (with 'source') configured.")
        return 0

    mcp_names = sorted(managed_mcps.keys())
    if agents is None and not check_only and is_interactive():
        agents = interactive_select(mcp_names, title="Select MCP servers to sync")
        if agents is None:
            print_status_line("info", "Cancelled.")
            return 0
        if not agents:
            print_status_line("info", "No MCP servers selected.")
            return 0

    if agents:
        managed_mcps = {name: cfg for name, cfg in managed_mcps.items() if name in agents}
        if not managed_mcps:
            print_status_line("warn", f"No managed MCP servers match: {', '.join(agents)}")
            return 0

    print_section("MCP Sync")
    print(f"Mode: {'check' if check_only else 'sync'}")
    if agents:
        print(f"Agents: {', '.join(agents)}")

    attempted = 0
    failed = 0
    synced = 0

    for name, cfg in managed_mcps.items():
        source = cfg["source"]
        mcp_dir = resolve_mcp_path(repo_root, name)
        install_cmd = cfg.get("install")

        attempted += 1
        print_status_line("info", f"Syncing {name} ({source})")

        if not mcp_dir.parent.exists():
            if not check_only:
                mcp_dir.parent.mkdir(parents=True, exist_ok=True)

        if not mcp_dir.exists():
            print(f"  {icon('bullet')} Cloning into {mcp_dir}...")
            if check_only:
                synced += 1
                continue
            try:
                subprocess.run(["git", "clone", source, str(mcp_dir)], check=True)
            except subprocess.CalledProcessError as exc:
                print_status_line("fail", f"Failed to clone {name}: {exc}")
                failed += 1
                continue
        else:
            print(f"  {icon('bullet')} Pulling latest changes in {mcp_dir}...")
            if not check_only:
                try:
                    subprocess.run(["git", "-C", str(mcp_dir), "pull", "--ff-only"], check=True)
                except subprocess.CalledProcessError as exc:
                    print_status_line("warn", f"Failed to pull {name} (continuing): {exc}")

        if install_cmd:
            print(f"  {icon('bullet')} Running install: {install_cmd}")
            if check_only:
                synced += 1
                continue

            # Run install command in the mcp directory
            try:
                cmd_parts = shlex.split(install_cmd)
                if not cmd_parts:
                    continue
                subprocess.run(cmd_parts, check=True, cwd=str(mcp_dir))
                print_status_line("ok", f"Successfully installed {name}")
                synced += 1
            except subprocess.CalledProcessError as exc:
                print_status_line("fail", f"Install failed for {name}: {exc}")
                failed += 1
                continue
        else:
            print_status_line("ok", f"Synced {name} (no install needed)")
            synced += 1

    print("")
    print(f"Summary: synced {synced}/{attempted} managed MCPs; failed {failed}.")
    return 1 if failed else 0


def cmd_mcp_status(repo_root: Path, config: dict[str, Any]) -> int:
    common_data = load_common_data(repo_root, config, include_local=True)
    mcp_servers = common_data.get("mcp_servers", {})

    print_section("MCP Status")

    for name, cfg in sorted(mcp_servers.items()):
        source = cfg.get("source")
        if source:
            mcp_dir = resolve_mcp_path(repo_root, name)
            if mcp_dir.exists():
                print_status_line("ok", f"{name} (managed): {mcp_dir}")
            else:
                print_status_line("missing", f"{name} (managed): {mcp_dir} NOT CLONED")
        else:
            print_status_line("ok", f"{name} (static): {cfg.get('command')} {shlex.join(cfg.get('args', []))}")

    return 0


def cmd_rtk_init(repo_root: Path, config: dict[str, Any], check_only: bool) -> int:
    if os.name == "nt":
        print_status_line("fail", "RTK hook-based initialization is not supported on Windows.")
        return 0

    if not shutil.which("rtk"):
        print_status_line("fail", "rtk command not found. Install it first (e.g., via 'oooconf deps rtk').")
        return 1

    rows = detect_clis(parse_agent_clis(config["agent_clis"]))
    installed_agents = {row["command"] for row in rows if row["installed"]}

    if not installed_agents:
        print("No agents detected; nothing to initialize.")
        return 0

    print_section("RTK Init")
    print(f"Mode: {'check' if check_only else 'init'}")

    # Mapping of agent commands to rtk init flags
    # rtk supports: claude (default), cursor, gemini, opencode, codex
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
            print(f"  command: {cmd_display}")

            if check_only:
                synced += 1
                continue

            try:
                subprocess.run(cmd, check=True)
                print_status_line("ok", f"Successfully initialized {agent_cmd}")
                synced += 1
            except subprocess.CalledProcessError as exc:
                print_status_line("fail", f"Failed to initialize {agent_cmd}: {exc}")
                failed += 1

    print("")
    print(f"Summary: initialized RTK for {synced}/{attempted} detected agents; failed {failed}.")
    return 1 if failed else 0


if __name__ == "__main__":
    args = parse_args()
    root = resolve_repo_root(args.repo_root)
    config_path = resolve_config_path(root, args.config)
    try:
        cfg = load_config(config_path)
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)

    if args.command == "detect":
        raise SystemExit(cmd_detect(cfg, json_output=args.json))
    if args.command == "sync":
        raise SystemExit(
            cmd_sync(
                root,
                cfg,
                check_only=args.check,
                global_sync=args.global_sync,
                materialize_secrets=args.materialize_secrets,
                agents=args.agents,
            )
        )
    if args.command == "doctor":
        raise SystemExit(cmd_doctor(root, cfg, strict_paths=args.strict_config_paths))
    if args.command == "mcp":
        if args.subcommand == "sync":
            raise SystemExit(cmd_mcp_sync(root, cfg, check_only=args.check, agents=args.agents))
        if args.subcommand == "add":
            raise SystemExit(
                cmd_mcp_add(
                    root,
                    cfg,
                    name=args.name,
                    json_payload=args.json_payload,
                    check_only=args.check,
                    sync_now=args.sync_now,
                    allow_multi=args.multi,
                    preview=args.preview,
                )
            )
        if args.subcommand == "status":
            raise SystemExit(cmd_mcp_status(root, cfg))
    if args.command == "rtk":
        if args.subcommand == "init":
            raise SystemExit(cmd_rtk_init(root, cfg, check_only=args.check))
    if args.command == "provider":
        if args.subcommand == "sync":
            raise SystemExit(
                cmd_provider_sync(
                    cfg,
                    provider=args.provider,
                    check_only=args.check,
                    materialize_secrets=args.materialize_secrets,
                    region=args.region,
                    agents=args.agents,
                )
            )
    if args.command == "update":
        raise SystemExit(cmd_update(root, cfg, check_only=args.check))
    if args.command == "install":
        raise SystemExit(
            cmd_install(
                root,
                cfg,
                args.agents,
                check_only=args.check,
                install_all=args.all,
                missing_only=args.missing,
            )
        )
    if args.command == "install-scripts-build":
        raise SystemExit(cmd_install_scripts_build(root, cfg))
    if args.command == "skills":
        if args.subcommand == "sync":
            raise SystemExit(cmd_skills_sync(root, cfg, check_only=args.check, agents=args.agents))
        if args.subcommand == "view":
            raise SystemExit(cmd_skills_view(json_output=args.json, check_only=args.check))
        if args.subcommand == "add":
            raise SystemExit(
                cmd_skills_add(
                    root,
                    cfg,
                    source=args.source,
                    agent=args.agent,
                    check_only=args.check,
                    sync_now=args.sync_now,
                )
            )
    raise SystemExit(1)
