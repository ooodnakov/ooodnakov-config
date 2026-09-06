#!/usr/bin/env python3
"""Build a deterministic, side-effect-free oooconf operation plan."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import asdict, dataclass, replace
from pathlib import Path
from typing import Literal

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from scripts.cli.profile_manager import ProfileError, resolve_profile  # noqa: E402
from scripts.cli.read_optional_deps import load_deps, normalized_deps  # noqa: E402
from scripts.link_manager import get_all_links, get_platform  # noqa: E402

SCHEMA_VERSION = 2
OperationKind = Literal["mkdir", "backup", "link", "unlink", "download", "install", "render", "command"]


class PlanError(ValueError):
    """Raised when a safe operation plan cannot be produced."""


@dataclass(frozen=True)
class Operation:
    """One validated, redacted operation in an oooconf plan."""

    id: str
    kind: OperationKind
    platform: str
    profile: str | None
    source: str | None
    target: str | None
    requires_elevation: bool
    requires_network: bool
    preconditions: tuple[str, ...]
    postconditions: tuple[str, ...]
    summary: str
    rollback: str


def _resolved(path: Path) -> Path:
    return path.expanduser().resolve(strict=False)


def _lexical_absolute(path: Path) -> Path:
    """Normalize a target without following its final symlink."""
    return Path(os.path.abspath(os.path.expanduser(str(path))))


def _is_within(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
    except ValueError:
        return False
    return True


def _approved_target_roots(platform: str) -> tuple[Path, ...]:
    home = _resolved(Path.home())
    config_home = (
        home / ".config"
        if platform == "windows"
        else _resolved(Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")))
    )
    data_home = (
        home / ".local" / "share"
        if platform == "windows"
        else _resolved(Path(os.environ.get("XDG_DATA_HOME", home / ".local/share")))
    )
    return tuple(dict.fromkeys((home, config_home, data_home, home / ".local/bin")))


def _validate_target(target: Path, platform: str) -> Path:
    if not target.is_absolute():
        raise PlanError(f"Link target must be absolute: {target}")
    lexical = _lexical_absolute(target)
    # Resolve existing parent symlinks without following the target itself. This
    # catches a seemingly safe target whose parent redirects outside user roots.
    resolved = _resolved(lexical.parent) / lexical.name
    roots = _approved_target_roots(platform)
    if resolved == _resolved(Path.home()) or not any(_is_within(resolved, root) for root in roots):
        raise PlanError(f"Link target is outside approved user roots: {target}")
    return resolved


def _validate_source(source: Path) -> Path:
    if not source.is_absolute():
        raise PlanError(f"Link source must be absolute: {source}")
    resolved = _resolved(source)
    if not source.exists():
        raise PlanError(f"Link source does not exist: {source}")
    return resolved


def _link_matches(source: Path, target: Path) -> bool:
    if not target.is_symlink():
        return False
    try:
        return target.resolve(strict=False) == source
    except OSError:
        return False


def _safe_id(value: str) -> str:
    return re.sub(r"[^a-z0-9_.-]+", "-", value.lower()).strip("-") or "unnamed"


def selected_links(
    repo_root: Path,
    platform: str,
    profile: str | None = None,
    allowed_link_keys: frozenset[str] | None = None,
) -> list[tuple[Path, Path, str]]:
    """Return the complete validated link selection in deterministic order."""
    raw_links = get_all_links(repo_root, platform)
    if allowed_link_keys is not None:
        available_keys = {key for _source, _target, key in raw_links if key}
        unknown_keys = sorted(allowed_link_keys - available_keys)
        if unknown_keys:
            raise PlanError(f"Profile {profile} selects links unavailable on {platform}: {', '.join(unknown_keys)}")
        raw_links = [link for link in raw_links if link[2] in allowed_link_keys]
    links = sorted(raw_links, key=lambda item: (item[1].casefold(), (item[2] or "").casefold()))
    result: list[tuple[Path, Path, str]] = []
    seen_targets: set[Path] = set()
    seen_ids: set[str] = set()
    for source_text, target_text, key in links:
        source = _validate_source(Path(source_text))
        target = _validate_target(Path(target_text), platform)
        if target in seen_targets:
            raise PlanError(f"Multiple managed links target the same path: {target}")
        seen_targets.add(target)
        operation_key = _safe_id(key or target.name)
        if operation_key in seen_ids:
            raise PlanError(f"Managed link keys are not unique: {operation_key}")
        seen_ids.add(operation_key)
        result.append((source, target, operation_key))
    return result


def build_link_operations(
    repo_root: Path,
    platform: str,
    profile: str | None = None,
    allowed_link_keys: frozenset[str] | None = None,
) -> list[Operation]:
    """Return required link mutations in deterministic target order."""
    links = selected_links(repo_root, platform, profile, allowed_link_keys)
    operations: list[Operation] = []
    planned_parents: set[Path] = set()

    for source, target, operation_key in links:
        common = {"platform": platform, "profile": profile, "requires_elevation": False, "requires_network": False}
        parent = target.parent
        if not parent.exists() and parent not in planned_parents:
            planned_parents.add(parent)
            try:
                parent_id = parent.relative_to(_resolved(Path.home())).as_posix()
            except ValueError:
                parent_id = parent.as_posix()
            operations.append(
                Operation(
                    id=f"mkdir:{_safe_id(parent_id)}",
                    kind="mkdir",
                    source=None,
                    target=str(parent),
                    preconditions=("parent is within an approved user root",),
                    postconditions=("directory exists",),
                    summary=f"Create parent directory for {operation_key}",
                    rollback="remove directory if empty",
                    **common,
                )
            )

        if _link_matches(source, target):
            continue
        if target.exists() or target.is_symlink():
            operations.append(
                Operation(
                    id=f"backup:{operation_key}",
                    kind="backup",
                    source=str(target),
                    target=None,
                    preconditions=("target exists", "backup destination is in managed state"),
                    postconditions=("target is preserved in managed backup storage",),
                    summary=f"Back up existing target for {operation_key}",
                    rollback="restore backup if the replacement link is removed",
                    **common,
                )
            )
        operations.append(
            Operation(
                id=f"link:{operation_key}",
                kind="link",
                source=str(source),
                target=str(target),
                preconditions=("source exists", "target is absent or has a preceding backup operation"),
                postconditions=("target is a symbolic link to source",),
                summary=f"Link managed config {operation_key}",
                rollback="remove link; restore preceding backup when present",
                **common,
            )
        )
    return operations


def _dependency_keys() -> set[str]:
    return {str(dep["key"]) for dep in load_deps()["deps"] if dep.get("key")}


def _runtime_directory_operations(platform: str) -> list[Operation]:
    home = _resolved(Path.home())
    config_home = (
        home / ".config"
        if platform == "windows"
        else _lexical_absolute(Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")))
    )
    data_home = (
        home / ".local/share"
        if platform == "windows"
        else _lexical_absolute(Path(os.environ.get("XDG_DATA_HOME", home / ".local/share")))
    )
    directories = {
        config_home,
        data_home,
        home / ".local/bin",
        home / ".local/state/ooodnakov-config/backups",
        home / ".local/state/ooodnakov-config/logs",
    }
    if platform == "windows":
        directories.update({home / ".cache/ooodnakov-config", data_home / "ooodnakov-config"})
    else:
        directories.add(data_home / "ooodnakov-config")

    operations = []
    for directory in sorted(
        (_validate_target(path / ".oooconf-placeholder", platform).parent for path in directories), key=str
    ):
        if directory.exists():
            continue
        relative = directory.relative_to(home).as_posix() if _is_within(directory, home) else directory.as_posix()
        operations.append(
            Operation(
                id=f"mkdir:{_safe_id(relative)}",
                kind="mkdir",
                platform=platform,
                profile=None,
                source=None,
                target=str(directory),
                requires_elevation=False,
                requires_network=False,
                preconditions=("directory is within an approved user root",),
                postconditions=("directory exists",),
                summary=f"Create managed runtime directory {relative}",
                rollback="remove directory if empty",
            )
        )
    return operations


def build_plan(
    repo_root: Path,
    platform: str,
    scope: str = "install",
    dependencies: tuple[str, ...] = (),
    profile_name: str | None = None,
) -> dict[str, object]:
    """Build a complete versioned plan without modifying the filesystem."""
    repo_root = _resolved(repo_root)
    if not (repo_root / "scripts/links.toml").is_file():
        raise PlanError(f"Repository root does not contain scripts/links.toml: {repo_root}")

    unknown = sorted(set(dependencies) - _dependency_keys())
    if unknown:
        raise PlanError(f"Unknown dependency key(s): {', '.join(unknown)}")
    if scope == "links" and dependencies:
        raise PlanError("Dependency keys cannot be combined with --scope links")

    profile = resolve_profile(repo_root, platform, profile_name)
    if profile:
        unknown_recommendations = sorted(set(profile.dependencies) - _dependency_keys())
        if unknown_recommendations:
            raise PlanError(
                f"Profile {profile.name} recommends unknown dependencies: {', '.join(unknown_recommendations)}"
            )
    operations = build_link_operations(
        repo_root,
        platform,
        profile.name if profile else None,
        profile.links if profile else None,
    )
    if scope == "install":
        directory_operations = _runtime_directory_operations(platform)
        prepared_directories = {operation.target for operation in directory_operations}
        operations = [
            operation
            for operation in operations
            if not (operation.kind == "mkdir" and operation.target in prepared_directories)
        ]
        dependency_operations = []
        dependencies_by_key = {str(dep["key"]): dep for dep in normalized_deps(platform)}
        for key in sorted(set(dependencies)):
            dependency = dependencies_by_key[key]
            manager = str(dependency.get("manager") or "")
            requires_elevation = manager in {"apt", "dnf", "pacman", "yum", "zypper"}
            dependency_operations.append(
                Operation(
                    id=f"install:{_safe_id(key)}",
                    kind="install",
                    platform=platform,
                    profile=None,
                    source=None,
                    target=None,
                    requires_elevation=requires_elevation,
                    requires_network=True,
                    preconditions=("dependency key exists in optional-deps.toml", "user approved installation"),
                    postconditions=(f"dependency {key} passes its configured availability check",),
                    summary=f"Install optional dependency {key}",
                    rollback="unavailable: package-manager rollback is platform-specific",
                ),
            )
        lifecycle_operations = [
            Operation(
                id="command:managed-tools",
                kind="command",
                platform=platform,
                profile=None,
                source=None,
                target=None,
                requires_elevation=False,
                requires_network=True,
                preconditions=("managed tool pins are present in dependency metadata",),
                postconditions=("managed shell tool checkouts match their configured pins",),
                summary="Synchronize pinned shell framework repositories",
                rollback="unavailable: existing pinned checkouts are updated in place",
            ),
            Operation(
                id="command:managed-utilities",
                kind="command",
                platform=platform,
                profile=None,
                source=None,
                target=None,
                requires_elevation=False,
                requires_network=True,
                preconditions=("managed utility pins are present in dependency metadata",),
                postconditions=("managed utility checkouts match their configured pins",),
                summary="Synchronize pinned managed utilities",
                rollback="unavailable: existing pinned checkouts are updated in place",
            ),
        ]
        final_operations = [
            Operation(
                id="render:ssh-include",
                kind="render",
                platform=platform,
                profile=None,
                source=None,
                target=str(_resolved(Path.home()) / ".ssh/config"),
                requires_elevation=False,
                requires_network=False,
                preconditions=("SSH config is absent or writable",),
                postconditions=("managed SSH include is present exactly once",),
                summary="Ensure the managed SSH include",
                rollback="remove only the managed include line",
            ),
            Operation(
                id="command:fonts",
                kind="command",
                platform=platform,
                profile=None,
                source=str(repo_root / "fonts/meslo"),
                target=None,
                requires_elevation=False,
                requires_network=False,
                preconditions=("bundled font directory exists",),
                postconditions=("bundled fonts are installed in user font storage",),
                summary="Install bundled fonts",
                rollback="remove only font files installed by oooconf",
            ),
            Operation(
                id="command:completions",
                kind="command",
                platform=platform,
                profile=None,
                source=None,
                target=None,
                requires_elevation=False,
                requires_network=False,
                preconditions=("completion generators are available",),
                postconditions=("managed completion files match their generators",),
                summary="Generate managed shell completions",
                rollback="restore generated files from the repository checkout",
            ),
            Operation(
                id="command:editor-plugins",
                kind="command",
                platform=platform,
                profile=None,
                source=None,
                target=None,
                requires_elevation=False,
                requires_network=True,
                preconditions=("Neovim is available or the step can be skipped",),
                postconditions=("configured editor plugins are synchronized when Neovim is available",),
                summary="Synchronize managed editor plugins",
                rollback="unavailable: plugin-manager state is external runtime data",
            ),
        ]
        operations = directory_operations + dependency_operations + lifecycle_operations + operations + final_operations

    if profile:
        operations = [replace(operation, profile=profile.name) for operation in operations]

    return {
        "schema_version": SCHEMA_VERSION,
        "command": scope,
        "platform": platform,
        "profile": profile.name if profile else None,
        "capabilities": list(profile.capabilities) if profile else [],
        "skipped_capabilities": list(profile.skipped_capabilities) if profile else [],
        "recommended_dependencies": list(profile.dependencies) if profile else [],
        "operations": [asdict(operation) for operation in operations],
    }


def _render_text(plan: dict[str, object]) -> str:
    operations = plan["operations"]
    assert isinstance(operations, list)
    lines = [f"oooconf {plan['command']} plan ({plan['platform']}, schema v{plan['schema_version']})"]
    if plan["profile"]:
        lines.append(f"Profile: {plan['profile']}")
    for capability in plan["skipped_capabilities"]:
        lines.append(f"- [skip] capability {capability} is not applicable on {plan['platform']}")
    if not operations:
        return "\n".join((*lines, "No changes required."))
    for operation in operations:
        assert isinstance(operation, dict)
        location = f" -> {operation['target']}" if operation.get("target") else ""
        lines.append(f"- [{operation['kind']}] {operation['summary']}{location}")
    return "\n".join(lines)


def _render_links(plan: dict[str, object]) -> str:
    rows = []
    for operation in plan["operations"]:
        if operation["kind"] != "link":
            continue
        key = operation["id"].split(":", 1)[1]
        rows.append(f"{key}|{operation['source']}|{operation['target']}")
    return "\n".join(rows)


def _render_managed_links(repo_root: Path, platform: str, profile_name: str | None) -> str:
    profile = resolve_profile(repo_root, platform, profile_name)
    links = selected_links(
        repo_root,
        platform,
        profile.name if profile else None,
        profile.links if profile else None,
    )
    return "\n".join(f"{key}|{source}|{target}" for source, target, key in links)


def cli(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build a safe, deterministic oooconf operation plan")
    parser.add_argument("dependencies", nargs="*", help="optional dependency keys to include")
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--platform", choices=("linux", "macos", "windows"), default=None)
    parser.add_argument("--scope", choices=("install", "links"), default="install")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--profile", help="portable capability profile (explicit overrides local default)")
    parser.add_argument("--emit-links", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--emit-managed-links", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    try:
        platform = args.platform or get_platform()
        plan = build_plan(
            args.repo_root,
            platform,
            args.scope,
            tuple(args.dependencies),
            args.profile,
        )
        managed_links = (
            _render_managed_links(args.repo_root.resolve(), platform, args.profile) if args.emit_managed_links else None
        )
    except (OSError, RuntimeError, PlanError, ProfileError) as error:
        parser.error(str(error))

    if args.emit_managed_links:
        print(managed_links)
    elif args.emit_links:
        print(_render_links(plan))
    elif args.format == "json":
        print(json.dumps(plan, indent=2, sort_keys=True))
    else:
        print(_render_text(plan))
    return 0


if __name__ == "__main__":
    raise SystemExit(cli())
