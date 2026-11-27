from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from .config import (
    detect_clis,
    existing_default_path,
    load_common_data,
    parse_agent_clis,
    parse_agent_targets,
)
from .models import (
    AGENT_EXTRA_HEADING,
    AgentConfigTarget,
    DoctorConfigResult,
    print_path,
    print_section,
    print_spacer,
    print_status_line,
    resolve_collab,
)

tomllib: Any
try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    tomllib = None

try:
    import yaml as _yaml
except ModuleNotFoundError:  # pragma: no cover
    _yaml = None


def extract_search_space(path: Path, fmt: str) -> str:
    """Read and normalize an agent config file into a searchable text representation."""
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
        if _yaml is not None:
            obj = _yaml.safe_load(raw)
            if isinstance(obj, dict):
                return json.dumps(obj, sort_keys=True)
        return raw
    return raw


def check_common_entries(content: str, common_data: dict[str, Any], fmt: str) -> tuple[list[str], list[str]]:
    """Return ``(missing_mcp, missing_skills)`` for a config file's content."""
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
    """Validate structural requirements for an agent config target."""
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
    if target.format == "markdown" and target.extra_text_file and AGENT_EXTRA_HEADING not in content:
        issues.append("missing agent-specific instructions section")
    if target.format == "markdown" and target.frontmatter:
        fm_match = re.match(r"^---\r?\n(.*?)\r?\n---(?:\r?\n|\Z)", content, flags=re.DOTALL)
        if not fm_match or not re.search(r"^\s*trigger\s*:\s*\S+", fm_match.group(1), flags=re.MULTILINE):
            issues.append("missing YAML frontmatter with trigger")
    return issues


def inspect_agent_configs(
    targets: list[AgentConfigTarget], common_data: dict[str, Any]
) -> tuple[list[DoctorConfigResult], bool]:
    """Inspect all configured agent targets and report missing entries or shape issues."""
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

        if target.extra_only:
            missing_mcp: list[str] = []
            missing_skills: list[str] = []
        else:
            missing_mcp, missing_skills = check_common_entries(search_space, common_data, target.format)

        # If mcp_skip is True, MCP is CLI-managed — skip MCP checks
        mcp_file_path: Path | None = None
        if target.mcp_skip:
            missing_mcp = []
        elif target.mcp_paths and not target.mcp_skip:
            for mp in target.mcp_paths:
                candidate = Path(mp).expanduser()
                if candidate.exists():
                    mcp_file_path = candidate
                    break
            if mcp_file_path:
                mcp_content = mcp_file_path.read_text(encoding="utf-8")
                mcp_only_missing, _ = check_common_entries(
                    mcp_content, {"mcp_servers": common_data.get("mcp_servers", {}), "skills": []}, "json"
                )
                missing_mcp = mcp_only_missing
            else:
                missing_mcp = list(common_data.get("mcp_servers", {}).keys())

        parsed_obj: dict[str, Any] | None = None
        if target.format == "json":
            try:
                parsed = json.loads(existing.read_text(encoding="utf-8"))
                if isinstance(parsed, dict):
                    parsed_obj = parsed
            except Exception:
                parsed_obj = None
        elif target.format in {"yaml", "yml"} and _yaml is not None:
            try:
                parsed = _yaml.safe_load(existing.read_text(encoding="utf-8"))
                if isinstance(parsed, dict):
                    parsed_obj = parsed
            except Exception:
                parsed_obj = None
        shape_issues = check_config_shape(target, search_space, parsed_obj)
        if missing_mcp or missing_skills or shape_issues:
            has_failures = True

        results.append(
            DoctorConfigResult(
                target=target,
                existing_path=existing,
                missing_mcp=missing_mcp,
                missing_skills=missing_skills,
                shape_issues=shape_issues,
                mcp_file_path=mcp_file_path,
            )
        )

    return results, has_failures


def cmd_detect(config: dict[str, Any], json_output: bool, dry_run: bool = False) -> int:
    """Detect configured agent CLIs available on PATH."""
    rows = resolve_collab("detect_clis", detect_clis)(parse_agent_clis(config["agent_clis"]))
    installed = sum(1 for row in rows if row["installed"])

    if dry_run:
        print_section("Agent CLI Detection (dry-run)")
        for row in rows:
            status = "ok" if row["installed"] else "missing"
            location = row["path"] or "-"
            print_status_line(status, f"{row['name']} ({row['command']})")
            print_status_line("hint", f"  path: {print_path(location)}")
        print_spacer()
        print_status_line("info", f"Summary: would detect {installed}/{len(rows)} configured agent CLIs.")
        return 0

    if json_output:
        print(json.dumps({"detected": rows}, indent=2))
    else:
        print_section("Agent CLI Detection")
        for row in rows:
            status = "ok" if row["installed"] else "missing"
            location = row["path"] or "-"
            print_status_line(status, f"{row['name']} ({row['command']})")
            print_status_line("hint", f"  path: {print_path(location)}")
        print_spacer()
        print_status_line("info", f"Summary: detected {installed}/{len(rows)} configured agent CLIs.")
    return 0


def cmd_doctor(repo_root: Path, config: dict[str, Any], strict_paths: bool, dry_run: bool = False) -> int:
    """Validate global agent configs and CLI availability."""
    merged_data = resolve_collab("load_common_data", load_common_data)(repo_root, config, include_local=True)

    config_targets = parse_agent_targets(config["agent_configs"])
    config_results, config_failures = inspect_agent_configs(config_targets, merged_data)
    rows = resolve_collab("detect_clis", detect_clis)(parse_agent_clis(config["agent_clis"]))

    failed = False

    print_section("AGENTS Doctor (dry-run)" if dry_run else "AGENTS Doctor")

    if dry_run:
        print_status_line("info", "Agent Configs that would FAIL:")
        dry_failures = 0
        for result in config_results:
            target = result.target
            if result.existing_path is None:
                print_status_line("warn", f"{target.name}: config path not found")
                if strict_paths:
                    dry_failures += 1
                continue
            if result.parse_error:
                print_status_line("fail", f"{target.name}: parse error")
                dry_failures += 1
                continue
            if result.missing_mcp or result.missing_skills or result.shape_issues:
                print_status_line("fail", f"{target.name}: missing or malformed entries")
                dry_failures += 1
                continue
        missing_clis = [row for row in rows if not row["installed"]]
        for row in missing_clis:
            print_status_line("missing", f"{row['name']} ({row['command']})")
            dry_failures += 1
        print_spacer()
        print_status_line("info", f"Summary: {dry_failures} checks would fail.")
        return 0

    print_section("Agent Configs")
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
            print_status_line("fail", f"{target.name}: failed parsing {print_path(result.existing_path)}")
            print_status_line("hint", f"  error: {result.parse_error}")
            continue

        if result.missing_mcp or result.missing_skills:
            print_status_line("fail", f"{target.name}: missing required markers in {print_path(result.existing_path)}")
            if result.missing_mcp:
                print_status_line("hint", f"  missing MCPs: {', '.join(result.missing_mcp)}")
            if result.missing_skills:
                print_status_line("hint", f"  missing skills: {', '.join(result.missing_skills)}")
            continue
        if result.shape_issues:
            print_status_line("fail", f"{target.name}: config shape mismatch in {print_path(result.existing_path)}")
            print_status_line("hint", f"  issues: {', '.join(result.shape_issues)}")
            continue

        print_status_line(
            "ok", f"{target.name}: required MCP/skills markers found in {print_path(result.existing_path)}"
        )

    print_spacer()
    print_section("Agent CLIs")
    missing_clis = [row for row in rows if not row["installed"]]
    installed_clis = [row for row in rows if row["installed"]]
    for row in installed_clis:
        print_status_line("ok", f"{row['name']} ({row['command']})")
    for row in missing_clis:
        print_status_line("missing", f"{row['name']} ({row['command']})")

    print_spacer()
    strict_note = "strict config paths enabled" if strict_paths else "missing config paths are warnings"
    print_status_line("info", f"Summary: {len(installed_clis)}/{len(rows)} CLIs installed, {strict_note}.")

    failed = failed or config_failures
    return 1 if failed else 0
