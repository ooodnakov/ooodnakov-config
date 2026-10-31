"""Behavioral checks for the managed a/aa directory-listing shortcuts."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
SHELL_CONFIG = REPO_ROOT / "home/.config/zsh/.zshrc.d/10-shell.zsh"
EZA_OPTIONS = [
    "-lah",
    "--git",
    "--color-scale",
    "all",
    "-g",
    "--smart-group",
    "--icons",
    "always",
    "--hyperlink",
    "auto",
]
pytestmark = pytest.mark.skipif(not shutil.which("zsh"), reason="zsh is not available")


def test_a_replaces_existing_alias_and_can_be_reloaded(tmp_path: Path) -> None:
    result = subprocess.run(
        [
            "zsh",
            "-dfc",
            'alias a=false; source "$1"; source "$1"; (( $+functions[a] && ! $+aliases[a] ))',
            "zsh-test",
            str(SHELL_CONFIG),
        ],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    assert result.stderr == ""


@pytest.mark.parametrize(
    ("shortcut", "arguments", "extra_options"),
    [
        ("a", [], []),
        ("a", ["directory with spaces"], []),
        ("a", ["file with spaces.txt", "literal[1].txt"], []),
        ("a", ["--sort", "size", "--reverse"], []),
        ("a", ["--", "-leading-dash.txt"], []),
        ("a", ["missing directory"], []),
        ("aa", [], ["-s", "modified", "-r"]),
    ],
)
def test_listing_matches_eza(tmp_path: Path, shortcut: str, arguments: list[str], extra_options: list[str]) -> None:
    if not shutil.which("eza"):
        pytest.skip("eza is not available")

    (tmp_path / "directory with spaces").mkdir()
    for name in [".hidden", "file with spaces.txt", "literal[1].txt", "-leading-dash.txt"]:
        (tmp_path / name).touch()
    env = os.environ.copy()
    env.update({"TERM": "xterm-256color", "LC_ALL": "C"})
    actual = subprocess.run(
        [
            "zsh",
            "-dfc",
            f'source "$1"\nshift\n{shortcut} "$@"',
            "zsh-test",
            str(SHELL_CONFIG),
            *arguments,
        ],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        timeout=30,
    )
    expected = subprocess.run(
        ["eza", *EZA_OPTIONS, *extra_options, *arguments],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        timeout=30,
    )
    assert (actual.returncode, actual.stdout, actual.stderr) == (
        expected.returncode,
        expected.stdout,
        expected.stderr,
    )
