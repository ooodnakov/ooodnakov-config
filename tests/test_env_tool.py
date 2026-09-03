from __future__ import annotations

import os
import subprocess
import sys
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
from unittest.mock import patch

REPO_ROOT = Path(__file__).resolve().parents[1]
TOOL = REPO_ROOT / "scripts/cli/env_tool.py"
SPEC = spec_from_file_location("env_tool", TOOL)
assert SPEC and SPEC.loader
env_tool = module_from_spec(SPEC)
SPEC.loader.exec_module(env_tool)


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


def test_env_rejects_multiline_values_before_writing(tmp_path: Path) -> None:
    result = run_env(tmp_path, "CERT", "first\nsecond")

    assert result.returncode == 1
    assert "multiline environment variable values are not supported" in result.stderr
    assert not (tmp_path / "ooodnakov/local/env.zsh").exists()
    assert not (tmp_path / "ooodnakov/local/env.ps1").exists()


def test_empty_xdg_config_home_uses_home_config(tmp_path: Path) -> None:
    env = os.environ.copy()
    env["HOME"] = str(tmp_path)
    env["XDG_CONFIG_HOME"] = ""
    result = subprocess.run(
        [sys.executable, str(TOOL), "EMPTY_XDG", "value"],
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert (tmp_path / ".config/ooodnakov/local/env.zsh").exists()


def test_global_dry_run_rejects_env_without_writing(tmp_path: Path) -> None:
    env = os.environ.copy()
    env["XDG_CONFIG_HOME"] = str(tmp_path)
    result = subprocess.run(
        [str(REPO_ROOT / "scripts/setup/ooodnakov.sh"), "--dry-run", "env", "KEY", "value"],
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )

    assert result.returncode == 1
    assert "--dry-run is not supported for env" in result.stderr
    assert not (tmp_path / "ooodnakov/local/env.zsh").exists()


def test_powershell_dispatch_rejects_global_dry_run_for_env() -> None:
    dispatch = (REPO_ROOT / "scripts/setup/ooodnakov.ps1").read_text(encoding="utf-8")
    env_branch = dispatch.split('    "env" {', 1)[1].split("    }", 1)[0]

    assert 'Assert-NoDryRun -CommandName "env"' in env_branch


def test_windows_write_does_not_call_fchmod(tmp_path: Path) -> None:
    with patch.object(env_tool.os, "name", "nt"), patch.object(env_tool.os, "fchmod") as fchmod:
        env_tool.write_override(tmp_path / "env.zsh", "KEY", "export KEY=value")

    fchmod.assert_not_called()


def test_bitwarden_upload_uses_stdin_session_timeout_and_updates_existing(tmp_path: Path) -> None:
    session_file = tmp_path / ".config/ooodnakov/local/bw-session"
    session_file.parent.mkdir(parents=True)
    session_file.write_text("saved-session\n", encoding="utf-8")
    calls: list[tuple[list[str], dict]] = []

    def fake_run(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        calls.append((command, kwargs))
        if command[1:3] == ["list", "items"]:
            stdout = '[{"id": "existing", "name": "oooconf env: TOKEN"}]'
        elif command[1] == "encode":
            stdout = "encoded-secret\n"
        else:
            stdout = '{"id": "existing"}'
        return subprocess.CompletedProcess(command, 0, stdout, "")

    with (
        patch.object(env_tool.Path, "home", return_value=tmp_path),
        patch.object(env_tool.subprocess, "run", side_effect=fake_run),
    ):
        assert env_tool.upload_to_bitwarden("TOKEN", "plaintext") == "existing"

    assert calls[-1][0] == ["bw", "edit", "item", "existing"]
    assert all("plaintext" not in argument for command, _ in calls for argument in command)
    assert calls[-1][1]["input"] == "encoded-secret"
    assert all(kwargs["timeout"] == env_tool.BW_TIMEOUT_SECONDS for _, kwargs in calls)
    assert all(kwargs["env"]["BW_SESSION"] == "saved-session" for _, kwargs in calls)


START = "# --- LOCAL OVERRIDES START ---"
END = "# --- LOCAL OVERRIDES END ---"
