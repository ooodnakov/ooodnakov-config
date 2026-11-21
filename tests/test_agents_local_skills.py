"""Local skills (`installer = "local"`) are linked into each agent's skills dir by `agents skills sync`."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts" / "cli"))

import agents_tool  # noqa: E402


def _symlinks_work(path: Path) -> bool:
    try:
        (path / "link").symlink_to(path, target_is_directory=True)
        return True
    except OSError:
        return False


def test_local_skill_links_each_agent_and_is_idempotent(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    if not _symlinks_work(tmp_path):
        pytest.skip("this platform cannot create symlinks without extra privileges")

    repo = tmp_path / "repo"
    source = repo / "agents" / "skills" / "demo"
    source.mkdir(parents=True)
    (source / "SKILL.md").write_text("---\nname: demo\n---\n", encoding="utf-8")

    dirs = {name: (name, str(tmp_path / f"home-{name}" / "skills")) for name in ("omp", "claude", "codex")}
    monkeypatch.setattr(agents_tool, "LOCAL_SKILL_DIRS", dirs)
    monkeypatch.setattr(agents_tool.shutil, "which", lambda name: f"/{name}" if name in dirs else None)

    spec = {"name": "demo", "installer": "local", "source": "agents/skills/demo", "agents": ["omp", "codex"]}
    assert agents_tool.sync_local_skills(repo, [spec], check_only=False, dry_run=False) == (2, 0, 0)

    for agent in ("omp", "codex"):
        link = tmp_path / f"home-{agent}" / "skills" / "demo"
        assert link.is_symlink()
        assert link.resolve() == source.resolve()
    assert not (tmp_path / "home-claude" / "skills" / "demo").exists()

    # Running again finds the links up to date and changes nothing.
    assert agents_tool.sync_local_skills(repo, [spec], check_only=False, dry_run=False) == (2, 0, 0)


def test_check_mode_only_plans_and_missing_source_fails(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    if not _symlinks_work(tmp_path):
        pytest.skip("this platform cannot create symlinks without extra privileges")

    repo = tmp_path / "repo"
    source = repo / "skills" / "demo"
    source.mkdir(parents=True)
    dirs = {"codex": ("codex", str(tmp_path / "home-codex" / "skills"))}
    monkeypatch.setattr(agents_tool, "LOCAL_SKILL_DIRS", dirs)
    monkeypatch.setattr(agents_tool.shutil, "which", lambda name: "/codex" if name in dirs else None)

    good = {"name": "demo", "installer": "local", "source": "skills/demo", "agents": ["codex"]}
    assert agents_tool.sync_local_skills(repo, [good], check_only=True, dry_run=False) == (1, 0, 0)
    assert not (tmp_path / "home-codex" / "skills" / "demo").exists()

    missing = {"name": "gone", "installer": "local", "source": "skills/gone", "agents": ["codex"]}
    assert agents_tool.sync_local_skills(repo, [missing], check_only=False, dry_run=False) == (0, 0, 1)


def test_local_skill_dirs_includes_antigravity() -> None:
    assert agents_tool.LOCAL_SKILL_DIRS["antigravity"] == ("agy", "~/.gemini/config/skills")
