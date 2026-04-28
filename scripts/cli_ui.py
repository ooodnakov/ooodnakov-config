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
THEME_COLORS = {
    "default": {"section": 111, "ok": 78, "warn": 221, "fail": 203, "info": 117, "hint": 245, "muted": 245},
    "catppuccin": {"section": 111, "ok": 150, "warn": 223, "fail": 203, "info": 117, "hint": 145, "muted": 145},
    "gruvbox": {"section": 214, "ok": 142, "warn": 214, "fail": 167, "info": 109, "hint": 248, "muted": 248},
    "nord": {"section": 110, "ok": 108, "warn": 180, "fail": 174, "info": 110, "hint": 146, "muted": 146},
    "tokyonight": {"section": 111, "ok": 114, "warn": 221, "fail": 203, "info": 117, "hint": 146, "muted": 146},
    "noctalia": {"section": 141, "ok": 110, "warn": 180, "fail": 174, "info": 117, "hint": 146, "muted": 146},
}


def _theme_palette() -> dict[str, int]:
    return THEME_COLORS.get(os.environ.get("OOOCONF_THEME", "default").lower(), THEME_COLORS["default"])


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
    palette = _theme_palette()
    color_num = palette.get(role)
    color = f"\033[38;5;{color_num}m" if color_num is not None else ""
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
