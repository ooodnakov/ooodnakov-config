"""`oooconf secrets login` unlocks the vault and persists the session."""

from __future__ import annotations

import argparse
import importlib.util
import os
import shutil
import subprocess
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


def test_bw_session_passed_via_env_never_argv(monkeypatch) -> None:
    token = "top-secret-session"
    monkeypatch.setenv("BW_SESSION", token)
    calls: list[tuple[list[str], dict]] = []

    def fake_run(command, **kwargs):
        calls.append((command, kwargs))
        if command == ["bw", "sync"]:
            return _Result(stdout="")
        if command == ["bw", "list", "items"]:
            return _Result(stdout='[{"id": "item-123"}]')
        if command == ["bw", "get", "item", "item-123"]:
            return _Result(stdout='{"id": "item-123", "notes": "val"}')
        raise AssertionError(f"unexpected command: {command}")

    monkeypatch.setattr(secrets.subprocess, "run", fake_run)

    secrets.sync_bw_vault({"BW_SESSION": token})
    assert secrets.fetch_all_bw_items() == [{"id": "item-123"}]
    assert secrets.read_bw_item("item-123", "MY_KEY") == {"id": "item-123", "notes": "val"}

    assert [cmd for cmd, _ in calls] == [
        ["bw", "sync"],
        ["bw", "sync"],
        ["bw", "list", "items"],
        ["bw", "sync"],
        ["bw", "get", "item", "item-123"],
    ]
    for command, kwargs in calls:
        assert "--session" not in command
        assert token not in command
        assert kwargs["env"]["BW_SESSION"] == token


def test_powershell_assignment_prevents_injection_and_roundtrips() -> None:
    unsafe_payloads = [
        "line1\n'@\n$env:PWNED = 'yes'\n$x = @'\nline2",
        "line1\r'@; $env:PWNED = 'yes'",
        "left\u2018; $env:PWNED = 'yes'; \u2018right",
        "left\u2019; $env:PWNED = 'yes'; \u2019right",
        "left\u201a; $env:PWNED = 'yes'; \u201aright",
        "left\u201b; $env:PWNED = 'yes'; \u201bright",
    ]
    for payload in unsafe_payloads:
        rendered = secrets.powershell_assignment("TEST_SECRET", payload)
        assert "[System.Convert]::FromBase64String(" in rendered
        assert "$env:PWNED" not in rendered
        assert "@'" not in rendered

    normal_payload = "plain'quote"
    assert secrets.powershell_assignment("TEST_SECRET", normal_payload) == "$env:TEST_SECRET = 'plain''quote'"

    pwsh = shutil.which("pwsh")
    if pwsh is not None:
        for payload in [*unsafe_payloads, normal_payload]:
            rendered = secrets.powershell_assignment("TEST_SECRET", payload)
            script = (
                "Remove-Item Env:PWNED -ErrorAction SilentlyContinue\n"
                f"{rendered}\n"
                "if (Test-Path Env:PWNED) { exit 42 }\n"
                "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8\n"
                "[Console]::Write($env:TEST_SECRET)\n"
            )
            proc = subprocess.run(
                [pwsh, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", "-"],
                input=script.encode("utf-8"),
                capture_output=True,
                check=False,
            )
            assert proc.returncode == 0, proc.stderr.decode("utf-8", errors="replace")
            assert proc.stdout.decode("utf-8") == payload


def test_unlock_pwsh_uses_safe_powershell_assignment(monkeypatch, capsys) -> None:
    token = "tok\u2019; $env:PWNED = 'yes'"
    monkeypatch.setattr(secrets, "shutil_which", lambda name: "/usr/bin/bw")
    monkeypatch.setattr(
        secrets.subprocess,
        "run",
        lambda command, **kwargs: _Result(stdout=f"{token}\n"),
    )

    rc = secrets.unlock_command(
        argparse.Namespace(password=None, shell="pwsh", raw=False, explicit_shell=True, explicit_raw=False)
    )
    assert rc == SUCCESS
    out = capsys.readouterr().out.strip()
    assert out == secrets.powershell_assignment("BW_SESSION", token)
    assert "$env:PWNED" not in out


def test_write_persisted_bw_session_and_write_file_atomic(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setattr(secrets.Path, "home", lambda: tmp_path)
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("USERPROFILE", str(tmp_path))

    session_path = secrets.write_persisted_bw_session("session-1")
    assert session_path == tmp_path / ".config/ooodnakov/local/bw-session"
    assert session_path.read_text(encoding="utf-8") == "session-1\n"
    assert list(session_path.parent.iterdir()) == [session_path]
    if os.name != "nt":
        assert (session_path.stat().st_mode & 0o777) == 0o600
        assert (session_path.parent.stat().st_mode & 0o777) == 0o700

    with monkeypatch.context() as mp:

        def fail_replace(src, dst):
            raise OSError("simulated replace failure")

        mp.setattr(secrets.os, "replace", fail_replace)
        with pytest.raises(OSError, match="simulated replace failure"):
            secrets.write_persisted_bw_session("session-2")

    assert session_path.read_text(encoding="utf-8") == "session-1\n"
    assert list(session_path.parent.iterdir()) == [session_path]

    env_file = tmp_path / "local/env.zsh"
    assert secrets.write_file(env_file, "export A=1\n", force=False) == "created"
    assert list(env_file.parent.iterdir()) == [env_file]
    assert secrets.write_file(env_file, "export A=2\n", force=False) == "updated"
    assert list(env_file.parent.iterdir()) == [env_file]
    if os.name != "nt":
        assert (env_file.stat().st_mode & 0o777) == 0o600

    with monkeypatch.context() as mp:
        mp.setattr(secrets.os, "replace", lambda src, dst: (_ for _ in ()).throw(OSError("disk full")))
        with pytest.raises(OSError, match="disk full"):
            secrets.write_file(env_file, "export A=3\n", force=False)

    assert "export A=2\n" in env_file.read_text(encoding="utf-8")
    assert list(env_file.parent.iterdir()) == [env_file]


def test_cli_secret_args_warn_and_preserve_behavior(monkeypatch, tmp_path: Path, capsys) -> None:
    monkeypatch.setattr(secrets.Path, "home", lambda: tmp_path)
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("USERPROFILE", str(tmp_path))
    monkeypatch.setattr(secrets, "shutil_which", lambda name: "/usr/bin/bw")
    calls: list[tuple[list[str], dict]] = []
    monkeypatch.setattr(secrets.subprocess, "run", _fake_run(calls, token="cli-unlock-token"))

    rc_unlock = secrets.unlock_command(
        argparse.Namespace(password="cli-pw", shell="sh", raw=False, explicit_shell=False, explicit_raw=False)
    )
    assert rc_unlock == SUCCESS
    unlock_out = capsys.readouterr().out
    assert "BW_PASSWORD" in unlock_out
    assert "command line" in unlock_out.lower()
    assert (tmp_path / ".config/ooodnakov/local/bw-session").read_text(encoding="utf-8").strip() == "cli-unlock-token"
    assert any(kwargs.get("env", {}).get("BW_PASSWORD") == "cli-pw" for _, kwargs in calls)

    calls.clear()

    class _NotTty(_Tty):
        def isatty(self):
            return False

    monkeypatch.setattr(secrets.sys, "stdout", _NotTty(secrets.sys.stdout))
    rc_login = secrets.login_command(_args(method="apikey", client_id="cli-id", client_secret="cli-secret"))
    assert rc_login == SUCCESS
    login_out = capsys.readouterr().out
    assert "--client-secret" in login_out
    assert "BW_CLIENTSECRET" in login_out
    assert any(
        cmd == ["bw", "login", "--apikey"]
        and kwargs.get("env", {}).get("BW_CLIENTID") == "cli-id"
        and kwargs.get("env", {}).get("BW_CLIENTSECRET") == "cli-secret"
        for cmd, kwargs in calls
    )
