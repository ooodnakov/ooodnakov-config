#!/usr/bin/env python3
"""Verify pinned download integrity and safely extract supported archives."""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import stat
import sys
import tarfile
import tempfile
import tomllib
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG = REPO_ROOT / "scripts/optional-deps.toml"


class IntegrityError(RuntimeError):
    """Raised when an artifact cannot be trusted or safely extracted."""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def expected_digest(dependency: str, asset: str, catalog: Path = CATALOG) -> str:
    with catalog.open("rb") as stream:
        document = tomllib.load(stream)
    for item in document.get("deps", []):
        if item.get("key") != dependency:
            continue
        version = str(item.get("ver", ""))
        integrity = item.get("integrity", {})
        if not isinstance(integrity, dict):
            break
        for template, digest in integrity.items():
            if template.replace("${ver}", version) == asset and isinstance(digest, str):
                normalized = digest.lower().removeprefix("sha256:")
                if len(normalized) == 64 and all(character in "0123456789abcdef" for character in normalized):
                    return normalized
        break
    raise IntegrityError(f"no SHA-256 is pinned for {dependency} artifact {asset}")


def verify(path: Path, expected: str) -> None:
    actual = sha256(path)
    if actual != expected.lower().removeprefix("sha256:"):
        raise IntegrityError(f"SHA-256 mismatch for {path.name}: expected {expected}, got {actual}")


def _safe_relative(name: str) -> Path:
    normalized = name.replace("\\", "/")
    pure = PurePosixPath(normalized)
    if pure.is_absolute() or ".." in pure.parts or (pure.parts and ":" in pure.parts[0]):
        raise IntegrityError(f"unsafe archive member path: {name}")
    return Path(*pure.parts)


def _within(root: Path, target: Path) -> bool:
    try:
        target.resolve().relative_to(root.resolve())
    except ValueError:
        return False
    return True


def extract_zip(archive: Path, destination: Path) -> None:
    with zipfile.ZipFile(archive) as bundle:
        for member in bundle.infolist():
            relative = _safe_relative(member.filename)
            mode = member.external_attr >> 16
            if stat.S_ISLNK(mode):
                raise IntegrityError(f"archive symlink is not allowed: {member.filename}")
            target = destination / relative
            if not _within(destination, target):
                raise IntegrityError(f"archive member escapes destination: {member.filename}")
            if member.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with bundle.open(member) as source, target.open("wb") as output:
                shutil.copyfileobj(source, output)


def extract_tar(archive: Path, destination: Path) -> None:
    with tarfile.open(archive, mode="r:*") as bundle:
        members = bundle.getmembers()
        for member in members:
            relative = _safe_relative(member.name)
            if member.issym() or member.islnk() or member.isdev():
                raise IntegrityError(f"unsafe archive member type: {member.name}")
            if not _within(destination, destination / relative):
                raise IntegrityError(f"archive member escapes destination: {member.name}")
        bundle.extractall(destination, members=members, filter="data")


def extract(archive: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    if archive.name.endswith(".zip"):
        extract_zip(archive, destination)
    elif archive.name.endswith((".tar.gz", ".tgz", ".tar.xz", ".tar.bz2")):
        extract_tar(archive, destination)
    else:
        raise IntegrityError(f"unsupported archive format: {archive.name}")


def download(url: str, output: Path, expected: str) -> None:
    if not url.startswith("https://"):
        raise IntegrityError("artifact downloads require HTTPS")
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix=f".{output.name}.", dir=output.parent)
    os.close(fd)
    temporary = Path(temporary_name)
    try:
        with urllib.request.urlopen(url, timeout=60) as response, temporary.open("wb") as stream:  # nosec B310
            shutil.copyfileobj(response, stream)
        verify(temporary, expected)
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)


def cli(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("verify", "extract", "download"))
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--dependency", required=True)
    parser.add_argument("--asset", required=True)
    parser.add_argument("--catalog", type=Path, default=CATALOG)
    parser.add_argument("--destination", type=Path)
    parser.add_argument("--url")
    args = parser.parse_args(argv)
    try:
        expected = expected_digest(args.dependency, args.asset, args.catalog)
        if args.command == "download":
            if not args.url:
                raise IntegrityError("download requires --url")
            download(args.url, args.archive, expected)
        else:
            verify(args.archive, expected)
        if args.command == "extract":
            if args.destination is None:
                raise IntegrityError("extract requires --destination")
            extract(args.archive, args.destination)
        return 0
    except (OSError, ValueError, tarfile.TarError, zipfile.BadZipFile, IntegrityError) as error:
        print(f"integrity error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(cli())
