#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import difflib
import getpass
import os
import shlex
import sys
from dataclasses import dataclass
from pathlib import Path

SCRIPTS_CLI_DIR = Path(__file__).resolve().parents[1] / "cli"
if str(SCRIPTS_CLI_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_CLI_DIR))

import bitwarden_cli as bw_cli  # noqa: E402
from cli_ui import bullet, section, spacer, status  # noqa: E402
from cli_ui import path as ui_path  # noqa: E402
from private_files import ensure_private_directory, write_private_atomic  # noqa: E402

DEFAULT_TEMPLATE_RELATIVE_PATH = Path("home/.config/ooodnakov/secrets/env.template")
DEFAULT_CONFIG_RELATIVE_PATH = Path(".config/ooodnakov")
DEFAULT_LOCAL_RELATIVE_PATH = Path(".config/ooodnakov/local")


def _xdg_data_home() -> Path:
    if os.name == "nt":
        return Path.home() / ".local/share"
    xdg_data = os.environ.get("XDG_DATA_HOME", "").strip()
    return Path(xdg_data).expanduser() if xdg_data else Path.home() / ".local/share"


def _read_first_config_line(path: Path) -> str:
    if not path.is_file():
        return ""
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line and not line.startswith("#"):
            return line
    return ""


def resolve_default_bw_server() -> str:
    """Resolve Bitwarden/Vaultwarden server URL from env, data-home, local file, or empty string."""
    env_server = os.environ.get("OOODNAKOV_BW_SERVER", "").strip()
    if env_server:
        return env_server

    candidates = (
        _xdg_data_home() / "ooodnakov-config" / "bw-server",
        Path.home() / DEFAULT_LOCAL_RELATIVE_PATH / "bw-server",
    )
    for candidate in candidates:
        value = _read_first_config_line(candidate)
        if value:
            return value

    return ""


DEFAULT_BW_SERVER = resolve_default_bw_server()
SECRETS_SUBCOMMANDS = ("sync", "doctor", "login", "unlock", "list", "status", "logout", "add", "remove")
SECRETS_SUBCOMMAND_ALIASES = {
    "ls": "list",
    "rm": "remove",
    "del": "remove",
}


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
        default=resolve_default_bw_server(),
        help="Bitwarden or Vaultwarden server URL.",
    )
    login.add_argument(
        "--method",
        choices=("auto", "password", "apikey"),
        default="auto",
        help="Login method. auto prompts in interactive terminals.",
    )
    login.add_argument(
        "--client-id",
        help="Bitwarden API key client ID (BW_CLIENTID).",
    )
    login.add_argument(
        "--client-secret",
        help="Bitwarden API key client secret (BW_CLIENTSECRET).",
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
        return bw_cli.resolve_reference(entry.value, entry.key, cache)
    return entry.value


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


def shell_assignment(key: str, value: str) -> str:
    return f"export {key}={shlex.quote(value)}"


_PS_UNSAFE_QUOTES = ("\u2018", "\u2019", "\u201a", "\u201b")


def powershell_assignment(key: str, value: str) -> str:
    if "\n" in value or "\r" in value or any(quote in value for quote in _PS_UNSAFE_QUOTES):
        b64 = base64.b64encode(value.encode("utf-8")).decode("ascii")
        return f"$env:{key} = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('{b64}'))"
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
                    item_id, _ = bw_cli.parse_reference(entry.value)
                    item_ids.add(item_id)
                    references_by_item_id.setdefault(item_id, []).append(entry.key)
                except (ValueError, RuntimeError):
                    pass  # will error during resolution with proper context
        if item_ids:
            total_ids = len(item_ids)
            status("hint", f"Fetching {total_ids} Bitwarden item(s) in batch...")
            cache = bw_cli.fetch_items(item_ids)
            missing_item_ids = item_ids - set(cache.keys())
            if missing_item_ids:
                raise RuntimeError(format_missing_bw_references(missing_item_ids, references_by_item_id))

    resolved_entries: list[tuple[str, str]] = []
    total = len(entries)
    for index, entry in enumerate(entries, start=1):
        status("hint", f"Resolving {index}/{total}: {entry.key}")
        resolved_entries.append((entry.key, resolve_value(entry, backend, cache)))
    return resolved_entries


def write_file(path: Path, content: str, force: bool) -> str:
    created = not path.exists()
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)

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
    write_private_atomic(path, content)
    return "created" if created else "updated"


def sync_command(args: argparse.Namespace, repo_root: Path) -> int:
    template_path = resolve_template_path(repo_root, args.template)
    if not template_path.is_file():
        status("fail", f"Template not found: {ui_path(template_path)}")
        return 1

    entries = parse_template(template_path)
    home = Path.home()
    local_root = home / DEFAULT_LOCAL_RELATIVE_PATH
    zsh_path = local_root / "env.zsh"
    ps1_path = local_root / "env.ps1"

    section("Secrets Sync")
    status("info", f"Template: {ui_path(template_path)}")
    status("info", f"Backend: {args.backend}")
    status("info", f"Targets: {ui_path(zsh_path)}, {ui_path(ps1_path)}")

    resolved_entries = resolve_entries_for_sync(entries, args.backend)
    zsh_content = render_zsh(resolved_entries, args.backend, template_path)
    ps1_content = render_ps1(resolved_entries, args.backend, template_path)

    if args.dry_run:
        bullet(f"Backend: {args.backend}")
        bullet(f"Template: {ui_path(template_path)}")
        bullet(f"Would render: {ui_path(zsh_path)}")
        bullet(f"Would render: {ui_path(ps1_path)}")
        status("ok", "Dry run complete.")
        return 0

    ensure_private_directory(local_root)
    zsh_status = write_file(zsh_path, zsh_content, args.force)
    ps1_status = write_file(ps1_path, ps1_content, args.force)
    status("ok", f"{zsh_status}: {ui_path(zsh_path)}")
    status("ok", f"{ps1_status}: {ui_path(ps1_path)}")
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
        if bw_cli.which_bw() is None:
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
    status("info", f"Template: {ui_path(template_path)}")
    status("info", f"Backend: {args.backend}")
    return 0


def unlock_after_login() -> bool:
    """Logging in leaves the vault locked; prompt once and persist the session."""
    try:
        password = getpass.getpass("Bitwarden master password (unlock vault): ")
    except (EOFError, KeyboardInterrupt):
        print("", file=sys.stderr)
        status("warn", "Vault unlock skipped. Run `oooconf secrets unlock` when ready.")
        return False

    try:
        token = bw_cli.unlock_raw(password)
    except bw_cli.BitwardenError as exc:
        status("fail", str(exc))
        status("hint", "Login succeeded, but the vault stays locked. Run `oooconf secrets unlock`.")
        return False

    path = bw_cli.write_session(token)
    status("ok", f"Vault unlocked; BW_SESSION saved to {ui_path(path)}")
    return True


def login_command(args: argparse.Namespace) -> int:
    if bw_cli.which_bw() is None:
        status("fail", "Bitwarden CLI (`bw`) is not installed or not on PATH.")
        return 1

    if getattr(args, "client_secret", None):
        status(
            "warn",
            "Supplying --client-secret on the command line exposes secrets in process lists; "
            "use BW_CLIENTSECRET or the interactive prompt instead.",
        )

    server = (args.server or "").strip().rstrip("/")
    if not server:
        status(
            "fail",
            "No Bitwarden/Vaultwarden server URL is configured. Pass `--server URL`, "
            "set `OOODNAKOV_BW_SERVER`, or configure `{DATA_HOME}/ooodnakov-config/bw-server` "
            "or `~/.config/ooodnakov/local/bw-server`.",
        )
        return 1
    config_result = bw_cli.config_server(server)
    if config_result != 0:
        return config_result

    interactive = sys.stdin.isatty() and sys.stdout.isatty()
    env = os.environ.copy()
    method = args.method

    if method == "auto":
        if interactive:
            method = prompt_login_method(
                default_method="apikey" if env.get("BW_CLIENTID") and env.get("BW_CLIENTSECRET") else "password"
            )
            status("info", f"Selected login method: {method}")
        else:
            method = "apikey" if env.get("BW_CLIENTID") and env.get("BW_CLIENTSECRET") else "password"

    if method == "apikey":
        client_id = args.client_id or env.get("BW_CLIENTID")
        client_secret = args.client_secret or env.get("BW_CLIENTSECRET")

        if not client_id and interactive:
            client_id = input("Bitwarden client ID (BW_CLIENTID): ").strip()
        if not client_secret and interactive:
            client_secret = getpass.getpass("Bitwarden client secret (BW_CLIENTSECRET): ").strip()

        if not client_id or not client_secret:
            status(
                "fail",
                "API key login requires BW_CLIENTID and BW_CLIENTSECRET. "
                "Provide --client-id/--client-secret or export both env vars.",
            )
            return 1

        env["BW_CLIENTID"] = client_id
        env["BW_CLIENTSECRET"] = client_secret
        status("info", "Attempting Bitwarden API key login...")
        login_result = bw_cli.login_apikey(env)
    else:
        status("info", "Attempting Bitwarden email/password login...")
        login_result = bw_cli.login_password()

    if login_result != 0:
        return login_result

    if interactive:
        unlock_after_login()
    else:
        status("hint", "Vault is locked after login. Run `oooconf secrets unlock` in an interactive shell.")
    return 0


def prompt_login_method(default_method: str) -> str:
    options = {
        "1": "password",
        "2": "apikey",
        "password": "password",
        "email": "password",
        "email-password": "password",
        "apikey": "apikey",
        "api": "apikey",
        "clientid": "apikey",
        "client-id": "apikey",
    }
    default_choice = "2" if default_method == "apikey" else "1"

    status("info", "Choose Bitwarden login method:")
    status("hint", "  1) email/password")
    status("hint", "  2) clientid/clientsecret (API key)")

    while True:
        try:
            raw = input(f"Method [1/2] (default {default_choice}): ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print("", file=sys.stderr)
            return default_method

        if not raw:
            return default_method
        method = options.get(raw)
        if method:
            return method
        status("warn", "Invalid selection. Enter 1 or 2.")


def unlock_command(args: argparse.Namespace) -> int:
    if bw_cli.which_bw() is None:
        status("fail", "Bitwarden CLI (`bw`) is not installed or not on PATH.")
        return 1

    should_persist = bool(args.password) or (not args.explicit_shell and not args.explicit_raw)
    if should_persist:
        password = args.password
        if password is None:
            try:
                password = getpass.getpass("Bitwarden password: ")
            except (EOFError, KeyboardInterrupt):
                status("warn", "Unlock cancelled.")
                return 1
        elif password:
            status(
                "warn",
                "Supplying a password on the command line exposes secrets in process lists; "
                "use the interactive prompt or BW_PASSWORD instead.",
            )
        try:
            token = bw_cli.unlock_raw(password)
        except bw_cli.BitwardenError as exc:
            status("fail", str(exc))
            return 1
        path = bw_cli.write_session(token)
        status("ok", f"Saved BW_SESSION to {ui_path(path)}")
        return 0

    try:
        token = bw_cli.unlock_raw()
    except bw_cli.BitwardenError as exc:
        status("fail", str(exc))
        return 1

    if args.raw:
        print(token)
        return 0

    if args.shell == "pwsh":
        print(powershell_assignment("BW_SESSION", token))
    else:
        print(f"export BW_SESSION={shlex.quote(token)}")
    return 0


def check_bw_status() -> list[str]:
    problems: list[str] = []
    try:
        state = bw_cli.status()
    except RuntimeError as exc:
        problems.append(str(exc))
        return problems

    current_server = (state.get("serverUrl") or "").rstrip("/")
    expected_server = resolve_default_bw_server().rstrip("/")
    if expected_server and current_server and current_server != expected_server:
        problems.append(
            f"Bitwarden CLI is pointed at {current_server}, expected {expected_server}. "
            f"Run `bw config server {expected_server}` if needed."
        )

    status_value = state.get("status")
    session_available = bool(os.environ.get("BW_SESSION") or bw_cli.read_session())
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
        status("fail", f"Template not found: {ui_path(template_path)}")
        return 1

    entries = parse_template(template_path)
    if not entries:
        status("info", "No secrets defined in template.")
        return 0

    section("Secrets List")
    status("info", f"Template: {ui_path(template_path)}")
    spacer()

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
        status("fail", f"Template not found: {ui_path(template_path)}")
        return 1

    template_mtime = template_path.stat().st_mtime
    problems: list[str] = []

    section("Secrets Status")
    status("info", f"Template: {ui_path(template_path)}")
    status("info", f"Backend: {os.environ.get('OOODNAKOV_SECRETS_BACKEND', 'bw')}")
    spacer()

    for local_path in (zsh_path, ps1_path):
        if not local_path.exists():
            status("fail", f"{ui_path(local_path)}: missing")
            problems.append(f"{local_path.name} is not synced")
        else:
            local_mtime = local_path.stat().st_mtime
            if local_mtime < template_mtime:
                status("warn", f"{ui_path(local_path)}: stale (template updated after last sync)")
                problems.append(f"{local_path.name} is stale")
            else:
                status("ok", f"{ui_path(local_path)}: up to date")

    session_available = bool(os.environ.get("BW_SESSION") or bw_cli.read_session())
    if session_available:
        if bw_cli.which_bw():
            try:
                vault_state = bw_cli.status()
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

    spacer()
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
    if bw_cli.which_bw() is None:
        status("fail", "Bitwarden CLI (`bw`) is not installed or not on PATH.")
        return 1

    lock_result = bw_cli.lock()
    if lock_result != 0:
        return lock_result

    logout_result = bw_cli.logout()
    bw_cli.clear_session()
    return logout_result


def add_command(args: argparse.Namespace, repo_root: Path) -> int:
    import re

    if not re.match(r"^[A-Z_][A-Z0-9_]*$", args.key):
        status("fail", f"Invalid key name: {args.key}. Use UPPER_SNAKE_CASE letters.")
        return 1

    template_path = resolve_template_path(repo_root, args.template)
    if not template_path.is_file():
        status("fail", f"Template not found: {ui_path(template_path)}")
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
    status("info", f"Template: {ui_path(template_path)}")
    return 0


def remove_command(args: argparse.Namespace, repo_root: Path) -> int:
    template_path = resolve_template_path(repo_root, args.template)
    if not template_path.is_file():
        status("fail", f"Template not found: {ui_path(template_path)}")
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
    status("info", f"Template: {ui_path(template_path)}")
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
