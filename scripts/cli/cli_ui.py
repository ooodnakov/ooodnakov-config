from __future__ import annotations

import os
import re
import sys
from pathlib import Path

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
    "section": "\uf054",
    "ok": "\uf00c",
    "warn": "\uf071",
    "fail": "\uf057",
    "missing": "\uf057",
    "outdated": "\uf017",
    "info": "\uf05a",
    "hint": "\uf061",
    "bullet": "\uf111",
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
    "bootstrap": "\U000f0320",
    "install": "\U000f05e0",
    "deps": "\U000f03d6",
    "update": "\U000f06b0",
    "doctor": "\U000f04d9",
    "dry-run": "\U000f0709",
    "version": "\U000f0386",
    "delete": "\U000f0a7a",
    "remove": "\U000f1238",
    "lock": "\U000f033e",
    "update-pins": "\U000f1942",
    "completions": "\U000f0a6b",
    "link": "\U000f0337",
    "shell": "\U000f1183",
    "color": "\U000f03d8",
    "secrets": "\U000f082e",
    "agents": "\U000f0b79",
    "check": "\U000f04d9",
    "preview": "\U000f0709",
    "upgrade": "\U000f06b0",
    "minimal": "\U000f060d",
    "wm": "\U000f030f",
    "komorebi": "\U000f0319",
}

ANSI_RESET = "\033[0m"
ANSI_BOLD = "\033[1m"
THEME_COLORS = {
    "default": {
        "section": 111,
        "ok": 78,
        "warn": 221,
        "fail": 203,
        "missing": 203,
        "outdated": 215,
        "info": 117,
        "hint": 245,
        "muted": 245,
    },
    "catppuccin": {
        "section": 111,
        "ok": 150,
        "warn": 223,
        "fail": 203,
        "missing": 203,
        "outdated": 181,
        "info": 117,
        "hint": 145,
        "muted": 145,
    },
    "gruvbox": {
        "section": 214,
        "ok": 142,
        "warn": 214,
        "fail": 167,
        "missing": 167,
        "outdated": 214,
        "info": 109,
        "hint": 248,
        "muted": 248,
    },
    "nord": {
        "section": 110,
        "ok": 108,
        "warn": 180,
        "fail": 174,
        "missing": 174,
        "outdated": 109,
        "info": 110,
        "hint": 146,
        "muted": 146,
    },
    "tokyonight": {
        "section": 111,
        "ok": 114,
        "warn": 221,
        "fail": 203,
        "missing": 203,
        "outdated": 180,
        "info": 117,
        "hint": 146,
        "muted": 146,
    },
    "noctalia": {
        "section": 141,
        "ok": 110,
        "warn": 180,
        "fail": 174,
        "missing": 174,
        "outdated": 109,
        "info": 117,
        "hint": 146,
        "muted": 146,
    },
}


def _theme_palette() -> dict[str, int]:
    return THEME_COLORS.get(os.environ.get("OOOCONF_THEME", "default").lower(), THEME_COLORS["default"])


_CONSOLE_STREAM = None


def _console_disabled() -> bool:
    mode = os.environ.get("OOOCONF_UI", "").lower()
    if mode in {"stdout", "off", "never"}:
        return True
    return os.environ.get("OOOCONF_NO_CONSOLE") == "1"


def console_stream():
    """Stream for interactive UI output: stdout on a TTY, else the Windows console device.

    PowerShell pipes a native command's stdout, so `sys.stdout.isatty()` is False there even
    though a console is attached; writing to CONOUT$ keeps progress live and colored.
    """
    global _CONSOLE_STREAM
    if sys.stdout.isatty() or sys.stdout is not sys.__stdout__:
        return sys.stdout
    if sys.platform != "win32" or _console_disabled():
        return sys.stdout
    if _CONSOLE_STREAM is None:
        try:
            candidate = open("CONOUT$", "w", encoding="utf-8", errors="replace", newline="\n", buffering=1)
        except OSError:
            candidate = None
        _CONSOLE_STREAM = candidate if candidate is not None and candidate.isatty() else False
    return _CONSOLE_STREAM or sys.stdout


_UI_OVERRIDE = False


def set_ui_override(enabled: bool) -> None:
    """Treat the console as interactive for this process (used when stdout is piped by a host)."""
    global _UI_OVERRIDE
    _UI_OVERRIDE = enabled


def _ui_stream():
    return console_stream() if _UI_OVERRIDE else sys.stdout


def supports_nerd_font_output() -> bool:
    if os.environ.get("OOOCONF_ASCII") == "1":
        return False
    stream = _ui_stream()
    if not stream.isatty():
        return False
    encoding = (stream.encoding or "").lower()
    return "utf" in encoding


def can_encode(text: str) -> bool:
    encoding = _ui_stream().encoding or "utf-8"
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
    return _ui_stream().isatty()


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


def error(role: str, message: str) -> None:
    print(f"{colorize(icon(role), role, bold=True)} {message}", file=sys.stderr)


def path(value: object, role: str = "info") -> str:
    """Home-relative path with muted directories and a role-colored leaf."""
    text = str(value)
    home = str(Path.home())
    if text == home:
        text = "~"
    elif text.startswith(home + os.sep) or text.startswith(home + "/"):
        text = "~" + text[len(home) :]
    trimmed = text.rstrip("/\\") or text
    index = max(trimmed.rfind("/"), trimmed.rfind("\\"))
    if index < 0:
        return colorize(trimmed, role, bold=True)
    return f"{colorize(trimmed[: index + 1], 'muted')}{colorize(trimmed[index + 1 :], role, bold=True)}"


def bullet(message: str) -> None:
    print(f"{colorize(icon('bullet'), 'hint')} {message}")


_ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
_INLINE_CODE = "\033[38;5;117m"
_BOLD = "\033[1m"
_ITALIC = "\033[3m"
_STRIKE = "\033[9m"
_RESET = "\033[0m"


def _gutter() -> str:
    return "│" if supports_nerd_font_output() else "|"


def _wrap(text: str, start: str) -> str:
    if not text or not supports_color_output():
        return text
    return f"{start}{text}{_RESET}"


def _link(match: re.Match[str]) -> str:
    label = _wrap(match.group(1), _INLINE_CODE)
    target = colorize(f"({match.group(2)})", "muted")
    return f"{label} {target}"


def _inline_markup(text: str) -> str:
    if not text:
        return text
    text = re.sub(r"\*\*(.+?)\*\*", lambda match: _wrap(match.group(1), _BOLD), text)
    text = re.sub(r"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)", lambda match: _wrap(match.group(1), _ITALIC), text)
    text = re.sub(r"~~(.+?)~~", lambda match: _wrap(match.group(1), _STRIKE), text)
    return re.sub(r"\[([^\]]+)\]\(([^)]+)\)", _link, text)


def _inline(text: str) -> str:
    """Format one Markdown line: code spans, bold, italics, strikethrough, links."""
    if not text:
        return text
    pieces = re.split(r"(`[^`\n]+`)", text)
    rendered: list[str] = []
    for piece in pieces:
        if len(piece) > 1 and piece.startswith("`") and piece.endswith("`"):
            rendered.append(_wrap(piece[1:-1], _INLINE_CODE))
        else:
            rendered.append(_inline_markup(piece))
    return "".join(rendered)


class MarkdownStream:
    """Render agent Markdown line by line, so streamed output stays readable.

    Headings, lists, quotes, rules, fenced code, tables, and inline emphasis are
    formatted with the shared icon/color helpers; lines that already carry ANSI
    styling (an agent with its own theme) are passed through untouched.
    """

    def __init__(self) -> None:
        self._fence: str | None = None
        self._table: list[str] = []
        self._blank = False

    def feed(self, line: str) -> str:
        text = line.rstrip("\r\n")
        if _ANSI_RE.search(text):
            return text
        stripped = text.strip()
        if self._fence is not None:
            if stripped.startswith(self._fence):
                self._fence = None
            else:
                return f"{colorize(_gutter(), 'muted')} {text}"
            return ""
        prefix = ""
        if self._table:
            if stripped.startswith("|"):
                self._table.append(text)
                return ""
            prefix = self._render_table() + "\n"
            self._table = []
        if not stripped:
            if self._blank:
                return prefix
            self._blank = True
            return prefix + "\n"
        self._blank = False
        if stripped.startswith("```") or stripped.startswith("~~~"):
            self._fence = stripped[:3]
            return prefix
        if stripped.startswith("|") and stripped.endswith("|") and len(stripped) > 1:
            self._table.append(text)
            return prefix
        return prefix + self._render_line(text)

    def flush(self) -> str:
        rendered = self._render_table() if self._table else ""
        self._table = []
        self._fence = None
        self._blank = False
        return rendered

    def _render_line(self, line: str) -> str:
        stripped = line.strip()
        if not stripped:
            return ""
        indent = line[: len(line) - len(line.lstrip())].replace("\t", "  ")
        heading = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if heading:
            level = len(heading.group(1))
            role = "section" if level <= 2 else "info"
            marker = icon("section") if level <= 2 else icon("bullet")
            return f"{indent}{colorize(marker, role)} {colorize(_inline(heading.group(2)), role, bold=True)}"
        if re.fullmatch(r"([-*_])\1{2,}", stripped):
            char = "─" if supports_nerd_font_output() else "-"
            return colorize(char * 40, "muted")
        quote = re.match(r"^>\s?(.*)$", stripped)
        if quote:
            return f"{indent}{colorize(_gutter(), 'muted')} {colorize(_inline(quote.group(1)), 'muted')}"
        bullet = re.match(r"^[-*+]\s+(.*)$", stripped)
        if bullet:
            return f"{indent}{colorize(icon('bullet'), 'hint')} {_inline(bullet.group(1))}"
        numbered = re.match(r"^(\d+[.)])\s+(.*)$", stripped)
        if numbered:
            return f"{indent}{colorize(numbered.group(1), 'muted')} {_inline(numbered.group(2))}"
        return f"{indent}{_inline(stripped)}"

    def _render_table(self) -> str:
        rows = [self._split_row(row) for row in self._table]
        rows = [row for row in rows if row]
        body = [row for row in rows if not all(re.fullmatch(r":?-{3,}:?", cell) for cell in row)]
        if not body:
            return ""
        columns = max(len(row) for row in body)
        widths = [
            max((len(_ANSI_RE.sub("", row[column])) if column < len(row) else 0) for row in body)
            for column in range(columns)
        ]
        rendered: list[str] = []
        for index, row in enumerate(body):
            cells: list[str] = []
            for column in range(columns):
                cell = row[column] if column < len(row) else ""
                pad = " " * max(0, widths[column] - len(cell))
                role = "info" if index == 0 else "muted"
                cells.append(colorize(_inline(cell), role, bold=index == 0) + pad)
            gutter = colorize(_gutter(), "muted")
            rendered.append(f"{gutter} " + f" {gutter} ".join(cells) + f" {gutter}")
        return "\n".join(rendered)

    @staticmethod
    def _split_row(row: str) -> list[str]:
        stripped = row.strip()
        if stripped.startswith("|"):
            stripped = stripped[1:]
        if stripped.endswith("|"):
            stripped = stripped[:-1]
        return [cell.strip() for cell in stripped.split("|")]
