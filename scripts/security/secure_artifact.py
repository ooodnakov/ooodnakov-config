#!/usr/bin/env python3
"""Verify pinned download integrity and safely extract supported archives."""

from __future__ import annotations

import argparse
import hashlib
import os
import re
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
            expanded = template.replace("${ver}", version)
            pattern = re.escape(expanded)
            pattern = pattern.replace(re.escape("${arch}"), r"(?:x86_64|aarch64|i686)")
            pattern = pattern.replace(re.escape("${goarch}"), r"(?:amd64|arm64|386)")
            pattern = pattern.replace(re.escape("${system}"), r"(?:linux|darwin|windows)")
            if re.fullmatch(pattern, asset) and isinstance(digest, str):
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


def extract_tar_zst(archive: Path, destination: Path) -> None:
    try:
        import zstandard  # type: ignore[import-not-found]
    except ImportError as error:  # pragma: no cover - depends on environment
        raise IntegrityError(
            "extracting .tar.zst archives requires the 'zstandard' package; "
            "run 'uv sync' (or 'uv add zstandard') and retry"
        ) from error

    handle, intermediate_name = tempfile.mkstemp(prefix=".oooconf-tarzst.", suffix=".tar")
    os.close(handle)
    intermediate = Path(intermediate_name)
    try:
        with archive.open("rb") as source, intermediate.open("wb") as target:
            zstandard.ZstdDecompressor().copy_stream(source, target)
        _extract_tar_materializing_links(intermediate, destination)
    finally:
        intermediate.unlink(missing_ok=True)


def _tar_link_target(link: tarfile.TarInfo, files: dict[str, tarfile.TarInfo]) -> str | None:
    """Resolve a tar symlink/hardlink member to an archived file path, or None."""
    name = PurePosixPath(link.name)
    if link.islnk():
        # Hardlink targets are relative to the archive root.
        resolved = PurePosixPath(link.linkname)
    else:
        if PurePosixPath(link.linkname).is_absolute():
            return None
        resolved = name.parent / PurePosixPath(link.linkname)
    parts: list[str] = []
    for part in resolved.parts:
        if part == "..":
            if not parts:
                return None
            parts.pop()
        elif part not in (".", ""):
            parts.append(part)
    candidate = str(PurePosixPath(*parts))
    return candidate if candidate in files else None


def _extract_tar_materializing_links(archive: Path, destination: Path) -> None:
    """Extract a distribution tarball, replacing internal symlinks/hardlinks
    with copies of their targets.

    MSYS2 packages ship symlinks (for example usr/bin/zsh.exe -> zsh-5.9.2.exe)
    that must survive extraction on Windows, where symlinks need privileges to
    recreate. Links pointing outside the archived file set are rejected like
    any other escape attempt.
    """
    with tarfile.open(archive, mode="r:*") as bundle:
        direct: list[tarfile.TarInfo] = []
        files: dict[str, tarfile.TarInfo] = {}
        links: list[tarfile.TarInfo] = []
        for member in bundle.getmembers():
            relative = _safe_relative(member.name)
            if member.isdev():
                raise IntegrityError(f"unsafe archive member type: {member.name}")
            if not _within(destination, destination / relative):
                raise IntegrityError(f"archive member escapes destination: {member.name}")
            if member.issym() or member.islnk():
                links.append(member)
            else:
                direct.append(member)
                if member.isfile():
                    files[relative.as_posix()] = member
        bundle.extractall(destination, members=direct, filter="data")
        for link in links:
            target = _tar_link_target(link, files)
            if target is None:
                raise IntegrityError(f"unsafe archive link target: {link.name} -> {link.linkname}")
            source_file = destination / target
            if not source_file.is_file():
                raise IntegrityError(f"archive link target missing: {link.name} -> {link.linkname}")
            shutil.copyfile(source_file, destination / _safe_relative(link.name))


def extract(archive: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    if archive.name.endswith(".zip"):
        extract_zip(archive, destination)
    elif archive.name.endswith(".tar.zst"):
        extract_tar_zst(archive, destination)
    elif archive.name.endswith((".tar.gz", ".tgz", ".tar.xz", ".tar.bz2")):
        extract_tar(archive, destination)
    else:
        # Some release projects publish a verified executable directly rather
        # than wrapping it in an archive. Preserve its release filename; the
        # caller chooses the final command name after verification.
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copy2(archive, destination / archive.name)


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
