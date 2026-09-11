#!/usr/bin/env python3
"""Register an installed binary with marcosnils/bin without re-downloading.

Adopts a checksum-verified GitHub release binary into bin's tracking config so
Topgrade's native ``bin update`` step upgrades it going forward. Mirrors the
config.json format and config-path resolution of marcosnils/bin
(``pkg/config/config.go``) so the record is compatible with what ``bin install``
writes, but the binary on disk is never re-downloaded here: the caller has
already installed and verified it.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def config_path() -> Path:
    """Mirror bin's getConfigPath resolution order."""
    env = os.environ.get("BIN_CONFIG")
    if env:
        return Path(env)
    home = Path.home()
    legacy = home / ".bin" / "config.json"
    if legacy.exists():
        return legacy
    xdg = os.environ.get("XDG_CONFIG_HOME")
    if xdg:
        return Path(xdg) / "bin" / "config.json"
    config_home = home / ".config"
    if config_home.exists():
        return config_home / "bin" / "config.json"
    return legacy


def load(path: Path) -> dict:
    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                return data
        except (json.JSONDecodeError, OSError):
            pass
    return {}


def track(args: argparse.Namespace) -> int:
    binary = Path(args.path).expanduser().resolve()
    if not binary.is_file():
        print(f"error: {args.path} is not a file", file=sys.stderr)
        return 1

    path = config_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    data = load(path)
    data.setdefault("default_path", str(Path.home() / ".local" / "bin"))
    data.setdefault("bins", {})

    version = f"v{args.version.lstrip('v')}"
    entry = {
        "path": str(binary),
        "remote_name": args.name,
        "version": version,
        "hash": sha256(binary),
        "url": f"https://github.com/{args.repo}/releases/tag/{version}",
        "provider": "github",
        "package_path": args.package_path or args.name,
        "selected_asset": args.asset,
        "pinned": False,
    }
    data["bins"][str(binary)] = entry

    path.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")
    print(f"tracked {args.name} {version} at {binary}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    t = sub.add_parser("track", help="register an installed binary with bin")
    t.add_argument("--path", required=True, help="installed binary path")
    t.add_argument("--name", required=True, help="binary/remote name")
    t.add_argument("--repo", required=True, help="GitHub owner/repo")
    t.add_argument("--version", required=True, help="pinned version (with or without v)")
    t.add_argument("--asset", required=True, help="release asset filename")
    t.add_argument("--package-path", help="binary name inside the archive")
    t.set_defaults(func=track)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
