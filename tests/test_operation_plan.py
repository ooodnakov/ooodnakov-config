"""Tests for the shared, side-effect-free oooconf operation planner."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from scripts.cli import operation_plan  # noqa: E402


def _plan_env(home: Path) -> dict[str, str]:
    env = os.environ.copy()
    env.update(
        {
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(home / ".config"),
            "XDG_DATA_HOME": str(home / ".local/share"),
        }
    )
    return env


def _run_plan(home: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "scripts/cli/operation_plan.py", "--repo-root", str(REPO_ROOT), *args],
        cwd=REPO_ROOT,
        env=_plan_env(home),
        capture_output=True,
        text=True,
        check=False,
    )


def test_json_plan_is_deterministic_versioned_and_side_effect_free(tmp_path: Path) -> None:
    home = tmp_path / "home"
    first = _run_plan(home, "--platform", "linux", "--format", "json")
    second = _run_plan(home, "--platform", "linux", "--format", "json")

    assert first.returncode == second.returncode == 0, first.stderr
    assert first.stdout == second.stdout
    assert not home.exists()

    plan = json.loads(first.stdout)
    assert plan["schema_version"] == 2
    assert plan["command"] == "install"
    assert plan["platform"] == "linux"
    assert plan["profile"] is None
    assert plan["capabilities"] == []
    assert plan["skipped_capabilities"] == []
    assert plan["recommended_dependencies"] == []
    assert plan["operations"]
    required = {
        "id",
        "kind",
        "platform",
        "profile",
        "source",
        "target",
        "requires_elevation",
        "requires_network",
        "preconditions",
        "postconditions",
        "summary",
        "rollback",
    }
    assert all(set(operation) == required for operation in plan["operations"])
    assert len({operation["id"] for operation in plan["operations"]}) == len(plan["operations"])

    schema = json.loads((REPO_ROOT / "scripts/cli/schemas/operation-plan-v2.schema.json").read_text(encoding="utf-8"))
    assert schema["properties"]["schema_version"]["const"] == plan["schema_version"]
    assert set(schema["$defs"]["operation"]["required"]) == required


def test_dependency_operations_are_validated_sorted_and_redacted(tmp_path: Path) -> None:
    secret = "DO-NOT-PRINT-this-secret-value"
    env = _plan_env(tmp_path / "home")
    env["BW_PASSWORD"] = secret
    result = subprocess.run(
        [
            sys.executable,
            "scripts/cli/operation_plan.py",
            "--repo-root",
            str(REPO_ROOT),
            "--format",
            "json",
            "zoxide",
            "bat",
        ],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert secret not in result.stdout
    plan = json.loads(result.stdout)
    install_operations = [item for item in plan["operations"] if item["kind"] == "install"]
    install_ids = [item["id"] for item in install_operations]
    assert install_ids == ["install:bat", "install:zoxide"]
    if sys.platform.startswith("linux"):
        elevation_by_id = {item["id"]: item["requires_elevation"] for item in install_operations}
        assert elevation_by_id == {"install:bat": False, "install:zoxide": True}

    invalid = _run_plan(tmp_path / "other-home", "not-a-real-dependency")
    assert invalid.returncode == 2
    assert "Unknown dependency key(s): not-a-real-dependency" in invalid.stderr

    invalid_scope = _run_plan(tmp_path / "scope-home", "--scope", "links", "bat")
    assert invalid_scope.returncode == 2
    assert "Dependency keys cannot be combined with --scope links" in invalid_scope.stderr


def test_existing_target_is_backed_up_before_link(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    home = tmp_path / "home"
    source = tmp_path / "repo/config"
    target = home / ".config/tool"
    source.mkdir(parents=True)
    target.parent.mkdir(parents=True)
    target.write_text("user data", encoding="utf-8")
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setattr(operation_plan, "get_all_links", lambda _root, _platform: [(str(source), str(target), "tool")])

    operations = operation_plan.build_link_operations(tmp_path / "repo", "linux")
    assert [operation.id for operation in operations] == ["backup:tool", "link:tool"]
    assert target.read_text(encoding="utf-8") == "user data"


def test_matching_link_is_a_noop(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    home = tmp_path / "home"
    source = tmp_path / "repo/config"
    target = home / ".config/tool"
    source.mkdir(parents=True)
    target.parent.mkdir(parents=True)
    target.symlink_to(source, target_is_directory=True)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setattr(operation_plan, "get_all_links", lambda _root, _platform: [(str(source), str(target), "tool")])

    assert operation_plan.build_link_operations(tmp_path / "repo", "linux") == []


def test_unsafe_or_missing_link_paths_are_rejected(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    home = tmp_path / "home"
    source = tmp_path / "repo/config"
    source.mkdir(parents=True)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setattr(
        operation_plan,
        "get_all_links",
        lambda _root, _platform: [(str(source), str(home / "../outside/tool"), "tool")],
    )
    with pytest.raises(operation_plan.PlanError, match="outside approved user roots"):
        operation_plan.build_link_operations(tmp_path / "repo", "linux")

    monkeypatch.setattr(
        operation_plan,
        "get_all_links",
        lambda _root, _platform: [(str(tmp_path / "missing"), str(home / ".config/tool"), "tool")],
    )
    with pytest.raises(operation_plan.PlanError, match="source does not exist"):
        operation_plan.build_link_operations(tmp_path / "repo", "linux")


def test_symlinked_parent_cannot_escape_approved_roots(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    home = tmp_path / "home"
    source = tmp_path / "repo/config"
    outside = tmp_path / "outside"
    source.mkdir(parents=True)
    home.mkdir()
    outside.mkdir()
    (home / "redirect").symlink_to(outside, target_is_directory=True)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setattr(
        operation_plan,
        "get_all_links",
        lambda _root, _platform: [(str(source), str(home / "redirect/tool"), "tool")],
    )

    with pytest.raises(operation_plan.PlanError, match="outside approved user roots"):
        operation_plan.build_link_operations(tmp_path / "repo", "linux")


@pytest.mark.skipif(sys.platform == "win32", reason="Bash compatibility entrypoint is Unix-only")
def test_dry_run_command_is_a_plan_alias(tmp_path: Path) -> None:
    home = tmp_path / "home"
    env = _plan_env(home)
    plan = subprocess.run(
        ["bash", "scripts/setup/ooodnakov.sh", "plan", "--platform", "linux", "--format", "json"],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    dry_run = subprocess.run(
        ["bash", "scripts/setup/ooodnakov.sh", "dry-run", "--platform", "linux", "--format", "json"],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert plan.returncode == dry_run.returncode == 0
    assert json.loads(plan.stdout) == json.loads(dry_run.stdout)


def test_setup_implementations_consume_the_shared_link_plan() -> None:
    unix_sources = "\n".join(
        (REPO_ROOT / path).read_text(encoding="utf-8")
        for path in ("scripts/setup/setup.sh", "scripts/setup/lib/setup-links.sh")
    )
    powershell_sources = "\n".join(
        (REPO_ROOT / path).read_text(encoding="utf-8")
        for path in ("scripts/setup/setup.ps1", "scripts/setup/lib/setup-dispatch.ps1")
    )

    assert "operation_plan.py" in unix_sources
    assert "operation_plan.py" in powershell_sources
    assert "scripts/link_manager.py" not in unix_sources
    assert "scripts/link_manager.py" not in powershell_sources
    assert "falling back to hardcoded links" not in powershell_sources
