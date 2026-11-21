#!/usr/bin/env python3
"""Resolve the optional private overlay repository root."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

_DEFAULT_REPO_ROOT = Path(__file__).resolve().parents[2]
_POINTER_RELATIVE = Path("home/.config/ooodnakov/local/private-repo")
_HOME_POINTER_RELATIVE = Path(".config/ooodnakov/local/private-repo")
_DEFAULT_SIBLING_NAME = "ooodnakov-config-private"


def _resolve_candidate(raw_path: str, repo_root: Path) -> Path | None:
    candidate = Path(raw_path).expanduser()
    if not candidate.is_absolute():
        candidate = repo_root / candidate
    if candidate.is_dir():
        return candidate.resolve()
    return None


def _read_first_pointer_line(path: Path) -> str | None:
    if not path.is_file():
        return None
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line and not line.startswith("#"):
            return line
    return None


def resolve_private_overlay_root(repo_root: Path | str) -> Path | None:
    """Resolve the optional private overlay repository root if present.

    Precedence:
    1. ``OOOCONF_PRIVATE_DIR`` environment variable (``""`` or ``"none"`` opts out).
    2. Pointer files at ``<repo_root>/home/.config/ooodnakov/local/private-repo``
       and ``~/.config/ooodnakov/local/private-repo``.
    3. Sibling directory ``../ooodnakov-config-private`` next to ``repo_root``.
    """
    repo_root_path = Path(repo_root)

    if "OOOCONF_PRIVATE_DIR" in os.environ:
        env_value = os.environ["OOOCONF_PRIVATE_DIR"].strip()
        if not env_value or env_value.lower() == "none":
            return None
        return _resolve_candidate(env_value, repo_root_path)

    pointer_files = (
        repo_root_path / _POINTER_RELATIVE,
        Path.home() / _HOME_POINTER_RELATIVE,
    )
    for pointer_file in pointer_files:
        pointer_value = _read_first_pointer_line(pointer_file)
        if pointer_value is not None:
            resolved = _resolve_candidate(pointer_value, repo_root_path)
            if resolved is not None:
                return resolved

    sibling = repo_root_path.resolve().parent / _DEFAULT_SIBLING_NAME
    if sibling.is_dir():
        return sibling.resolve()

    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Resolve private overlay repository root")
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=_DEFAULT_REPO_ROOT,
        help="Main configuration repository root",
    )
    args = parser.parse_args(argv)
    resolved = resolve_private_overlay_root(args.repo_root)
    if resolved is None:
        return 1
    print(str(resolved))
    return 0


if __name__ == "__main__":
    sys.exit(main())
