from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
TOOL = REPO_ROOT / "scripts/cli/env_tool.py"


def run_env(config_home: Path, *args: str) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["XDG_CONFIG_HOME"] = str(config_home)
    return subprocess.run(
        [sys.executable, str(TOOL), *args],
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )


def test_env_writes_and_updates_both_local_override_files(tmp_path: Path) -> None:
    first = run_env(tmp_path, "SUPER_TOKEN", "a value's $HOME")
    assert first.returncode == 0, first.stderr

    zsh = tmp_path / "ooodnakov/local/env.zsh"
    ps1 = tmp_path / "ooodnakov/local/env.ps1"
    assert "export SUPER_TOKEN='a value'\"'\"'s $HOME'" in zsh.read_text(encoding="utf-8")
    assert "$env:SUPER_TOKEN = 'a value''s $HOME'" in ps1.read_text(encoding="utf-8")

    second = run_env(tmp_path, "SUPER_TOKEN", "replacement")
    assert second.returncode == 0, second.stderr
    assert zsh.read_text(encoding="utf-8").count("export SUPER_TOKEN=") == 1
    assert "export SUPER_TOKEN=replacement" in zsh.read_text(encoding="utf-8")
    assert ps1.read_text(encoding="utf-8").count("$env:SUPER_TOKEN = ") == 1


def test_env_preserves_content_outside_managed_block(tmp_path: Path) -> None:
    target = tmp_path / "ooodnakov/local/env.zsh"
    target.parent.mkdir(parents=True)
    target.write_text(f"generated\n{START}\nexport OLD=yes\n{END}\ntail\n", encoding="utf-8")

    result = run_env(tmp_path, "NEW", "yes")
    assert result.returncode == 0, result.stderr
    assert target.read_text(encoding="utf-8").startswith("generated\n")
    assert target.read_text(encoding="utf-8").endswith("tail\n")


def test_env_help_alias_and_invalid_key(tmp_path: Path) -> None:
    help_result = run_env(tmp_path, "help")
    assert help_result.returncode == 0
    assert "oooconf env" in help_result.stdout
    invalid = run_env(tmp_path, "BAD-NAME", "value")
    assert invalid.returncode == 1
    assert "invalid environment variable name" in invalid.stderr


START = "# --- LOCAL OVERRIDES START ---"
END = "# --- LOCAL OVERRIDES END ---"
