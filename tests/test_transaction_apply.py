"""Integration tests for transactional managed-link application."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from scripts.cli import transaction_apply  # noqa: E402


def _repo(tmp_path: Path) -> tuple[Path, Path]:
    repo = tmp_path / "repo"
    source = repo / "home/.config/example"
    source.mkdir(parents=True)
    (source / "config.toml").write_text("managed = true\n", encoding="utf-8")
    scripts = repo / "scripts"
    scripts.mkdir()
    (scripts / "links.toml").write_text(
        """
[discovery]
autolink_dirs = []

[[links]]
key = "example"
source = "home/.config/example"
target = "{CONFIG_HOME}/example"
""",
        encoding="utf-8",
    )
    return repo, source


def _configure_home(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> Path:
    home = tmp_path / "home"
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(home / ".config"))
    monkeypatch.setenv("XDG_STATE_HOME", str(home / ".local/state"))
    return home


def _journals(home: Path) -> list[Path]:
    return sorted((home / ".local/state/ooodnakov-config/transactions").glob("*.json"))


def test_apply_is_journaled_idempotent_and_rollback_restores_backup(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    repo, source = _repo(tmp_path)
    home = _configure_home(monkeypatch, tmp_path)
    target = home / ".config/example"
    target.parent.mkdir(parents=True)
    target.write_text("user config\n", encoding="utf-8")

    journal_path, result = transaction_apply.apply(repo, "linux")
    assert result == 0
    assert journal_path is not None
    assert target.is_symlink()
    assert target.resolve() == source.resolve()
    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    assert journal["status"] == "complete"
    assert all(entry["status"] == "completed" for entry in journal["operations"])
    if os.name != "nt":
        assert journal_path.stat().st_mode & 0o777 == 0o600

    existing_journals = _journals(home)
    second_path, second_result = transaction_apply.apply(repo, "linux")
    assert second_result == 0
    assert second_path is None
    assert _journals(home) == existing_journals

    assert transaction_apply.rollback_last() == 0
    assert not target.is_symlink()
    assert target.read_text(encoding="utf-8") == "user config\n"
    assert json.loads(journal_path.read_text(encoding="utf-8"))["status"] == "rolled_back"


def test_apply_failure_rolls_back_and_redacts_secret(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    repo, _source = _repo(tmp_path)
    home = _configure_home(monkeypatch, tmp_path)
    target = home / ".config/example"
    target.parent.mkdir(parents=True)
    target.write_text("original\n", encoding="utf-8")
    secret = "sentinel-super-secret"
    monkeypatch.setenv("TEST_API_TOKEN", secret)
    original_apply_entry = transaction_apply._apply_entry

    def fail_link(entry: dict[str, object], transaction_id: str) -> None:
        if entry["kind"] == "link":
            raise transaction_apply.TransactionError(f"injected failure {secret}")
        original_apply_entry(entry, transaction_id)

    monkeypatch.setattr(transaction_apply, "_apply_entry", fail_link)
    with pytest.raises(transaction_apply.TransactionError) as raised:
        transaction_apply.apply(repo, "linux")

    assert secret not in str(raised.value)
    assert target.read_text(encoding="utf-8") == "original\n"
    journal_path = _journals(home)[0]
    journal_text = journal_path.read_text(encoding="utf-8")
    assert secret not in journal_text
    assert json.loads(journal_text)["status"] == "rolled_back"


def test_rollback_never_deletes_user_modified_target(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    repo, _source = _repo(tmp_path)
    home = _configure_home(monkeypatch, tmp_path)
    target = home / ".config/example"

    journal_path, _result = transaction_apply.apply(repo, "linux")
    assert journal_path is not None
    target.unlink()
    target.write_text("created after apply\n", encoding="utf-8")

    with pytest.raises(transaction_apply.TransactionError, match="manual recovery"):
        transaction_apply.rollback_last()
    assert target.read_text(encoding="utf-8") == "created after apply\n"
    assert json.loads(journal_path.read_text(encoding="utf-8"))["status"] == "rollback_failed"


def test_active_lock_blocks_concurrent_apply(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    repo, _source = _repo(tmp_path)
    home = _configure_home(monkeypatch, tmp_path)
    lock = home / ".local/state/ooodnakov-config/apply.lock"
    lock.mkdir(parents=True)
    (lock / "owner.json").write_text(json.dumps({"pid": os.getpid()}), encoding="utf-8")

    with pytest.raises(transaction_apply.TransactionError, match="Another apply or rollback is active"):
        transaction_apply.apply(repo, "linux")
    assert not (home / ".config/example").exists()


def test_incomplete_journals_are_reported(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    home = _configure_home(monkeypatch, tmp_path)
    journal_root = home / ".local/state/ooodnakov-config/transactions"
    journal_root.mkdir(parents=True)
    incomplete = journal_root / "incomplete.json"
    incomplete.write_text(json.dumps({"journal_version": 1, "status": "applying"}), encoding="utf-8")
    complete = journal_root / "complete.json"
    complete.write_text(json.dumps({"journal_version": 1, "status": "complete"}), encoding="utf-8")

    assert transaction_apply.incomplete_journals() == [incomplete]


@pytest.mark.skipif(sys.platform == "win32", reason="Bash CLI integration is Unix-only")
def test_unix_cli_apply_is_idempotent_and_rollback_restores_user_file(tmp_path: Path) -> None:
    home = tmp_path / "home"
    home.mkdir()
    original = home / ".zshrc"
    original.write_text("original\n", encoding="utf-8")
    env = os.environ.copy()
    env.update(
        {
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(home / ".config"),
            "XDG_DATA_HOME": str(home / ".local/share"),
            "XDG_STATE_HOME": str(home / ".local/state"),
        }
    )

    def run(*arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", "scripts/setup/ooodnakov.sh", *arguments],
            cwd=REPO_ROOT,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

    first = run("apply", "--profile", "minimal")
    assert first.returncode == 0, first.stderr
    assert original.is_symlink()
    assert not (home / ".config/nvim").exists()
    journal_count = len(_journals(home))
    journal = json.loads(_journals(home)[0].read_text(encoding="utf-8"))
    assert journal["profile"] == "minimal"

    second = run("apply", "--profile", "minimal")
    assert second.returncode == 0, second.stderr
    assert "No changes required." in second.stdout
    assert len(_journals(home)) == journal_count

    rollback = run("rollback", "--last")
    assert rollback.returncode == 0, rollback.stderr
    assert not original.is_symlink()
    assert original.read_text(encoding="utf-8") == "original\n"
