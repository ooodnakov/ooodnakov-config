"""Behavioral checks for `z <ssh-host>` dispatch and SSH host parsing."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
SHELL_CONFIG = REPO_ROOT / "home/.config/zsh/.zshrc.d/10-shell.zsh"
DISPATCH_SCRIPT = 'source "$1"\n__zoxide_z() { print -r -- "zoxide:$*" }\n_oooconf_z_wrap_zoxide\nshift\n"$@"'

pytestmark = pytest.mark.skipif(not shutil.which("zsh"), reason="zsh is not available")


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


def _run(tmp_path: Path, script: str, argv: list[str]) -> subprocess.CompletedProcess[str]:
    home = tmp_path / "home"
    home.mkdir()
    _write_ssh_configs(home)

    # `command ssh` bypasses shell functions, so the fake SSH must live on PATH.
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    fake_ssh = bin_dir / "ssh"
    fake_ssh.write_text('#!/bin/sh\nprintf "ssh:%s\\n" "$*"\n', encoding="utf-8")
    fake_ssh.chmod(0o755)

    env = os.environ.copy()
    env.update({"HOME": str(home), "LC_ALL": "C", "PATH": f"{bin_dir}{os.pathsep}{env['PATH']}"})
    return subprocess.run(
        ["zsh", "-dfc", script, "zsh-test", str(SHELL_CONFIG), *argv],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )


def test_hosts_follow_include_and_skip_wildcards(tmp_path: Path) -> None:
    result = _run(tmp_path, 'source "$1"\nshift\n"$@"', ["_oooconf_ssh_hosts"])
    assert result.returncode == 0, result.stderr
    assert sorted(result.stdout.split()) == ["direct", "host1", "host2", "included", "localonly"]


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
