#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
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
ANSI_COLORS = {
    "section": "\033[38;5;111m",
    "ok": "\033[38;5;78m",
    "warn": "\033[38;5;221m",
    "fail": "\033[38;5;203m",
    "missing": "\033[38;5;203m",
    "outdated": "\033[38;5;215m",
    "info": "\033[38;5;117m",
    "muted": "\033[38;5;245m",
}


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


@dataclass(frozen=True)
class AgentUpdateSpec:
    name: str
    command: str
    preferred: str
    package: str


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
        "--global", dest="global_sync", action="store_true", help="Also sync MCP servers to global agent configs."
    )

    doctor_parser = subparsers.add_parser(
        "doctor", help="Validate AGENTS.md managed block and check common MCP/skills in agent config paths."
    )
    doctor_parser.add_argument(
        "--strict-config-paths",
        action="store_true",
        help="Fail if no default config path exists for an agent target.",
    )

    mcp_parser = subparsers.add_parser(
        "mcp", help="Manage Model Context Protocol (MCP) servers."
    )
    mcp_subparsers = mcp_parser.add_subparsers(dest="subcommand", required=True)
    mcp_sync_parser = mcp_subparsers.add_parser("sync", help="Synchronize (clone/pull/install) managed MCP servers.")
    mcp_sync_parser.add_argument("--check", action="store_true", help="Print planned actions without executing.")
    mcp_status_parser = subparsers.add_parser("status", help="Show status of managed MCP servers.")

    rtk_parser = subparsers.add_parser(
        "rtk", help="Manage RTK (Rust Token Killer) integration."
    )
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
        help="Install a specific agent CLI.",
    )
    install_parser.add_argument(
        "agent",
        help="The agent key or name to install (e.g., claude, gemini, aider).",
    )
    install_parser.add_argument(
        "--check",
        action="store_true",
        help="Print planned install command without executing it.",
    )

    subparsers.add_parser(
        "install-scripts-build",
        help="Build standalone install.sh and install.ps1 scripts for agents.",
    )

    skills_parser = subparsers.add_parser(
        "skills",
        help="Manage agent skills and extensions across different agent ecosystems.",
    )
    skills_subparsers = skills_parser.add_subparsers(dest="subcommand", required=True)
    skills_sync_parser = skills_subparsers.add_parser("sync", help="Synchronize configured skill_specs across agents.")
    skills_sync_parser.add_argument("--check", action="store_true", help="Print planned skill installs without executing.")

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


def colorize(text: str, role: str, *, bold: bool = False) -> str:
    if not supports_color_output():
        return text
    color = ANSI_COLORS.get(role, "")
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
        if missing_mcp or missing_skills:
            has_failures = True

        results.append(
            DoctorConfigResult(
                target=target,
                existing_path=existing,
                missing_mcp=missing_mcp,
                missing_skills=missing_skills,
            )
        )

    return results, has_failures


def sync_global_configs(
    repo_root: Path, targets: list[AgentConfigTarget], common_data: dict[str, Any], managed_block: str, check_only: bool
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
                        
                        mcp_dir = resolve_mcp_path(repo_root, name)
                        command = expand_mcp_vars(config["command"], mcp_dir, repo_root)
                        args = [expand_mcp_vars(arg, mcp_dir, repo_root) for arg in config.get("args", [])]
                        
                        # Basic TOML injection (appending to end of file)
                        block = f"\n[mcp_servers.{name}]\ncommand = {json.dumps(command)}\nargs = {json.dumps(args)}\n"
                        if "env" in config:
                            block += f"[mcp_servers.{name}.env]\n"
                            for k, v in config["env"].items():
                                val = expand_mcp_vars(v, mcp_dir, repo_root) if isinstance(v, str) else v
                                block += f"{k} = {json.dumps(val)}\n"
                        
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
            if mcp_servers:
                if "mcpServers" not in data:
                    data["mcpServers"] = {}

                for name, config in mcp_servers.items():
                    if name not in data["mcpServers"]:
                        if "command" not in config:
                            continue

                        mcp_dir = resolve_mcp_path(repo_root, name)
                        command = expand_mcp_vars(config["command"], mcp_dir, repo_root)
                        args = [expand_mcp_vars(arg, mcp_dir, repo_root) for arg in config.get("args", [])]

                        data["mcpServers"][name] = {
                            "command": command,
                            "args": args,
                        }
                        if "env" in config:
                            env = {
                                k: expand_mcp_vars(v, mcp_dir, repo_root) if isinstance(v, str) else v
                                for k, v in config["env"].items()
                            }
                            data["mcpServers"][name]["env"] = env
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


def cmd_sync(repo_root: Path, config: dict[str, Any], check_only: bool, global_sync: bool) -> int:
    common_text = get_platform_common_text(repo_root, config)

    print_section("AGENTS Sync")
    print(f"Mode: {'check' if check_only else 'sync'}")

    g_count = 0
    g_files = []
    if global_sync:
        merged_data = load_common_data(repo_root, config, include_local=True)
        managed_block_global = render_markdown_block(common_text, merged_data)
        config_targets = parse_agent_targets(config["agent_configs"])
        g_count, g_files = sync_global_configs(repo_root, config_targets, merged_data, managed_block_global, check_only)
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
    common_text = get_platform_common_text(repo_root, config)
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
    print(
        "Summary: "
        f"{len(installed_clis)}/{len(rows)} CLIs installed, "
        f"{strict_note}."
    )

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
        # Resolve command (we use the update logic which is basically install latest)
        cmd_list, runner = resolve_update_command(spec)
        cmd_str = shlex.join(cmd_list)

        # Build Unix .sh script
        sh_path = install_dir / f"install-{spec.command}.sh"
        sh_content = f"#!/bin/sh\n# Generated by oooconf agents install-scripts-build\necho \"Installing {spec.name} via {runner}...\"\n{cmd_str}\n"
        sh_path.write_text(sh_content, encoding="utf-8")
        sh_path.chmod(0o755)

        # Build PowerShell .ps1 script
        ps1_path = install_dir / f"install-{spec.command}.ps1"
        # For powershell, we might want to ensure the runner exists
        ps1_content = f"# Generated by oooconf agents install-scripts-build\nWrite-Host \"Installing {spec.name} via {runner}...\"\n{cmd_str}\n"
        ps1_path.write_text(ps1_content, encoding="utf-8")

        print_status_line("ok", f"{spec.name} ({spec.command})")
        count += 1

    print(f"\nSummary: built install scripts for {count} agents.")
    return 0


def cmd_install(repo_root: Path, config: dict[str, Any], agent_query: str, check_only: bool) -> int:
    specs = parse_agent_update_specs(config.get("agent_updates", []))
    spec = next((s for s in specs if s.command == agent_query or s.name.lower() == agent_query.lower()), None)
    
    if not spec:
        print_status_line("fail", f"No agent update/install spec found for '{agent_query}'.")
        return 1

    print_section(f"Installing {spec.name}")
    print(f"Mode: {'check' if check_only else 'install'}")

    try:
        command, runner = resolve_update_command(spec)
    except RuntimeError as exc:
        print_status_line("fail", f"{spec.name}: {exc}")
        return 1

    command_display = shlex.join(command)
    if check_only:
        print_status_line("ok", f"Plan: install {spec.name} via {runner}")
        print(f"  command: {command_display}")
        return 0

    resolved_runner = shutil.which(command[0])
    if not resolved_runner:
        print_status_line("fail", f"Required runner '{command[0]}' is not installed.")
        return 1

    print_status_line("info", f"Executing: {command_display}")
    try:
        subprocess.run(command, check=True)
        print_status_line("ok", f"Successfully installed {spec.name}")
        return 0
    except subprocess.CalledProcessError as exc:
        print_status_line("fail", f"Failed to install {spec.name}: {exc}")
        return 1


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
                        print(f"  {colorize('Note:', 'warn')} active binary '{installed_path}' is SHADOWING the {runner} version.")
                        print(f"  Expected in: {runner_bin_dir}")
                else:
                    if is_shadowed:
                        print_status_line("warn", f"{spec.name} is up to date in {runner}, but SHADOWED on PATH.")
                        print(f"  Active: {installed_path}")
                        print(f"  Try: npm uninstall -g {spec.package} (if installed via npm)")
                    else:
                        print_status_line("ok", f"{spec.name} is already up to date ({version_after})")
            else:
                if is_shadowed:
                    print_status_line("warn", f"{spec.name} updated, but still SHADOWED on PATH.")
                    print(f"  Active version: {version_after}")
                    print(f"  Active path: {installed_path}")
                else:
                    print_status_line("ok", f"{spec.name} updated: {version_before or 'unknown'} -> {version_after or 'unknown'}")
            updated += 1
        else:
            print_status_line("fail", f"{spec.name} update failed via {runner}")
            if output_lines:
                print("  (combined stdout/stderr shown above)")
            failed += 1
    print("")
    print(f"Summary: updated {updated}/{attempted} attempted; skipped {skipped} missing; failed {failed}.")
    return 1 if failed else 0


def cmd_skills_sync(repo_root: Path, config: dict[str, Any], check_only: bool) -> int:
    common_data = load_common_data(repo_root, config, include_local=True)
    skill_specs = common_data.get("skill_specs", [])
    if not skill_specs:
        print("No skill_specs configured.", file=sys.stderr)
        return 0

    print_section("Agent Skills Sync")
    print(f"Mode: {'check' if check_only else 'sync'}")

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

        agent_cli = next((a for a in parse_agent_clis(config["agent_clis"]) if a.command == agent_key or a.name.lower() == agent_key), None)
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


def resolve_mcp_path(repo_root: Path, name: str) -> Path:
    base = Path("~/.local/share/ooodnakov-config/mcp").expanduser()
    return (base / name).resolve()


def expand_mcp_vars(text: str, mcp_dir: Path, repo_root: Path) -> str:
    # Use ~ expansion first
    expanded = str(Path(text).expanduser()) if text.startswith("~") else text
    return expanded.replace("{mcp_dir}", str(mcp_dir)).replace("{repo_root}", str(repo_root))


def cmd_mcp_sync(repo_root: Path, config: dict[str, Any], check_only: bool) -> int:
    common_data = load_common_data(repo_root, config, include_local=True)
    mcp_servers = common_data.get("mcp_servers", {})
    managed_mcps = {name: cfg for name, cfg in mcp_servers.items() if "source" in cfg}

    if not managed_mcps:
        print("No managed MCP servers (with 'source') configured.")
        return 0

    print_section("MCP Sync")
    print(f"Mode: {'check' if check_only else 'sync'}")

    attempted = 0
    failed = 0
    synced = 0
    skipped = 0

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
                # Use shell=True to support command chains like "npm install && npm run build"
                subprocess.run(install_cmd, shell=True, check=True, cwd=str(mcp_dir))
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
        raise SystemExit(cmd_sync(root, cfg, check_only=args.check, global_sync=args.global_sync))
    if args.command == "doctor":
        raise SystemExit(cmd_doctor(root, cfg, strict_paths=args.strict_config_paths))
    if args.command == "mcp":
        if args.subcommand == "sync":
            raise SystemExit(cmd_mcp_sync(root, cfg, check_only=args.check))
        if args.subcommand == "status":
            raise SystemExit(cmd_mcp_status(root, cfg))
    if args.command == "rtk":
        if args.subcommand == "init":
            raise SystemExit(cmd_rtk_init(root, cfg, check_only=args.check))
    if args.command == "update":
        raise SystemExit(cmd_update(root, cfg, check_only=args.check))
    if args.command == "install":
        raise SystemExit(cmd_install(root, cfg, args.agent, check_only=args.check))
    if args.command == "install-scripts-build":
        raise SystemExit(cmd_install_scripts_build(root, cfg))
    if args.command == "skills":
        if args.subcommand == "sync":
            raise SystemExit(cmd_skills_sync(root, cfg, check_only=args.check))
    raise SystemExit(1)
