"""Load and validate portable oooconf capability profiles."""

from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass
from pathlib import Path


class ProfileError(ValueError):
    """Raised when profile metadata is invalid."""


@dataclass(frozen=True)
class Capability:
    name: str
    links: tuple[str, ...]
    dependencies: tuple[str, ...]
    platforms: tuple[str, ...]


@dataclass(frozen=True)
class ResolvedProfile:
    name: str
    capabilities: tuple[str, ...]
    skipped_capabilities: tuple[str, ...]
    links: frozenset[str]
    dependencies: tuple[str, ...]


def _read_toml(path: Path) -> dict[str, object]:
    try:
        with path.open("rb") as handle:
            return tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise ProfileError(f"Unable to read profile metadata {path}: {error}") from error


def _string_list(value: object, location: str) -> tuple[str, ...]:
    if value is None:
        return ()
    if not isinstance(value, list) or not all(isinstance(item, str) and item for item in value):
        raise ProfileError(f"{location} must be an array of non-empty strings")
    return tuple(value)


def load_capabilities(repo_root: Path) -> dict[str, Capability]:
    path = repo_root / "home/.config/ooodnakov/profiles/capabilities.toml"
    document = _read_toml(path)
    if document.get("version") != 1:
        raise ProfileError(f"{path} must declare version = 1")
    raw = document.get("capabilities")
    if not isinstance(raw, dict) or not raw:
        raise ProfileError(f"No capabilities are defined in {path}")
    result = {}
    for name, value in raw.items():
        if not isinstance(name, str) or not isinstance(value, dict):
            raise ProfileError(f"Invalid capability entry in {path}: {name}")
        platforms = _string_list(value.get("platforms"), f"capabilities.{name}.platforms")
        unknown_platforms = sorted(set(platforms) - {"linux", "macos", "windows"})
        if unknown_platforms:
            raise ProfileError(f"Capability {name} has unknown platforms: {', '.join(unknown_platforms)}")
        result[name] = Capability(
            name=name,
            links=_string_list(value.get("links"), f"capabilities.{name}.links"),
            dependencies=_string_list(value.get("dependencies"), f"capabilities.{name}.dependencies"),
            platforms=platforms,
        )
    return result


def _profile_path(repo_root: Path, name: str) -> Path:
    if not name or Path(name).name != name or any(character in name for character in "/\\"):
        raise ProfileError(f"Invalid profile name: {name!r}")
    return repo_root / "home/.config/ooodnakov/profiles" / f"{name}.toml"


def _expand_profile(
    repo_root: Path,
    name: str,
    capabilities: dict[str, Capability],
    visiting: tuple[str, ...] = (),
) -> tuple[str, ...]:
    if name in visiting:
        cycle = " -> ".join((*visiting, name))
        raise ProfileError(f"Profile inheritance cycle detected: {cycle}")
    path = _profile_path(repo_root, name)
    if not path.is_file():
        raise ProfileError(f"Unknown profile: {name}")
    raw = _read_toml(path)
    if raw.get("version") != 1:
        raise ProfileError(f"{path} must declare version = 1")
    profile = raw.get("profile")
    if not isinstance(profile, dict):
        raise ProfileError(f"{path} must contain a [profile] table")
    declared_name = profile.get("name")
    if declared_name != name:
        raise ProfileError(f"Profile {path} declares name {declared_name!r}, expected {name!r}")

    resolved: list[str] = []
    parent = profile.get("extends")
    if parent is not None:
        if not isinstance(parent, str) or not parent:
            raise ProfileError(f"profile.extends in {path} must be a non-empty string")
        resolved.extend(_expand_profile(repo_root, parent, capabilities, (*visiting, name)))
    declared = _string_list(profile.get("capabilities"), f"profile.capabilities in {path}")
    unknown = sorted(set(declared) - capabilities.keys())
    if unknown:
        raise ProfileError(f"Profile {name} references unknown capabilities: {', '.join(unknown)}")
    resolved.extend(declared)
    return tuple(dict.fromkeys(resolved))


def local_default_profile(repo_root: Path) -> str | None:
    path = repo_root / "home/.config/ooodnakov/local/profile.toml"
    if not path.is_file():
        return None
    raw = _read_toml(path)
    value = raw.get("profile")
    if not isinstance(value, str) or not value:
        raise ProfileError(f'{path} must define profile = "name"')
    return value


def resolve_profile(repo_root: Path, platform: str, explicit: str | None = None) -> ResolvedProfile | None:
    """Resolve explicit, environment, then machine-local profile preference."""
    name = explicit or os.environ.get("OOODNAKOV_PROFILE") or local_default_profile(repo_root)
    if not name:
        return None
    capabilities = load_capabilities(repo_root)
    selected = _expand_profile(repo_root, name, capabilities)
    active = tuple(
        capability
        for capability in selected
        if not capabilities[capability].platforms or platform in capabilities[capability].platforms
    )
    skipped = tuple(capability for capability in selected if capability not in active)
    links = frozenset(link for name in active for link in capabilities[name].links)
    dependencies = tuple(dict.fromkeys(dep for name in active for dep in capabilities[name].dependencies))
    return ResolvedProfile(name, selected, skipped, links, dependencies)
