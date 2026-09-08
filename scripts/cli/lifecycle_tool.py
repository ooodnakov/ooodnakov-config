#!/usr/bin/env python3
"""Structured diagnostics and portable snapshot support for oooconf."""

from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import tomllib
from dataclasses import asdict, dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from scripts.cli.env_tool import write_override  # noqa: E402
from scripts.cli.operation_plan import build_plan, selected_links  # noqa: E402
from scripts.cli.profile_manager import ProfileError, resolve_profile  # noqa: E402
from scripts.cli.read_optional_deps import normalized_deps  # noqa: E402
from scripts.cli.transaction_apply import INCOMPLETE_STATUSES, _load_journals, apply  # noqa: E402
from scripts.link_manager import get_platform  # noqa: E402

DIAGNOSTIC_SCHEMA_VERSION = 1
SNAPSHOT_VERSION = 1
GENERATED_FILES = (
    "home/.config/ooodnakov/completions/oooconf-completions.ps1",
    "home/.config/ooodnakov/zsh/completions/_oooconf",
    "scripts/cli/oooconf-commands.txt",
)
PREFERENCES = {
    "theme": ("OOOCONF_THEME", {"default", "catppuccin", "gruvbox", "nord", "tokyonight", "noctalia"}),
    "color_mode": ("OOOCONF_COLOR_MODE", {"dark", "light"}),
    "prompt": ("OOOCONF_ZSH_PROMPT", {"p10k", "ohmyposh"}),
    "prompt_style": ("OOOCONF_PROMPT_STYLE", {"verbose", "concise"}),
    "forgit_aliases": ("OOODNAKOV_FORGIT_ALIAS_MODE", {"plain", "forgit"}),
    "typo_handling": ("OOODNAKOV_TYPO_HANDLING_MODE", {"silent", "suggest", "help"}),
    "psfzf_tab": ("OOODNAKOV_PSFZF_TAB", {"enabled", "disabled"}),
    "psfzf_git": ("OOODNAKOV_PSFZF_GIT", {"enabled", "disabled"}),
    "auto_uv_env": ("OOODNAKOV_AUTO_UV_ENV_MODE", {"disabled", "existing", "enabled", "quiet"}),
    "window_manager": ("OOODNAKOV_DEFAULT_WM", {"komorebi", "glazewm", "aerospace", "omniwm"}),
    "bar": ("OOODNAKOV_DEFAULT_BAR", {"zebar", "yabs", "sketchybar"}),
}


class LifecycleError(ValueError):
    """Raised for an invalid diagnostic or snapshot request."""


@dataclass(frozen=True)
class Check:
    id: str
    status: str
    severity: str
    message: str
    remediation: str | None = None


def _dependency_available(dependency: dict[str, object]) -> bool:
    binary = dependency.get("bin") or dependency.get("key")
    return isinstance(binary, str) and shutil.which(binary) is not None


def _generated_drift(repo_root: Path) -> bool:
    if not (repo_root / ".git").exists():
        return False
    result = subprocess.run(["git", "diff", "--quiet", "--", *GENERATED_FILES], cwd=repo_root, check=False)
    return result.returncode != 0


def diagnostics(repo_root: Path, platform: str, profile_name: str | None, mode: str) -> dict[str, object]:
    """Return a stable, secret-free diagnostic document."""
    repo_root = repo_root.resolve()
    profile = resolve_profile(repo_root, platform, profile_name)
    checks: list[Check] = []
    checks.append(
        Check(
            "profile.selection",
            "pass" if profile else "warning",
            "info" if profile else "warning",
            f"Profile {profile.name} is valid." if profile else "No portable profile is selected.",
            None if profile else "Pass --profile NAME or create local/profile.toml.",
        )
    )
    links = selected_links(repo_root, platform, profile.name if profile else None, profile.links if profile else None)
    healthy = 0
    for source, target, _key in links:
        if target.is_symlink() and target.resolve(strict=False) == source.resolve(strict=False):
            healthy += 1
    checks.append(
        Check(
            "links.managed",
            "pass" if healthy == len(links) else "error",
            "info" if healthy == len(links) else "error",
            f"{healthy} of {len(links)} managed links are correct.",
            None if healthy == len(links) else "Run oooconf apply to repair managed links.",
        )
    )
    records = {str(item["key"]): item for item in normalized_deps(platform)}
    dependencies = profile.dependencies if profile else tuple(records)
    available = sum(_dependency_available(records[key]) for key in dependencies if key in records)
    checks.append(
        Check(
            "dependencies.available",
            "pass" if available == len(dependencies) else "warning",
            "info" if available == len(dependencies) else "warning",
            f"{available} of {len(dependencies)} recommended dependencies are available.",
            None if available == len(dependencies) else "Run oooconf deps with the missing dependency keys.",
        )
    )
    incomplete = sum(data.get("status") in INCOMPLETE_STATUSES for _path, data in _load_journals())
    checks.append(
        Check(
            "transactions.incomplete",
            "pass" if not incomplete else "error",
            "info" if not incomplete else "error",
            f"{incomplete} incomplete transaction(s) found.",
            None if not incomplete else "Run oooconf rollback --last, then inspect the transaction journal.",
        )
    )
    drift = _generated_drift(repo_root)
    checks.append(
        Check(
            "generated.drift",
            "warning" if drift else "pass",
            "warning" if drift else "info",
            "Generated artifacts differ from the checkout." if drift else "Generated artifacts have no tracked drift.",
            "Run oooconf completions and oooconf lock, then review the diff." if drift else None,
        )
    )
    counts = {status: sum(check.status == status for check in checks) for status in ("pass", "warning", "error")}
    return {
        "schema_version": DIAGNOSTIC_SCHEMA_VERSION,
        "command": mode,
        "platform": platform,
        "profile": profile.name if profile else None,
        "capabilities": list(profile.capabilities) if profile else [],
        "skipped_capabilities": list(profile.skipped_capabilities) if profile else [],
        "managed_links": {"total": len(links), "healthy": healthy},
        "dependencies": {"recommended": len(dependencies), "available": available},
        "incomplete_transactions": incomplete,
        "generated_artifact_drift": drift,
        "summary": counts,
        "checks": [asdict(check) for check in checks],
    }


def render_diagnostics(document: dict[str, object], output_format: str) -> str:
    if output_format == "json":
        return json.dumps(document, indent=2, sort_keys=True)
    lines = [f"oooconf {document['command']} ({document['platform']}, schema v{document['schema_version']})"]
    for item in document["checks"]:
        lines.append(f"- [{item['status']}] {item['id']}: {item['message']}")
        if item["remediation"]:
            lines.append(f"  remediation: {item['remediation']}")
    summary = document["summary"]
    lines.append(f"Summary: {summary['pass']} passed, {summary['warning']} warning(s), {summary['error']} error(s)")
    return "\n".join(lines)


def _safe_preferences() -> dict[str, str]:
    result = {}
    for name, (variable, allowed) in PREFERENCES.items():
        value = os.environ.get(variable)
        if value in allowed:
            result[name] = value
    return result


def _snapshot_document(repo_root: Path, platform: str, profile_name: str | None) -> dict[str, object]:
    profile = resolve_profile(repo_root, platform, profile_name)
    if profile is None:
        raise LifecycleError("snapshot export requires --profile or a machine-local default profile")
    return {
        "version": SNAPSHOT_VERSION,
        "profile": profile.name,
        "capabilities": list(profile.capabilities),
        "preferences": _safe_preferences(),
    }


def _toml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def render_snapshot(document: dict[str, object]) -> str:
    capabilities = document["capabilities"]
    preferences = document["preferences"]
    lines = [
        f"version = {SNAPSHOT_VERSION}",
        f"profile = {_toml_string(str(document['profile']))}",
        "capabilities = [" + ", ".join(_toml_string(str(item)) for item in capabilities) + "]",
        "",
        "[preferences]",
    ]
    lines.extend(f"{key} = {_toml_string(str(preferences[key]))}" for key in sorted(preferences))
    return "\n".join(lines) + "\n"


def _atomic_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        if os.name != "nt":
            os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(content)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def load_snapshot(path: Path, repo_root: Path, platform: str) -> dict[str, object]:
    try:
        with path.open("rb") as stream:
            document = tomllib.load(stream)
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise LifecycleError(f"Unable to read snapshot: {error}") from error
    if (
        set(document) != {"version", "profile", "capabilities", "preferences"}
        or document.get("version") != SNAPSHOT_VERSION
    ):
        raise LifecycleError("snapshot must contain only version 1, profile, capabilities, and preferences")
    profile_name = document.get("profile")
    capabilities = document.get("capabilities")
    preferences = document.get("preferences")
    if not isinstance(profile_name, str) or not profile_name:
        raise LifecycleError("snapshot profile must be a non-empty string")
    profile = resolve_profile(repo_root, platform, profile_name)
    if not isinstance(capabilities, list) or capabilities != list(profile.capabilities):
        raise LifecycleError("snapshot capabilities do not match the declared profile")
    if not isinstance(preferences, dict) or set(preferences) - PREFERENCES.keys():
        raise LifecycleError("snapshot contains an unknown preference")
    for key, value in preferences.items():
        if not isinstance(value, str) or value not in PREFERENCES[key][1]:
            raise LifecycleError(f"snapshot preference {key} has an unsupported value")
    return document


def snapshot_preview(document: dict[str, object], repo_root: Path, platform: str) -> dict[str, object]:
    plan = build_plan(repo_root, platform, scope="links", profile_name=str(document["profile"]))
    return {
        "schema_version": SNAPSHOT_VERSION,
        "valid": True,
        "profile": document["profile"],
        "capabilities": document["capabilities"],
        "preferences": document["preferences"],
        "planned_operations": len(plan["operations"]),
    }


def apply_snapshot(document: dict[str, object], repo_root: Path, platform: str) -> int:
    profile_name = str(document["profile"])
    build_plan(repo_root, platform, scope="links", profile_name=profile_name)
    _path, status = apply(repo_root, platform, profile_name)
    if status:
        return status
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    local = config_home / "ooodnakov/local"
    for key, value in document["preferences"].items():
        variable = PREFERENCES[key][0]
        write_override(local / "env.zsh", variable, f"export {variable}={shlex.quote(value)}")
        write_override(local / "env.ps1", variable, f"$env:{variable} = '{value}'")
    _atomic_text(repo_root / "home/.config/ooodnakov/local/profile.toml", f"profile = {_toml_string(profile_name)}\n")
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    result.add_argument("--platform", choices=("linux", "macos", "windows"), default=None)
    result.add_argument("--profile")
    commands = result.add_subparsers(dest="command", required=True)
    for command in ("doctor", "status"):
        child = commands.add_parser(command)
        child.add_argument("--format", choices=("text", "json"), default="text")
        child.add_argument("--platform", choices=("linux", "macos", "windows"), default=None)
    snapshot = commands.add_parser("snapshot")
    snapshot.add_argument("--platform", choices=("linux", "macos", "windows"), default=None)
    snapshot_commands = snapshot.add_subparsers(dest="snapshot_command", required=True)
    export = snapshot_commands.add_parser("export")
    export.add_argument("--output", "-o", type=Path, required=True)
    for command in ("inspect", "apply"):
        child = snapshot_commands.add_parser(command)
        child.add_argument("file", type=Path)
        if command == "inspect":
            child.add_argument("--format", choices=("text", "json"), default="text")
    return result


def cli(argv: list[str] | None = None) -> int:
    argument_parser = parser()
    args = argument_parser.parse_args(argv)
    platform = args.platform or get_platform()
    try:
        if args.command in {"doctor", "status"}:
            document = diagnostics(args.repo_root, platform, args.profile, args.command)
            print(render_diagnostics(document, args.format))
            return 1 if args.command == "doctor" and document["summary"]["error"] else 0
        if args.snapshot_command == "export":
            document = _snapshot_document(args.repo_root, platform, args.profile)
            _atomic_text(args.output, render_snapshot(document))
            print(f"Exported portable snapshot to {args.output}")
            return 0
        document = load_snapshot(args.file, args.repo_root, platform)
        if args.snapshot_command == "inspect":
            preview = snapshot_preview(document, args.repo_root, platform)
            if args.format == "json":
                print(json.dumps(preview, indent=2, sort_keys=True))
            else:
                print(f"Valid snapshot for profile {preview['profile']}.")
                print(f"Capabilities: {', '.join(preview['capabilities'])}")
                print(
                    f"Preferences: {len(preview['preferences'])}; planned operations: {preview['planned_operations']}"
                )
            return 0
        return apply_snapshot(document, args.repo_root, platform)
    except (LifecycleError, ProfileError, OSError, RuntimeError) as error:
        argument_parser.error(str(error))
    return 2


if __name__ == "__main__":
    raise SystemExit(cli())
