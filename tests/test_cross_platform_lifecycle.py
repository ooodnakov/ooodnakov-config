"""Isolated, network-free lifecycle coverage for every CI operating system."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
PLATFORM = {"linux": "linux", "darwin": "macos", "win32": "windows"}[sys.platform]


def _copy_test_repo(destination: Path) -> Path:
    repo = destination / "repo"
    shutil.copytree(
        REPO_ROOT,
        repo,
        symlinks=True,
        ignore=shutil.ignore_patterns(".git", ".venv", "node_modules", ".pytest_cache", "__pycache__"),
    )
    return repo


def _command(repo: Path, *arguments: str) -> list[str]:
    if sys.platform == "win32":
        return ["pwsh", "-NoProfile", "-File", str(repo / "scripts/setup/ooodnakov.ps1"), "-C", str(repo), *arguments]
    return ["bash", str(repo / "scripts/setup/ooodnakov.sh"), "-C", str(repo), *arguments]


def _run(
    repo: Path, environment: dict[str, str], *arguments: str, check: bool = True
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        _command(repo, *arguments),
        cwd=repo,
        env=environment,
        text=True,
        capture_output=True,
        check=check,
        timeout=90,
    )


@pytest.mark.integration
def test_complete_lifecycle_in_isolated_home(tmp_path: Path) -> None:
    repo = _copy_test_repo(tmp_path)
    home = tmp_path / "home"
    config_home = home / ".config"
    state_home = home / ".local/state"
    environment = os.environ.copy()
    environment.update(
        {
            "HOME": str(home),
            "USERPROFILE": str(home),
            "XDG_CONFIG_HOME": str(config_home),
            "XDG_DATA_HOME": str(home / ".local/share"),
            "XDG_STATE_HOME": str(state_home),
            "XDG_CACHE_HOME": str(home / ".cache"),
            "OOODNAKOV_BACKUP_ROOT": str(state_home / "ooodnakov-config/backups"),
            "OOODNAKOV_PROFILE": "minimal",
            "OOODNAKOV_SKIP_DEPS": "1",
            "OOODNAKOV_INSTALL_OPTIONAL": "never",
            "OOODNAKOV_NO_NETWORK": "1",
            "NO_COLOR": "1",
            "OOOCONF_TEST_API_TOKEN": "lifecycle-secret-sentinel",
        }
    )

    secret_sentinel = environment["OOOCONF_TEST_API_TOKEN"]

    plan_result = _run(repo, environment, "plan", "--scope", "links", "--format", "json")
    assert secret_sentinel not in plan_result.stdout
    assert secret_sentinel not in plan_result.stderr
    plan = json.loads(plan_result.stdout)
    assert plan["profile"] == "minimal"
    assert plan["operations"]
    assert not home.exists(), "planning must not create the isolated home"

    exported_snapshot = tmp_path / "exported-snapshot.toml"
    snapshot_export = _run(repo, environment, "snapshot", "export", "--output", str(exported_snapshot))
    assert secret_sentinel not in snapshot_export.stdout
    assert secret_sentinel not in snapshot_export.stderr
    assert secret_sentinel not in exported_snapshot.read_text(encoding="utf-8")

    snapshot = tmp_path / "snapshot.toml"
    snapshot.write_text(
        'version = 1\nprofile = "minimal"\ncapabilities = ["shell"]\n\n[preferences]\ntheme = "default"\n',
        encoding="utf-8",
    )
    _run(repo, environment, "snapshot", "apply", str(snapshot))
    assert (home / ".zshrc").is_symlink()
    local = repo / "home/.config/ooodnakov/local"
    assert "LOCAL OVERRIDES START" in (local / "env.zsh").read_text(encoding="utf-8")
    assert "LOCAL OVERRIDES START" in (local / "env.ps1").read_text(encoding="utf-8")

    second_apply = _run(repo, environment, "apply")
    assert "No changes required" in second_apply.stdout

    managed_target = home / ".zshrc"
    managed_target.unlink()
    managed_target.write_text("user-owned\n", encoding="utf-8")
    _run(repo, environment, "apply")
    assert managed_target.is_symlink()
    assert list((state_home / "ooodnakov-config/backups").rglob(".zshrc.*"))

    doctor_text = _run(repo, environment, "doctor")
    assert "links.managed" in doctor_text.stdout
    doctor_json = json.loads(_run(repo, environment, "doctor", "--format", "json").stdout)
    assert doctor_json["summary"]["error"] == 0

    _run(repo, environment, "remove")
    assert not managed_target.exists()
    _run(repo, environment, "apply")
    assert managed_target.is_symlink()
    _run(repo, environment, "delete")
    assert managed_target.read_text(encoding="utf-8") == "user-owned\n"

    managed_target.unlink()
    failure_environment = {**environment, "OOODNAKOV_TEST_FAIL_AFTER": "2"}
    failed = _run(repo, failure_environment, "apply", check=False)
    assert failed.returncode != 0
    assert not managed_target.exists()
    journals = sorted((state_home / "ooodnakov-config/transactions").glob("*.json"))
    failed_journal = next(
        document
        for journal in journals
        if "injected integration-test failure"
        in ((document := json.loads(journal.read_text(encoding="utf-8")))["error"] or "")
    )
    assert failed_journal["status"] == "rolled_back"
    assert all(entry["status"] in {"pending", "rolled_back"} for entry in failed_journal["operations"])

    # The same sentinel must stay out of every lifecycle artifact, including setup
    # logs, transaction journals, generated local files, snapshots, and diagnostics.
    diagnostic = _run(repo, environment, "status", "--format", "json")
    assert secret_sentinel not in diagnostic.stdout
    assert secret_sentinel not in diagnostic.stderr
    for artifact_root in (home, state_home):
        for artifact in artifact_root.rglob("*"):
            if artifact.is_file():
                assert secret_sentinel not in artifact.read_text(encoding="utf-8", errors="replace"), artifact
