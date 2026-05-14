from __future__ import annotations

import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def run_script(script: str, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, script, *args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=30,
    )


def test_secrets_script_resolves_shared_cli_ui_when_run_directly() -> None:
    result = run_script("scripts/generate/render_secrets.py", "--help")

    assert result.returncode == 0, result.stderr
    assert "oooconf secrets" in result.stdout


def test_update_pins_script_resolves_shared_cli_ui_when_run_directly() -> None:
    result = run_script("scripts/update/update_pins.py", "--help")

    assert result.returncode == 0, result.stderr
    assert "Check/update pinned git refs" in result.stdout


def test_update_pins_script_exercises_non_help_path_when_run_directly() -> None:
    result = run_script("scripts/update/update_pins.py", "--offline", "--dry-run")

    assert result.returncode == 0, result.stderr
    assert "Dependency Pin Status" in result.stdout
    assert "Dry run: skipped report and lock artifact writes." in result.stdout
