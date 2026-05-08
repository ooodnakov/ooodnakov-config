"""Static smoke checks for managed terminal/editor config and completions."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
SUBPROCESS_TIMEOUT_SECONDS = int(os.environ.get("OOOCONF_TEST_TIMEOUT", "60"))


@pytest.mark.parametrize(
    "path",
    [
        Path("home/.config/nvim/lazy-lock.json"),
        Path("home/.config/nvim/lazyvim.json"),
    ],
)
def test_managed_neovim_json_is_valid(path: Path) -> None:
    """Validate tracked Neovim JSON files without launching Neovim."""
    json.loads((REPO_ROOT / path).read_text(encoding="utf-8"))


@pytest.mark.parametrize(
    "path",
    [
        Path("home/.config/nvim/init.lua"),
        Path("home/.config/nvim/lua/config/lazy.lua"),
        Path("home/.config/wezterm/wezterm.lua"),
        Path("home/.config/wezterm/config/init.lua"),
    ],
)
def test_managed_terminal_entrypoints_exist(path: Path) -> None:
    """Catch accidental removal of core managed Neovim/WezTerm entrypoints."""
    assert (REPO_ROOT / path).is_file()


def test_unix_help_smoke() -> None:
    """Verify the Unix CLI help surface renders key commands cleanly."""
    if sys.platform == "win32" or not shutil.which("bash"):
        pytest.skip("bash is not available")

    result = subprocess.run(
        ["bash", "scripts/ooodnakov.sh", "--help"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=SUBPROCESS_TIMEOUT_SECONDS,
    )
    assert result.returncode == 0, result.stderr
    assert "oooconf install" in result.stdout
    assert "oooconf deps" in result.stdout


@pytest.mark.parametrize("command", ["deps", "secrets", "agents"])
def test_unix_command_help_smoke(command: str) -> None:
    """Verify command-specific help examples render for major command groups."""
    if sys.platform == "win32" or not shutil.which("bash"):
        pytest.skip("bash is not available")

    result = subprocess.run(
        ["bash", "scripts/ooodnakov.sh", "help", command],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=SUBPROCESS_TIMEOUT_SECONDS,
    )
    assert result.returncode == 0, result.stderr
    assert "Examples:" in result.stdout


def test_powershell_completion_file_loads() -> None:
    """Dot-source the managed PowerShell completion file to catch parse/load errors."""
    if not shutil.which("pwsh"):
        pytest.skip("pwsh is not available")

    completion_path = REPO_ROOT / "home/.config/ooodnakov/completions/oooconf-completions.ps1"
    result = subprocess.run(
        [
            "pwsh",
            "-NoProfile",
            "-Command",
            f". '{completion_path.as_posix()}'; 'loaded'",
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=SUBPROCESS_TIMEOUT_SECONDS,
    )
    assert result.returncode == 0, result.stderr
    assert "loaded" in result.stdout
