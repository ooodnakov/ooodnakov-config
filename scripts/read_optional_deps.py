#!/usr/bin/env python3
"""Central parser for scripts/optional-deps.toml — the SINGLE source of truth.
All install logic, versions, URLs, and managed tools now flow through here.
"""

from __future__ import annotations

import sys
import tomllib
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TOML_PATH = REPO_ROOT / "scripts" / "optional-deps.toml"


def load_deps() -> dict:
    """Proper TOML parser + template substitution (${ver} → actual version)."""
    with open(TOML_PATH, "rb") as f:
        data = tomllib.load(f)

    defaults = data.get("defaults", {})
    deps = []
    for raw in data.get("deps", []):
        entry = dict(raw)
        ver = entry.get("ver")
        # Flatten nested platform tables (linux.manager -> linux.manager) for compatibility
        for platform in ("linux", "macos", "windows"):
            if platform in entry and isinstance(entry[platform], dict):
                for subkey, value in entry[platform].items():
                    entry[f"{platform}.{subkey}"] = value
                del entry[platform]  # remove nested to keep flat
        # Replace ${ver} in any URL field (top-level or platform-specific)
        if ver:
            for k, v in list(entry.items()):
                if isinstance(v, str) and ("url" in k.lower() or k == "url"):
                    entry[k] = v.replace("${ver}", ver)
        for k in ("ver", "url", "bin", "check", "after", "repo", "ref"):
            if k in raw:
                entry[k] = raw[k]
        deps.append(entry)

    return {
        "deps": deps,
        "managed_tools": data.get("managed-tools", {}),
        "defaults": defaults,
    }


def output_catalog() -> None:
    """Print pipe-delimited catalog: key|display|description"""
    data = load_deps()
    for d in data["deps"]:
        key = d.get("key", "")
        display = d.get("display", key)
        desc = d.get("description", "")
        print(f"{key}|{display}|{desc}")


def output_json() -> None:
    """Print JSON array for PowerShell or other consumers."""
    import json

    data = load_deps()
    result = []
    for d in data["deps"]:
        entry = {
            "key": d.get("key", ""),
            "display": d.get("display", d.get("key", "")),
            "description": d.get("description", ""),
            "ver": d.get("ver"),
            "url": d.get("url"),
            "bin": d.get("bin"),
            "check": d.get("check"),
            "after": d.get("after"),
        }
        # Platform info (backward compatible)
        for platform in ("linux", "macos", "windows"):
            pentry = {}
            for subkey in ("manager", "package", "command", "winget_id", "choco_id"):
                key = f"{platform}.{subkey}"
                if key in d:
                    pentry[subkey] = d[key]
            if pentry:
                entry[platform] = pentry
        result.append({k: v for k, v in entry.items() if v is not None})
    print(json.dumps(result, indent=2))


def get_dep(key: str) -> None:
    """Print pipe-delimited single dep or nothing."""
    data = load_deps()
    for d in data["deps"]:
        if d.get("key") == key:
            print(f"{d.get('key', '')}|{d.get('display', '')}|{d.get('description', '')}")
            return
    sys.exit(1)


def get_install_info(key: str, platform: str) -> None:
    """Print pipe-delimited install info. Now includes new rich fields."""
    data = load_deps()
    for d in data["deps"]:
        if d.get("key") == key:
            pfx = platform + "."
            manager = d.get(pfx + "manager", d.get("manager", ""))
            package = d.get(pfx + "package", d.get("package", ""))
            command = d.get(pfx + "command", d.get("command", ""))
            winget_id = d.get(pfx + "winget_id", "")
            choco_id = d.get(pfx + "choco_id", "")
            ver = d.get("ver", "")
            url = d.get("url", "")
            print(f"{manager}|{package}|{command}|{winget_id}|{choco_id}|{ver}|{url}")
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
        data = load_deps()
        for d in data["deps"]:
            if d.get("key") == sys.argv[2]:
                return 0
        return 1
    elif cmd == "keys":
        data = load_deps()
        for d in data["deps"]:
            print(d.get("key", ""))
    elif cmd == "managed-tools":
        data = load_deps()
        import json
        print(json.dumps(data["managed_tools"], indent=2))
    elif cmd == "check-command" and len(sys.argv) >= 3:
        data = load_deps()
        key = sys.argv[2]
        for d in data["deps"]:
            if d.get("key") == key:
                print(d.get("check", f"command -v {key}"))
                return 0
        print(f"command -v {key}")
        return 0
    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
