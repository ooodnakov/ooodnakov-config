#!/usr/bin/env python3
"""Read scripts/optional-deps.toml and output in various formats for shell consumption."""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TOML_PATH = REPO_ROOT / "scripts" / "optional-deps.toml"


def _parse_toml_simple(path: Path) -> list[dict]:
    """Minimal TOML parser for our flat [[deps]] blocks.

    Handles: key = "value", dotted keys like linux.manager = "apt",
    comments, blank lines, and [[deps]] headers.
    """
    text = path.read_text(encoding="utf-8")
    deps: list[dict] = []
    current: dict | None = None

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line == "[[deps]]":
            if current is not None:
                deps.append(current)
            current = {}
            continue
        if current is None:
            continue
        if "=" not in line:
            continue

        dotted_key, _, value = line.partition("=")
        dotted_key = dotted_key.strip()
        value = value.strip().strip('"')

        # Flatten dotted keys: linux.manager -> linux.manager
        current[dotted_key] = value

    if current is not None:
        deps.append(current)
    return deps


def output_catalog() -> None:
    """Print pipe-delimited catalog: key|display|description"""
    deps = _parse_toml_simple(TOML_PATH)
    for d in deps:
        key = d.get("key", "")
        display = d.get("display", key)
        desc = d.get("description", "")
        print(f"{key}|{display}|{desc}")


def output_json() -> None:
    """Print JSON array for PowerShell or other consumers."""
    import json

    deps = _parse_toml_simple(TOML_PATH)
    result = []
    for d in deps:
        entry = {}
        entry["key"] = d.get("key", "")
        entry["display"] = d.get("display", entry["key"])
        entry["description"] = d.get("description", "")
        # Platform info
        for platform in ("linux", "macos", "windows"):
            pfx = platform + "."
            pentry = {}
            for subkey in ("manager", "package", "command", "winget_id", "choco_id"):
                full = pfx + subkey
                if full in d:
                    pentry[subkey] = d[full]
            if pentry:
                entry[platform] = pentry
        result.append(entry)
    print(json.dumps(result, indent=2))


def get_dep(key: str) -> None:
    """Print pipe-delimited single dep or nothing."""
    deps = _parse_toml_simple(TOML_PATH)
    for d in deps:
        if d.get("key") == key:
            print(f"{d.get('key', '')}|{d.get('display', '')}|{d.get('description', '')}")
            return
    sys.exit(1)


def get_install_info(key: str, platform: str) -> None:
    """Print pipe-delimited install info for a dep on a platform.
    Format: manager|package|command|winget_id|choco_id
    """
    deps = _parse_toml_simple(TOML_PATH)
    for d in deps:
        if d.get("key") == key:
            pfx = platform + "."
            manager = d.get(pfx + "manager", "")
            package = d.get(pfx + "package", "")
            command = d.get(pfx + "command", "")
            winget_id = d.get(pfx + "winget_id", "")
            choco_id = d.get(pfx + "choco_id", "")
            print(f"{manager}|{package}|{command}|{winget_id}|{choco_id}")
            return
    sys.exit(1)


def main() -> int:
    if len(sys.argv) < 2:
        output_catalog()
        return 0

    cmd = sys.argv[1]
    if cmd == "catalog":
        output_catalog()
    elif cmd == "json":
        output_json()
    elif cmd == "get" and len(sys.argv) >= 3:
        get_dep(sys.argv[2])
    elif cmd == "install-info" and len(sys.argv) >= 4:
        get_install_info(sys.argv[2], sys.argv[3])
    elif cmd == "exists" and len(sys.argv) >= 3:
        deps = _parse_toml_simple(TOML_PATH)
        for d in deps:
            if d.get("key") == sys.argv[2]:
                return 0
        return 1
    elif cmd == "keys":
        deps = _parse_toml_simple(TOML_PATH)
        for d in deps:
            print(d.get("key", ""))
    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
