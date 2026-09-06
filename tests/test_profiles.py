"""Tests for portable capability profiles and planner integration."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from scripts.cli.operation_plan import build_plan  # noqa: E402
from scripts.cli.profile_manager import ProfileError, resolve_profile  # noqa: E402
from scripts.link_manager import get_all_links  # noqa: E402


def _profile_repo(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    source = REPO_ROOT / "home/.config/ooodnakov/profiles"
    shutil.copytree(source, repo / "home/.config/ooodnakov/profiles")
    return repo


def test_builtin_profile_inheritance_and_platform_skips(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.delenv("OOODNAKOV_PROFILE", raising=False)
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    profile = resolve_profile(REPO_ROOT, "linux", "workstation")
    assert profile is not None
    assert profile.capabilities == (
        "shell",
        "productivity",
        "terminal",
        "desktop-linux",
        "desktop-windows",
        "desktop-macos",
    )
    assert profile.skipped_capabilities == ("desktop-windows", "desktop-macos")
    assert {"niri", "hypr", "pypr", "noctalia"} <= profile.links
    assert "glazewm" not in profile.links


def test_explicit_then_environment_then_local_precedence(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    repo = _profile_repo(tmp_path)
    local = repo / "home/.config/ooodnakov/local"
    local.mkdir(parents=True)
    (local / "profile.toml").write_text('profile = "minimal"\n', encoding="utf-8")

    monkeypatch.delenv("OOODNAKOV_PROFILE", raising=False)
    assert resolve_profile(repo, "linux").name == "minimal"  # type: ignore[union-attr]
    monkeypatch.setenv("OOODNAKOV_PROFILE", "terminal")
    assert resolve_profile(repo, "linux").name == "terminal"  # type: ignore[union-attr]
    assert resolve_profile(repo, "linux", "developer").name == "developer"  # type: ignore[union-attr]


def test_profile_cycles_and_unknown_capabilities_fail(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    repo = _profile_repo(tmp_path)
    profile_dir = repo / "home/.config/ooodnakov/profiles"
    (profile_dir / "cycle-a.toml").write_text(
        'version = 1\n[profile]\nname = "cycle-a"\nextends = "cycle-b"\ncapabilities = []\n', encoding="utf-8"
    )
    (profile_dir / "cycle-b.toml").write_text(
        'version = 1\n[profile]\nname = "cycle-b"\nextends = "cycle-a"\ncapabilities = []\n', encoding="utf-8"
    )
    with pytest.raises(ProfileError, match="cycle-a -> cycle-b -> cycle-a"):
        resolve_profile(repo, "linux", "cycle-a")

    (profile_dir / "unknown.toml").write_text(
        'version = 1\n[profile]\nname = "unknown"\ncapabilities = ["does-not-exist"]\n', encoding="utf-8"
    )
    with pytest.raises(ProfileError, match="unknown capabilities: does-not-exist"):
        resolve_profile(repo, "linux", "unknown")


def test_plan_filters_links_and_reports_inapplicable_capabilities(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    home = tmp_path / "home"
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(home / ".config"))
    monkeypatch.setenv("XDG_DATA_HOME", str(home / ".local/share"))
    monkeypatch.delenv("OOODNAKOV_PROFILE", raising=False)

    plan = build_plan(REPO_ROOT, "linux", "links", profile_name="workstation")
    assert plan["profile"] == "workstation"
    assert plan["skipped_capabilities"] == ["desktop-windows", "desktop-macos"]
    linked_ids = {operation["id"] for operation in plan["operations"] if operation["kind"] == "link"}
    assert "link:niri" in linked_ids
    assert "link:glazewm" not in linked_ids
    assert all(operation["profile"] == "workstation" for operation in plan["operations"])

    rendered = json.dumps(plan)
    assert '"recommended_dependencies"' in rendered
    assert "wezterm" in plan["recommended_dependencies"]


def test_no_profile_preserves_the_complete_platform_link_set(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    home = tmp_path / "home"
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(home / ".config"))
    monkeypatch.delenv("OOODNAKOV_PROFILE", raising=False)

    plan = build_plan(REPO_ROOT, "linux", "links")
    expected = {f"link:{key}" for _source, _target, key in get_all_links(REPO_ROOT, "linux")}
    actual = {operation["id"] for operation in plan["operations"] if operation["kind"] == "link"}
    assert plan["profile"] is None
    assert plan["capabilities"] == []
    assert actual == expected


@pytest.mark.skipif(sys.platform == "win32", reason="Bash profile entrypoint is Unix-only")
def test_unix_cli_explicit_profile_reaches_planner(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    home = tmp_path / "home"
    monkeypatch.delenv("OOODNAKOV_PROFILE", raising=False)
    env = {
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_DATA_HOME": str(home / ".local/share"),
        "PATH": str(Path(sys.executable).parent) + ":/usr/bin:/bin",
    }
    result = subprocess.run(
        [
            "bash",
            "scripts/setup/ooodnakov.sh",
            "plan",
            "--profile",
            "minimal",
            "--platform",
            "linux",
            "--format",
            "json",
        ],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["profile"] == "minimal"
