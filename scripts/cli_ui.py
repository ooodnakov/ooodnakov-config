from __future__ import annotations

import os
import sys

ASCII_ICONS = {
    "section": "==",
    "ok": "[ok]",
    "warn": "[warn]",
    "fail": "[fail]",
    "info": "[info]",
    "hint": "->",
    "bullet": "-",
}

NERD_FONT_ICONS = {
    "section": "▸",
    "ok": "✓",
    "warn": "⚠",
    "fail": "✗",
    "info": "ℹ",
    "hint": "→",
    "bullet": "•",
}

ANSI_RESET = "\033[0m"
ANSI_BOLD = "\033[1m"
ANSI_COLORS = {
    "section": "\033[38;5;111m",
    "ok": "\033[38;5;78m",
    "warn": "\033[38;5;221m",
    "fail": "\033[38;5;203m",
    "info": "\033[38;5;117m",
    "hint": "\033[38;5;245m",
    "muted": "\033[38;5;245m",
}


def supports_nerd_font_output() -> bool:
    if os.environ.get("OOOCONF_ASCII") == "1":
        return False
    if not sys.stdout.isatty():
        return False
    encoding = (sys.stdout.encoding or "").lower()
    return "utf" in encoding


def can_encode(text: str) -> bool:
    encoding = sys.stdout.encoding or "utf-8"
    try:
        text.encode(encoding)
        return True
    except UnicodeEncodeError:
        return False


def supports_color_output() -> bool:
    mode = os.environ.get("OOOCONF_COLOR", "").lower()
    if mode in {"0", "false", "never"} or os.environ.get("NO_COLOR") is not None:
        return False
    if mode in {"1", "true", "always"} or os.environ.get("FORCE_COLOR") is not None:
        return True
    return sys.stdout.isatty()


def icon(name: str) -> str:
    candidate = (NERD_FONT_ICONS if supports_nerd_font_output() else ASCII_ICONS).get(name, ASCII_ICONS["bullet"])
    if not can_encode(candidate):
        return ASCII_ICONS.get(name, ASCII_ICONS["bullet"])
    return candidate


def colorize(text: str, role: str, *, bold: bool = False) -> str:
    if not supports_color_output():
        return text
    color = ANSI_COLORS.get(role, "")
    weight = ANSI_BOLD if bold else ""
    return f"{weight}{color}{text}{ANSI_RESET}"


def section(title: str) -> None:
    prefix = icon("section")
    print(f"{colorize(prefix, 'section', bold=True)} {colorize(title, 'section', bold=True)}")
    line_char = "─" if supports_nerd_font_output() else "-"
    print(colorize(line_char * (len(title) + 3), "muted"))


def status(role: str, message: str) -> None:
    print(f"{colorize(icon(role), role, bold=True)} {message}")


def bullet(message: str) -> None:
    print(f"{colorize(icon('bullet'), 'hint')} {message}")
