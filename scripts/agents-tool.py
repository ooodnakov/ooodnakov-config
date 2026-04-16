#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
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
    "section": "󰆍",
    "ok": "󰄬",
    "warn": "󰀪",
    "fail": "󰅖",
    "missing": "󰅖",
    "outdated": "󰏫",
    "bullet": "󰘍",
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

    doctor_parser = subparsers.add_parser(
        "doctor", help="Validate AGENTS.md managed block and check common MCP/skills in agent config paths."
    )
    doctor_parser.add_argument(
        "--strict-config-paths",
        action="store_true",
        help="Fail if no default config path exists for an agent target.",
    )

    return parser.parse_args()


def resolve_repo_root(repo_root: str | None) -> Path:
    return Path(repo_root).expanduser().resolve() if repo_root else Path(__file__).resolve().parent.parent


def resolve_config_path(repo_root: Path, config_override: str | None) -> Path:
    return Path(config_override).expanduser().resolve() if config_override else (repo_root / DEFAULT_CONFIG_PATH).resolve()


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


def discover_agent_files(repo_root: Path, configured_files: list[str]) -> list[Path]:
    discovered: set[Path] = set()
    for rel in configured_files:
        candidate = (repo_root / rel).resolve()
        if candidate.exists() and candidate.is_file():
            discovered.add(candidate)
    for path in repo_root.rglob("AGENTS.md"):
        rel_path = path.resolve().relative_to(repo_root)
        if any(part in {".git", "third_party"} for part in rel_path.parts):
            continue
        discovered.add(path.resolve())
    return sorted(discovered)


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


def supports_nerd_font_output() -> bool:
    if os.environ.get("OOOCONF_ASCII") == "1":
        return False
    if not sys.stdout.isatty():
        return False
    encoding = (sys.stdout.encoding or "").lower()
    return "utf" in encoding


def icon(name: str) -> str:
    palette = NERD_FONT_ICONS if supports_nerd_font_output() else ASCII_ICONS
    return palette[name]


def print_section(title: str) -> None:
    prefix = icon("section")
    print(f"{prefix} {title}")
    print("─" * (len(title) + 2) if prefix != ASCII_ICONS["section"] else "-" * (len(title) + 3))


def print_status_line(status: str, message: str) -> None:
    print(f"{icon(status)} {message}")


def detect_clis(agent_clis: list[AgentCli]) -> list[dict[str, str | bool]]:
    rows: list[dict[str, str | bool]] = []
    for cli in agent_clis:
        resolved = shutil.which(cli.command)
        rows.append({"name": cli.name, "command": cli.command, "installed": bool(resolved), "path": resolved or ""})
    return rows


def render_markdown_block(common_text: str, common_data: dict[str, Any]) -> str:
    mcp_entries: list[dict[str, str]] = common_data.get("mcp_servers", [])
    skills_entries: list[str] = common_data.get("skills", [])

    lines = [
        MANAGED_BEGIN,
        "## oooconf shared agent policy",
        "",
        common_text.rstrip(),
        "",
        "## Common MCP servers",
        "",
    ]
    lines.extend([f"- `{entry['name']}`: {entry['description']}" for entry in mcp_entries])
    lines.extend(["", "## Common Skills", ""])
    lines.extend([f"- {skill}" for skill in skills_entries])
    lines.extend([MANAGED_END, ""])
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

    for entry in common_data.get("mcp_servers", []):
        if entry["name"].lower() not in lowered:
            missing_mcp.append(entry["name"])

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


def cmd_sync(repo_root: Path, config: dict[str, Any], check_only: bool) -> int:
    common_text = read_text(repo_root, config["common_text_file"])
    common_data = read_json(repo_root, config["common_data_file"])
    managed_block = render_markdown_block(common_text, common_data)
    agent_files = discover_agent_files(repo_root, config["agent_files"])

    if not agent_files:
        print("No AGENTS.md files found from configured locations/discovery.", file=sys.stderr)
        return 1

    changed_count, changed_files = sync_files(agent_files, managed_block, check_only)
    print_section("AGENTS Sync")
    print(f"Mode: {'check' if check_only else 'sync'}")
    print(f"Files scanned: {len(agent_files)}")
    print(f"Files needing updates: {changed_count}")

    if changed_files:
        print("")
        print("Changed files:")
        for file_path in changed_files:
            print(f"{icon('bullet')} {file_path}")
    else:
        print("")
        print("All discovered AGENTS.md files are up to date.")

    return 1 if check_only and changed_count > 0 else 0


def cmd_doctor(repo_root: Path, config: dict[str, Any], strict_paths: bool) -> int:
    common_text = read_text(repo_root, config["common_text_file"])
    common_data = read_json(repo_root, config["common_data_file"])
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
        raise SystemExit(cmd_sync(root, cfg, check_only=args.check))
    if args.command == "doctor":
        raise SystemExit(cmd_doctor(root, cfg, strict_paths=args.strict_config_paths))
    raise SystemExit(1)
