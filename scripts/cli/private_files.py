"""Atomic writers for secret-bearing files (session token, rendered env files)."""

from __future__ import annotations

import os
import tempfile
from pathlib import Path


def ensure_private_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if os.name != "nt":
        path.chmod(0o700)


def write_private_atomic(path: Path, content: str) -> None:
    fd, temp_name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        try:
            fchmod = getattr(os, "fchmod", None)
            if os.name != "nt" and fchmod is not None:
                fchmod(fd, 0o600)
        except Exception:
            os.close(fd)
            raise
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(content)
        os.replace(temp_name, path)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)
