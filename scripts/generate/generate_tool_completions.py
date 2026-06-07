#!/usr/bin/env python3
"""Generate shell completions for third-party tools from a typed manifest."""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = REPO_ROOT / "scripts/generate/tool-completions.toml"

_HERMES_REPLACEMENTS = {
    "'(-h --help){-h,--help}[Show help and exit]'": "'(-h --help)'{-h,--help}'[Show help and exit]'",
    "'(-V --version){-V,--version}[Show version and exit]'": "'(-V --version)'{-V,--version}'[Show version and exit]'",
    "'(-p --profile){-p,--profile}[Profile name]:profile:_hermes_profiles'": "'(-p --profile)'{-p,--profile}'[Profile name]:profile:_hermes_profiles'",
}


@dataclass(frozen=True)
class ZshCompletion:
    tool_key: str
    binary: str
    output: str
    provides: tuple[str, ...]
    argv: tuple[str, ...]
    env: dict[str, str]
    filter_name: str | None
    description: str


@dataclass(frozen=True)
class ZshConfig:
    output_dir: Path
    stamp_name: str
    prune: bool
    validate: bool


@dataclass(frozen=True)
class GeneratedCompletion:
    spec: ZshCompletion
    content: str


class CompletionError(RuntimeError):
    """Completion generation failed."""


def load_manifest(path: Path) -> dict[str, Any]:
    with path.open("rb") as fh:
        manifest = tomllib.load(fh)
    if manifest.get("version") != 1:
        raise CompletionError(f"unsupported completion manifest version: {manifest.get('version')!r}")
    return manifest


def zsh_config(manifest: dict[str, Any], repo_root: Path) -> ZshConfig:
    raw = manifest.get("zsh")
    if not isinstance(raw, dict):
        raise CompletionError("manifest missing [zsh] config")
    output_dir_raw = raw.get("output_dir")
    if not isinstance(output_dir_raw, str) or not output_dir_raw:
        raise CompletionError("manifest [zsh].output_dir must be a non-empty string")
    stamp_name = raw.get("stamp", ".autogen-stamp")
    if not isinstance(stamp_name, str) or "/" in stamp_name or not stamp_name:
        raise CompletionError("manifest [zsh].stamp must be a file name")
    return ZshConfig(
        output_dir=repo_root / output_dir_raw,
        stamp_name=stamp_name,
        prune=bool(raw.get("prune", True)),
        validate=bool(raw.get("validate", True)),
    )


def zsh_completions(manifest: dict[str, Any]) -> list[ZshCompletion]:
    completions: list[ZshCompletion] = []
    tools = manifest.get("tools", [])
    if not isinstance(tools, list):
        raise CompletionError("manifest tools must be an array")

    for tool in tools:
        if not isinstance(tool, dict):
            raise CompletionError("each [[tools]] entry must be a table")
        key = require_string(tool, "key")
        binary = require_string(tool, "binary")
        tool_description = str(tool.get("description") or key)
        zsh_entries = tool.get("zsh", [])
        if not isinstance(zsh_entries, list):
            raise CompletionError(f"tool {key}: zsh entries must be an array")
        for entry in zsh_entries:
            if not isinstance(entry, dict):
                raise CompletionError(f"tool {key}: each zsh entry must be a table")
            output = require_string(entry, "output", context=key)
            if not output.startswith("_"):
                raise CompletionError(f"tool {key}: zsh output must start with '_': {output}")
            provides = tuple(require_string_list(entry, "provides", context=key))
            argv = tuple(require_string_list(entry, "argv", context=key))
            env = entry.get("env", {})
            if not isinstance(env, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in env.items()):
                raise CompletionError(f"tool {key}: env must be a string map")
            filter_name = entry.get("filter")
            if filter_name is not None and not isinstance(filter_name, str):
                raise CompletionError(f"tool {key}: filter must be a string")
            description = str(entry.get("description") or f"Generating {tool_description} completions")
            completions.append(
                ZshCompletion(
                    tool_key=key,
                    binary=binary,
                    output=output,
                    provides=provides,
                    argv=argv,
                    env=dict(env),
                    filter_name=filter_name,
                    description=description,
                )
            )
    return completions


def require_string(table: dict[str, Any], key: str, *, context: str = "manifest") -> str:
    value = table.get(key)
    if not isinstance(value, str) or not value:
        raise CompletionError(f"{context}: {key} must be a non-empty string")
    return value


def require_string_list(table: dict[str, Any], key: str, *, context: str = "manifest") -> list[str]:
    value = table.get(key)
    if not isinstance(value, list) or not value or not all(isinstance(item, str) and item for item in value):
        raise CompletionError(f"{context}: {key} must be a non-empty string array")
    return value


def normalize_completion_content(content: str) -> str:
    normalized = content.replace("\r\n", "\n").replace("\r", "\n")
    if not normalized.endswith("\n"):
        normalized += "\n"
    return normalized


def apply_filter(filter_name: str | None, content: str, spec: ZshCompletion) -> str:
    if filter_name is None:
        return normalize_completion_content(content)
    if filter_name == "strip-before-compdef":
        idx = content.find("#compdef")
        if idx == -1:
            raise CompletionError(f"{spec.tool_key}: strip-before-compdef could not find #compdef")
        return normalize_completion_content(content[idx:])
    if filter_name == "hermes-v0.12-zsh-fix":
        patched = content
        for old, new in _HERMES_REPLACEMENTS.items():
            patched = patched.replace(old, new)
        return normalize_completion_content(patched)
    if filter_name == "npm-zsh-wrapper":
        return npm_zsh_wrapper()
    raise CompletionError(f"{spec.tool_key}: unknown completion filter: {filter_name}")


def npm_zsh_wrapper() -> str:
    return normalize_completion_content(
        "\n".join(
            [
                "#compdef npm",
                "",
                "_npm() {",
                "  local si=$IFS",
                "  compadd -- $(COMP_CWORD=$((CURRENT-1)) \\",
                "               COMP_LINE=$BUFFER \\",
                "               COMP_POINT=$CURSOR \\",
                '               npm completion -- "${words[@]}" \\',
                "               2>/dev/null)",
                "  IFS=$si",
                "}",
            ]
        )
    )


def command_available(spec: ZshCompletion) -> bool:
    return shutil.which(spec.binary) is not None


def generate_completion(spec: ZshCompletion, repo_root: Path) -> GeneratedCompletion:
    env = os.environ.copy()
    env.update(spec.env)
    proc = subprocess.run(
        spec.argv,
        cwd=repo_root,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        stderr = proc.stderr.strip()
        stdout = proc.stdout.strip()
        detail = stderr or stdout or f"exit {proc.returncode}"
        raise CompletionError(f"{spec.tool_key}: {' '.join(spec.argv)} failed: {detail}")
    return GeneratedCompletion(spec=spec, content=apply_filter(spec.filter_name, proc.stdout, spec))


def write_if_changed(path: Path, content: str) -> bool:
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return False
    path.write_text(content, encoding="utf-8")
    return True


def prune_stale_outputs(output_dir: Path, expected_outputs: set[str]) -> list[str]:
    removed: list[str] = []
    if not output_dir.exists():
        return removed
    for path in output_dir.iterdir():
        if path.is_file() and path.name.startswith("_") and path.name not in expected_outputs:
            path.unlink()
            removed.append(path.name)
    return removed


def stamp_content(generated: list[GeneratedCompletion], removed: list[str]) -> str:
    digest = hashlib.sha256()
    for item in sorted(generated, key=lambda entry: entry.spec.output):
        digest.update(item.spec.output.encode())
        digest.update(b"\0")
        digest.update(item.content.encode())
        digest.update(b"\0")
    generated_names = ", ".join(sorted(item.spec.output for item in generated)) or "none"
    removed_names = ", ".join(sorted(removed)) or "none"
    return (
        "# Generated by scripts/generate/generate_tool_completions.py; "
        "edit scripts/generate/tool-completions.toml instead.\n"
        f"digest={digest.hexdigest()}\n"
        f"generated={generated_names}\n"
        f"pruned={removed_names}\n"
    )


def validate_zsh_files(config: ZshConfig, generated: list[GeneratedCompletion]) -> None:
    zsh = shutil.which("zsh")
    if zsh is None or not generated:
        return

    for item in generated:
        path = config.output_dir / item.spec.output
        proc = subprocess.run([zsh, "-n", str(path)], text=True, capture_output=True, check=False)
        if proc.returncode != 0:
            detail = proc.stderr.strip() or proc.stdout.strip() or f"exit {proc.returncode}"
            raise CompletionError(f"{item.spec.output}: zsh syntax validation failed: {detail}")

    checks: list[tuple[str, str]] = []
    for item in generated:
        function_name = item.spec.output
        checks.extend((command, function_name) for command in item.spec.provides)
    if not checks:
        return

    check_lines = [
        f"fpath=({zsh_quote(str(config.output_dir))} $fpath)",
        "autoload -Uz compinit",
        "compinit -D",
        "ret=0",
    ]
    for command, function_name in checks:
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", command):
            raise CompletionError(f"unsafe zsh command name in manifest: {command}")
        check_lines.append(f"actual=${{_comps[{command}]-}}")
        check_lines.append(
            f"if [[ $actual != {zsh_quote(function_name)} ]]; then "
            f"print -u2 -- {zsh_quote(f'{command}: expected {function_name}, got ')}$actual; ret=1; fi"
        )
    check_lines.append("exit $ret")
    proc = subprocess.run([zsh, "-dfc", "\n".join(check_lines)], text=True, capture_output=True, check=False)
    if proc.returncode != 0:
        detail = proc.stderr.strip() or proc.stdout.strip() or f"exit {proc.returncode}"
        raise CompletionError(f"zsh compinit map validation failed: {detail}")


def zsh_quote(value: str) -> str:
    return "'" + value.replace("'", "'\\''") + "'"


def dry_run(config: ZshConfig, specs: list[ZshCompletion]) -> None:
    print(f"Autogen zsh completions: {config.output_dir}")
    expected: set[str] = set()
    for spec in specs:
        if command_available(spec):
            expected.add(spec.output)
            print(f"generate {spec.output}: {' '.join(spec.argv)}")
        else:
            print(f"skip {spec.output}: {spec.binary} not found on PATH")
    if config.prune and config.output_dir.exists():
        stale = sorted(
            path.name
            for path in config.output_dir.iterdir()
            if path.is_file() and path.name.startswith("_") and path.name not in expected
        )
        for name in stale:
            print(f"prune {name}: not generated by current manifest/PATH")


def generate(config: ZshConfig, specs: list[ZshCompletion], repo_root: Path, *, validate: bool) -> None:
    config.output_dir.mkdir(parents=True, exist_ok=True)
    generated: list[GeneratedCompletion] = []
    skipped: list[str] = []
    for spec in specs:
        if not command_available(spec):
            skipped.append(spec.output)
            continue
        generated.append(generate_completion(spec, repo_root))

    for item in generated:
        write_if_changed(config.output_dir / item.spec.output, item.content)

    expected_outputs = {item.spec.output for item in generated}
    removed = prune_stale_outputs(config.output_dir, expected_outputs) if config.prune else []
    write_if_changed(config.output_dir / config.stamp_name, stamp_content(generated, removed))

    if validate and config.validate:
        validate_zsh_files(config, generated)

    for item in generated:
        print(f"generated {item.spec.output}: {', '.join(item.spec.provides)}")
    for output in sorted(skipped):
        print(f"skipped {output}: binary not found")
    for output in sorted(removed):
        print(f"pruned {output}")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--no-validate", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    repo_root = args.repo_root.resolve()
    manifest_path = args.manifest if args.manifest.is_absolute() else repo_root / args.manifest
    try:
        manifest = load_manifest(manifest_path)
        config = zsh_config(manifest, repo_root)
        specs = zsh_completions(manifest)
        if args.dry_run:
            dry_run(config, specs)
        else:
            generate(config, specs, repo_root, validate=not args.no_validate)
    except CompletionError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
