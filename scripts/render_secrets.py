#!/usr/bin/env python3
from __future__ import annotations

import argparse
import difflib
import getpass
import json
import os
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from cli_ui import bullet, section, status

DEFAULT_TEMPLATE_RELATIVE_PATH = Path("home/.config/ooodnakov/secrets/env.template")
DEFAULT_CONFIG_RELATIVE_PATH = Path(".config/ooodnakov")
DEFAULT_LOCAL_RELATIVE_PATH = Path(".config/ooodnakov/local")
DEFAULT_BW_SESSION_RELATIVE_PATH = DEFAULT_LOCAL_RELATIVE_PATH / "bw-session"
DEFAULT_BW_SERVER = os.environ.get("OOODNAKOV_BW_SERVER", "https://vaultwarden.ooodnakov.ru")
BWH_CLI_TIMEOUT_SECONDS = 20
SECRETS_SUBCOMMANDS = ("sync", "doctor", "login", "unlock", "list", "status", "logout", "add", "remove")
SECRETS_SUBCOMMAND_ALIASES = {
    "ls": "list",
    "rm": "remove",
    "del": "remove",
}


def shutil_which(name: str) -> str | None:
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        if not directory:
            continue
        candidate = Path(directory) / name
        if candidate.exists() and os.access(candidate, os.X_OK):
            return str(candidate)
        if os.name == "nt":
            candidate_exe = Path(directory) / f"{name}.exe"
            if candidate_exe.exists() and os.access(candidate_exe, os.X_OK):
                return str(candidate_exe)
    return None


@dataclass
class SecretEntry:
    key: str
    value: str
    line_number: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="oooconf secrets",
        description="Render local shell env files from a tracked secrets template.",
    )
    parser.add_argument(
        "--repo-root",
        default=os.environ.get("OOODNAKOV_REPO_ROOT"),
        help="Repo root that contains the tracked secrets template.",
    )

    subparsers = parser.add_subparsers(dest="command", required=False)

    sync = subparsers.add_parser("sync", help="Render local secret env files.")
    sync.add_argument(
        "--backend",
        default=os.environ.get("OOODNAKOV_SECRETS_BACKEND", "bw"),
        choices=("bw",),
        help="Secret backend to resolve reference values.",
    )
    sync.add_argument(
        "--template",
        help="Override the tracked template path.",
    )
    sync.add_argument(
        "--force",
        action="store_true",
        help="Rewrite generated files even when the content is unchanged.",
    )
    sync.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview the sync without writing files.",
    )

    doctor = subparsers.add_parser("doctor", help="Check secret sync prerequisites.")
    doctor.add_argument(
        "--backend",
        default=os.environ.get("OOODNAKOV_SECRETS_BACKEND", "bw"),
        choices=("bw",),
        help="Secret backend to check.",
    )
    doctor.add_argument(
        "--template",
        help="Override the tracked template path.",
    )

    login = subparsers.add_parser("login", help="Configure Bitwarden server and start login.")
    login.add_argument(
        "--server",
        default=DEFAULT_BW_SERVER,
        help="Bitwarden or Vaultwarden server URL.",
    )

    unlock = subparsers.add_parser("unlock", help="Unlock Bitwarden and print or persist BW_SESSION.")
    unlock.add_argument(
        "password",
        nargs="?",
        help="Optional Bitwarden password. When provided, save the unlocked session locally for later syncs.",
    )
    unlock.add_argument(
        "--shell",
        choices=("sh", "zsh", "bash", "pwsh"),
        default=detect_shell_kind(),
        help="Shell syntax to emit.",
    )
    unlock.add_argument(
        "--raw",
        action="store_true",
        help="Print only the unlocked session token.",
    )

    list_parser = subparsers.add_parser("list", help="List secrets from the tracked template.")
    list_parser.add_argument(
        "--template",
        help="Override the tracked template path.",
    )
    list_parser.add_argument(
        "--resolved",
        action="store_true",
        help="Resolve bw:// references (requires unlocked BW_SESSION).",
    )
    list_parser.add_argument(
        "--backend",
        default=os.environ.get("OOODNAKOV_SECRETS_BACKEND", "bw"),
        choices=("bw",),
        help="Secret backend for --resolved.",
    )

    status_parser = subparsers.add_parser("status", help="Show sync status of local secret env files.")
    status_parser.add_argument(
        "--template",
        help="Override the tracked template path.",
    )

    subparsers.add_parser("logout", help="Lock vault and revoke Bitwarden session.")

    add_parser = subparsers.add_parser("add", help="Add a secret entry to the tracked template.")
    add_parser.add_argument("key", help="Environment variable name (e.g. GITHUB_TOKEN).")
    add_parser.add_argument("value", help="Plain value or bw://item/<id>/selector reference.")
    add_parser.add_argument(
        "--template",
        help="Override the tracked template path.",
    )

    remove_parser = subparsers.add_parser("remove", help="Remove a secret entry from the tracked template.")
    remove_parser.add_argument("key", help="Environment variable name to remove.")
    remove_parser.add_argument(
        "--template",
        help="Override the tracked template path.",
    )

    argv = sys.argv[1:]
    normalized_argv, requested_command = normalize_subcommand_argv(argv)
    if (
        requested_command
        and requested_command not in SECRETS_SUBCOMMANDS
        and requested_command not in SECRETS_SUBCOMMAND_ALIASES
    ):
        suggestion = suggest_subcommand(requested_command)
        if suggestion:
            parser.error(f"unknown command: {requested_command}\nDid you mean: {suggestion}")
        parser.error(f"unknown command: {requested_command}")

    args = parser.parse_args(normalized_argv)
    if args.command is None:
        args.command = "status"
        args.template = None
    if args.command == "unlock":
        args.explicit_shell = "--shell" in argv
        args.explicit_raw = "--raw" in argv
    return args


def normalize_subcommand_argv(argv: list[str]) -> tuple[list[str], str | None]:
    normalized = list(argv)
    index = 0
    while index < len(normalized):
        arg = normalized[index]
        if arg == "--repo-root":
            index += 2
            continue
        if arg.startswith("-"):
            index += 1
            continue
        normalized[index] = SECRETS_SUBCOMMAND_ALIASES.get(arg, arg)
        return normalized, arg
    return normalized, None


def suggest_subcommand(command: str) -> str | None:
    candidates = list(SECRETS_SUBCOMMANDS) + list(SECRETS_SUBCOMMAND_ALIASES)
    matches = difflib.get_close_matches(command, candidates, n=1, cutoff=0.6)
    if matches:
        return SECRETS_SUBCOMMAND_ALIASES.get(matches[0], matches[0])
    return None


def detect_shell_kind() -> str:
    shell = os.environ.get("SHELL", "")
    shell_name = Path(shell).name.lower()
    if shell_name in {"bash", "zsh"}:
        return shell_name
    if "pwsh" in shell_name or "powershell" in shell_name:
        return "pwsh"
    return "sh"


def resolve_repo_root(repo_root: str | None) -> Path:
    if repo_root:
        return Path(repo_root).expanduser().resolve()
    return Path(__file__).resolve().parent.parent


def resolve_template_path(repo_root: Path, template_override: str | None) -> Path:
    if template_override:
        return Path(template_override).expanduser().resolve()
    return (repo_root / DEFAULT_TEMPLATE_RELATIVE_PATH).resolve()


def parse_template(template_path: Path) -> list[SecretEntry]:
    entries: list[SecretEntry] = []
    for line_number, raw_line in enumerate(template_path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"{template_path}:{line_number}: expected KEY=VALUE")
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            raise ValueError(f"{template_path}:{line_number}: missing variable name")
        entries.append(SecretEntry(key=key, value=strip_matching_quotes(value), line_number=line_number))
    return entries


def strip_matching_quotes(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value


def resolve_value(entry: SecretEntry, backend: str, cache: dict[str, dict] | None = None) -> str:
    if entry.value.startswith("bw://"):
        if backend != "bw":
            raise ValueError(f"unsupported backend for secret reference: {backend}")
        return read_bw_secret(entry.value, entry.key, cache)
    return entry.value


def read_bw_secret(reference: str, key: str, cache: dict[str, dict] | None = None) -> str:
    item_id, selector = parse_bw_reference(reference)
    item = read_bw_item(item_id, key, cache)
    return select_bw_value(item, selector, key)


def parse_bw_reference(reference: str) -> tuple[str, str]:
    prefix = "bw://item/"
    if not reference.startswith(prefix):
        raise ValueError(
            f"unsupported Bitwarden reference: {reference}. "
            "Use bw://item/<item-id>/(password|username|notes|uri|field/<field-name>)."
        )

    remainder = reference[len(prefix) :]
    parts = [part for part in remainder.split("/") if part]
    if len(parts) < 2:
        raise ValueError(f"invalid Bitwarden reference: {reference}. Expected bw://item/<item-id>/<selector>.")

    item_id = parts[0]
    if parts[1] == "field":
        if len(parts) < 3:
            raise ValueError(
                f"invalid Bitwarden field reference: {reference}. Expected bw://item/<item-id>/field/<field-name>."
            )
        selector = "field/" + "/".join(parts[2:])
    else:
        selector = parts[1]

    return item_id, selector


def ensure_bw_unlocked(env: dict) -> None:
    """Auto-login and unlock if BW_PASSWORD/BW_CLIENTID/BW_CLIENTSECRET are available."""
    bw_password = env.get("BW_PASSWORD")
    bw_clientid = env.get("BW_CLIENTID")
    bw_clientsecret = env.get("BW_CLIENTSECRET")

    if bw_password and bw_clientid and bw_clientsecret:
        if shutil_which("bw") is None:
            raise RuntimeError("Bitwarden CLI (`bw`) is not installed or not on PATH.")
        try:
            result = subprocess.run(
                ["bw", "unlock", "--raw", "--passwordenv", "BW_PASSWORD"],
                check=True,
                capture_output=True,
                text=True,
                encoding="utf-8",
                env=env,
                timeout=BWH_CLI_TIMEOUT_SECONDS,
            )
            token = result.stdout.strip()
            if token:
                env["BW_SESSION"] = token
                return
        except subprocess.CalledProcessError:
            pass  # fall through to manual error
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError(
                f"`bw unlock` timed out after {BWH_CLI_TIMEOUT_SECONDS}s. "
                "Check Bitwarden connectivity and CLI auth state."
            ) from exc

    raise RuntimeError(
        'BW_SESSION is not set. Unlock Bitwarden first, for example with `export BW_SESSION="$(bw unlock --raw)"` '
        "or the PowerShell equivalent. "
        "Alternatively, set BW_CLIENTID, BW_CLIENTSECRET, and BW_PASSWORD for auto-unlock."
    )


def _get_session_env() -> dict:
    """Return a copy of os.environ with BW_SESSION set if available."""
    env = os.environ.copy()
    session = env.get("BW_SESSION") or read_persisted_bw_session()
    if session:
        env["BW_SESSION"] = session
    return env


def _ensure_session_available(env: dict) -> None:
    """Ensure BW_SESSION is set in env, auto-unlocking if needed."""
    if not env.get("BW_SESSION"):
        ensure_bw_unlocked(env)
        if not env.get("BW_SESSION"):
            raise RuntimeError("Failed to auto-unlock vault. Check BW_CLIENTID/BW_CLIENTSECRET/BW_PASSWORD.")


def get_bw_status(env: dict | None = None) -> dict:
    """Return parsed `bw status` output using the provided session-aware env."""
    status_env = env.copy() if env is not None else _get_session_env()
    try:
        status_result = subprocess.run(
            ["bw", "status"],
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            env=status_env,
            timeout=BWH_CLI_TIMEOUT_SECONDS,
        )
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip()
        raise RuntimeError(stderr or "`bw status` failed") from exc
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"`bw status` timed out after {BWH_CLI_TIMEOUT_SECONDS}s") from exc

    try:
        return json.loads(status_result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError("`bw status` did not return valid JSON") from exc


def sync_bw_vault(env: dict) -> None:
    """Refresh the Bitwarden CLI cache before resolving secrets."""
    command = ["bw", "sync", "--session", env["BW_SESSION"]]
    try:
        subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            env=env,
            timeout=BWH_CLI_TIMEOUT_SECONDS,
        )
    except FileNotFoundError as exc:
        raise RuntimeError("Bitwarden CLI (`bw`) is not installed or not on PATH.") from exc
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"`bw sync` timed out after {BWH_CLI_TIMEOUT_SECONDS}s") from exc
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip()
        message = stderr or f"`{' '.join(command)}` failed"
        raise RuntimeError(f"failed to sync Bitwarden vault: {message}") from exc


def fetch_all_bw_items() -> list[dict]:
    """Fetch all Bitwarden items in a single call and return parsed JSON list."""
    env = _get_session_env()
    _ensure_session_available(env)
    sync_bw_vault(env)
    command = ["bw", "list", "items", "--session", env["BW_SESSION"]]
    try:
        result = subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            env=env,
            timeout=BWH_CLI_TIMEOUT_SECONDS,
        )
    except FileNotFoundError as exc:
        raise RuntimeError("Bitwarden CLI (`bw`) is not installed or not on PATH.") from exc
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"timed out fetching Bitwarden items after {BWH_CLI_TIMEOUT_SECONDS}s") from exc
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip()
        message = stderr or f"`{' '.join(command)}` failed"
        raise RuntimeError(f"failed to fetch Bitwarden items: {message}") from exc

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError("Bitwarden returned invalid JSON for items list.") from exc


def build_item_cache(item_ids: set[str]) -> dict[str, dict]:
    """Build a lookup dict for the requested item IDs, using batch fetch when possible."""
    cache: dict[str, dict] = {}
    if not item_ids:
        return cache

    all_items = fetch_all_bw_items()
    for item in all_items:
        item_id = item.get("id")
        if item_id in item_ids:
            cache[item_id] = item
    return cache


def format_missing_bw_references(
    missing_item_ids: set[str],
    references_by_item_id: dict[str, list[str]],
) -> str:
    lines = [
        "Bitwarden items referenced by the tracked template were not found in the current vault:",
    ]
    for item_id in sorted(missing_item_ids):
        keys = ", ".join(sorted(references_by_item_id.get(item_id, []))) or "<unknown>"
        lines.append(f"  - {keys}: {item_id}")
    lines.append("Update the `bw://item/...` references in the template or log into the intended vault.")
    return "\n".join(lines)


def read_bw_item(item_id: str, key: str, cache: dict[str, dict] | None = None) -> dict:
    if cache is not None and item_id in cache:
        return cache[item_id]

    # Fallback: individual fetch (for callers outside sync context)
    env = _get_session_env()
    _ensure_session_available(env)
    sync_bw_vault(env)
    command = ["bw", "get", "item", item_id, "--session", env["BW_SESSION"]]
    try:
        result = subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            env=env,
            timeout=BWH_CLI_TIMEOUT_SECONDS,
        )
    except FileNotFoundError as exc:
        raise RuntimeError("Bitwarden CLI (`bw`) is not installed or not on PATH.") from exc
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(
            f"timed out resolving {key} from Bitwarden after {BWH_CLI_TIMEOUT_SECONDS}s (item {item_id})"
        ) from exc
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip()
        message = stderr or f"`{' '.join(command)}` failed"
        raise RuntimeError(f"failed to resolve {key} from Bitwarden: {message}") from exc

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Bitwarden returned invalid JSON for {key}.") from exc


def select_bw_value(item: dict, selector: str, key: str) -> str:
    if selector == "password":
        value = (item.get("login") or {}).get("password")
    elif selector == "username":
        value = (item.get("login") or {}).get("username")
    elif selector == "notes":
        value = item.get("notes")
    elif selector == "uri":
        uris = ((item.get("login") or {}).get("uris")) or []
        value = uris[0].get("uri") if uris else None
    elif selector.startswith("field/"):
        field_name = selector.split("/", 1)[1]
        value = None
        for field in item.get("fields") or []:
            if field.get("name") == field_name:
                value = field.get("value")
                break
    else:
        raise ValueError(
            f"unsupported Bitwarden selector for {key}: {selector}. "
            "Use password, username, notes, uri, or field/<field-name>."
        )

    if value is None:
        raise RuntimeError(f"Bitwarden item does not contain `{selector}` for {key}.")
    return str(value)


def shell_assignment(key: str, value: str) -> str:
    return f"export {key}={shlex.quote(value)}"


def powershell_assignment(key: str, value: str) -> str:
    if "\n" in value:
        return f"$env:{key} = @'\n{value}\n'@"
    escaped = value.replace("'", "''")
    return f"$env:{key} = '{escaped}'"


LOCAL_OVERRIDES_START = "# --- LOCAL OVERRIDES START ---"
LOCAL_OVERRIDES_END = "# --- LOCAL OVERRIDES END ---"
_LOCAL_DEFAULT_COMMENT = "# Add machine-specific env vars here. This section is preserved across syncs."


def extract_local_overrides(content: str) -> list[str]:
    """Extract user lines between LOCAL_OVERRIDES markers (exclusive)."""
    start = content.find(LOCAL_OVERRIDES_START)
    if start == -1:
        return []
    end = content.find(LOCAL_OVERRIDES_END, start)
    if end == -1:
        return []
    block_start = start + len(LOCAL_OVERRIDES_START)
    block = content[block_start:end].strip()
    if not block:
        return []
    # Filter out the default comment — only keep user-added lines.
    return [line for line in block.splitlines() if line != _LOCAL_DEFAULT_COMMENT]


def render_zsh(resolved_entries: list[tuple[str, str]], backend: str, template_path: Path) -> str:
    lines = [
        "# Generated by `oooconf secrets sync`.",
        "# Do not commit plaintext secrets. Update the tracked template instead.",
        f"# Source template: {template_path}",
        f"# Backend: {backend}",
        "",
    ]
    for key, value in resolved_entries:
        lines.append(shell_assignment(key, value))
    lines.append("")
    return "\n".join(lines)


def render_ps1(resolved_entries: list[tuple[str, str]], backend: str, template_path: Path) -> str:
    lines = [
        "# Generated by `oooconf secrets sync`.",
        "# Do not commit plaintext secrets. Update the tracked template instead.",
        f"# Source template: {template_path}",
        f"# Backend: {backend}",
        "",
    ]
    for key, value in resolved_entries:
        lines.append(powershell_assignment(key, value))
    lines.append("")
    return "\n".join(lines)


def resolve_entries_for_sync(entries: list[SecretEntry], backend: str) -> list[tuple[str, str]]:
    # Pre-fetch all needed Bitwarden items in a single batch call.
    cache: dict[str, dict] = {}
    if backend == "bw":
        item_ids = set()
        references_by_item_id: dict[str, list[str]] = {}
        for entry in entries:
            if entry.value.startswith("bw://"):
                try:
                    item_id, _ = parse_bw_reference(entry.value)
                    item_ids.add(item_id)
                    references_by_item_id.setdefault(item_id, []).append(entry.key)
                except (ValueError, RuntimeError):
                    pass  # will error during resolution with proper context
        if item_ids:
            total_ids = len(item_ids)
            print(f"Fetching {total_ids} Bitwarden item(s) in batch...", flush=True)
            cache = build_item_cache(item_ids)
            missing_item_ids = item_ids - set(cache.keys())
            if missing_item_ids:
                raise RuntimeError(format_missing_bw_references(missing_item_ids, references_by_item_id))

    resolved_entries: list[tuple[str, str]] = []
    total = len(entries)
    for index, entry in enumerate(entries, start=1):
        print(f"Resolving {index}/{total}: {entry.key}", flush=True)
        resolved_entries.append((entry.key, resolve_value(entry, backend, cache)))
    return resolved_entries


def ensure_private_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    if os.name != "nt":
        path.chmod(0o700)


def session_file_path() -> Path:
    return Path.home() / DEFAULT_BW_SESSION_RELATIVE_PATH


def read_persisted_bw_session() -> str | None:
    path = session_file_path()
    if not path.exists():
        return None
    token = path.read_text(encoding="utf-8").strip()
    return token or None


def write_persisted_bw_session(token: str) -> Path:
    path = session_file_path()
    ensure_private_directory(path.parent)
    path.write_text(token + "\n", encoding="utf-8")
    if os.name != "nt":
        path.chmod(0o600)
    return path


def clear_persisted_bw_session() -> None:
    path = session_file_path()
    if path.exists():
        path.unlink()


def write_file(path: Path, content: str, force: bool) -> str:
    created = not path.exists()
    path.parent.mkdir(parents=True, exist_ok=True)

    if not created:
        existing = path.read_text(encoding="utf-8")
        overrides = extract_local_overrides(existing)
        # Append LOCAL OVERRIDES section
        content += LOCAL_OVERRIDES_START + "\n"
        content += "# Add machine-specific env vars here. This section is preserved across syncs.\n"
        for line in overrides:
            content += line + "\n"
        content += LOCAL_OVERRIDES_END + "\n"
        if existing == content and not force:
            return "unchanged"
    else:
        content += LOCAL_OVERRIDES_START + "\n"
        content += "# Add machine-specific env vars here. This section is preserved across syncs.\n"
        content += LOCAL_OVERRIDES_END + "\n"
    path.write_text(content, encoding="utf-8")
    if os.name != "nt":
        path.chmod(0o600)
    return "created" if created else "updated"


def sync_command(args: argparse.Namespace, repo_root: Path) -> int:
    template_path = resolve_template_path(repo_root, args.template)
    if not template_path.is_file():
        status("fail", f"Template not found: {template_path}")
        return 1

    entries = parse_template(template_path)
    home = Path.home()
    local_root = home / DEFAULT_LOCAL_RELATIVE_PATH
    zsh_path = local_root / "env.zsh"
    ps1_path = local_root / "env.ps1"

    section("Secrets Sync")
    status("info", f"Template: {template_path}")
    status("info", f"Backend: {args.backend}")
    status("info", f"Targets: {zsh_path}, {ps1_path}")

    resolved_entries = resolve_entries_for_sync(entries, args.backend)
    zsh_content = render_zsh(resolved_entries, args.backend, template_path)
    ps1_content = render_ps1(resolved_entries, args.backend, template_path)

    if args.dry_run:
        bullet(f"Would render {zsh_path}")
        bullet(f"Would render {ps1_path}")
        status("ok", "Dry run complete.")
        return 0

    ensure_private_directory(local_root)
    zsh_status = write_file(zsh_path, zsh_content, args.force)
    ps1_status = write_file(ps1_path, ps1_content, args.force)
    status("ok", f"{zsh_status}: {zsh_path}")
    status("ok", f"{ps1_status}: {ps1_path}")
    status("ok", "Secrets sync complete.")
    return 0


def doctor_command(args: argparse.Namespace, repo_root: Path) -> int:
    template_path = resolve_template_path(repo_root, args.template)
    problems: list[str] = []

    if not template_path.is_file():
        problems.append(f"missing tracked template: {template_path}")

    tracked_local_paths = [
        repo_root / "home/.config/ooodnakov/local/env.zsh",
        repo_root / "home/.config/ooodnakov/local/env.ps1",
    ]
    for tracked_path in tracked_local_paths:
        if tracked_path.exists():
            problems.append(f"plaintext local env file is present in the repo tree: {tracked_path}")

    if args.backend == "bw":
        if shutil_which("bw") is None:
            problems.append("Bitwarden CLI `bw` is not installed or not on PATH")
        else:
            problems.extend(check_bw_status())

    local_root = Path.home() / DEFAULT_LOCAL_RELATIVE_PATH
    for local_path in (local_root / "env.zsh", local_root / "env.ps1"):
        if not local_path.exists():
            problems.append(f"local rendered env file is missing: {local_path}")

    if problems:
        for problem in problems:
            status("fail", problem)
        return 1

    section("Secrets Doctor")
    status("ok", "Secrets doctor passed.")
    status("info", f"Template: {template_path}")
    status("info", f"Backend: {args.backend}")
    return 0


def login_command(args: argparse.Namespace) -> int:
    if shutil_which("bw") is None:
        status("fail", "Bitwarden CLI (`bw`) is not installed or not on PATH.")
        return 1

    server = args.server.rstrip("/")
    config_result = subprocess.run(["bw", "config", "server", server], text=True)
    if config_result.returncode != 0:
        return config_result.returncode

    env = os.environ.copy()
    if env.get("BW_CLIENTID") and env.get("BW_CLIENTSECRET"):
        status("info", "Detected BW_CLIENTID and BW_CLIENTSECRET. Attempting API key login...")
        login_result = subprocess.run(["bw", "login", "--apikey"], env=env, text=True)
    else:
        login_result = subprocess.run(["bw", "login"], text=True)

    return login_result.returncode


def unlock_command(args: argparse.Namespace) -> int:
    if shutil_which("bw") is None:
        status("fail", "Bitwarden CLI (`bw`) is not installed or not on PATH.")
        return 1

    env = os.environ.copy()
    should_persist = bool(args.password) or (not args.explicit_shell and not args.explicit_raw)
    if should_persist:
        password = args.password
        if password is None:
            try:
                password = getpass.getpass("Bitwarden password: ")
            except (EOFError, KeyboardInterrupt):
                status("warn", "Unlock cancelled.")
                return 1
        env["BW_PASSWORD"] = password
        command = ["bw", "unlock", "--raw", "--passwordenv", "BW_PASSWORD"]
    else:
        command = ["bw", "unlock", "--raw"]

    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            encoding="utf-8",
            env=env,
            timeout=BWH_CLI_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        status("fail", f"`bw unlock` timed out after {BWH_CLI_TIMEOUT_SECONDS}s.")
        return 1
    if result.returncode != 0:
        stderr = result.stderr.strip()
        if stderr:
            status("fail", stderr)
        return result.returncode

    token = result.stdout.strip()
    if not token:
        status("fail", "`bw unlock --raw` returned an empty session token.")
        return 1

    if should_persist:
        path = write_persisted_bw_session(token)
        status("ok", f"Saved BW_SESSION to {path}")
        return 0

    if args.raw:
        print(token)
        return 0

    if args.shell == "pwsh":
        escaped = token.replace("'", "''")
        print(f"$env:BW_SESSION = '{escaped}'")
    else:
        print(f"export BW_SESSION={shlex.quote(token)}")
    return 0


def check_bw_status() -> list[str]:
    problems: list[str] = []
    try:
        status = get_bw_status()
    except RuntimeError as exc:
        problems.append(str(exc))
        return problems

    current_server = (status.get("serverUrl") or "").rstrip("/")
    expected_server = DEFAULT_BW_SERVER.rstrip("/")
    if current_server and current_server != expected_server:
        problems.append(
            f"Bitwarden CLI is pointed at {current_server}, expected {expected_server}. "
            "Run `bw config server https://vaultwarden.ooodnakov.ru` if needed."
        )

    status_value = status.get("status")
    session_available = bool(os.environ.get("BW_SESSION") or read_persisted_bw_session())
    if status_value == "unauthenticated":
        problems.append("Bitwarden CLI is not logged in. Run `bw login`.")
    elif status_value == "locked" and not session_available:
        problems.append("Bitwarden vault is locked. Unlock it before syncing.")
    elif status_value == "unlocked" and not session_available:
        problems.append("Bitwarden reports unlocked, but no BW_SESSION is available. Run `oooconf secrets unlock`.")

    return problems


def list_command(args: argparse.Namespace, repo_root: Path) -> int:
    template_path = resolve_template_path(repo_root, args.template)
    if not template_path.is_file():
        status("fail", f"Template not found: {template_path}")
        return 1

    entries = parse_template(template_path)
    if not entries:
        status("info", "No secrets defined in template.")
        return 0

    section("Secrets List")
    status("info", f"Template: {template_path}")
    print()

    for entry in entries:
        is_bw_ref = entry.value.startswith("bw://")
        if args.resolved and is_bw_ref:
            try:
                resolved = resolve_value(entry, args.backend)
                masked = "*" * min(len(resolved), 12)
                print(f"{entry.key}={masked}  (resolved)")
            except (RuntimeError, ValueError) as exc:
                print(f"{entry.key}=<error>  ({exc})")
        elif is_bw_ref:
            print(f"{entry.key}={entry.value}")
        else:
            print(f"{entry.key}={entry.value}")

    return 0


def status_command(args: argparse.Namespace, repo_root: Path) -> int:
    template_path = resolve_template_path(repo_root, args.template)
    home = Path.home()
    local_root = home / DEFAULT_LOCAL_RELATIVE_PATH
    zsh_path = local_root / "env.zsh"
    ps1_path = local_root / "env.ps1"

    if not template_path.is_file():
        status("fail", f"Template not found: {template_path}")
        return 1

    template_mtime = template_path.stat().st_mtime
    problems: list[str] = []

    section("Secrets Status")
    status("info", f"Template: {template_path}")
    status("info", f"Backend: {os.environ.get('OOODNAKOV_SECRETS_BACKEND', 'bw')}")
    print()

    for local_path in (zsh_path, ps1_path):
        if not local_path.exists():
            status("fail", f"{local_path}: missing")
            problems.append(f"{local_path.name} is not synced")
        else:
            local_mtime = local_path.stat().st_mtime
            if local_mtime < template_mtime:
                status("warn", f"{local_path}: stale (template updated after last sync)")
                problems.append(f"{local_path.name} is stale")
            else:
                status("ok", f"{local_path}: up to date")

    session_available = bool(os.environ.get("BW_SESSION") or read_persisted_bw_session())
    if session_available:
        if shutil_which("bw"):
            try:
                vault_state = get_bw_status()
                vault_status = vault_state.get("status", "unknown")
                status("info", f"Vault status: {vault_status}")
                if vault_status == "locked":
                    problems.append("Vault is locked, BW_SESSION may be expired")
            except RuntimeError as exc:
                status("fail", f"Vault status: error checking ({exc})")
        else:
            status("warn", "Vault status: bw CLI not found")
    else:
        status("warn", "Vault status: no BW_SESSION available")

    print()
    if problems:
        section("Issues")
        for problem in problems:
            bullet(problem)
        return 1

    if session_available:
        status("ok", "All synced and unlocked.")
    else:
        status("ok", "Local env files are synced.")
    return 0


def logout_command() -> int:
    if shutil_which("bw") is None:
        status("fail", "Bitwarden CLI (`bw`) is not installed or not on PATH.")
        return 1

    lock_result = subprocess.run(["bw", "lock"], text=True)
    if lock_result.returncode != 0:
        return lock_result.returncode

    logout_result = subprocess.run(["bw", "logout"], text=True)
    clear_persisted_bw_session()
    return logout_result.returncode


def add_command(args: argparse.Namespace, repo_root: Path) -> int:
    import re

    if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", args.key):
        status("fail", f"Invalid key name: {args.key}. Use UPPER_SNAKE_CASE letters.")
        return 1

    template_path = resolve_template_path(repo_root, args.template)
    if not template_path.is_file():
        status("fail", f"Template not found: {template_path}")
        return 1

    lines = template_path.read_text(encoding="utf-8").splitlines()
    # Check for duplicate
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("#") or not stripped:
            continue
        if "=" in stripped and stripped.split("=", 1)[0].strip() == args.key:
            status("fail", f"Key already exists in template: {args.key}")
            return 1

    # Insert after header comments, before first non-comment entry (or at end)
    insert_at = 0
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("#") or not stripped:
            insert_at = i + 1
        else:
            break

    lines.insert(insert_at, f"{args.key}={args.value}")
    template_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    status("ok", f"Added {args.key}={args.value}")
    status("info", f"Template: {template_path}")
    return 0


def remove_command(args: argparse.Namespace, repo_root: Path) -> int:
    template_path = resolve_template_path(repo_root, args.template)
    if not template_path.is_file():
        status("fail", f"Template not found: {template_path}")
        return 1

    lines = template_path.read_text(encoding="utf-8").splitlines()
    found = False
    new_lines = []
    for line in lines:
        stripped = line.strip()
        if "=" in stripped and stripped.split("=", 1)[0].strip() == args.key:
            found = True
            continue
        new_lines.append(line)

    if not found:
        status("fail", f"Key not found in template: {args.key}")
        return 1

    template_path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
    status("ok", f"Removed {args.key}")
    status("info", f"Template: {template_path}")
    return 0


def main() -> int:
    args = parse_args()
    repo_root = resolve_repo_root(args.repo_root)

    try:
        if args.command == "sync":
            return sync_command(args, repo_root)
        if args.command == "doctor":
            return doctor_command(args, repo_root)
        if args.command == "login":
            return login_command(args)
        if args.command == "unlock":
            return unlock_command(args)
        if args.command == "list":
            return list_command(args, repo_root)
        if args.command == "status":
            return status_command(args, repo_root)
        if args.command == "logout":
            return logout_command()
        if args.command == "add":
            return add_command(args, repo_root)
        if args.command == "remove":
            return remove_command(args, repo_root)
        raise ValueError(f"unsupported command: {args.command}")
    except (RuntimeError, ValueError) as exc:
        status("fail", str(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
