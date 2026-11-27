"""Tests for generate_dependency_lock.py (reads solely from optional-deps.toml)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

# Make scripts importable
sys.path.insert(0, str(Path(__file__).parent.parent))
from scripts.generate import generate_dependency_lock as lock_mod  # noqa: E402


def test_parse_managed_tools() -> None:
    """Test that parse_managed_tools returns list of pinned repos from TOML."""
    pins = lock_mod.parse_managed_tools()
    assert len(pins) > 10
    names = {p["name"] for p in pins}
    assert "oh-my-zsh" in names
    assert "powerlevel10k" in names
    assert "k" in names
    for pin in pins:
        assert "repo" in pin
        assert "ref" in pin
        assert pin["repo"].startswith("https://github.com/")


def test_lock_files_are_generated_from_toml() -> None:
    """Test that lock files reference the TOML as source."""
    lock_path = Path("deps.lock.json")
    assert lock_path.exists()
    data = json.loads(lock_path.read_text(encoding="utf-8"))
    assert data["source"] == "scripts/optional-deps.toml"
    assert len(data["dependencies"]) > 10


def test_parse_artifact_integrity_substitutes_ver_and_collects_exceptions(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    scripts_dir = tmp_path / "scripts"
    scripts_dir.mkdir()
    (scripts_dir / "optional-deps.toml").write_text(
        """
[[deps]]
key = "ripgrep"
ver = "14.1.1"
[deps.integrity]
"ripgrep-${ver}-x86_64.tar.gz" = "ABCDEF0123456789"

[[deps]]
key = "rustup"
ver = "1.0.0"
checksum_exception = "Upstream installer script"
""",
        encoding="utf-8",
    )
    monkeypatch.setattr(lock_mod, "REPO_ROOT", tmp_path)

    artifacts, exceptions = lock_mod.parse_artifact_integrity()
    assert artifacts == [
        {
            "dependency": "ripgrep",
            "version": "14.1.1",
            "asset": "ripgrep-14.1.1-x86_64.tar.gz",
            "sha256": "abcdef0123456789",
        }
    ]
    assert exceptions == [{"dependency": "rustup", "reason": "Upstream installer script"}]


def test_write_locks_and_main_preserves_timestamp_when_unchanged(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    json_lock = tmp_path / "deps.lock.json"
    md_lock = tmp_path / "dependency-lock.md"
    monkeypatch.setattr(lock_mod, "JSON_LOCK", json_lock)
    monkeypatch.setattr(lock_mod, "MD_LOCK", md_lock)

    pins = [{"name": "tool-a", "repo": "https://github.com/org/tool-a", "ref": "abc123"}]
    artifacts = [
        {
            "dependency": "tool-a",
            "version": "1.0.0",
            "asset": "tool-a.tar.gz",
            "sha256": "0" * 64,
        }
    ]
    exceptions: list[dict[str, str]] = []

    monkeypatch.setattr(lock_mod, "parse_managed_tools", lambda: pins)
    monkeypatch.setattr(lock_mod, "parse_artifact_integrity", lambda: (artifacts, exceptions))

    assert lock_mod.main() == 0
    first_json = json.loads(json_lock.read_text(encoding="utf-8"))
    first_md = md_lock.read_text(encoding="utf-8")
    assert first_json["dependencies"] == pins
    assert first_json["artifacts"] == artifacts
    assert "None." in first_md

    # Force a fixed prior timestamp; unchanged inputs must preserve it.
    first_json["generated_at_utc"] = "2025-01-01T00:00:00+00:00"
    json_lock.write_text(json.dumps(first_json, indent=2) + "\n", encoding="utf-8")
    assert lock_mod.main() == 0
    second_json = json.loads(json_lock.read_text(encoding="utf-8"))
    assert second_json["generated_at_utc"] == "2025-01-01T00:00:00+00:00"

    # Corrupt existing lock file is recovered cleanly, and exceptions render in markdown.
    json_lock.write_text("{corrupt", encoding="utf-8")
    monkeypatch.setattr(
        lock_mod,
        "parse_artifact_integrity",
        lambda: (artifacts, [{"dependency": "uv", "reason": "bootstrap script"}]),
    )
    assert lock_mod.main() == 0
    recovered = json.loads(json_lock.read_text(encoding="utf-8"))
    assert recovered["checksum_exceptions"] == [{"dependency": "uv", "reason": "bootstrap script"}]
    assert "- `uv`: bootstrap script" in md_lock.read_text(encoding="utf-8")
