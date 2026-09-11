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
import platform
import re
import shutil
import subprocess
import sys
import tomllib
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
    if xdg and Path(xdg).exists():
        return Path(xdg) / "bin" / "config.json"
    config_home = home / ".config"
    if config_home.exists():
        return config_home / "bin" / "config.json"
    return legacy


def load(path: Path) -> dict:
    if path.exists():
        content = path.read_text(encoding="utf-8")
        data = json.loads(content) if content.strip() else {}
        if not isinstance(data, dict) or not isinstance(data.get("bins", {}), (dict, type(None))):
            raise ValueError(f"invalid bin config: {path}")
        if data.get("bins") is None:
            data["bins"] = {}
        return data
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

    # Adopt only: never overwrite an entry bin already tracks. bin may have
    # upgraded the binary past the catalog pin (Topgrade's native `bin update`);
    # re-recording the pinned version would regress that tracking record.
    if str(binary) in data["bins"]:
        print(f"already tracked {args.name} at {binary}")
        return 0

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


def adopt(args: argparse.Namespace) -> int:
    """Discover catalog binaries in oooconf's install directories, even off PATH."""
    with Path(args.catalog).open("rb") as stream:
        dependencies = tomllib.load(stream)["deps"]
    home = Path.home()
    data_home = Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share")
    roots = [home / ".local/bin", data_home / "ooodnakov-config", home / ".local/share/ooodnakov-config"]
    if args.install_root:
        roots.extend(Path(root) for root in args.install_root)
    roots = [root.resolve() for root in roots]
    tracked = load(config_path()).get("bins", {})
    arch = {"AMD64": "x86_64", "arm64": "aarch64"}.get(platform.machine(), platform.machine())
    for dep in dependencies:
        config = dep.get(args.platform, {})
        url = config.get("url", "")
        repo = config.get("package", "") if config.get("manager") == "github-release" else ""
        match = re.match(r"https://github.com/([^/]+/[^/]+)/releases/download/", url)
        if match:
            repo = match[1]
        if not repo or dep["key"] == "bin":
            continue
        name = dep.get("bin", dep["key"])
        filename = name + (".exe" if args.platform == "windows" else "")
        candidates = [root / filename for root in roots] + [root / "bin" / filename for root in roots]
        found = shutil.which(filename)
        if found:
            candidates.insert(0, Path(found))
        for candidate in candidates:
            binary = candidate.resolve()
            if not binary.is_file() or not any(binary.is_relative_to(root) for root in roots):
                continue
            if str(binary) in tracked:
                break
            try:
                version_flag = "version" if dep.get("check") == f"{name} version" else "--version"
                result = subprocess.run([str(binary), version_flag], capture_output=True, text=True, timeout=5)
                version_match = re.search(r"\bv?(\d+\.\d+\.\d+(?:[-+][\w.-]+)?)\b", result.stdout + result.stderr)
                if result.returncode or not version_match:
                    print(f"warning: cannot determine installed version of {binary}", file=sys.stderr)
                    break
                version = version_match[1]
                asset = config.get("asset") or url.rsplit("/", 1)[-1]
                if name == "nvim":
                    nvim_arch = "arm64" if arch == "aarch64" else arch
                    asset = (
                        ("nvim-win-arm64.zip" if nvim_arch == "arm64" else "nvim-win64.zip")
                        if args.platform == "windows"
                        else f"nvim-{args.platform}-{nvim_arch}.tar.gz"
                    )
                if name == "rtk" and args.platform != "windows":
                    target = (
                        "apple-darwin"
                        if args.platform == "macos"
                        else ("unknown-linux-gnu" if arch == "aarch64" else "unknown-linux-musl")
                    )
                    asset = f"rtk-{arch}-{target}.tar.gz"
                for key, value in {
                    "ver": version,
                    "system": "darwin" if args.platform == "macos" else args.platform,
                    "arch": arch,
                    "goarch": {"x86_64": "amd64", "aarch64": "arm64"}.get(arch, arch),
                }.items():
                    asset = asset.replace("${" + key + "}", value)
                if not asset:
                    break
                if args.dry_run:
                    print(f"[dry-run] Adopt {name} v{version} at {binary} into bin tracking")
                else:
                    track(
                        argparse.Namespace(
                            path=str(binary), name=name, repo=repo, version=version, asset=asset, package_path=filename
                        )
                    )
            except (OSError, subprocess.SubprocessError, UnicodeError) as error:
                print(f"warning: cannot adopt {binary}: {error}", file=sys.stderr)
            break
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
    a = sub.add_parser("adopt", help="adopt previously installed catalog GitHub binaries")
    a.add_argument("--catalog", default=str(Path(__file__).resolve().parents[1] / "optional-deps.toml"))
    a.add_argument("--platform", required=True, choices=("linux", "macos", "windows"))
    a.add_argument("--install-root", action="append")
    a.add_argument("--dry-run", action="store_true")
    a.set_defaults(func=adopt)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
