#!/usr/bin/env python3
"""
Dotfiles symlink manager.

Handles symlink discovery, manifest parsing, and platform filtering.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

try:
    import tomllib
except ImportError:
    import tomli as tomllib  # Python < 3.11 fallback


def get_platform() -> str:
    """Detect platform from uname or sys.platform.

    Returns:
        "linux", "macos", or "windows".
    """
    if sys.platform == "win32":
        return "windows"
    # Unix-like: check uname
    try:
        uname_result = os.uname()
        system = uname_result.sysname.lower()
        if system == "darwin":
            return "macos"
        elif system == "linux":
            return "linux"
        elif system == "windows":
            return "windows"
        else:
            # Fallback: check environment variables for WSL or other
            if "microsoft" in os.uname().release.lower():
                return "linux"  # WSL treated as linux
            return system
    except AttributeError:
        # os.uname not available, use sys.platform
        plat = sys.platform
        if plat.startswith("linux"):
            return "linux"
        elif plat.startswith("darwin"):
            return "macos"
        elif plat.startswith("win"):
            return "windows"
        else:
            return "unknown"


def expand_path_template(template: str, platform: str) -> str:
    """Expand path templates in a string.

    Templates:
        {HOME}       -> os.path.expanduser("~")
        {CONFIG_HOME} -> ~/.config (unix) or ~/.config (windows, same style)
        {DATA_HOME}  -> ~/.local/share (unix) or ~/.local/share (windows)
        {LOCAL_BIN}  -> ~/.local/bin (both platforms)

    Args:
        template: Path template string with placeholders.
        platform: Platform string ("linux", "macos", "windows").

    Returns:
        Expanded path string with all templates replaced.
    """
    home = Path(os.path.expanduser("~"))

    # CONFIG_HOME: Unix XDG_CONFIG_HOME or ~/.config; Windows ~/.config
    if platform == "windows":
        config_home = home / ".config"
    else:
        xdg_config = os.environ.get("XDG_CONFIG_HOME")
        if xdg_config:
            config_home = Path(xdg_config)
        else:
            config_home = home / ".config"

    # DATA_HOME: Unix XDG_DATA_HOME or ~/.local/share; Windows ~/.local/share
    if platform == "windows":
        data_home = home / ".local" / "share"
    else:
        xdg_data = os.environ.get("XDG_DATA_HOME")
        if xdg_data:
            data_home = Path(xdg_data)
        else:
            data_home = home / ".local" / "share"

    # LOCAL_BIN: ~/.local/bin (both platforms)
    local_bin = home / ".local" / "bin"

    replacements = {
        "{HOME}": str(home),
        "{CONFIG_HOME}": str(config_home),
        "{DATA_HOME}": str(data_home),
        "{LOCAL_BIN}": str(local_bin),
    }

    result = template
    for placeholder, value in replacements.items():
        result = result.replace(placeholder, value)

    # Normalize to use forward slashes in output and os.path.join
    # Convert any backslashes to forward slashes for cross-platform consistency
    if platform == "windows":
        # On windows, os.path.join uses backslashes, but we want forward slashes
        # for the template expansion output
        result = result.replace("\\", "/")

    return result


def _platform_matches(entry_platform: str | None, entry_except: str | None, platform: str) -> bool:
    """Check if an entry matches the current platform.

    Args:
        entry_platform: Value of 'only' field, or None.
        entry_except: Value of 'except' field, or None.
        platform: Current platform.

    Returns:
        True if entry should be included for this platform.
    """
    # Check 'only' field
    if entry_platform is not None:
        return entry_platform == platform

    # Check 'except' field
    if entry_except is not None:
        return entry_except != platform

    # Default: include on all platforms
    return True


def read_links_manifest(repo_root: Path | str, platform: str) -> list[dict]:
    """Parse scripts/links.toml from repo_root.

    Args:
        repo_root: Root directory of the repository.
        platform: Current platform string.

    Returns:
        List of dicts with keys: key, source, target.
    """
    manifest_path = Path(repo_root) / "scripts" / "links.toml"

    if not manifest_path.exists():
        print(f"Warning: manifest not found at {manifest_path}", file=sys.stderr)
        return []

    with open(manifest_path, "rb") as f:
        manifest = tomllib.load(f)

    links = manifest.get("links", [])
    result = []

    for entry in links:
        # Check platform filtering
        only_platform = entry.get("only")
        except_platform = entry.get("except")

        if platform is not None and not _platform_matches(only_platform, except_platform, platform):
            continue

        # Get key (optional, defaults to None for auto-discovered)
        key = entry.get("key")

        # Expand path templates
        source = expand_path_template(entry["source"], platform)
        target = expand_path_template(entry["target"], platform)

        # Resolve source to absolute path relative to repo_root
        source_path = Path(source)
        if not os.path.isabs(source_path):
            source = str((repo_root / source_path).resolve())

        entry_dict = {
            "key": key,
            "source": source,
            "target": target,
        }
        # Preserve platform tags for discover_links to use
        if entry.get("only"):
            entry_dict["only"] = entry["only"]
        if entry.get("except"):
            entry_dict["except"] = entry["except"]
        result.append(entry_dict)

    return result


def _matches_exclude(path: Path, exclude_patterns: list[str]) -> bool:
    """Check if path matches any exclude pattern.

    Simple substring or glob-style matching.
    Handles both forward and back slashes.

    Args:
        path: Path to check.
        exclude_patterns: List of patterns to match against.

    Returns:
        True if path matches any exclude pattern.
    """
    path_str = str(path).replace("\\", "/")

    for pattern in exclude_patterns:
        pattern = pattern.replace("\\", "/")
        # Simple substring match
        if pattern in path_str:
            return True
        # Glob-style: check if pattern matches end (e.g., "*.lock")
        if "*" in pattern:
            import fnmatch
            if fnmatch.fnmatch(path_str, pattern):
                return True
            if fnmatch.fnmatch(path.name, pattern):
                return True
    return False


def discover_links(repo_root: Path | str, manifest: dict, platform: str = "linux", explicit_links: list = None) -> list[dict]:
    """Discover symlinks by scanning configured directories.

    Args:
        repo_root: Root directory of the repository.
        manifest: Parsed manifest dict (should contain 'discovery' key).

    Returns:
        List of discovered link dicts with key, source, target.
    """
    repo_root = Path(repo_root)
    discovery = manifest.get("discovery", {})
    autolink_dirs = discovery.get("autolink_dirs", [])
    exclude_patterns = discovery.get("exclude", [])

    discovered = []

    for autolink_dir in autolink_dirs:
        scan_path = Path(repo_root) / autolink_dir

        if not scan_path.exists():
            print(f"Warning: autolink dir not found: {scan_path}", file=sys.stderr)
            continue

        # Scan subdirectories
        try:
            for entry in scan_path.iterdir():
                if not entry.is_dir():
                    continue

                # Check exclude patterns
                if _matches_exclude(entry, exclude_patterns):
                    continue

                # Generate link entry
                key = entry.name
                source = str(entry.resolve()).replace("\\", "/")

                # Skip if ANY explicit entry (from full manifest) restricts this key to a different platform
                if explicit_links:
                    for link in explicit_links:
                        if link.get("key") == key:
                            if not _platform_matches(link.get("only"), link.get("except"), platform):
                                skip = True
                            break
                if skip:
                    continue

                target = expand_path_template(f"{{CONFIG_HOME}}/{key}", platform)
                discovered.append({
                    "key": key,
                    "source": source,
                    "target": target,
                })
        except PermissionError as e:
            print(f"Warning: permission denied scanning {scan_path}: {e}", file=sys.stderr)
            continue

    return discovered


def merge_with_local(links: list[dict], local_toml_path: Path | str | None) -> list[dict]:
    """Merge explicit links with local overrides.

    Args:
        links: List of link dicts from manifest.
        local_toml_path: Path to links.local.toml, or None to skip.

    Returns:
        Merged list of link dicts.
    """
    if local_toml_path is None:
        return links

    local_path = Path(local_toml_path) if local_toml_path else None
    if not local_path or not local_path.exists():
        return links

    with open(local_path, "rb") as f:
        local_data = tomllib.load(f)

    local_links = local_data.get("links", {})

    # Build dict of links by key for easy override
    result = []
    existing_keys = set()

    for link in links:
        key = link.get("key")
        if key and key in local_links:
            # Override target from local
            override = local_links[key]
            target = override.get("target", link["target"])
            result.append({
                "key": key,
                "source": link["source"],
                "target": target,
            })
            existing_keys.add(key)
        else:
            result.append(link)
            if link.get("key"):
                existing_keys.add(link.get("key"))

    # Add any new keys from local that weren't in original
    for key, override in local_links.items():
        if key not in existing_keys:
            # This is a new entry from local
            result.append({
                "key": key,
                "source": override.get("source", ""),
                "target": override.get("target", ""),
            })

    return result


def get_all_links(repo_root: Path | str) -> list[tuple[str, str, str | None]]:
    """Get all links, merging manifest and local config.

    Args:
        repo_root: Root directory of the repository.

    Returns:
        List of tuples: (source, target, key).
    """
    platform = get_platform()
    repo_root = Path(repo_root)

    # Read manifest
    all_explicit_links = read_links_manifest(repo_root, None)  # None = no platform filter, returns all

    # Build manifest dict for discovery
    manifest = {"discovery": {}}
    manifest_path = repo_root / "scripts" / "links.toml"
    if manifest_path.exists():
        with open(manifest_path, "rb") as f:
            manifest = tomllib.load(f)

    # Discover auto links
    # Merge explicit (precedence) and discovered
    all_links = []
    platform_filtered = [l for l in all_explicit_links if _platform_matches(l.get("only"), l.get("except"), platform)]
    explicit_dict = {link["key"]: link for link in platform_filtered if link.get("key")}

    # Discover auto links
    discovered_links = discover_links(repo_root, manifest, platform, all_explicit_links)

    # Add explicit links first (they take precedence)
    for link in platform_filtered:
        all_links.append((link["source"], link["target"], link.get("key")))

    # Add discovered links that don't conflict with explicit
    for link in discovered_links:
        key = link["key"]
        if key not in explicit_dict:
            all_links.append((link["source"], link["target"], key))

    # Local overrides - use same path pattern as other ooodnakov local files
    # i.e., repo_root/home/.config/ooodnakov/local/links.local.toml
    local_path = repo_root / "home" / ".config" / "ooodnakov" / "local" / "links.local.toml"
    merged = merge_with_local(
        [{"key": key, "source": src, "target": tgt} for src, tgt, key in all_links],
        local_path
    )

    return [(link["source"], link["target"], link["key"]) for link in merged]


def cli() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Dotfiles symlink manager"
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=None,
        help="Repository root (default: script dir parent)",
    )
    parser.add_argument(
        "--platform",
        choices=["linux", "macos", "windows"],
        default=None,
        help="Platform (default: auto-detect)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Just print links, don't create",
    )
    parser.add_argument(
        "--format",
        choices=["text", "json"],
        default="text",
        help="Output format (default: text)",
    )

    args = parser.parse_args()

    # Determine repo root
    if args.repo_root is None:
        script_dir = Path(__file__).parent.resolve()
        args.repo_root = script_dir.parent

    # Determine platform
    platform = args.platform or get_platform()

    # Get links
    links = get_all_links(args.repo_root)

    # Validate sources exist (for dry-run reporting)
    missing_sources = []
    for source, target, key in links:
        source_path = Path(source)
        if not source_path.exists():
            print(f"Warning: source not found: {source}", file=sys.stderr)
            missing_sources.append(source)

    # Output
    if args.format == "json":
        output = {
            "links": [
                {"key": k, "source": s, "target": t}
                for s, t, k in links
            ]
        }
        print(json.dumps(output, indent=2))
    else:
        for source, target, key in links:
            key_part = f"{key}|" if key else ""
            print(f"{key_part}{source}|{target}")

    if args.dry_run:
        print(f"\n[Dry-run] Would process {len(links)} links", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(cli())