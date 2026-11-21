"""Behavioral and security checks for `z <ssh-host>`, SSH host parsing, and ssh-forward."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
SHELL_CONFIG = REPO_ROOT / "home/.config/zsh/.zshrc.d/10-shell.zsh"
PS_SSH_FORWARD = REPO_ROOT / "home/.config/ooodnakov/bin/ssh-forward.ps1"
DISPATCH_SCRIPT = 'source "$1"\n__zoxide_z() { print -r -- "zoxide:$*" }\n_oooconf_z_wrap_zoxide\nshift\n"$@"'

requires_zsh = pytest.mark.skipif(not shutil.which("zsh"), reason="zsh is not available")
requires_unix_zsh = pytest.mark.skipif(
    sys.platform == "win32" or not shutil.which("zsh"),
    reason="requires Unix zsh and python3",
)
requires_pwsh = pytest.mark.skipif(not shutil.which("pwsh"), reason="pwsh is not available")


def _write_ssh_configs(home: Path) -> None:
    ssh = home / ".ssh"
    (ssh / "conf.d").mkdir(parents=True)
    (ssh / "config").write_text(
        "Host direct\n"
        "    HostName 10.0.0.9\n"
        "Host *.wild\n"
        "    User nobody\n"
        "Host host1 host2\n"
        "    User multi\n"
        "# Host commented\n"
        "Include ~/.ssh/conf.d/*\n",
        encoding="utf-8",
    )
    (ssh / "conf.d" / "extra").write_text("Host included\n    HostName 10.0.0.10\n", encoding="utf-8")
    (ssh / "config.local").write_text("Host localonly\n    HostName 10.0.0.11\n", encoding="utf-8")


def _run(
    tmp_path: Path,
    script: str,
    argv: list[str],
    *,
    extra_env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    home = tmp_path / "home"
    home.mkdir(exist_ok=True)
    if not (home / ".ssh").exists():
        _write_ssh_configs(home)

    # `command ssh` bypasses shell functions, so the fake SSH must live on PATH.
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    fake_ssh = bin_dir / "ssh"
    if not fake_ssh.exists():
        fake_ssh.write_text('#!/bin/sh\nprintf "ssh:%s\\n" "$*"\n', encoding="utf-8")
        fake_ssh.chmod(0o755)

    runtime_dir = tmp_path / "runtime"
    runtime_dir.mkdir(exist_ok=True)

    env = os.environ.copy()
    env.update(
        {
            "HOME": str(home),
            "XDG_CACHE_HOME": str(home / ".cache"),
            "XDG_RUNTIME_DIR": runtime_dir.as_posix(),
            "LC_ALL": "C",
            "PATH": f"{bin_dir}{os.pathsep}{env['PATH']}",
        }
    )
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        ["zsh", "-dfc", script, "zsh-test", str(SHELL_CONFIG), *argv],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )


@requires_zsh
def test_hosts_follow_include_and_skip_wildcards(tmp_path: Path) -> None:
    result = _run(tmp_path, 'source "$1"\nshift\n"$@"', ["_oooconf_ssh_hosts"])
    assert result.returncode == 0, result.stderr
    assert sorted(result.stdout.split()) == ["direct", "host1", "host2", "included", "localonly"]


@requires_zsh
@pytest.mark.parametrize(
    ("arguments", "expected"),
    [
        (["z", "direct"], "ssh:direct\n"),
        (["z", "direct", "uptime"], "ssh:direct uptime\n"),
        (["z", "included"], "ssh:included\n"),
        (["z", "somedir"], "zoxide:somedir\n"),
        (["z", "--", "direct"], "zoxide:-- direct\n"),
        (["z", "-"], "zoxide:-\n"),
        (["z"], "zoxide:\n"),
    ],
)
def test_z_dispatches_hosts_to_ssh(tmp_path: Path, arguments: list[str], expected: str) -> None:
    result = _run(tmp_path, DISPATCH_SCRIPT, arguments)
    assert result.returncode == 0, result.stderr
    assert result.stdout == expected


@requires_unix_zsh
def test_ssh_forward_recent_port_does_not_execute_python_injection(tmp_path: Path) -> None:
    sentinel = tmp_path / "pwned"
    malicious_host = f"''')); from pathlib import Path; Path({str(sentinel)!r}).write_text('pwned'); ('''"
    cache_dir = tmp_path / "home" / ".cache" / "ooodnakov"
    cache_dir.mkdir(parents=True)
    (cache_dir / "ssh-forward-recent.json").write_text(
        json.dumps({malicious_host: 9443, "direct": 8080}),
        encoding="utf-8",
    )

    result = _run(tmp_path, 'source "$1"\nshift\n_ssh_forward_recent_port "$1"', [malicious_host])
    assert result.returncode == 0, result.stderr
    assert not sentinel.exists()
    assert result.stdout.strip() == "9443"


@requires_zsh
@pytest.mark.parametrize(
    "arguments",
    [
        ["-oProxyCommand=evil", "8080"],
        ["-r", "-oProxyCommand=evil", "8080"],
        ["host/evil", "8080"],
        ["host..evil", "8080"],
        [".", "8080"],
        ["direct", "0"],
        ["direct", "65536"],
        ["direct", "080"],
        ["direct", "notaport"],
        ["direct", "8080", "70000"],
    ],
)
def test_ssh_forward_rejects_invalid_host_and_ports(tmp_path: Path, arguments: list[str]) -> None:
    result = _run(tmp_path, 'source "$1"\nshift\nssh-forward "$@"', arguments)
    assert result.returncode == 1


def test_10_shell_zsh_security_invariants() -> None:
    text = SHELL_CONFIG.read_text(encoding="utf-8")
    assert "/tmp/ssh-fwd-" not in text
    assert "http://api.db-ip.com" not in text
    assert "https://api.db-ip.com/v2/free/" in text
    assert re.search(r"^\s*_ssh_forward_socket_dir\s*\(\)", text, re.M)
    assert text.count('-- "$host"') >= 2
    assert not re.search(r"python3\s+-c\b.*(?:\$host|\$cache)", text, re.S)


def test_ssh_forward_ps1_security_invariants() -> None:
    text = PS_SSH_FORWARD.read_text(encoding="utf-8")
    assert "StartTimeUtc" in text
    assert "$proc.ProcessName" in text
    assert text.count("'--', $sshHostArg") == 2
    assert "$Hostname -replace" in text


@requires_pwsh
def test_ssh_forward_ps1_parses_cleanly() -> None:
    escaped = str(PS_SSH_FORWARD).replace("'", "''")
    ps_cmd = (
        "$tokens = $null; $errors = $null; "
        f"$null = [System.Management.Automation.Language.Parser]::ParseFile('{escaped}', [ref]$tokens, [ref]$errors); "
        "if ($errors.Count -gt 0) { $errors | Out-String | Write-Error; exit 1 }"
    )
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", ps_cmd],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
