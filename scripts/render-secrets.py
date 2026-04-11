#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


DEFAULT_TEMPLATE_RELATIVE_PATH = Path("home/.config/ooodnakov/secrets/env.template")
DEFAULT_CONFIG_RELATIVE_PATH = Path(".config/ooodnakov")
DEFAULT_LOCAL_RELATIVE_PATH = Path(".config/ooodnakov/local")
DEFAULT_BW_SERVER = os.environ.get("OOODNAKOV_BW_SERVER", "https://vaultwarden.ooodnakov.ru")


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

    subparsers = parser.add_subparsers(dest="command", required=True)

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

    unlock = subparsers.add_parser("unlock", help="Unlock Bitwarden and print shell code for BW_SESSION.")
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

    return parser.parse_args()


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


def resolve_value(entry: SecretEntry, backend: str) -> str:
    if entry.value.startswith("bw://"):
        if backend != "bw":
            raise ValueError(f"unsupported backend for secret reference: {backend}")
        return read_bw_secret(entry.value, entry.key)
    return entry.value


def read_bw_secret(reference: str, key: str) -> str:
    item_id, selector = parse_bw_reference(reference)
    item = read_bw_item(item_id, key)
    return select_bw_value(item, selector, key)


def parse_bw_reference(reference: str) -> tuple[str, str]:
    prefix = "bw://item/"
    if not reference.startswith(prefix):
        raise ValueError(
            f"unsupported Bitwarden reference: {reference}. "
            "Use bw://item/<item-id>/(password|username|notes|uri|field/<field-name>)."
        )

    remainder = reference[len(prefix):]
    parts = [part for part in remainder.split("/") if part]
    if len(parts) < 2:
        raise ValueError(
            f"invalid Bitwarden reference: {reference}. "
            "Expected bw://item/<item-id>/<selector>."
        )

    item_id = parts[0]
    if parts[1] == "field":
        if len(parts) < 3:
            raise ValueError(
                f"invalid Bitwarden field reference: {reference}. "
                "Expected bw://item/<item-id>/field/<field-name>."
            )
        selector = "field/" + "/".join(parts[2:])
    else:
        selector = parts[1]

    return item_id, selector


def read_bw_item(item_id: str, key: str) -> dict:
    env = os.environ.copy()
    session = env.get("BW_SESSION")
    if not session:
        raise RuntimeError(
            "BW_SESSION is not set. Unlock Bitwarden first, for example with `export BW_SESSION=\"$(bw unlock --raw)\"` "
            "or the PowerShell equivalent."
        )

    command = ["bw", "get", "item", item_id, "--session", session]
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True, env=env)
    except FileNotFoundError as exc:
        raise RuntimeError("Bitwarden CLI (`bw`) is not installed or not on PATH.") from exc
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
        value = ((item.get("login") or {}).get("password"))
    elif selector == "username":
        value = ((item.get("login") or {}).get("username"))
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


def render_zsh(entries: list[SecretEntry], backend: str, template_path: Path) -> str:
    lines = [
        "# Generated by `oooconf secrets sync`.",
        "# Do not commit plaintext secrets. Update the tracked template instead.",
        f"# Source template: {template_path}",
        f"# Backend: {backend}",
        "",
    ]
    for entry in entries:
        lines.append(shell_assignment(entry.key, resolve_value(entry, backend)))
    lines.append("")
    return "\n".join(lines)


def render_ps1(entries: list[SecretEntry], backend: str, template_path: Path) -> str:
    lines = [
        "# Generated by `oooconf secrets sync`.",
        "# Do not commit plaintext secrets. Update the tracked template instead.",
        f"# Source template: {template_path}",
        f"# Backend: {backend}",
        "",
    ]
    for entry in entries:
        lines.append(powershell_assignment(entry.key, resolve_value(entry, backend)))
    lines.append("")
    return "\n".join(lines)


def ensure_private_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    if os.name != "nt":
        path.chmod(0o700)


def write_file(path: Path, content: str, force: bool) -> str:
    if path.exists():
        existing = path.read_text(encoding="utf-8")
        if existing == content and not force:
            return "unchanged"
    path.write_text(content, encoding="utf-8")
    if os.name != "nt":
        path.chmod(0o600)
    return "updated"


def sync_command(args: argparse.Namespace, repo_root: Path) -> int:
    template_path = resolve_template_path(repo_root, args.template)
    if not template_path.is_file():
        print(f"Template not found: {template_path}", file=sys.stderr)
        return 1

    entries = parse_template(template_path)
    home = Path.home()
    local_root = home / DEFAULT_LOCAL_RELATIVE_PATH
    zsh_path = local_root / "env.zsh"
    ps1_path = local_root / "env.ps1"

    zsh_content = render_zsh(entries, args.backend, template_path)
    ps1_content = render_ps1(entries, args.backend, template_path)

    if args.dry_run:
        print(f"Would render {zsh_path}")
        print(f"Would render {ps1_path}")
        return 0

    ensure_private_directory(local_root)
    zsh_status = write_file(zsh_path, zsh_content, args.force)
    ps1_status = write_file(ps1_path, ps1_content, args.force)
    print(f"{zsh_status}: {zsh_path}")
    print(f"{ps1_status}: {ps1_path}")
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
            print(f"ERROR: {problem}")
        return 1

    print("Secrets doctor passed.")
    print(f"Template: {template_path}")
    print(f"Backend: {args.backend}")
    return 0


def login_command(args: argparse.Namespace) -> int:
    if shutil_which("bw") is None:
        print("Bitwarden CLI (`bw`) is not installed or not on PATH.", file=sys.stderr)
        return 1

    server = args.server.rstrip("/")
    config_result = subprocess.run(["bw", "config", "server", server], text=True)
    if config_result.returncode != 0:
        return config_result.returncode

    login_result = subprocess.run(["bw", "login", "--server", server], text=True)
    return login_result.returncode


def unlock_command(args: argparse.Namespace) -> int:
    if shutil_which("bw") is None:
        print("Bitwarden CLI (`bw`) is not installed or not on PATH.", file=sys.stderr)
        return 1

    result = subprocess.run(["bw", "unlock", "--raw"], capture_output=True, text=True)
    if result.returncode != 0:
        stderr = result.stderr.strip()
        if stderr:
            print(stderr, file=sys.stderr)
        return result.returncode

    token = result.stdout.strip()
    if not token:
        print("`bw unlock --raw` returned an empty session token.", file=sys.stderr)
        return 1

    if args.raw:
        print(token)
        return 0

    if args.shell == "pwsh":
        escaped = token.replace("'", "''")
        print(f"$env:BW_SESSION = '{escaped}'")
    else:
        print(f"export BW_SESSION={shlex.quote(token)}")
    return 0


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


def check_bw_status() -> list[str]:
    problems: list[str] = []
    try:
        status_result = subprocess.run(
            ["bw", "status"],
            check=True,
            capture_output=True,
            text=True,
            env=os.environ.copy(),
        )
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip()
        problems.append(stderr or "`bw status` failed")
        return problems

    try:
        status = json.loads(status_result.stdout)
    except json.JSONDecodeError:
        problems.append("`bw status` did not return valid JSON")
        return problems

    current_server = (status.get("serverUrl") or "").rstrip("/")
    expected_server = DEFAULT_BW_SERVER.rstrip("/")
    if current_server and current_server != expected_server:
        problems.append(
            f"Bitwarden CLI is pointed at {current_server}, expected {expected_server}. "
            "Run `bw config server https://vaultwarden.ooodnakov.ru` if needed."
        )

    status_value = status.get("status")
    if status_value == "unauthenticated":
        problems.append("Bitwarden CLI is not logged in. Run `bw login --server https://vaultwarden.ooodnakov.ru`.")
    elif status_value == "locked" and not os.environ.get("BW_SESSION"):
        problems.append("Bitwarden vault is locked. Unlock it and export BW_SESSION before syncing.")
    elif status_value == "unlocked" and not os.environ.get("BW_SESSION"):
        problems.append("Bitwarden reports unlocked, but BW_SESSION is not exported in this shell.")

    return problems


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
        raise ValueError(f"unsupported command: {args.command}")
    except (RuntimeError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
