#!/usr/bin/env python3
"""Manage machine-local environment variables for oooconf."""

from __future__ import annotations

import argparse
import getpass
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

START = "# --- LOCAL OVERRIDES START ---"
END = "# --- LOCAL OVERRIDES END ---"
KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        prog="oooconf env",
        description="Add or update a variable in machine-local env files.",
    )
    result.add_argument("key", nargs="?", help="Environment variable name")
    result.add_argument("value", nargs="?", help="Environment variable value")
    result.add_argument(
        "--secrets",
        action="store_true",
        help="also upload the value to Bitwarden as a secure note",
    )
    result.add_argument(
        "--config-home",
        help=argparse.SUPPRESS,
        default=os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")),
    )
    return result


def replace_override(content: str, key: str, line: str) -> str:
    lines = content.splitlines()
    if START not in lines or END not in lines or lines.index(START) > lines.index(END):
        if lines and lines[-1]:
            lines.append("")
        lines.extend([START, "# Machine-local values managed by oooconf env.", END])
    start, end = lines.index(START), lines.index(END)
    patterns = (f"export {key}=", f"$env:{key} = ")
    block = [candidate for candidate in lines[start + 1 : end] if not candidate.startswith(patterns)]
    block.append(line)
    return "\n".join(lines[: start + 1] + block + lines[end:]) + "\n"


def write_override(path: Path, key: str, line: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    content = path.read_text(encoding="utf-8") if path.exists() else ""
    rendered = replace_override(content, key, line)
    fd, temp_name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(rendered)
        os.replace(temp_name, path)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


def upload_to_bitwarden(key: str, value: str) -> str:
    item = {
        "type": 2,
        "name": f"oooconf env: {key}",
        "secureNote": {"type": 0},
        "notes": value,
    }
    encoded = subprocess.run(
        ["bw", "encode"],
        input=json.dumps(item),
        text=True,
        capture_output=True,
        check=True,
    ).stdout.strip()
    created = subprocess.run(
        ["bw", "create", "item", encoded],
        text=True,
        capture_output=True,
        check=True,
    )
    return str(json.loads(created.stdout)["id"])


def prompt_missing(args: argparse.Namespace) -> tuple[str, str, bool]:
    if not sys.stdin.isatty():
        raise ValueError("KEY and VALUE are required outside an interactive terminal")
    key = args.key or input("Variable name: ").strip()
    value = args.value if args.value is not None else getpass.getpass("Variable value: ")
    upload = args.secrets
    if not upload:
        answer = input("Upload to Bitwarden secrets? [y/N]: ").strip().lower()
        upload = answer in {"y", "yes"}
    return key, value, upload


def main() -> int:
    argv = sys.argv[1:]
    if argv and argv[0] == "help":
        argv[0] = "--help"
    args = parser().parse_args(argv)
    try:
        key, value, upload = (
            prompt_missing(args) if args.key is None or args.value is None else (args.key, args.value, args.secrets)
        )
        if not KEY_RE.fullmatch(key):
            raise ValueError(f"invalid environment variable name: {key}")

        local = Path(args.config_home).expanduser() / "ooodnakov" / "local"
        write_override(local / "env.zsh", key, f"export {key}={shlex.quote(value)}")
        ps_value = value.replace("'", "''")
        write_override(local / "env.ps1", key, f"$env:{key} = '{ps_value}'")
        print(f"Updated {key} in {local / 'env.zsh'} and {local / 'env.ps1'}")
        if upload:
            item_id = upload_to_bitwarden(key, value)
            print(f"Uploaded {key} to Bitwarden item {item_id}")
        return 0
    except (ValueError, FileNotFoundError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        detail = exc.stderr.strip() if isinstance(exc, subprocess.CalledProcessError) and exc.stderr else str(exc)
        print(f"oooconf env: {detail}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
