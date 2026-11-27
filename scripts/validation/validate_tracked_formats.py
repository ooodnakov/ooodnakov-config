#!/usr/bin/env python3
"""Parse or smoke-check tracked structured configuration files."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
EXCLUDED_PREFIXES = ("third_party/",)


def tracked_files(repo_root: Path = REPO_ROOT) -> list[Path]:
    output = subprocess.run(["git", "ls-files", "-z"], cwd=repo_root, check=True, capture_output=True).stdout
    return [
        repo_root / name.decode()
        for name in output.split(b"\0")
        if name and not name.decode().startswith(EXCLUDED_PREFIXES)
    ]


def _text(path: Path) -> str:
    content = path.read_text(encoding="utf-8")
    if "\0" in content or "<<<<<<<" in content or ">>>>>>>" in content:
        raise ValueError("contains NUL or unresolved merge markers")
    return content


def _raw_string_end(text: str, start: int) -> int | None:
    """If a KDL raw string starts at `start`, return index just past its closing delimiter."""
    length = len(text)
    if text[start] == "r":
        if start > 0 and (text[start - 1].isalnum() or text[start - 1] in "_-"):
            return None
        cursor = start + 1
        hashes = 0
        while cursor < length and text[cursor] == "#":
            hashes += 1
            cursor += 1
    elif text[start] == "#":
        cursor = start
        hashes = 0
        while cursor < length and text[cursor] == "#":
            hashes += 1
            cursor += 1
        if hashes == 0:
            return None
    else:
        return None

    if cursor >= length or text[cursor] != '"':
        return None

    quote = '"""' if text.startswith('"""', cursor) else '"'
    closing = quote + "#" * hashes
    end_idx = text.find(closing, cursor + len(quote))
    if end_idx == -1:
        raise ValueError("has an unterminated raw string")
    return end_idx + len(closing)


def _quoted_string_end(text: str, start: int) -> int:
    """Return index just past the KDL quoted or multiline string starting at `start`."""
    length = len(text)
    multiline = text.startswith('"""', start)
    cursor = start + (3 if multiline else 1)
    while cursor < length:
        if text[cursor] == "\\":
            cursor += 2
            continue
        if multiline:
            if text.startswith('"""', cursor):
                return cursor + 3
        elif text[cursor] == '"':
            return cursor + 1
        cursor += 1
    raise ValueError("has an unterminated string or brace block")


def _validate_kdl(path: Path) -> None:
    text = _text(path)
    length = len(text)
    index = 0
    depth = 0
    block_comment_depth = 0

    while index < length:
        if block_comment_depth > 0:
            if text.startswith("/*", index):
                block_comment_depth += 1
                index += 2
            elif text.startswith("*/", index):
                block_comment_depth -= 1
                index += 2
            else:
                index += 1
            continue

        if text.startswith("//", index):
            newline = text.find("\n", index + 2)
            index = length if newline == -1 else newline + 1
            continue

        if text.startswith("/*", index):
            block_comment_depth = 1
            index += 2
            continue

        if text[index] in {"r", "#"}:
            raw_end = _raw_string_end(text, index)
            if raw_end is not None:
                index = raw_end
                continue

        if text[index] == '"':
            index = _quoted_string_end(text, index)
            continue

        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth < 0:
                raise ValueError("has an unmatched closing brace")
        index += 1

    if block_comment_depth > 0:
        raise ValueError("has an unterminated block comment")
    if depth != 0:
        raise ValueError("has an unterminated string or brace block")


def _validate_lua(path: Path) -> None:
    _text(path)
    compiler = shutil.which("luac") or shutil.which("luac5.4")
    if compiler:
        subprocess.run([compiler, "-p", str(path)], check=True, capture_output=True)


def validate(path: Path) -> None:
    suffix = path.suffix.lower()
    if suffix == ".json":
        json.loads(_text(path))
    elif suffix == ".toml":
        with path.open("rb") as stream:
            tomllib.load(stream)
    elif suffix in {".yaml", ".yml"}:
        list(yaml.safe_load_all(_text(path)))
    elif suffix == ".kdl":
        _validate_kdl(path)
    elif suffix == ".lua":
        _validate_lua(path)


def main() -> int:
    failures = []
    checked = 0
    for path in tracked_files():
        if path.suffix.lower() not in {".json", ".toml", ".yaml", ".yml", ".kdl", ".lua"}:
            continue
        checked += 1
        try:
            validate(path)
        except (
            OSError,
            ValueError,
            json.JSONDecodeError,
            tomllib.TOMLDecodeError,
            yaml.YAMLError,
            subprocess.SubprocessError,
        ) as error:
            failures.append(f"{path.relative_to(REPO_ROOT)}: {error}")
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"Validated {checked} tracked JSON/TOML/YAML/KDL/Lua files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
