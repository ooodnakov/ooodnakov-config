#!/usr/bin/env python3
"""Shared store for the repo-managed `herdr-task` and `herdr-artifact` commands.

One JSON list per folder under ~/.local/share/ooodnakov/herdr, written only by
those two commands and read by the `oo-tasks` / `oo-artifacts` mods:

    index.json                     {"format": 1, "folders": {"<folder>": "<slug>"}}
    tasks/<slug>.json              {"format": 1, "folder": "<folder>", "tasks": [...]}
    artifacts/<slug>.json          {"format": 1, "folder": "<folder>", "artifacts": [...]}
    artifacts/files/<id>/v<n>.md   an artifact version's content

Every write takes a `<file>.lock` and replaces the file atomically, so an agent,
a person and a mod never see half a list.
"""

from __future__ import annotations

import json
import os
import re
import secrets
import subprocess
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator

FORMAT = 1
TASK_STATUSES = ("todo", "doing", "blocked", "done")
KIND_BY_SUFFIX = {"md": "markdown", "markdown": "markdown", "html": "html", "htm": "html"}


class Fail(Exception):
    """A user-facing failure: printed without a traceback."""


def data_root() -> Path:
    """The store's root. Fixed (not XDG-derived) so the mods find it without an environment."""
    override = os.environ.get("OODNAKOV_HERDR_DATA")
    if override:
        return Path(override).expanduser()
    return Path.home() / ".local" / "share" / "ooodnakov" / "herdr"


def normalize(path: str) -> str:
    """Absolute, forward slashes, no trailing slash."""
    resolved = os.path.abspath(os.path.expanduser(path)).replace("\\", "/")
    return resolved.rstrip("/") or "/"


def folder_for(arg: str | None) -> str:
    """The folder a command acts on: --folder, else the current git worktree root, else the cwd."""
    if arg:
        return normalize(arg)
    cwd = os.getcwd()
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0 and result.stdout.strip():
            return normalize(result.stdout.strip())
    except (OSError, subprocess.SubprocessError):
        pass
    return normalize(cwd)


def now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def new_id(prefix: str) -> str:
    return f"{prefix}-{time.strftime('%Y%m%d')}-{secrets.token_hex(3)}"


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except OSError as error:
        raise Fail(f"cannot read {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise Fail(f"{path} is not valid JSON: {error}") from error


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temp = tempfile.mkstemp(dir=str(path.parent), prefix=f"{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(handle, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(data, stream, indent=2, ensure_ascii=False)
            stream.write("\n")
        os.replace(temp, path)
    except BaseException:
        try:
            os.unlink(temp)
        except OSError:
            pass
        raise


@contextmanager
def locked(path: Path) -> Iterator[None]:
    """An exclusive lock beside `path`; other writers wait."""
    path.parent.mkdir(parents=True, exist_ok=True)
    stream = open(path, "a+b")
    try:
        if os.name == "nt":
            import msvcrt

            while True:
                try:
                    stream.seek(0)
                    msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
                    break
                except OSError:
                    time.sleep(0.02)
        else:
            import fcntl

            fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
        yield
    finally:
        try:
            if os.name == "nt":
                import msvcrt

                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl

                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)
        finally:
            stream.close()


def _slug_base(folder: str) -> str:
    name = re.sub(r"[^A-Za-z0-9._-]+", "-", Path(folder).name).strip("-.").lower()
    return (name or "root")[:60]


def slug_for(root: Path, folder: str) -> str:
    """The folder's slug, assigning and remembering one in the shared index."""
    index_path = root / "index.json"
    with locked(root / "index.json.lock"):
        index = read_json(index_path) or {}
        folders = index.get("folders")
        if not isinstance(folders, dict):
            folders = {}
        slug = folders.get(folder)
        if isinstance(slug, str) and slug:
            return slug
        taken = {value for value in folders.values() if isinstance(value, str)}
        base = _slug_base(folder)
        slug, number = base, 1
        while slug in taken:
            number += 1
            slug = f"{base}-{number}"
        folders[folder] = slug
        write_json(index_path, {"format": FORMAT, "folders": folders})
        return slug


def list_path(root: Path, kind: str, slug: str) -> Path:
    return root / kind / f"{slug}.json"


def load_list(path: Path, folder: str, key: str) -> dict[str, Any]:
    data = read_json(path)
    if data is None:
        return {"format": FORMAT, "folder": folder, key: []}
    if not isinstance(data, dict) or not isinstance(data.get(key), list):
        raise Fail(f"{path} is not a {key} list")
    return data


def read_list(kind: str, key: str, folder: str) -> tuple[Path, dict[str, Any]]:
    """A folder's list as it is; atomic replaces keep readers consistent without a lock."""
    root = data_root()
    path = list_path(root, kind, slug_for(root, folder))
    return path, load_list(path, folder, key)


@contextmanager
def edit_list(kind: str, key: str, folder: str) -> Iterator[dict[str, Any]]:
    """A folder's list, locked for read-modify-write; saved when the block ends."""
    root = data_root()
    path = list_path(root, kind, slug_for(root, folder))
    with locked(path.with_name(f"{path.name}.lock")):
        data = load_list(path, folder, key)
        yield data
        write_json(path, data)


def find(items: list[dict[str, Any]], item_id: str) -> dict[str, Any]:
    for item in items:
        if item.get("id") == item_id:
            return item
    raise Fail(f"no such id: {item_id}")


def kind_for(name: str) -> str:
    suffix = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    return KIND_BY_SUFFIX.get(suffix, "text")
