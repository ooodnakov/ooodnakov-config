from __future__ import annotations

import os
import shlex
import shutil
import subprocess
from pathlib import Path
from typing import Any

from .config import (
    load_common_data,
    parse_agent_clis,
    prompt_yes_no,
    read_json,
    write_common_data,
)
from .models import (
    interactive_select,
    is_interactive,
    print_error_line,
    print_section,
    print_spacer,
    print_status_line,
    resolve_collab,
)

# Agent skills directories for repo-local skills (`installer = "local"`).
LOCAL_SKILL_DIRS: dict[str, tuple[str, str]] = {
    "omp": ("omp", "~/.omp/agent/skills"),
    "claude": ("claude", "~/.claude/skills"),
    "codex": ("codex", "~/.codex/skills"),
    "antigravity": ("agy", "~/.gemini/config/skills"),
}


def windows_launcher(name: str, which: Any = None) -> str:
    """Return ``name`` resolved to a path Windows can actually launch.

    ``shutil.which`` returns the extensionless POSIX shim first on Windows
    (pnpm ships one) and ``CreateProcess`` cannot run it, so prefer a PATHEXT
    variant. Returns ``name`` unchanged when no such variant exists or on
    non-Windows platforms.
    """
    if os.name != "nt":
        return name
    finder = which or shutil.which
    extensions = [ext.strip() for ext in os.environ.get("PATHEXT", ".COM;.EXE;.BAT;.CMD").split(";") if ext.strip()]
    lowered = {ext.lower() for ext in extensions}
    found = finder(name)
    if found and Path(found).suffix.lower() in lowered:
        return found
    for ext in extensions:
        candidate = finder(name + ext)
        if candidate:
            return candidate
    return name


def canonicalize_skill_source(source: str) -> str:
    """Normalize a skill repository specifier to a canonical URL."""
    src = source.strip()
    if src.startswith("https://github.com/"):
        src = src.rstrip("/")
        if src.endswith(".git"):
            src = src[:-4]
        return src
    if "://" in src:
        return src.rstrip("/")
    return f"https://github.com/{src.rstrip('/')}"


def local_skill_links(
    repo_root: Path, spec: dict[str, Any], wanted: set[str] | None = None
) -> list[tuple[str, Path, Path]]:
    """Return ``(agent, source dir, target link)`` for a local skill spec, for installed agents."""
    skill_dirs = resolve_collab("LOCAL_SKILL_DIRS", LOCAL_SKILL_DIRS)
    shutil_mod = resolve_collab("shutil", shutil)
    source = repo_root / str(spec.get("source", ""))
    name = str(spec.get("name", ""))
    agents = [str(agent).lower() for agent in spec.get("agents") or list(skill_dirs)]
    links: list[tuple[str, Path, Path]] = []
    for agent in agents:
        if wanted and agent not in wanted:
            continue
        entry = skill_dirs.get(agent)
        if not entry or not shutil_mod.which(entry[0]):
            continue
        links.append((agent, source, Path(entry[1]).expanduser() / name))
    return links


def sync_local_skills(
    repo_root: Path,
    specs: list[dict[str, Any]],
    check_only: bool,
    dry_run: bool,
    wanted: set[str] | None = None,
) -> tuple[int, int, int]:
    """Link repo-local skill folders into each agent's skills directory."""
    attempted = skipped = failed = 0
    for spec in specs:
        name = str(spec.get("name", "unknown"))
        source = repo_root / str(spec.get("source", ""))
        if not source.is_dir():
            print_status_line("fail", f"Local skill source missing: {source}")
            failed += 1
            continue
        links = local_skill_links(repo_root, spec, wanted)
        if not links:
            print_status_line("missing", f"{name}: no configured agent CLI found; skipping.")
            skipped += 1
            continue
        for agent, src, target in links:
            attempted += 1
            if target.is_symlink():
                if target.resolve() == src.resolve():
                    print_status_line("ok", f"{name}: {agent} up to date ({target})")
                else:
                    print_status_line("warn", f"{name}: {target} points elsewhere; leaving it")
                    skipped += 1
                continue
            if target.exists():
                print_status_line("warn", f"{name}: {target} exists and is not a managed link; leaving it")
                skipped += 1
                continue
            if check_only or dry_run:
                print_status_line("ok", f"Plan: link {name} into {agent} ({target})")
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            try:
                target.symlink_to(src, target_is_directory=True)
            except OSError as error:
                print_status_line("fail", f"{name}: cannot link {target}: {error}")
                failed += 1
                continue
            print_status_line("ok", f"{name}: linked into {agent} ({target})")
    return attempted, skipped, failed


def skills_cli_agent_targets(config: dict[str, Any]) -> list[str]:
    """Return ``skills`` CLI ``-a`` target names for installed agent CLIs."""
    mapping = {
        "claude": "claude-code",
        "codex": "codex",
        "agy": "antigravity",
        "pi": "pi",
        "opencode": "opencode",
        "cursor-agent": "cursor",
        "command-code": "command-code",
        "qwen": "qwen-code",
    }
    shutil_mod = resolve_collab("shutil", shutil)
    targets: list[str] = []
    for cli in parse_agent_clis(config["agent_clis"]):
        mapped = mapping.get(cli.command)
        if mapped and mapped not in targets and shutil_mod.which(cli.command):
            targets.append(mapped)
    return targets


def build_skills_cli_command(spec: dict[str, Any], config: dict[str, Any]) -> list[str]:
    """Build the ``pnpm dlx skills add`` command for a skill spec."""
    command = [
        "pnpm",
        "dlx",
        "skills",
        "add",
        str(spec["source"]),
        "--skill",
        str(spec["name"]),
        "-g",
        "-y",
    ]
    for target in skills_cli_agent_targets(config):
        command.extend(["-a", target])
    return command


def cmd_skills_sync(
    repo_root: Path,
    config: dict[str, Any],
    check_only: bool,
    agents: list[str] | None = None,
    dry_run: bool = False,
    select: bool = False,
) -> int:
    """Synchronize configured ``skill_specs`` across agent ecosystems."""
    common_data = resolve_collab("load_common_data", load_common_data)(repo_root, config, include_local=True)
    skill_specs = common_data.get("skill_specs", [])
    if not skill_specs:
        print_error_line("fail", "No skill_specs configured.")
        return 0

    local_specs = [s for s in skill_specs if str(s.get("installer", "")).lower() == "local"]
    cli_specs = [s for s in skill_specs if str(s.get("installer", "")).lower() == "skills"]
    unknown_specs = [s for s in skill_specs if s not in cli_specs and s not in local_specs]

    skill_dirs = resolve_collab("LOCAL_SKILL_DIRS", LOCAL_SKILL_DIRS)
    spec_agents = sorted({str(agent).lower() for spec in local_specs for agent in (spec.get("agents") or skill_dirs)})
    if select and agents is not None:
        print_status_line("fail", "--select cannot be combined with --agents.")
        return 1
    if select:
        if not resolve_collab("is_interactive", is_interactive)():
            print_status_line("fail", "--select requires an interactive terminal.")
            return 1
        agents = resolve_collab("interactive_select", interactive_select)(
            spec_agents, title="Select agents to sync skills for"
        )
        if agents is None:
            print_status_line("info", "Cancelled.")
            return 1
        if not agents:
            print_status_line("info", "No agents selected.")
            return 0

    wanted: set[str] = set()
    if agents:
        wanted = {agent.lower() for agent in agents}
        unmatched = sorted(wanted - set(spec_agents))
        for agent in unmatched:
            print_status_line("warn", f"No skill specs configured for agent '{agent}'.")
        if not cli_specs and not local_specs:
            print_status_line("warn", f"No skill specs match agents: {', '.join(agents)}")
            return 1

    print_section("Agent Skills Sync (dry-run)" if dry_run else "Agent Skills Sync")
    print_status_line("hint", f"Mode: {'dry-run' if dry_run else 'check' if check_only else 'sync'}")
    if agents:
        print_status_line("hint", f"Agents: {', '.join(agents)}")

    shutil_mod = resolve_collab("shutil", shutil)
    subprocess_mod = resolve_collab("subprocess", subprocess)

    attempted = 0
    failed = 0
    skipped = 0
    synced = 0

    for spec in unknown_specs:
        attempted += 1
        failed += 1
        print_status_line(
            "fail",
            f"Unsupported skill spec '{spec.get('name', 'unknown')}': set installer to 'skills' or 'local'.",
        )

    for spec in cli_specs:
        name = str(spec.get("name", "unknown"))
        source = str(spec.get("source", "")).strip()
        if not source:
            print_status_line("fail", f"Invalid skill spec: {name} (missing source)")
            failed += 1
            continue

        attempted += 1
        if not shutil_mod.which("pnpm"):
            print_status_line("missing", f"pnpm not found; skipping skill {name}.")
            skipped += 1
            continue

        command = build_skills_cli_command(spec, config)
        command_display = shlex.join(command)
        if check_only or dry_run:
            print_status_line("ok", f"Plan: {name} via skills CLI")
            print_status_line("hint", f"  command: {command_display}")
            continue

        print_status_line("ok", f"Syncing {name} via skills CLI...")
        print_status_line("hint", f"  command: {command_display}")
        command[0] = windows_launcher(command[0], shutil_mod.which)
        try:
            subprocess_mod.run(command, check=True)
            print_status_line("ok", f"Successfully synced {name}")
            synced += 1
        except subprocess.CalledProcessError as exc:
            print_status_line("fail", f"Failed to sync {name}: {exc}")
            failed += 1
        except OSError as exc:
            print_status_line(
                "missing",
                f"Cannot execute '{command[0]}' ({exc}); skipping skill {name}.",
            )
            skipped += 1

    if local_specs:
        sync_local_fn = resolve_collab("sync_local_skills", sync_local_skills)
        local_attempted, local_skipped, local_failed = sync_local_fn(
            repo_root, local_specs, check_only, dry_run, wanted if agents else None
        )
        attempted += local_attempted
        skipped += local_skipped
        failed += local_failed
        synced += local_attempted

    print_spacer()
    print_status_line("info", f"Summary: synced {synced}/{attempted} attempted; skipped {skipped}; failed {failed}.")
    return 1 if failed else 0


def cmd_skills_view(json_output: bool, check_only: bool) -> int:
    """List globally installed skills via ``pnpm dlx skills ls -g``."""
    command = ["pnpm", "dlx", "skills", "ls", "-g"]
    if json_output:
        command.append("--json")
    command_display = shlex.join(command)
    print_section("Agent Skills View")
    if check_only:
        print_status_line("ok", "Plan: list global shared skills catalog")
        print_status_line("hint", f"  command: {command_display}")
        return 0

    shutil_mod = resolve_collab("shutil", shutil)
    subprocess_mod = resolve_collab("subprocess", subprocess)

    if not shutil_mod.which("pnpm"):
        print_status_line("missing", "pnpm not found; cannot run skills catalog view.")
        print_status_line("hint", "  install pnpm first, then rerun: oooconf agents skills view")
        return 1

    print_status_line("info", "Listing global shared skills catalog via pnpm dlx")
    print_status_line("hint", f"  command: {command_display}")
    command[0] = windows_launcher(command[0], shutil_mod.which)
    result = subprocess_mod.run(command)
    if result.returncode != 0:
        print_status_line("fail", "skills list command failed.")
        print_status_line("hint", "  ensure the `skills` package is reachable from pnpm dlx in your environment.")
        return result.returncode
    return 0


def cmd_skills_add(repo_root: Path, config: dict[str, Any], source: str, check_only: bool, sync_now: bool) -> int:
    """Add a shared skill source entry to ``common-data.json``."""
    data = read_json(repo_root, config["common_data_file"])
    skill_specs = data.setdefault("skill_specs", [])
    source_url = canonicalize_skill_source(source)
    name = source.rstrip("/").split("/")[-1]
    spec = {
        "installer": "skills",
        "name": name,
        "source": source_url,
        "description": f"Added via oooconf agents skills add ({source})",
    }
    exists = any(
        str(s.get("installer", "")).lower() == "skills"
        and canonicalize_skill_source(str(s.get("source", ""))) == source_url
        for s in skill_specs
    )
    if not exists:
        skill_specs.append(spec)
    skills = data.setdefault("skills", [])
    if name not in skills:
        skills.append(name)
    if check_only:
        print_status_line("ok", f"Plan: add skill spec '{source_url}'")
        return 0
    write_common_data(repo_root, config, data)
    print_status_line("ok", f"Added skill spec '{source_url}'")
    prompt_fn = resolve_collab("prompt_yes_no", prompt_yes_no)
    should_sync = sync_now or prompt_fn("Sync skills to local agents now?")
    if should_sync:
        return resolve_collab("cmd_skills_sync", cmd_skills_sync)(repo_root, config, check_only=False)
    return 0
