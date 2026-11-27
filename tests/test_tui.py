"""Unit tests for pure and mocked curses helpers in scripts/cli/tui.py."""

from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.cli import tui  # noqa: E402


def test_is_interactive_respects_curses_env_and_ttys(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(tui, "_CURSES_AVAILABLE", False)
    assert tui.is_interactive() is False

    monkeypatch.setattr(tui, "_CURSES_AVAILABLE", True)
    monkeypatch.setenv("OOOCONF_INTERACTIVE", "0")
    assert tui.is_interactive() is False

    monkeypatch.setenv("OOOCONF_INTERACTIVE", "1")
    assert tui.is_interactive() is True

    monkeypatch.delenv("OOOCONF_INTERACTIVE", raising=False)
    monkeypatch.setattr(tui.sys, "stdout", SimpleNamespace(fileno=lambda: 1))
    monkeypatch.setattr(tui.sys, "stdin", SimpleNamespace(isatty=lambda: False))
    monkeypatch.setattr(tui.os, "isatty", lambda fd: True)
    assert tui.is_interactive() is True

    monkeypatch.setattr(tui.os, "isatty", lambda fd: False)
    monkeypatch.setattr(tui.sys, "stdin", SimpleNamespace(isatty=lambda: True))
    assert tui.is_interactive() is True

    monkeypatch.setattr(tui.sys, "stdin", SimpleNamespace(isatty=lambda: False))
    assert tui.is_interactive() is False


def test_arrow_key_and_read_key_decoding(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(tui, "_CURSES_AVAILABLE", False)
    assert tui._arrow_key(ord("A")) is None

    fake_curses = SimpleNamespace(KEY_UP=259, KEY_DOWN=258, KEY_RIGHT=261, KEY_LEFT=260)
    monkeypatch.setattr(tui, "_CURSES_AVAILABLE", True)
    monkeypatch.setattr(tui, "curses", fake_curses)

    assert tui._arrow_key(ord("A")) == 259
    assert tui._arrow_key(ord("D")) == 260
    assert tui._arrow_key(ord("Z")) is None
    assert tui._arrow_key(-1) is None

    # Regular key passes straight through.
    win = MagicMock()
    win.getch.side_effect = [ord("x")]
    assert tui._read_key(win) == ord("x")

    # Bare ESC (not '[' or 'O').
    win.getch.side_effect = [27, ord("x")]
    assert tui._read_key(win) == 27

    # CSI arrow up (\x1b[A) and SS3 arrow left (\x1bOD).
    win.getch.side_effect = [27, ord("["), ord("A")]
    assert tui._read_key(win) == 259
    win.getch.side_effect = [27, ord("O"), ord("D")]
    assert tui._read_key(win) == 260

    # Unknown escape sequence falls back to ESC.
    win.getch.side_effect = [27, ord("["), ord("Z")]
    assert tui._read_key(win) == 27


def test_interactive_select_and_confirm_non_tty_and_errors(monkeypatch: pytest.MonkeyPatch) -> None:
    assert tui.interactive_select([]) is None

    monkeypatch.setattr(tui, "is_interactive", lambda: False)
    assert tui.interactive_select(["a", "b"]) is None

    monkeypatch.setattr(tui, "_CURSES_AVAILABLE", False)
    assert tui.confirm("Proceed?") is None

    class FakeCursesError(Exception):
        pass

    fake_curses = SimpleNamespace(error=FakeCursesError)
    monkeypatch.setattr(tui, "_CURSES_AVAILABLE", True)
    monkeypatch.setattr(tui, "curses", fake_curses)
    monkeypatch.setattr(tui, "is_interactive", lambda: True)
    monkeypatch.setattr(tui, "_curses_select", lambda *a: (_ for _ in ()).throw(FakeCursesError("no tty")))
    monkeypatch.setattr(tui, "_curses_confirm", lambda *a: (_ for _ in ()).throw(OSError("closed")))

    assert tui.interactive_select(["a"]) is None
    assert tui.confirm("Proceed?") is None


def _make_fake_curses(keys: list[int]):
    win = MagicMock()
    key_iter = iter(keys)
    win.getch.side_effect = lambda: next(key_iter)
    stdscr = MagicMock()
    fake_curses = SimpleNamespace(
        error=RuntimeError,
        LINES=24,
        COLS=80,
        KEY_UP=259,
        KEY_DOWN=258,
        KEY_LEFT=260,
        KEY_RIGHT=261,
        A_REVERSE=1,
        A_NORMAL=0,
        A_DIM=2,
        initscr=MagicMock(return_value=stdscr),
        noecho=MagicMock(),
        cbreak=MagicMock(),
        start_color=MagicMock(),
        newwin=MagicMock(return_value=win),
        nocbreak=MagicMock(),
        echo=MagicMock(),
        endwin=MagicMock(),
    )
    return fake_curses, stdscr, win


def test_curses_select_navigation_toggle_all_none_and_cancel(monkeypatch: pytest.MonkeyPatch) -> None:
    # Select all -> clear -> move down -> toggle item 1 -> move up -> toggle item 0 -> confirm
    keys = [ord("a"), ord("n"), ord("j"), ord(" "), ord("k"), ord("l"), ord("\n")]
    fake_curses, stdscr, _win = _make_fake_curses(keys)
    monkeypatch.setattr(tui, "_CURSES_AVAILABLE", True)
    monkeypatch.setattr(tui, "curses", fake_curses)
    monkeypatch.setattr(tui, "is_interactive", lambda: True)

    result = tui.interactive_select(["alpha", "beta", "gamma"], title="Tools")
    assert result == ["alpha", "beta"]
    fake_curses.endwin.assert_called_once()
    stdscr.keypad.assert_any_call(False)

    # Quit returns None
    fake_curses_quit, _, _ = _make_fake_curses([ord("q")])
    monkeypatch.setattr(tui, "curses", fake_curses_quit)
    assert tui.interactive_select(["alpha"]) is None


def test_curses_confirm_toggle_and_cancel(monkeypatch: pytest.MonkeyPatch) -> None:
    # Start default=False -> toggle with right arrow -> confirm True
    fake_curses, _, _ = _make_fake_curses([261, ord("\n")])
    monkeypatch.setattr(tui, "_CURSES_AVAILABLE", True)
    monkeypatch.setattr(tui, "curses", fake_curses)
    assert tui.confirm("Continue?", default=False) is True

    # Cancel with bare ESC (followed by -1 timeout on sequence lookahead) -> None
    fake_curses_esc, _, _ = _make_fake_curses([27, -1])
    monkeypatch.setattr(tui, "curses", fake_curses_esc)
    assert tui.confirm("Continue?", default=True) is None
