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
EXCLUDED_PREFIXES = ("third_party/", "scripts/fleet/node_modules/")


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


def _validate_kdl(path: Path) -> None:
    text = _text(path)
    depth = 0
    quoted = False
    escaped = False
    for character in text:
        if escaped:
            escaped = False
        elif quoted and character == "\\":
            escaped = True
        elif character == '"':
            quoted = not quoted
        elif not quoted and character == "{":
            depth += 1
        elif not quoted and character == "}":
            depth -= 1
            if depth < 0:
                raise ValueError("has an unmatched closing brace")
    if quoted or depth:
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
