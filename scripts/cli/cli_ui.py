from __future__ import annotations

import os
import sys

ASCII_ICONS = {
    "section": "==",
    "ok": "[ok]",
    "warn": "[warn]",
    "fail": "[fail]",
    "missing": "[missing]",
    "outdated": "[outdated]",
    "info": "[info]",
    "hint": "->",
    "bullet": "-",
}

NERD_FONT_ICONS = {
    "section": "▸",
    "ok": "✓",
    "warn": "⚠",
    "fail": "✗",
    "missing": "✗",
    "outdated": "󰏫",
    "info": "ℹ",
    "hint": "→",
    "bullet": "•",
}

COMMAND_ICONS_ASCII = {
    "bootstrap": "[boot]",
    "install": "[inst]",
    "deps": "[deps]",
    "update": "[up]",
    "doctor": "[doc]",
    "dry-run": "[dry]",
    "version": "[ver]",
    "delete": "[del]",
    "remove": "[rm]",
    "lock": "[lock]",
    "update-pins": "[pins]",
    "completions": "[comp]",
    "link": "[link]",
    "shell": "[sh]",
    "color": "[clr]",
    "secrets": "[sec]",
    "agents": "[agt]",
    "check": "[doc]",
    "preview": "[dry]",
    "upgrade": "[up]",
    "minimal": "[min]",
    "wm": "[wm]",
    "komorebi": "[kom]",
}

COMMAND_ICONS_NERD = {
    "bootstrap": "󰌠",
    "install": "󰗠",
    "deps": "󰏖",
    "update": "󰚰",
    "doctor": "󰓙",
    "dry-run": "󰜉",
    "version": "󰎆",
    "delete": "󰩺",
    "remove": "󱈸",
    "lock": "󰌾",
    "update-pins": "󱥂",
    "completions": "󰩫",
    "link": "🔗",
    "shell": "󱆃",
    "color": "󰏘",
    "secrets": "󰠮",
    "agents": "󰭹",
    "check": "󰓙",
    "preview": "󰜉",
    "upgrade": "󰚰",
    "minimal": "󰘍",
    "wm": "󰘍",
    "komorebi": "󰘍",
}

ANSI_RESET = "\033[0m"
ANSI_BOLD = "\033[1m"
THEME_COLORS = {
    "default": {"section": 111, "ok": 78, "warn": 221, "fail": 203, "missing": 203, "outdated": 215, "info": 117, "hint": 245, "muted": 245},
    "catppuccin": {"section": 111, "ok": 150, "warn": 223, "fail": 203, "missing": 203, "outdated": 181, "info": 117, "hint": 145, "muted": 145},
    "gruvbox": {"section": 214, "ok": 142, "warn": 214, "fail": 167, "missing": 167, "outdated": 214, "info": 109, "hint": 248, "muted": 248},
    "nord": {"section": 110, "ok": 108, "warn": 180, "fail": 174, "missing": 174, "outdated": 109, "info": 110, "hint": 146, "muted": 146},
    "tokyonight": {"section": 111, "ok": 114, "warn": 221, "fail": 203, "missing": 203, "outdated": 180, "info": 117, "hint": 146, "muted": 146},
    "noctalia": {"section": 141, "ok": 110, "warn": 180, "fail": 174, "missing": 174, "outdated": 109, "info": 117, "hint": 146, "muted": 146},
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


def _cmd_icon_table() -> dict[str, str]:
    return COMMAND_ICONS_NERD if supports_nerd_font_output() else COMMAND_ICONS_ASCII


def cmd_icon(name: str) -> str:
    table = _cmd_icon_table()
    return table.get(name, table.get("default", "[cmd]"))


def colorize(text: str, role: str, *, bold: bool = False) -> str:
    if not supports_color_output():
        return text
    palette = _theme_palette()
    color_num = palette.get(role)
    color = f"\033[38;5;{color_num}m" if color_num is not None else ""
    weight = ANSI_BOLD if bold else ""
    return f"{weight}{color}{text}{ANSI_RESET}"


def _repeat_char(char: str, count: int) -> str:
    return char * count


def banner() -> None:
    width = 58
    use_nerd = supports_nerd_font_output()
    horiz = "─" if use_nerd else "-"
    tl = "┌" if use_nerd else "+"
    tr = "┐" if use_nerd else "+"
    bl = "└" if use_nerd else "+"
    br = "┘" if use_nerd else "+"
    left = "│" if use_nerd else "|"
    right = "│" if use_nerd else "|"
    platform = "Linux • Windows • macOS" if use_nerd else "Linux / Windows / macOS"
    print(colorize(f"{tl}{_repeat_char(horiz, width)}{tr}", "section", bold=True))
    _banner_row("oooconf", width, left, right)
    _banner_row("reproducible dotfiles manager", width, left, right)
    _banner_row(platform, width, left, right)
    print(colorize(f"{bl}{_repeat_char(horiz, width)}{br}", "section", bold=True))


def _banner_row(text: str, width: int, left: str, right: str) -> None:
    padding = max(0, width - len(text))
    left_pad = padding // 2
    right_pad = padding - left_pad
    line = f"{left}{_repeat_char(' ', left_pad)}{text}{_repeat_char(' ', right_pad)}{right}"
    print(colorize(line, "section", bold=True))


def separator() -> None:
    char = "─" if supports_nerd_font_output() else "-"
    print(colorize(_repeat_char(char, 54), "muted"))


def spacer() -> None:
    print()


def section_fancy(icon_name: str, title: str) -> None:
    use_nerd = supports_nerd_font_output()
    rule_char = "─" if use_nerd else "-"
    icon_text = colorize(cmd_icon(icon_name), "hint")
    title_text = colorize(title, "section", bold=True)
    rule = _repeat_char(rule_char, len(title) + 6)
    print(f"  {icon_text}  {title_text}")
    print(f"  {colorize(rule, 'muted')}")


def command_row(command_name: str, description: str) -> None:
    icon_text = colorize(f"{cmd_icon(command_name):<6}", "hint")
    command_text = colorize(f"{command_name:<16}", "info")
    description_text = colorize(description, "muted")
    print(f"    {icon_text} {command_text} {description_text}")


def section(title: str) -> None:
    prefix = icon("section")
    print(f"{colorize(prefix, 'section', bold=True)} {colorize(title, 'section', bold=True)}")
    line_char = "─" if supports_nerd_font_output() else "-"
    print(colorize(line_char * (len(title) + 3), "muted"))


def status(role: str, message: str) -> None:
    print(f"{colorize(icon(role), role, bold=True)} {message}")


def bullet(message: str) -> None:
    print(f"{colorize(icon('bullet'), 'hint')} {message}")
