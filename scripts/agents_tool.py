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
DEFAULT_CONFIG_PATH = Path("home/.config/ooodnakov/agents/config.json")
ASCII_ICONS = {
    "section": "==",
    "ok": "[ok]",
    "warn": "[warn]",
    "fail": "[fail]",
    "missing": "[missing]",
    "outdated": "[outdated]",
    "bullet": "-",
}
NERD_FONT_ICONS = {
    "section": "▸",
    "ok": "✓",
    "warn": "⚠",
    "fail": "✗",
    "missing": "✗",
    "outdated": "󰏫",
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
    update_parser = subparsers.add_parser(
        "update",
        help="Update installed agent CLIs with their preferred package manager (npm routes through pnpm).",
    )
    update_parser.add_argument(
        "--check",
        action="store_true",
        help="Print planned update commands without executing them.",
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
                common_data.setdefault("mcp_servers", {}).update(local_data["mcp_servers"])
            if "extensions" in local_data:
                current_exts = common_data.get("extensions", [])
                for ext in local_data["extensions"]:
                    if ext not in current_exts:
                        current_exts.append(ext)
                common_data["extensions"] = current_exts
        except Exception as exc:
            print(f"warning: failed to load local agent data: {exc}", file=sys.stderr)

    return common_data


def discover_agent_files(repo_root: Path, configured_files: list[str]) -> list[Path]:
    discovered: set[Path] = set()
    for rel in configured_files:
        candidate = (repo_root / rel).resolve()
        if candidate.exists() and candidate.is_file():
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
        end = existing.index(MANAGED_END) + len(MANAGED_END)
        return existing[:start].rstrip() + "\n\n" + managed_block + existing[end:].lstrip("\n")
    return existing.rstrip() + "\n\n" + managed_block


def sync_files(agent_files: list[Path], managed_block: str, check_only: bool) -> tuple[int, list[Path]]:
    changed: list[Path] = []
    for path in agent_files:
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


def check_common_entries(content: str, common_data: dict[str, Any]) -> tuple[list[str], list[str]]:
    lowered = content.lower()
    missing_mcp: list[str] = []
    missing_skills: list[str] = []

    mcp_servers = common_data.get("mcp_servers", {})
    for name in mcp_servers:
        if name.lower() not in lowered:
            missing_mcp.append(name)

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

        missing_mcp, missing_skills = check_common_entries(search_space, common_data)
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
    targets: list[AgentConfigTarget], common_data: dict[str, Any], managed_block: str, check_only: bool
) -> tuple[int, list[Path]]:
    changed: list[Path] = []

    for target in targets:
        existing = existing_default_path(target.default_paths)
        if existing is None:
            continue

        if target.format == "markdown":
            try:
                current = existing.read_text(encoding="utf-8")
                updated = upsert_managed_block(current, managed_block)
                if updated != current:
                    changed.append(existing)
                    if not check_only:
                        existing.write_text(updated, encoding="utf-8")
            except Exception as exc:
                print(f"warning: failed to sync global markdown {existing}: {exc}", file=sys.stderr)
            continue

        if target.format != "json":
            continue

        mcp_servers = common_data.get("mcp_servers", {})
        if not mcp_servers:
            continue

        try:
            data = json.loads(existing.read_text(encoding="utf-8"))
            # Standard MCP injection (Claude/Gemini format)
            if "mcpServers" not in data:
                data["mcpServers"] = {}

            needs_update = False
            for name, config in mcp_servers.items():
                if name not in data["mcpServers"]:
                    if "command" not in config:
                        continue
                    data["mcpServers"][name] = {
                        "command": config["command"],
                        "args": config.get("args", []),
                    }
                    if "env" in config:
                        data["mcpServers"][name]["env"] = config["env"]
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


def cmd_sync(repo_root: Path, config: dict[str, Any], check_only: bool, global_sync: bool) -> int:
    common_text = read_text(repo_root, config["common_text_file"])
    agent_files = discover_agent_files(repo_root, config["agent_files"])

    changed_count = 0
    changed_files = []
    if agent_files:
        repo_data = load_common_data(repo_root, config, include_local=False)
        managed_block_repo = render_markdown_block(common_text, repo_data)
        changed_count, changed_files = sync_files(agent_files, managed_block_repo, check_only)

    print_section("AGENTS Sync")
    print(f"Mode: {'check' if check_only else 'sync'}")
    print(f"Files scanned: {len(agent_files)}")
    print(f"Repo files needing updates: {changed_count}")

    if changed_files:
        print("")
        print("Changed repo files:")
        for file_path in changed_files:
            print(f"{icon('bullet')} {file_path}")

    g_count = 0
    g_files = []
    if global_sync:
        merged_data = load_common_data(repo_root, config, include_local=True)
        managed_block_global = render_markdown_block(common_text, merged_data)
        config_targets = parse_agent_targets(config["agent_configs"])
        g_count, g_files = sync_global_configs(config_targets, merged_data, managed_block_global, check_only)
        print("")
        print(f"Global configs scanned: {len(config_targets)}")
        print(f"Global configs needing updates: {g_count}")
        if g_files:
            for file_path in g_files:
                print(f"{icon('bullet')} {file_path}")

    if not changed_files and (not global_sync or not g_files):
        print("")
        print("All target files are up to date.")

    return 1 if check_only and (changed_count > 0 or (global_sync and g_count > 0)) else 0


def cmd_doctor(repo_root: Path, config: dict[str, Any], strict_paths: bool) -> int:
    common_text = read_text(repo_root, config["common_text_file"])
    common_data = load_common_data(repo_root, config)
    managed_block = render_markdown_block(common_text, common_data)
    agent_files = discover_agent_files(repo_root, config["agent_files"])
    config_targets = parse_agent_targets(config["agent_configs"])
    config_results, config_failures = inspect_agent_configs(config_targets, common_data)
    rows = detect_clis(parse_agent_clis(config["agent_clis"]))

    failed = False
    outdated_agent_files: list[Path] = []
    if not agent_files:
        failed = True
    else:
        for path in agent_files:
            text = path.read_text(encoding="utf-8")
            if upsert_managed_block(text, managed_block) != text:
                outdated_agent_files.append(path)
                failed = True

    print_section("AGENTS Doctor")

    print("AGENTS.md Files")
    print("---------------")
    if not agent_files:
        print_status_line("fail", "No AGENTS.md files found from configured locations/discovery.")
    elif outdated_agent_files:
        for path in outdated_agent_files:
            print_status_line("outdated", f"Managed block needs update: {path}")
    else:
        print_status_line("ok", f"Managed blocks are current in {len(agent_files)} file(s).")

    print("")
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
        f"{len(agent_files)} AGENTS.md file(s), "
        f"{len(outdated_agent_files)} outdated, "
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


def cmd_update(config: dict[str, Any], check_only: bool) -> int:
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
            print(f"  command: {command_display}")
            continue
        resolved_runner = shutil.which(command[0])
        if not resolved_runner:
            print_status_line("fail", f"{spec.name}: required updater '{command[0]}' is not installed.")
            failed += 1
            continue
        command_exec = [resolved_runner, *command[1:]]
        print_status_line("ok", f"{spec.name} via {runner}")
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
            print_status_line("ok", f"{spec.name} updated via {runner}")
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
    if args.command == "update":
        raise SystemExit(cmd_update(cfg, check_only=args.check))
    if args.command == "skills":
        if args.subcommand == "sync":
            raise SystemExit(cmd_skills_sync(root, cfg, check_only=args.check))
    raise SystemExit(1)
