#!/usr/bin/env python3
"""Transactionally apply and roll back managed oooconf links."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time
import uuid
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path
from typing import Iterator

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from scripts.cli.operation_plan import Operation, PlanError, build_link_operations  # noqa: E402
from scripts.cli.profile_manager import ProfileError, resolve_profile  # noqa: E402
from scripts.link_manager import get_platform  # noqa: E402

JOURNAL_VERSION = 1
INCOMPLETE_STATUSES = {"applying", "failed", "rollback_failed"}


class TransactionError(RuntimeError):
    """Raised when a transaction cannot safely proceed or roll back."""


def _utc_now() -> str:
    return datetime.now(UTC).isoformat(timespec="microseconds")


def _redact(value: object) -> str:
    text = str(value)
    for name, secret in os.environ.items():
        if (
            secret
            and len(secret) >= 4
            and any(marker in name.upper() for marker in ("KEY", "PASSWORD", "SECRET", "SESSION", "TOKEN"))
        ):
            text = text.replace(secret, "[redacted]")
    return text


def _state_root() -> Path:
    base = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    return base.expanduser() / "ooodnakov-config"


def _backup_root() -> Path:
    configured = os.environ.get("OOODNAKOV_BACKUP_ROOT")
    return Path(configured).expanduser() if configured else Path.home() / ".local/state/ooodnakov-config/backups"


def _journal_root() -> Path:
    return _state_root() / "transactions"


def _atomic_write(path: Path, data: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    try:
        with temporary.open("w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        if os.name != "nt":
            temporary.chmod(0o600)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def _process_alive(pid: int) -> bool:
    """Return whether pid is running without signalling it.

    Windows os.kill(pid, 0) terminates the target process, so liveness there
    goes through OpenProcess instead of the POSIX signal probe.
    """
    if pid <= 0:
        return False
    if sys.platform == "win32":
        import ctypes

        process_query_limited_information = 0x1000
        still_active = 259
        kernel32 = ctypes.windll.kernel32  # type: ignore[attr-defined]
        handle = kernel32.OpenProcess(process_query_limited_information, False, pid)
        if not handle:
            return False
        try:
            exit_code = ctypes.c_ulong()
            if not kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code)):
                return False
            return exit_code.value == still_active
        finally:
            kernel32.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _lock_conflict(lock: Path) -> TransactionError:
    return TransactionError(
        f"Another apply or rollback is active (lock: {lock}). "
        "If no other oooconf process is running, remove that directory and retry."
    )


def _lock_owner_pid(lock: Path) -> int | None:
    owner_path = lock / "owner.json"
    try:
        owner = json.loads(owner_path.read_text(encoding="utf-8"))
        return int(owner["pid"])
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError):
        return None


@contextmanager
def _apply_lock() -> Iterator[None]:
    lock = _state_root() / "apply.lock"
    lock.parent.mkdir(parents=True, exist_ok=True)
    for _attempt in range(3):
        try:
            lock.mkdir()
            break
        except FileExistsError:
            pid = _lock_owner_pid(lock)
            if pid is not None and _process_alive(pid):
                raise _lock_conflict(lock) from None
            # Missing or unreadable owner metadata means the previous holder
            # died before recording itself; an exited pid is equally stale.
            shutil.rmtree(lock, ignore_errors=True)
    else:
        raise _lock_conflict(lock)
    try:
        _atomic_write(lock / "owner.json", {"pid": os.getpid(), "started_at": _utc_now()})
        yield
    finally:
        shutil.rmtree(lock, ignore_errors=True)


def _backup_path(target: Path, transaction_id: str) -> Path:
    drive, tail = os.path.splitdrive(str(target.parent))
    del drive
    relative_parent = tail.lstrip("/\\")
    return _backup_root() / relative_parent / f"{target.name}.{transaction_id}"


def _new_journal(repo_root: Path, platform: str, profile: str | None, operations: list[Operation]) -> dict[str, object]:
    transaction_id = datetime.now(UTC).strftime("%Y%m%d-%H%M%S") + f"-{uuid.uuid4().hex[:8]}"
    return {
        "journal_version": JOURNAL_VERSION,
        "transaction_id": transaction_id,
        "status": "applying",
        "platform": platform,
        "profile": profile,
        "repo_root": str(repo_root.resolve()),
        "created_at_ns": time.time_ns(),
        "started_at": _utc_now(),
        "completed_at": None,
        "failed_operation": None,
        "error": None,
        "operations": [
            {
                "id": operation.id,
                "kind": operation.kind,
                "source": operation.source,
                "target": operation.target,
                "status": "pending",
                "created": False,
                "backup_path": None,
            }
            for operation in operations
        ],
    }


def _journal_path(journal: dict[str, object]) -> Path:
    return _journal_root() / f"{journal['transaction_id']}.json"


def _link_matches(source: Path, target: Path) -> bool:
    if not target.is_symlink():
        return False
    try:
        return target.resolve(strict=False) == source.resolve(strict=False)
    except (OSError, RuntimeError):
        # pathlib reports ELOOP as RuntimeError on some versions.
        return False


def _is_self_link(target: Path) -> bool:
    """Return whether target is a symlink that points back at itself."""
    if not target.is_symlink():
        return False
    try:
        raw = Path(os.readlink(target))
    except OSError:
        return False
    if not raw.is_absolute():
        raw = target.parent / raw
    raw_text = os.path.abspath(raw)
    target_text = os.path.abspath(target)
    if os.name == "nt":
        if raw_text.startswith("\\\\?\\UNC\\"):
            raw_text = "\\\\" + raw_text[8:]
        elif raw_text.startswith("\\\\?\\"):
            raw_text = raw_text[4:]
        if target_text.startswith("\\\\?\\UNC\\"):
            target_text = "\\\\" + target_text[8:]
        elif target_text.startswith("\\\\?\\"):
            target_text = target_text[4:]
    normalized_raw = os.path.normcase(os.path.normpath(raw_text))
    normalized_target = os.path.normcase(os.path.normpath(target_text))
    return normalized_raw == normalized_target


def _link_failure_hint() -> str:
    if sys.platform == "win32":
        return (
            " Windows denies symbolic links unless the account holds"
            " SeCreateSymbolicLinkPrivilege: enable Developer Mode (Settings > System > For developers)"
            " or run oooconf from an elevated shell."
        )
    return ""


def _assert_link_support() -> None:
    """Fail before mutating anything when this host cannot create symlinks."""
    probe_root = _state_root() / "capability"
    probe_root.mkdir(parents=True, exist_ok=True)
    probe_id = uuid.uuid4().hex
    source = probe_root / f"source-{probe_id}"
    target = probe_root / f"link-{probe_id}"
    try:
        source.write_text("probe\n", encoding="utf-8")
        target.unlink(missing_ok=True)
        try:
            target.symlink_to(source)
        except OSError as error:
            raise TransactionError(f"Cannot create symbolic links: {error}.{_link_failure_hint()}") from error
    finally:
        target.unlink(missing_ok=True)
        source.unlink(missing_ok=True)


def _apply_entry(entry: dict[str, object], transaction_id: str) -> None:
    kind = entry["kind"]
    if kind == "mkdir":
        target = Path(str(entry["target"]))
        if not target.exists():
            target.mkdir(parents=True)
        return
    if kind == "backup":
        target = Path(str(entry["source"]))
        if not (target.exists() or target.is_symlink()):
            raise TransactionError(f"Backup target disappeared before apply: {target}")
        backup = Path(str(entry["backup_path"]))
        backup.parent.mkdir(parents=True, exist_ok=True)
        if backup.exists() or backup.is_symlink():
            raise TransactionError(f"Backup destination already exists: {backup}")
        shutil.move(str(target), str(backup))
        return
    if kind == "link":
        source = Path(str(entry["source"]))
        target = Path(str(entry["target"]))
        if target.exists() or target.is_symlink():
            raise TransactionError(f"Refusing to replace an unbacked target: {target}")
        resolved_target = target.parent.resolve(strict=False) / target.name
        if resolved_target == source.resolve(strict=False):
            raise TransactionError(
                f"Refusing to create a self-referential link: {target} resolves onto its own source. "
                "Migrate legacy whole-directory links (docs/symlink-manifest.md#omp-file-and-content-links)."
            )
        try:
            target.symlink_to(source, target_is_directory=source.is_dir())
        except OSError as error:
            raise TransactionError(f"Cannot link {target} -> {source}: {error}.{_link_failure_hint()}") from error
        if not _link_matches(source, target):
            raise TransactionError(f"Link postcondition failed: {target}")
        return
    raise TransactionError(f"Unsupported transactional operation: {kind}")


def _rollback_entries(journal: dict[str, object]) -> list[str]:
    errors: list[str] = []
    entries = journal.get("operations", [])
    assert isinstance(entries, list)
    for entry in reversed(entries):
        if not isinstance(entry, dict) or entry.get("status") not in {"applying", "completed", "rollback_failed"}:
            continue
        try:
            kind = entry["kind"]
            if kind == "link" and entry.get("created"):
                target = Path(str(entry["target"]))
                source = Path(str(entry["source"]))
                if target.is_symlink() and (_link_matches(source, target) or _is_self_link(target)):
                    target.unlink()
                elif target.exists() or target.is_symlink():
                    raise TransactionError(f"Refusing to remove user-modified target: {target}")
            elif kind == "backup" and entry.get("backup_path"):
                original = Path(str(entry["source"]))
                backup = Path(str(entry["backup_path"]))
                if backup.exists() or backup.is_symlink():
                    if original.exists() or original.is_symlink():
                        raise TransactionError(f"Refusing to overwrite target while restoring: {original}")
                    original.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(backup), str(original))
            elif kind == "mkdir" and entry.get("created"):
                directory = Path(str(entry["target"]))
                if directory.exists():
                    directory.rmdir()
            entry["status"] = "rolled_back"
        except (OSError, RuntimeError, TransactionError) as error:
            entry["status"] = "rollback_failed"
            errors.append(str(error))
    return errors


def apply(repo_root: Path, platform: str, profile_name: str | None = None) -> tuple[Path | None, int]:
    """Apply all currently required managed link operations as one transaction."""
    repo_root = repo_root.resolve()
    profile = resolve_profile(repo_root, platform, profile_name)
    operations = build_link_operations(
        repo_root,
        platform,
        profile.name if profile else None,
        profile.links if profile else None,
    )
    if not operations:
        print("No changes required.")
        return None, 0
    if any(operation.kind == "link" for operation in operations):
        _assert_link_support()

    journal = _new_journal(repo_root, platform, profile.name if profile else None, operations)
    path = _journal_path(journal)
    test_fail_after = 0
    if os.environ.get("PYTEST_CURRENT_TEST") and os.environ.get("OOODNAKOV_TEST_FAIL_AFTER"):
        try:
            test_fail_after = int(os.environ["OOODNAKOV_TEST_FAIL_AFTER"])
        except ValueError as error:
            raise TransactionError("OOODNAKOV_TEST_FAIL_AFTER must be an integer") from error
    with _apply_lock():
        _atomic_write(path, journal)
        entries = journal["operations"]
        assert isinstance(entries, list)
        failed_operation = None
        try:
            for operation_index, entry in enumerate(entries, start=1):
                assert isinstance(entry, dict)
                journal["failed_operation"] = entry["id"]
                failed_operation = entry["id"]
                entry["status"] = "applying"
                if entry["kind"] in {"mkdir", "link"}:
                    entry["created"] = True
                elif entry["kind"] == "backup":
                    entry["backup_path"] = str(_backup_path(Path(str(entry["source"])), str(journal["transaction_id"])))
                _atomic_write(path, journal)
                _apply_entry(entry, str(journal["transaction_id"]))
                entry["status"] = "completed"
                journal["failed_operation"] = None
                failed_operation = None
                _atomic_write(path, journal)
                if test_fail_after and operation_index == test_fail_after:
                    failed_operation = entry["id"]
                    raise TransactionError(f"injected integration-test failure after operation {operation_index}")
        except BaseException as error:
            journal["status"] = "failed"
            journal["failed_operation"] = failed_operation
            journal["error"] = _redact(f"{type(error).__name__}: {error}")
            rollback_errors = _rollback_entries(journal)
            journal["status"] = "rollback_failed" if rollback_errors else "rolled_back"
            journal["completed_at"] = _utc_now()
            if rollback_errors:
                journal["error"] = _redact(f"{journal['error']}; rollback: {'; '.join(rollback_errors)}")
            _atomic_write(path, journal)
            if isinstance(error, (KeyboardInterrupt, SystemExit)):
                raise
            raise TransactionError(
                f"Apply failed at {failed_operation}; changes were rolled back: {_redact(error)}"
            ) from error

        journal["status"] = "complete"
        journal["completed_at"] = _utc_now()
        _atomic_write(path, journal)
    print(f"Applied {len(operations)} operation(s). Journal: {path}")
    return path, 0


def _load_journals() -> list[tuple[Path, dict[str, object]]]:
    journals = []
    for path in _journal_root().glob("*.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(data, dict) and data.get("journal_version") == JOURNAL_VERSION:
            journals.append((path, data))

    def creation_order(item: tuple[Path, dict[str, object]]) -> tuple[int, str]:
        path, data = item
        created_at_ns = data.get("created_at_ns")
        if isinstance(created_at_ns, int):
            return created_at_ns, str(data.get("started_at", ""))
        try:
            return path.stat().st_mtime_ns, str(data.get("started_at", ""))
        except OSError:
            return 0, str(data.get("started_at", ""))

    return sorted(journals, key=creation_order, reverse=True)


def rollback_last() -> int:
    """Roll back the latest completed or interrupted eligible transaction."""
    eligible = [
        (path, data) for path, data in _load_journals() if data.get("status") in {"complete", *INCOMPLETE_STATUSES}
    ]
    if not eligible:
        raise TransactionError("No eligible transaction is available to roll back")
    path, journal = eligible[0]
    with _apply_lock():
        errors = _rollback_entries(journal)
        journal["status"] = "rollback_failed" if errors else "rolled_back"
        journal["completed_at"] = _utc_now()
        journal["error"] = _redact("; ".join(errors)) if errors else None
        _atomic_write(path, journal)
    if errors:
        raise TransactionError(f"Rollback requires manual recovery: {_redact('; '.join(errors))}")
    print(f"Rolled back transaction {journal['transaction_id']}.")
    return 0


def incomplete_journals() -> list[Path]:
    return [path for path, data in _load_journals() if data.get("status") in INCOMPLETE_STATUSES]


def cli(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Apply or roll back managed links transactionally")
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--platform", choices=("linux", "macos", "windows"), default=None)
    parser.add_argument("--profile", help="portable capability profile (explicit overrides local default)")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("apply", help="validate and transactionally apply managed links")
    rollback_parser = subparsers.add_parser("rollback", help="roll back an eligible transaction")
    rollback_parser.add_argument("--last", action="store_true", required=True)
    status_parser = subparsers.add_parser("status", help="report incomplete transactions")
    status_parser.add_argument("--check-incomplete", action="store_true")
    args = parser.parse_args(argv)

    try:
        if args.command == "apply":
            return apply(args.repo_root, args.platform or get_platform(), args.profile)[1]
        if args.command == "rollback":
            return rollback_last()
        incomplete = incomplete_journals()
        for path in incomplete:
            print(f"Incomplete transaction: {path}")
        if not incomplete:
            print("No incomplete transactions.")
        return 1 if args.check_incomplete and incomplete else 0
    except (OSError, RuntimeError, PlanError, ProfileError, TransactionError) as error:
        print(f"transaction_apply: error: {error}", file=sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(cli())
