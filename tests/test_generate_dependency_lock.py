"""Tests for generate_dependency_lock.py (now reads solely from optional-deps.toml)."""

import sys
from pathlib import Path

# Make scripts importable
sys.path.insert(0, str(Path(__file__).parent.parent))
from scripts.generate_dependency_lock import parse_managed_tools


def test_parse_managed_tools():
    """Test that parse_managed_tools returns list of pinned repos from TOML."""
    pins = parse_managed_tools()
    assert len(pins) > 10  # many managed tools
    names = {p["name"] for p in pins}
    assert "oh-my-zsh" in names
    assert "powerlevel10k" in names
    assert "k" in names
    for pin in pins:
        assert "repo" in pin
        assert "ref" in pin
        assert pin["repo"].startswith("https://github.com/")


def test_lock_files_are_generated_from_toml():
    """Test that lock files reference the TOML as source."""
    lock_path = Path("deps.lock.json")
    assert lock_path.exists()
    import json

    data = json.loads(lock_path.read_text())
    assert data["source"] == "scripts/optional-deps.toml"
    assert len(data["dependencies"]) > 10
