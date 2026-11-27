"""Shared pytest fixtures for unit test isolation."""

from __future__ import annotations

import pytest


@pytest.fixture(autouse=True)
def _isolate_private_overlay(monkeypatch: pytest.MonkeyPatch) -> None:
    """Prevent a sibling private checkout from leaking into unit tests."""
    monkeypatch.setenv("OOOCONF_PRIVATE_DIR", "none")
