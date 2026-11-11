"""`oooconf secrets login` unlocks the vault and persists the session."""

from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("render_secrets_login_test", ROOT / "scripts/generate/render_secrets.py")
assert _spec is not None and _spec.loader is not None
secrets = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = secrets
_spec.loader.exec_module(secrets)

SUCCESS = 0


class _Tty:
    encoding = "utf-8"

    def __init__(self, stream=None):
        self._stream = stream

    def isatty(self):
        return True

    def write(self, data):
        return self._stream.write(data) if self._stream else len(data)

    def flush(self):
        if self._stream:
            self._stream.flush()

    def __getattr__(self, name):
        return getattr(self._stream, name)


def _args(**overrides) -> argparse.Namespace:
    values = {
        "server": "https://vault.example",
        "method": "password",
        "client_id": None,
        "client_secret": None,
    }
    values.update(overrides)
    return argparse.Namespace(**values)


class _Result:
    def __init__(self, returncode=0, stdout="", stderr=""):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


def _fake_run(calls, login_rc=0, unlock_rc=0, token="session-token"):
    def run(command, **kwargs):
        calls.append((command, kwargs))
        if command[:2] == ["bw", "config"]:
            return _Result()
        if command[:2] == ["bw", "login"]:
            return _Result(returncode=login_rc, stderr="login failed" if login_rc else "")
        if command[:2] == ["bw", "unlock"]:
            return _Result(returncode=unlock_rc, stdout=f"{token}\n", stderr="bad password" if unlock_rc else "")
        raise AssertionError(f"unexpected command: {command}")

    return run


def _interactive(monkeypatch) -> None:
    monkeypatch.setattr(secrets.sys, "stdin", _Tty())
    monkeypatch.setattr(secrets.sys, "stdout", _Tty(secrets.sys.stdout))


def test_login_prompts_for_unlock_and_persists_session(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setattr(secrets, "shutil_which", lambda name: "/usr/bin/bw")
    _interactive(monkeypatch)
    calls: list[tuple[list[str], dict]] = []
    monkeypatch.setattr(secrets.subprocess, "run", _fake_run(calls))

    prompts: list[str] = []

    def fake_getpass(prompt=""):
        prompts.append(prompt)
        return "master-password"

    monkeypatch.setattr(secrets.getpass, "getpass", fake_getpass)

    assert secrets.login_command(_args()) == SUCCESS

    assert prompts == ["Bitwarden master password (unlock vault): "]
    unlock_calls = [command for command, _ in calls if command[:2] == ["bw", "unlock"]]
    assert unlock_calls == [["bw", "unlock", "--raw", "--passwordenv", "BW_PASSWORD"]]
    assert any(kwargs.get("env", {}).get("BW_PASSWORD") == "master-password" for _, kwargs in calls)

    session = tmp_path / ".config/ooodnakov/local/bw-session"
    assert session.read_text(encoding="utf-8").strip() == "session-token"


def test_login_failure_does_not_prompt(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setattr(secrets, "shutil_which", lambda name: "/usr/bin/bw")
    _interactive(monkeypatch)
    calls: list[tuple[list[str], dict]] = []
    monkeypatch.setattr(secrets.subprocess, "run", _fake_run(calls, login_rc=1))
    monkeypatch.setattr(
        secrets.getpass,
        "getpass",
        lambda prompt="": pytest.fail("must not prompt after a failed login"),
    )

    assert secrets.login_command(_args()) == 1
    assert not (tmp_path / ".config/ooodnakov/local/bw-session").exists()
    assert not any(command[:2] == ["bw", "unlock"] for command, _ in calls)


def test_cancelled_unlock_keeps_login_successful(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setattr(secrets, "shutil_which", lambda name: "/usr/bin/bw")
    _interactive(monkeypatch)
    calls: list[tuple[list[str], dict]] = []
    monkeypatch.setattr(secrets.subprocess, "run", _fake_run(calls))

    def cancel(prompt=""):
        raise KeyboardInterrupt

    monkeypatch.setattr(secrets.getpass, "getpass", cancel)

    assert secrets.login_command(_args()) == SUCCESS
    assert not (tmp_path / ".config/ooodnakov/local/bw-session").exists()


def test_wrong_password_keeps_login_successful_without_session(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setattr(secrets, "shutil_which", lambda name: "/usr/bin/bw")
    _interactive(monkeypatch)
    calls: list[tuple[list[str], dict]] = []
    monkeypatch.setattr(secrets.subprocess, "run", _fake_run(calls, unlock_rc=1))
    monkeypatch.setattr(secrets.getpass, "getpass", lambda prompt="": "wrong-password")

    assert secrets.login_command(_args()) == SUCCESS
    assert not (tmp_path / ".config/ooodnakov/local/bw-session").exists()


def test_non_interactive_login_does_not_prompt(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setattr(secrets, "shutil_which", lambda name: "/usr/bin/bw")
    monkeypatch.setattr(secrets.sys, "stdin", _Tty())  # isatty but stdout redirected
    monkeypatch.setattr(secrets.sys, "stdout", _Tty())
    calls: list[tuple[list[str], dict]] = []
    monkeypatch.setattr(secrets.subprocess, "run", _fake_run(calls))
    monkeypatch.setattr(
        secrets.getpass,
        "getpass",
        lambda prompt="": pytest.fail("must not prompt without a tty"),
    )

    class _NotTty(_Tty):
        def isatty(self):
            return False

    monkeypatch.setattr(secrets.sys, "stdout", _NotTty())

    assert secrets.login_command(_args()) == SUCCESS
    assert not any(command[:2] == ["bw", "unlock"] for command, _ in calls)
