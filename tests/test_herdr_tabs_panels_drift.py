"""Drift guard: tabs-panels is the shipped tabs mod plus exactly the known hunks."""

from __future__ import annotations

import difflib
import os
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
CLONE = REPO_ROOT / "home/.config/herdr-app/mods/tabs-panels/main.js"
EXPECTED_DIFF = Path(__file__).resolve().parent / "fixtures" / "herdr-tabs-panels.diff"


def _mods_dir() -> Path:
    app_home = os.environ.get("HERDR_APP_HOME")
    if app_home:
        return Path(app_home).expanduser() / "mods"
    return Path.home() / ".config" / "herdr-app" / "mods"


def _diff(upstream: Path, clone: Path) -> list[str]:
    return list(
        difflib.unified_diff(
            upstream.read_text(encoding="utf-8").splitlines(),
            clone.read_text(encoding="utf-8").splitlines(),
            fromfile="tabs/main.js",
            tofile="tabs-panels/main.js",
            lineterm="",
        )
    )


def test_tabs_panels_clone_is_tabs_plus_known_hunks() -> None:
    mods = _mods_dir()
    if not mods.is_dir():
        pytest.skip(f"Herdr app mods folder not installed: {mods}")

    upstream = mods / "tabs" / "main.js"
    assert upstream.is_file(), f"shipped tabs mod missing from {mods}"
    assert CLONE.is_file(), f"tracked tabs-panels clone missing: {CLONE}"

    expected = EXPECTED_DIFF.read_text(encoding="utf-8").splitlines()
    actual = _diff(upstream, CLONE)
    assert actual == expected, (
        "tabs-panels/main.js is no longer tabs/main.js plus the known hunks; "
        "update tests/fixtures/herdr-tabs-panels.diff only for intended changes"
    )
