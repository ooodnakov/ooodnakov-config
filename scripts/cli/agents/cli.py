from __future__ import annotations

import argparse
import os
import shlex
import shutil
import subprocess
from pathlib import Path
from typing import Any

from .config import (
    load_config,
    parse_agent_update_specs,
    resolve_config_path,
    resolve_repo_root,
    write_text_atomic,
)
from .doctor import cmd_detect, cmd_doctor
from .mcp import cmd_mcp_add, cmd_mcp_status, cmd_mcp_sync
from .models import (
    AGENTS_EPILOG,
    AgentUpdateSpec,
    print_error_line,
    print_path,
    print_section,
    print_spacer,
    print_status_line,
    resolve_collab,
)
from .skills import cmd_skills_add, cmd_skills_sync, cmd_skills_view
from .sync import cmd_provider_sync, cmd_rtk_init, cmd_sync


def build_parser() -> argparse.ArgumentParser:
    """Build the ``oooconf agents`` CLI argument parser."""
    parser = argparse.ArgumentParser(
        prog="oooconf agents",
        description="Detect AI agent CLIs and manage shared AGENTS.md instructions.",
        epilog=AGENTS_EPILOG,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--repo-root", default=None, help="Repo root containing oooconf agent config.")
    parser.add_argument("--config", default=None, help="Override agent config JSON path.")

    subparsers = parser.add_subparsers(dest="command", required=False)

    detect_parser = subparsers.add_parser("detect", help="Detect known agent CLIs available on PATH.")
    detect_parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON output.")
    detect_parser.add_argument("--dry-run", action="store_true", help="Show what would be detected.")

    sync_parser = subparsers.add_parser(
        "sync", help="Sync the managed AGENTS.md block and MCP entries into global agent configs."
    )
    sync_parser.add_argument("--check", action="store_true", help="Validate only; do not write files.")
    sync_parser.add_argument("--dry-run", action="store_true", help="Show what would change without writing files.")
    sync_parser.add_argument(
        "--materialize-secrets",
        action="store_true",
        help="Write current env values instead of keeping {VAR} placeholders (never commit the result).",
    )
    sync_parser.add_argument(
        "--global",
        dest="global_sync",
        action="store_true",
        default=True,
        help=argparse.SUPPRESS,
    )
    sync_parser.add_argument(
        "--agents",
        nargs="+",
        metavar="AGENT",
        help="Sync only these agents (accepts keys such as claude, codex, omp).",
    )
    sync_parser.add_argument(
        "--select",
        action="store_true",
        help="Pick agents interactively instead of syncing all targets.",
    )

    doctor_parser = subparsers.add_parser(
        "doctor", help="Validate AGENTS.md managed block and check common MCP/skills in agent config paths."
    )
    doctor_parser.add_argument(
        "--strict-config-paths",
        action="store_true",
        help="Fail if no default config path exists for an agent target.",
    )
    doctor_parser.add_argument("--dry-run", action="store_true", help="Show what checks would fail.")

    mcp_parser = subparsers.add_parser("mcp", help="Manage Model Context Protocol (MCP) servers.")
    mcp_subparsers = mcp_parser.add_subparsers(dest="subcommand", required=True)
    mcp_sync_parser = mcp_subparsers.add_parser("sync", help="Synchronize (clone/pull/install) managed MCP servers.")
    mcp_sync_parser.add_argument("--check", action="store_true", help="Print planned actions without executing.")
    mcp_sync_parser.add_argument("--dry-run", action="store_true", help="Show what MCP servers would be synced.")
    mcp_sync_parser.add_argument(
        "--servers",
        "--agents",
        dest="servers",
        metavar="SERVER",
        nargs="+",
        default=None,
        help="Restrict sync to these MCP servers (legacy alias: --agents).",
    )
    mcp_sync_parser.add_argument(
        "--select",
        action="store_true",
        help="Pick managed MCP servers interactively instead of syncing all of them.",
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
    mcp_subparsers.add_parser("status", help="Show status of managed MCP servers.")

    help_parser = subparsers.add_parser("help", help="Show this help message or a subcommand's help.")
    help_parser.add_argument("topics", nargs="*", help="One or more subcommand names, e.g. 'help mcp sync'.")

    rtk_parser = subparsers.add_parser("rtk", help="Manage RTK (Rust Token Killer) integration.")
    rtk_subparsers = rtk_parser.add_subparsers(dest="subcommand", required=True)
    rtk_init_parser = rtk_subparsers.add_parser("init", help="Run 'rtk init --global' for all detected agents.")
    rtk_init_parser.add_argument("--check", action="store_true", help="Print planned actions without executing.")
    rtk_init_parser.add_argument("--dry-run", action="store_true", help="Show what would be initialized.")

    update_parser = subparsers.add_parser(
        "update",
        help="Update installed agent CLIs and rebuild install scripts.",
    )
    update_parser.add_argument(
        "--check",
        action="store_true",
        help="Print planned update commands without executing them.",
    )
    update_parser.add_argument("--dry-run", action="store_true", help="Show what would be updated.")

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
    install_parser.add_argument("--dry-run", action="store_true", help="Show what agents would be installed.")

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
    provider_sync_parser.add_argument("--dry-run", action="store_true", help="Show what would be synced.")
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
        nargs="+",
        default=None,
        help="Restrict sync to these agents (e.g., claude codex opencode).",
    )
    provider_sync_parser.add_argument(
        "--select",
        action="store_true",
        help="Pick supported agents interactively instead of configuring all of them.",
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
    skills_sync_parser.add_argument("--dry-run", action="store_true", help="Show what would be synced.")
    skills_sync_parser.add_argument(
        "--agents",
        metavar="AGENT",
        nargs="+",
        default=None,
        help="Restrict sync to these agents.",
    )
    skills_sync_parser.add_argument(
        "--select",
        action="store_true",
        help="Pick agents interactively instead of syncing every configured skill spec.",
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

    subparsers.add_parser("status", help="Show status of managed MCP servers.")

    return parser


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse CLI arguments."""
    return build_parser().parse_args(argv)


def resolve_update_command(spec: AgentUpdateSpec) -> tuple[list[str], str]:
    """Resolve the package manager install/update command for an agent CLI."""
    preferred = spec.preferred.strip().lower()
    package = spec.package.strip() or spec.command
    if preferred in {"npm", "pnpm"}:
        return ["pnpm", "add", "-g", f"{package}@latest"], "pnpm"
    if preferred == "uv":
        return ["uv", "tool", "install", "--upgrade", package], "uv"
    if preferred == "pipx":
        return ["pipx", "upgrade", package], "pipx"
    raise RuntimeError(f"unsupported preferred update manager: {spec.preferred!r}")


def _script_lines(script: str | None) -> list[str]:
    if not script:
        return []
    normalized = script.replace("&&", "\n").replace("\r\n", "\n")
    return [line.strip() for line in normalized.split("\n") if line.strip()]


def _post_install_script(spec: AgentUpdateSpec) -> tuple[str | None, bool]:
    """Return the post-install script and whether it must run through PowerShell."""
    if os.name == "nt" and spec.install_script_ps:
        return spec.install_script_ps, True
    return spec.install_script, False


def run_post_install(spec: AgentUpdateSpec) -> bool:
    """Run an agent's configured post-install script."""
    script, use_powershell = _post_install_script(spec)
    if not script:
        return True

    shutil_mod = resolve_collab("shutil", shutil)
    subprocess_mod = resolve_collab("subprocess", subprocess)

    if use_powershell:
        shell = shutil_mod.which("pwsh") or shutil_mod.which("powershell")
        if shell is None:
            print_status_line("fail", "No PowerShell executable found for the post-install step.")
            return False
        print_status_line("info", "Running post-install step via PowerShell")
        try:
            subprocess_mod.run([shell, "-NoProfile", "-NonInteractive", "-Command", script], check=True)
        except subprocess.CalledProcessError as exc:
            print_status_line("fail", f"Post-install step failed: {exc}")
            return False
        print_status_line("ok", "Post-install step succeeded")
        return True

    for line in _script_lines(script):
        print_status_line("info", f"Running post-install step: {line}")
        try:
            cmd_parts = shlex.split(line)
        except ValueError as exc:
            print_status_line("fail", f"Post-install step failed to parse: {exc}")
            return False
        if not cmd_parts:
            continue
        try:
            subprocess_mod.run(cmd_parts, check=True)
        except subprocess.CalledProcessError as exc:
            print_status_line("fail", f"Post-install step failed: {exc}")
            return False
        print_status_line("ok", "Post-install step succeeded")
    return True


def resolve_exec_command(spec: AgentUpdateSpec, command: list[str]) -> list[str] | None:
    """Resolve the installer executable, falling back from pnpm to npm."""
    shutil_mod = resolve_collab("shutil", shutil)
    resolved = shutil_mod.which(command[0])
    if resolved:
        return [resolved, *command[1:]]
    if command[0] == "pnpm":
        npm = shutil_mod.which("npm")
        if npm:
            return [npm, "install", "-g", f"{spec.package}@latest"]
    return None


def cmd_install_scripts_build(repo_root: Path, config: dict[str, Any]) -> int:
    """Generate standalone ``install-<cmd>.sh`` and ``install-<cmd>.ps1`` scripts."""
    specs = parse_agent_update_specs(config.get("agent_updates", []))
    if not specs:
        print_error_line("fail", "No agent_updates configured.")
        return 1

    install_dir = repo_root / "home" / ".config" / "ooodnakov" / "agents" / "install"
    install_dir.mkdir(parents=True, exist_ok=True)

    print_section("Building Agent Install Scripts")
    print_status_line("hint", f"Target: {print_path(install_dir)}")

    for spec in specs:
        if (
            not spec.command
            or not spec.command.strip()
            or "/" in spec.command
            or "\\" in spec.command
            or ".." in spec.command
            or "\x00" in spec.command
        ):
            raise ValueError(f"invalid agent command name: {spec.command!r}")

    count = 0
    for spec in specs:
        cmd_list, runner = resolve_update_command(spec)
        cmd_str = shlex.join(cmd_list)
        message = f"Installing {spec.name} via {runner}..."

        sh_lines = [
            "#!/usr/bin/env sh",
            "set -eu",
            "# Generated by oooconf agents install-scripts-build",
            f"printf '%s\\n' {shlex.quote(message)}",
            cmd_str,
            *_script_lines(spec.install_script),
        ]
        sh_path = install_dir / f"install-{spec.command}.sh"
        write_text_atomic(sh_path, "\n".join(sh_lines) + "\n", mode=0o755)

        ps1_script = spec.install_script_ps or spec.install_script
        ps_msg = message
        for quote in ("'", "\u2018", "\u2019", "\u201a", "\u201b"):
            ps_msg = ps_msg.replace(quote, quote * 2)
        ps1_lines = [
            "# Generated by oooconf agents install-scripts-build",
            "$ErrorActionPreference = 'Stop'",
            f"Write-Host '{ps_msg}'",
            cmd_str,
            *_script_lines(ps1_script),
        ]
        ps1_path = install_dir / f"install-{spec.command}.ps1"
        write_text_atomic(ps1_path, "\n".join(ps1_lines) + "\n")

        print_status_line("ok", f"{spec.name} ({spec.command})")
        count += 1

    print_spacer()
    print_status_line("info", f"Summary: built install scripts for {count} agents.")
    return 0


def agent_matches_query(spec: AgentUpdateSpec, query: str) -> bool:
    """Return True if a CLI query matches an ``AgentUpdateSpec``."""
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
    """Select ``AgentUpdateSpec`` items based on queries, ``--all``, or ``--missing``."""
    if install_all and queries:
        return [], ["--all cannot be combined with explicit agent names."]
    if install_all and missing_only:
        return [], ["--all and --missing are mutually exclusive."]

    if install_all:
        return specs, []

    shutil_mod = resolve_collab("shutil", shutil)

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
            deduped = [spec for spec in deduped if not shutil_mod.which(spec.command)]
        return deduped, errors

    return [spec for spec in specs if not shutil_mod.which(spec.command)], []


def run_install_spec(spec: AgentUpdateSpec, check_only: bool) -> tuple[bool, bool]:
    """Install a single agent CLI spec, returning ``(ok, installed)``."""
    try:
        command, runner = resolve_update_command(spec)
    except RuntimeError as exc:
        print_status_line("fail", f"{spec.name}: {exc}")
        return False, False

    command_display = shlex.join(command)
    if check_only:
        print_status_line("ok", f"Plan: install {spec.name} via {runner}")
        print_status_line("hint", f"  command: {command_display}")
        if spec.install_script or spec.install_script_ps:
            print_status_line("hint", f"  post-install: {spec.install_script_ps or spec.install_script}")
        return True, False

    command_exec = resolve_exec_command(spec, command)
    if command_exec is None:
        print_status_line("fail", f"{spec.name}: required installer '{command[0]}' is not installed.")
        return False, False

    subprocess_mod = resolve_collab("subprocess", subprocess)
    print_status_line("info", f"Installing {spec.name} via {runner}")
    print_status_line("hint", f"  command: {command_display}")
    try:
        subprocess_mod.run(command_exec, check=True)
        print_status_line("ok", f"Successfully installed {spec.name}")
    except subprocess.CalledProcessError as exc:
        print_status_line("fail", f"Failed to install {spec.name}: {exc}")
        return False, False

    if not resolve_collab("run_post_install", run_post_install)(spec):
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
    dry_run: bool = False,
) -> int:
    """Install configured agent CLIs."""
    del repo_root
    specs = parse_agent_update_specs(config.get("agent_updates", []))
    if not specs:
        print_error_line("fail", "No agent_updates configured.")
        return 1

    selected, errors = select_install_specs(specs, agent_queries, install_all=install_all, missing_only=missing_only)
    for error in errors:
        print_status_line("fail", error)
    if errors:
        return 1

    print_section("Agent CLI Installation (dry-run)" if dry_run else "Agent CLI Installation")
    if install_all:
        scope = "all configured agents"
    elif agent_queries:
        scope = ", ".join(agent_queries)
        if missing_only:
            scope = f"missing selected agents ({scope})"
    else:
        scope = "missing configured agents"
    print_status_line("hint", f"Mode: {'dry-run' if dry_run else 'check' if check_only else 'install'}")
    print_status_line("hint", f"Scope: {scope}")

    if not selected:
        print_status_line("ok", "No matching agents require installation.")
        return 0

    install_fn = resolve_collab("run_install_spec", run_install_spec)
    attempted = 0
    planned_or_installed = 0
    failed = 0
    for spec in selected:
        attempted += 1
        ok, _installed = install_fn(spec, check_only or dry_run)
        if ok:
            planned_or_installed += 1
        else:
            failed += 1

    print_spacer()
    action = "planned" if check_only or dry_run else "installed"
    print_status_line("info", f"Summary: {action} {planned_or_installed}/{attempted} agents; failed {failed}.")
    return 1 if failed else 0


def get_command_version(command: str) -> str | None:
    """Return ``<command> --version`` output or ``None`` if unavailable."""
    subprocess_mod = resolve_collab("subprocess", subprocess)
    try:
        result = subprocess_mod.run(
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
    """Return the global binary directory for ``runner`` when supported."""
    subprocess_mod = resolve_collab("subprocess", subprocess)
    if runner == "pnpm":
        try:
            result = subprocess_mod.run(
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


def cmd_update(repo_root: Path, config: dict[str, Any], check_only: bool, dry_run: bool = False) -> int:
    """Update installed agent CLIs and rebuild standalone install scripts."""
    if not check_only and not dry_run:
        resolve_collab("cmd_install_scripts_build", cmd_install_scripts_build)(repo_root, config)

    specs = parse_agent_update_specs(config.get("agent_updates", []))
    if not specs:
        print_error_line("fail", "No agent_updates configured.")
        return 1

    print_section("Agent CLI Updates (dry-run)" if dry_run else "Agent CLI Updates")
    print_status_line("hint", f"Mode: {'dry-run' if dry_run else 'check' if check_only else 'update'}")

    shutil_mod = resolve_collab("shutil", shutil)
    subprocess_mod = resolve_collab("subprocess", subprocess)
    version_fn = resolve_collab("get_command_version", get_command_version)
    bin_dir_fn = resolve_collab("get_runner_bin_dir", get_runner_bin_dir)
    post_install_fn = resolve_collab("run_post_install", run_post_install)

    attempted = 0
    failed = 0
    skipped = 0
    updated = 0
    for spec in specs:
        installed_path = shutil_mod.which(spec.command)
        if not installed_path:
            print_status_line("missing", f"{spec.name} ({spec.command}) not found on PATH; skipping.")
            skipped += 1
            continue

        version_before = version_fn(spec.command)

        try:
            command, runner = resolve_update_command(spec)
        except RuntimeError as exc:
            print_status_line("fail", f"{spec.name}: {exc}")
            failed += 1
            continue
        attempted += 1
        command_display = shlex.join(command)
        if check_only or dry_run:
            print_status_line("ok", f"Plan: update {spec.name} via {runner}")
            if version_before:
                print_status_line("hint", f"  current version: {version_before}")
            print_status_line("hint", f"  command: {command_display}")
            if spec.install_script or spec.install_script_ps:
                print_status_line("hint", f"  post-install: {spec.install_script_ps or spec.install_script}")
            continue
        command_exec = resolve_exec_command(spec, command)
        if command_exec is None:
            print_status_line("fail", f"{spec.name}: required updater '{command[0]}' is not installed.")
            failed += 1
            continue
        print_status_line("info", f"Updating {spec.name} via {runner}")
        print_status_line("hint", f"  command: {command_display}")

        output_lines: list[str] = []
        process = subprocess_mod.Popen(
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
            if not post_install_fn(spec):
                failed += 1
                continue
            version_after = version_fn(spec.command)
            runner_bin_dir = bin_dir_fn(runner)

            is_shadowed = False
            if installed_path and runner_bin_dir:
                p_installed = Path(installed_path).resolve()
                p_runner_bin = Path(runner_bin_dir).resolve()
                if p_runner_bin not in p_installed.parents:
                    is_shadowed = True

            if version_before and version_after and version_before == version_after:
                output_str = "\n".join(output_lines)
                if "Already up to date" not in output_str and "is up to date" not in output_str:
                    print_status_line("warn", f"{spec.name} version did not change ({version_after}).")
                    if is_shadowed:
                        print_status_line(
                            "hint",
                            f"  Note: active binary '{installed_path}' is SHADOWING the {runner} version.",
                        )
                        print_status_line("hint", f"  Expected in: {print_path(runner_bin_dir)}")
                else:
                    if is_shadowed:
                        print_status_line("warn", f"{spec.name} is up to date in {runner}, but SHADOWED on PATH.")
                        print_status_line("hint", f"  Active: {print_path(installed_path)}")
                        print_status_line("hint", f"  Try: pnpm remove -g {spec.package} (if installed via pnpm)")
                    else:
                        print_status_line("ok", f"{spec.name} is already up to date ({version_after})")
            else:
                if is_shadowed:
                    print_status_line("warn", f"{spec.name} updated, but still SHADOWED on PATH.")
                    print_status_line("hint", f"  Active version: {version_after}")
                    print_status_line("hint", f"  Active path: {print_path(installed_path)}")
                else:
                    print_status_line(
                        "ok", f"{spec.name} updated: {version_before or 'unknown'} -> {version_after or 'unknown'}"
                    )
            updated += 1
        else:
            print_status_line("fail", f"{spec.name} update failed via {runner}")
            if output_lines:
                print_status_line("hint", "  (combined stdout/stderr shown above)")
            failed += 1
    print_spacer()
    print_status_line(
        "info", f"Summary: updated {updated}/{attempted} attempted; skipped {skipped} missing; failed {failed}."
    )
    return 1 if failed else 0


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint for ``oooconf agents``."""
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command is None:
        parser.print_help()
        return 0

    if args.command == "help":
        topics = getattr(args, "topics", [])
        parser.parse_args([*topics, "--help"] if topics else ["--help"])
        return 0

    root = resolve_repo_root(args.repo_root)
    config_path = resolve_config_path(root, args.config)
    try:
        cfg = load_config(config_path)
    except Exception as exc:
        print_error_line("fail", f"{exc}")
        return 1

    if args.command == "detect":
        return cmd_detect(cfg, json_output=args.json, dry_run=args.dry_run)
    if args.command == "sync":
        return cmd_sync(
            root,
            cfg,
            check_only=args.check,
            materialize_secrets=args.materialize_secrets,
            agents=args.agents,
            select=args.select,
            dry_run=args.dry_run,
        )
    if args.command == "doctor":
        return cmd_doctor(root, cfg, strict_paths=args.strict_config_paths, dry_run=args.dry_run)
    if args.command == "mcp":
        if args.subcommand == "sync":
            return cmd_mcp_sync(
                root,
                cfg,
                check_only=args.check,
                servers=args.servers,
                select=args.select,
                dry_run=args.dry_run,
            )
        if args.subcommand == "add":
            return cmd_mcp_add(
                root,
                cfg,
                name=args.name,
                json_payload=args.json_payload,
                check_only=args.check,
                sync_now=args.sync_now,
                allow_multi=args.multi,
                preview=args.preview,
            )
        if args.subcommand == "status":
            return cmd_mcp_status(root, cfg)
    if args.command == "rtk" and args.subcommand == "init":
        return cmd_rtk_init(root, cfg, check_only=args.check, dry_run=args.dry_run)
    if args.command == "provider" and args.subcommand == "sync":
        return cmd_provider_sync(
            cfg,
            provider=args.provider,
            check_only=args.check,
            materialize_secrets=args.materialize_secrets,
            region=args.region,
            agents=args.agents,
            select=args.select,
            dry_run=args.dry_run,
        )
    if args.command == "update":
        return cmd_update(root, cfg, check_only=args.check, dry_run=args.dry_run)
    if args.command == "install":
        return cmd_install(
            root,
            cfg,
            args.agents,
            check_only=args.check,
            install_all=args.all,
            missing_only=args.missing,
            dry_run=args.dry_run,
        )
    if args.command == "install-scripts-build":
        return cmd_install_scripts_build(root, cfg)
    if args.command == "skills":
        if args.subcommand == "sync":
            return cmd_skills_sync(
                root,
                cfg,
                check_only=args.check,
                agents=args.agents,
                select=args.select,
                dry_run=args.dry_run,
            )
        if args.subcommand == "view":
            return cmd_skills_view(json_output=args.json, check_only=args.check)
        if args.subcommand == "add":
            return cmd_skills_add(
                root,
                cfg,
                source=args.source,
                agent=args.agent,
                check_only=args.check,
                sync_now=args.sync_now,
            )
    if args.command == "status":
        return cmd_mcp_status(root, cfg)
    return 1
