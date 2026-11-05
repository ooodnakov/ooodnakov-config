"""Static smoke checks for managed terminal/editor config and completions."""

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


def test_setup_entrypoint_module_references_exist() -> None:
    """Keep sourced/dot-sourced setup modules in sync with their thin entrypoints."""
    referenced: set[Path] = set()
    for entrypoint in ["scripts/setup/setup.sh", "scripts/setup/ooodnakov.sh"]:
        content = (REPO_ROOT / entrypoint).read_text(encoding="utf-8")
        referenced.update(Path(match) for match in re.findall(r'source "\$REPO_ROOT/([^"]+)"', content))

    for entrypoint in ["scripts/setup/setup.ps1", "scripts/setup/ooodnakov.ps1"]:
        content = (REPO_ROOT / entrypoint).read_text(encoding="utf-8")
        referenced.update(
            Path(match)
            for match in re.findall(r'Join-Path \$RepoRoot "([^"]+)"', content)
            if match.startswith("scripts/setup/lib/")
        )

    assert referenced, "No setup modules were referenced by entrypoints"
    missing = [path for path in sorted(referenced) if not (REPO_ROOT / path).is_file()]
    assert not missing, f"Missing sourced setup modules: {missing}"


def test_unix_help_smoke() -> None:
    """Verify the Unix CLI help surface renders key commands cleanly."""
    if sys.platform == "win32" or not shutil.which("bash"):
        pytest.skip("bash is not available")

    result = subprocess.run(
        ["bash", "scripts/setup/ooodnakov.sh", "--help"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=SUBPROCESS_TIMEOUT_SECONDS,
        env={"OOODNAKOV_REPO_ROOT": str(REPO_ROOT)},
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
        ["bash", "scripts/setup/ooodnakov.sh", "help", command],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=SUBPROCESS_TIMEOUT_SECONDS,
        env={"OOODNAKOV_REPO_ROOT": str(REPO_ROOT)},
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


def test_managed_zshrc_tolerates_missing_oh_my_zsh(tmp_path: Path) -> None:
    """A failed/partial bootstrap should not leave new shells with source errors."""
    if sys.platform == "win32" or not shutil.which("zsh"):
        pytest.skip("zsh is not available")

    env = os.environ.copy()
    env.update(
        {
            "HOME": str(tmp_path),
            "XDG_CONFIG_HOME": str(tmp_path / "config"),
            "ZDOTDIR": str(REPO_ROOT / "home/.config/zsh"),
            "XDG_DATA_HOME": str(tmp_path / "share"),
            "XDG_STATE_HOME": str(tmp_path / "state"),
            "XDG_CACHE_HOME": str(tmp_path / "cache"),
            "OOOCONF_ZSH_PROMPT": "p10k",
        }
    )
    result = subprocess.run(
        ["zsh", "-dfc", "source home/.config/zsh/.zshrc"],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        timeout=SUBPROCESS_TIMEOUT_SECONDS,
    )
    assert result.returncode == 0, result.stderr
    assert "no such file or directory" not in result.stderr
    assert "oh-my-zsh is missing" in result.stderr


def test_powershell_font_dry_run_does_not_mutate(tmp_path: Path) -> None:
    """Previewing font installation must not copy files or write the registry."""
    if not shutil.which("pwsh"):
        pytest.skip("pwsh is not available")

    script = tmp_path / "font-dry-run.ps1"
    script.write_text(
        r"""param([string]$RepoRoot, [string]$FontHome)
$ErrorActionPreference = 'Stop'
$DryRun = $true
$env:LOCALAPPDATA = $FontHome
function Invoke-Action { param($Description, $Action) return $true }
function Write-UiLine { param($Role, $Message) Write-Output $Message }
function Add-ToolSummary { param($Message) }
. (Join-Path $RepoRoot 'scripts/setup/lib/setup-links.ps1')
function Copy-Item { throw 'dry-run attempted to copy a font' }
function New-Item { throw 'dry-run attempted to create a file or registry key' }
function New-ItemProperty { throw 'dry-run attempted to register a font' }
function Send-FontChangeBroadcast { throw 'dry-run attempted to notify applications' }
Install-MesloFontsIfMissing
""",
        encoding="utf-8",
    )
    font_home = tmp_path / "font-home"
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-File", str(script), str(REPO_ROOT), str(font_home)],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=SUBPROCESS_TIMEOUT_SECONDS,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "[dry-run]" in result.stdout
    assert not font_home.exists()
