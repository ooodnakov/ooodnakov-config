"""Single seam for the Bitwarden CLI (`bw`) used by oooconf.

Every `bw` invocation, session-token file and `bw://` reference interpretation lives
here so command code never shells out directly. Replacing the backend (for example
with a native client) means reimplementing this module, not editing its callers.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

from private_files import ensure_private_directory, write_private_atomic

BW_TIMEOUT_SECONDS = 30
SESSION_RELATIVE_PATH = Path(".config/ooodnakov/local/bw-session")
REFERENCE_PREFIX = "bw://item/"


class BitwardenError(RuntimeError):
    """A `bw` invocation failed, is missing, or returned unusable data."""


class BitwardenUnavailable(BitwardenError):
    """The `bw` executable is not installed or not on PATH."""


class BitwardenTimeout(BitwardenError):
    """A `bw` invocation exceeded BW_TIMEOUT_SECONDS."""


def which_bw() -> str | None:
    """Return the resolved `bw` executable path, or None when it is not installed."""
    return shutil.which("bw")


def require_cli() -> None:
    if which_bw() is None:
        raise BitwardenUnavailable("Bitwarden CLI (`bw`) is not installed or not on PATH.")


def _label(args: list[str]) -> str:
    return " ".join(["bw", *args])


def _run(
    args: list[str],
    *,
    env: dict[str, str] | None = None,
    input_value: str | None = None,
    check: bool = True,
    stream: bool = False,
) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(
            ["bw", *args],
            input=input_value,
            text=True,
            capture_output=not stream,
            env=env if env is not None else os.environ.copy(),
            timeout=BW_TIMEOUT_SECONDS,
            check=False,
        )
    except FileNotFoundError as exc:
        raise BitwardenUnavailable("Bitwarden CLI (`bw`) is not installed or not on PATH.") from exc
    except subprocess.TimeoutExpired as exc:
        raise BitwardenTimeout(f"`{_label(args)}` timed out after {BW_TIMEOUT_SECONDS}s") from exc
    if check and result.returncode != 0:
        stderr = (result.stderr or "").strip()
        raise BitwardenError(stderr or f"`{_label(args)}` failed")
    return result


def session_path() -> Path:
    return Path.home() / SESSION_RELATIVE_PATH


def read_session() -> str | None:
    path = session_path()
    if not path.exists():
        return None
    return path.read_text(encoding="utf-8").strip() or None


def write_session(token: str) -> Path:
    path = session_path()
    ensure_private_directory(path.parent)
    write_private_atomic(path, token + "\n")
    return path


def clear_session() -> None:
    path = session_path()
    if path.exists():
        path.unlink()


def session_env(base: dict[str, str] | None = None) -> dict[str, str]:
    """Copy an environment with BW_SESSION set from the persisted session file."""
    env = dict(base if base is not None else os.environ)
    if not env.get("BW_SESSION"):
        session = read_session()
        if session:
            env["BW_SESSION"] = session
    return env


def ensure_session(env: dict[str, str]) -> None:
    """Require BW_SESSION, auto-unlocking from BW_PASSWORD when API keys are present."""
    if env.get("BW_SESSION"):
        return

    if env.get("BW_PASSWORD") and env.get("BW_CLIENTID") and env.get("BW_CLIENTSECRET"):
        require_cli()
        result = _run(["unlock", "--raw", "--passwordenv", "BW_PASSWORD"], env=env, check=False)
        token = (result.stdout or "").strip()
        if result.returncode == 0 and token:
            env["BW_SESSION"] = token
            return
        raise BitwardenError("Failed to auto-unlock vault. Check BW_CLIENTID/BW_CLIENTSECRET/BW_PASSWORD.")

    raise BitwardenError(
        'BW_SESSION is not set. Unlock Bitwarden first, for example with `export BW_SESSION="$(bw unlock --raw)"` '
        "or the PowerShell equivalent. "
        "Alternatively, set BW_CLIENTID, BW_CLIENTSECRET, and BW_PASSWORD for auto-unlock."
    )


def status(env: dict[str, str] | None = None) -> dict:
    result = _run(["status"], env=env if env is not None else session_env())
    try:
        return json.loads(result.stdout or "")
    except json.JSONDecodeError as exc:
        raise BitwardenError("`bw status` did not return valid JSON") from exc


def sync(env: dict[str, str] | None = None) -> None:
    try:
        _run(["sync"], env=env if env is not None else session_env())
    except BitwardenError as exc:
        raise BitwardenError(f"failed to sync Bitwarden vault: {exc}") from exc


def list_items(*, env: dict[str, str] | None = None, search: str | None = None) -> list[dict]:
    args = ["list", "items"]
    if search:
        args += ["--search", search]
    result = _run(args, env=env if env is not None else session_env())
    try:
        return json.loads(result.stdout or "")
    except json.JSONDecodeError as exc:
        raise BitwardenError("Bitwarden returned invalid JSON for items list.") from exc


def get_item(item_id: str, key: str, *, env: dict[str, str] | None = None) -> dict:
    session = env if env is not None else session_env()
    ensure_session(session)
    sync(session)
    try:
        result = _run(["get", "item", item_id], env=session)
    except BitwardenTimeout as exc:
        raise BitwardenTimeout(
            f"timed out resolving {key} from Bitwarden after {BW_TIMEOUT_SECONDS}s (item {item_id})"
        ) from exc
    except BitwardenUnavailable:
        raise
    except BitwardenError as exc:
        raise BitwardenError(f"failed to resolve {key} from Bitwarden: {exc}") from exc
    try:
        return json.loads(result.stdout or "")
    except json.JSONDecodeError as exc:
        raise BitwardenError(f"Bitwarden returned invalid JSON for {key}.") from exc


def fetch_items(item_ids: set[str]) -> dict[str, dict]:
    """Fetch the requested item IDs with one sync + one full list call."""
    if not item_ids:
        return {}
    env = session_env()
    ensure_session(env)
    sync(env)
    return {item["id"]: item for item in list_items(env=env) if item.get("id") in item_ids}


def encode(value: str, *, env: dict[str, str] | None = None) -> str:
    result = _run(["encode"], env=env if env is not None else session_env(), input_value=value)
    return (result.stdout or "").strip()


def save_item(item_id: str | None, encoded: str, *, env: dict[str, str] | None = None) -> dict:
    session = env if env is not None else session_env()
    args = ["edit", "item", item_id] if item_id else ["create", "item"]
    result = _run(args, env=session, input_value=encoded)
    try:
        return json.loads(result.stdout or "")
    except json.JSONDecodeError as exc:
        raise BitwardenError("Bitwarden returned invalid JSON when saving the item.") from exc


def config_server(url: str) -> int:
    return _run(["config", "server", url], stream=True, check=False).returncode


def login_apikey(env: dict[str, str]) -> int:
    return _run(["login", "--apikey"], env=env, stream=True, check=False).returncode


def login_password() -> int:
    return _run(["login"], stream=True, check=False).returncode


def unlock_raw(password: str | None = None) -> str:
    """Unlock the vault and return the raw session token."""
    env = os.environ.copy()
    args = ["unlock", "--raw"]
    if password is not None:
        env["BW_PASSWORD"] = password
        args += ["--passwordenv", "BW_PASSWORD"]
    result = _run(args, env=env, check=False)
    if result.returncode != 0:
        raise BitwardenError((result.stderr or "").strip() or "`bw unlock` failed.")
    token = (result.stdout or "").strip()
    if not token:
        raise BitwardenError("`bw unlock --raw` returned an empty session token.")
    return token


def lock() -> int:
    return _run(["lock"], stream=True, check=False).returncode


def logout() -> int:
    return _run(["logout"], stream=True, check=False).returncode


def parse_reference(reference: str) -> tuple[str, str]:
    if not reference.startswith(REFERENCE_PREFIX):
        raise ValueError(
            f"unsupported Bitwarden reference: {reference}. "
            "Use bw://item/<item-id>/(password|username|notes|uri|field/<field-name>)."
        )

    remainder = reference[len(REFERENCE_PREFIX) :]
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


def select_value(item: dict, selector: str, key: str) -> str:
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
        raise BitwardenError(f"Bitwarden item does not contain `{selector}` for {key}.")
    return str(value)


def resolve_reference(reference: str, key: str, cache: dict[str, dict] | None = None) -> str:
    item_id, selector = parse_reference(reference)
    if cache is not None and item_id in cache:
        item = cache[item_id]
    else:
        item = get_item(item_id, key)
    return select_value(item, selector, key)
