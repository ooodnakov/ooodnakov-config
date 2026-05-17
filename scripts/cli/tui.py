"""Interactive TUI components using stdlib curses."""

from __future__ import annotations

import os
import sys

try:
    import curses

    _CURSES_AVAILABLE = True
except ImportError:
    curses = None
    _CURSES_AVAILABLE = False


def is_interactive() -> bool:
    """Check if we should run in interactive mode.

    Mirrors the bash ui_is_interactive() logic: [ -t 1 ] checks stdout TTY.
    Also checks stdin and env override for robustness.
    """
    if not _CURSES_AVAILABLE:
        return False
    explicit = os.environ.get("OOOCONF_INTERACTIVE", "")
    if explicit == "0":
        return False
    if explicit == "1":
        return True

    # bash uses [ -t 1 ] which checks stdout fd 1.
    if hasattr(sys.stdout, "fileno") and os.isatty(sys.stdout.fileno()):
        return True
    # Fallback: stdin TTY for direct terminal prompts with redirected stdout.
    if hasattr(sys.stdin, "isatty") and sys.stdin.isatty():
        return True
    return False


def interactive_select(
    items: list[str],
    title: str = "Select items",
    instructions: str = "SPACE toggle  ENTER confirm  A all  N none  Q quit",
) -> list[str] | None:
    """Interactive curses selector. Returns selected items or None if cancelled."""
    if not items or not is_interactive():
        return None
    if not _CURSES_AVAILABLE:
        return None
    try:
        return _curses_select(items, title, instructions)
    except (curses.error, OSError):
        return None


def _curses_select(
    items: list[str],
    title: str,
    instructions: str,
) -> list[str] | None:
    """Curses-based interactive selector."""
    stdscr = curses.initscr()
    curses.noecho()
    curses.cbreak()
    curses.start_color()
    stdscr.keypad(True)
    stdscr.timeout(100)

    try:
        selected: set[int] = set()
        cursor = 0
        height = min(curses.LINES - 2, len(items) + 6)
        width = max(min(curses.COLS - 4, max(len(t) for t in items) + 10), len(instructions) + 2)

        win = curses.newwin(height, width, (curses.LINES - height) // 2, (curses.COLS - width) // 2)

        while True:
            win.clear()
            win.border()

            # Title
            win.addstr(0, 2, f" {title} ", curses.A_REVERSE)

            # Items
            for i, item in enumerate(items):
                y = i + 2
                if y >= height - 1:
                    break
                prefix = "[x]" if i in selected else "[ ]"
                attr = curses.A_REVERSE if cursor == i else curses.A_NORMAL
                try:
                    win.addstr(y, 2, f"{prefix} {item}", attr)
                except curses.error:
                    pass

            # Instructions
            instr_y = height - 2
            win.addstr(instr_y, 2, instructions[: width - 4], curses.A_DIM)

            win.refresh()

            try:
                key = win.getch()
            except curses.error:
                key = -1

            if key in (curses.KEY_UP, ord("k")):
                cursor = max(0, cursor - 1)
            elif key in (curses.KEY_DOWN, ord("j")):
                cursor = min(len(items) - 1, cursor + 1)
            elif key in (curses.KEY_LEFT, ord("h")):
                selected.discard(cursor)
            elif key in (curses.KEY_RIGHT, ord("l"), ord(" ")):
                if cursor in selected:
                    selected.discard(cursor)
                else:
                    selected.add(cursor)
            elif key in (ord("\n"), ord("\r")):
                return sorted(items[i] for i in selected) or None
            elif key in (ord("a"), ord("A")):
                selected = set(range(len(items)))
            elif key in (ord("n"), ord("N")):
                selected = set()
            elif key in (ord("q"), ord("Q"), 27):
                return None

        return None
    finally:
        curses.nocbreak()
        stdscr.keypad(False)
        curses.echo()
        curses.endwin()


def confirm(prompt: str, default: bool = False) -> bool | None:
    """Ask yes/no confirmation. Returns None if cancelled."""
    if not _CURSES_AVAILABLE:
        return None
    try:
        return _curses_confirm(prompt, default)
    except (curses.error, OSError):
        return None


def _curses_confirm(prompt: str, default: bool) -> bool | None:
    """Curses-based yes/no confirmation dialog."""
    stdscr = curses.initscr()
    curses.noecho()
    curses.cbreak()
    stdscr.keypad(True)
    stdscr.timeout(-1)

    try:
        width = max(min(curses.COLS - 4, len(prompt) + 10), 40)
        height = 7
        win = curses.newwin(height, width, (curses.LINES - height) // 2, (curses.COLS - width) // 2)

        choice = -1
        while choice == -1:
            win.clear()
            win.border()
            win.addstr(0, 2, " Confirm ", curses.A_REVERSE)
            win.addstr(2, 4, prompt[: width - 8])
            btn_yes = "[ Yes ]" if default else "[ *Yes *]"
            btn_no = "[  No  ]" if not default else "[  *No* ]"
            win.addstr(4, width // 2 - 10, btn_yes)
            win.addstr(4, width // 2 + 2, btn_no)
            win.refresh()

            try:
                key = win.getch()
            except curses.error:
                key = -1

            if key in (curses.KEY_LEFT, ord("h")):
                default = not default
            elif key in (curses.KEY_RIGHT, ord("l")):
                default = not default
            elif key in (ord("\n"), ord("\r")):
                choice = 0 if default else 1
            elif key in (ord("q"), ord("Q"), 27):
                return None

        return choice == 0
    finally:
        curses.nocbreak()
        stdscr.keypad(False)
        curses.echo()
        curses.endwin()
