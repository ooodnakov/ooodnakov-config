"""Keep the Bash, PowerShell, and Python Nerd Font icon tables in lockstep."""

from __future__ import annotations

import importlib.util
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASH_UI = ROOT / "scripts/setup/lib/oooconf-ui.sh"
POWERSHELL_UI = ROOT / "scripts/setup/lib/oooconf-ui.ps1"
POWERSHELL_ENTRY = ROOT / "scripts/setup/ooodnakov.ps1"
PYTHON_UI = ROOT / "scripts/cli/cli_ui.py"


def _load_cli_ui():
    spec = importlib.util.spec_from_file_location("cli_ui_icons_test", PYTHON_UI)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _bash_block(start: str, end: str) -> str:
    text = BASH_UI.read_text(encoding="utf-8")
    begin = text.index(start)
    return text[begin : text.index(end, begin)]


def _bash_role_icons() -> dict[str, int]:
    block = _bash_block("ui_icon() {", "ui_cmd_icon() {")
    icons: dict[str, int] = {}
    for names, codepoint in re.findall(r"^\s+([\w| ]+)\) printf '\\U([0-9A-F]{8})'", block, re.MULTILINE):
        for name in names.split("|"):
            icons[name.strip()] = int(codepoint, 16)
    return icons


def _bash_command_icons() -> dict[str, int]:
    block = _bash_block("ui_cmd_icon() {", "ui_colorize() {")
    nerd_branch = block[: block.index("  else")]
    return {
        name: int(codepoint, 16)
        for name, codepoint in re.findall(r"^\s+([\w-]+)\) printf '\\U([0-9A-F]{8})'", nerd_branch, re.MULTILINE)
    }


def _powershell_role_icons() -> dict[str, int]:
    text = POWERSHELL_ENTRY.read_text(encoding="utf-8")
    begin = text.index("$UiNerd = @{")
    block = text[begin : text.index("}", begin)]
    return {name: int(value, 16) for name, value in re.findall(r"(\w+)\s*=\s*0x([0-9A-Fa-f]+)", block)}


def _powershell_command_icons() -> dict[str, int]:
    text = POWERSHELL_UI.read_text(encoding="utf-8")
    begin = text.index("function Get-UiCommandIcon")
    block = text[begin : text.index("function Format-UiText", begin)]
    return {
        name: int(codepoint, 16)
        for name, codepoint in re.findall(
            r'"([\w-]+)"\s*\{\s*return \[char\]::ConvertFromUtf32\(0x([0-9A-Fa-f]+)\)', block
        )
    }


def _python_role_icons() -> dict[str, int]:
    return {name: ord(value) for name, value in _load_cli_ui().NERD_FONT_ICONS.items()}


def _python_command_icons() -> dict[str, int]:
    return {name: ord(value) for name, value in _load_cli_ui().COMMAND_ICONS_NERD.items()}


def test_role_icon_tables_match_across_shells() -> None:
    assert _bash_role_icons() == _powershell_role_icons() == _python_role_icons()


def test_command_icon_tables_match_across_shells() -> None:
    bash_icons = _bash_command_icons()
    powershell_icons = _powershell_command_icons()
    python_icons = _python_command_icons()
    assert bash_icons == powershell_icons
    assert bash_icons == python_icons


def test_ascii_fallback_covers_every_role() -> None:
    ascii_icons = _load_cli_ui().ASCII_ICONS
    assert set(_python_role_icons()) <= set(ascii_icons)


def test_glyphs_are_private_use_not_emoji() -> None:
    for name, codepoint in _python_role_icons().items():
        assert 0xE000 <= codepoint <= 0xF8FF or 0xF0000 <= codepoint <= 0xFFFFD, name
    for name, codepoint in _python_command_icons().items():
        assert 0xF0000 <= codepoint <= 0xFFFFD, name
