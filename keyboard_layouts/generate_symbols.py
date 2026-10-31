#!/usr/bin/env python3
"""Derive xkb_symbols files from the Universal Layout keymap.

ul_combo.xkb is a complete xkb_keymap file. Compositors that load keymap
files directly (niri) can use it as-is, but compositors that resolve layouts
through the XKB rules (Umbriel) need xkb_symbols sections instead, because
the rules machinery treats one layout name as one group.

The rules chain for a two-layout list is "pc+<first>+<second>:2+inet(evdev)",
so the layout is split into two single-group symbols files that each carry one
group of the original. The result matches ul_combo.xkb key for key.

Usage:
    python3 generate_symbols.py
    umbriel config validate
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "ul_combo.xkb"
# xkbcommon searches ~/.config/xkb for user layouts, so the symbols files live
# there and are referenced by name instead of by absolute path.
TARGET = HERE.parent / "home" / ".config" / "xkb" / "symbols"

# Group name, base layout include, and the statements that belong to the
# English group only (the Russian group reuses the stock Russian layout).
GROUPS = {
    "en": {
        "title": "Universal Layout EN",
        "base": "us(basic)",
        "extra": (
            "        modifier_map Mod5 { <LVL3> };\n"
            "        modifier_map Mod5 { <RALT> };\n"
            "\n"
            "        key<CAPS> { [ISO_Next_Group] };\n"
            "\n"
        ),
    },
    "ru": {
        "title": "Universal Layout RU",
        "base": "ru(common)",
        "extra": "",
    },
}

HEADER = """\
// {title}: {group} group of the Universal Layout custom layout.
//
// Generated from ul_combo.xkb by generate_symbols.py -- do not edit by hand.
//
// Reference: https://www.xkb.org/docs/current/symbols-format.html

default partial alphanumeric_keys modifier_keys

xkb_symbols "ul_combo_{group}" {{
        include "{base}"
        include "level3(ralt_switch)"
{extra}        name[Group1]= "{title}";

{keys}}};
"""


def read_symbols_body(path: Path) -> str:
    """Return the contents of the xkb_symbols block of a keymap file."""
    text = path.read_text(encoding="utf-8")
    start = text.index("xkb_symbols")
    brace = text.index("{", start)
    depth = 0
    for index in range(brace, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1 : index]
    raise ValueError(f"{path}: unterminated xkb_symbols block")


def parse_keys(body: str) -> list[tuple[str, str | None, str, str]]:
    """Return (key, type, group1 symbols, group2 symbols) for every key."""
    keys: list[tuple[str, str | None, str, str]] = []
    lines = body.split("\n")
    index = 0
    while index < len(lines):
        match = re.match(r"\s*key\s*<([A-Z0-9]+)>\s*\{\s*$", lines[index])
        if not match:
            index += 1
            continue
        block = [lines[index]]
        end = index + 1
        while end < len(lines) and not re.match(r"\s*\};\s*$", lines[end]):
            block.append(lines[end])
            end += 1
        block.append(lines[end])
        text = "\n".join(block)
        key_type = re.search(r'type\s*=\s*"([^"]+)"', text)
        group1 = re.search(r"symbols\[Group1\]\s*=\s*\[([^\]]*)\]", text, re.S)
        group2 = re.search(r"symbols\[Group2\]\s*=\s*\[([^\]]*)\]", text, re.S)
        if group1:
            keys.append(
                (
                    match.group(1),
                    key_type.group(1) if key_type else None,
                    group1.group(1),
                    group2.group(1) if group2 else group1.group(1),
                )
            )
        index = end + 1
    return keys


def render(keys: list[tuple[str, str | None, str, str]], group: int) -> str:
    lines = []
    for name, key_type, group1, group2 in keys:
        symbols = group1 if group == 1 else group2
        type_prefix = f'type = "{key_type}", ' if key_type else ""
        lines.append(f"        key <{name}> {{ {type_prefix}[{symbols}] }};")
    return "\n".join(lines)


def main() -> int:
    if not SOURCE.is_file():
        print(f"error: {SOURCE} not found", file=sys.stderr)
        return 1

    keys = parse_keys(read_symbols_body(SOURCE))
    if not keys:
        print(f"error: no key statements found in {SOURCE}", file=sys.stderr)
        return 1

    for group, spec in GROUPS.items():
        TARGET.mkdir(parents=True, exist_ok=True)
        target = TARGET / f"ul_combo_{group}"
        target.write_text(
            HEADER.format(
                title=spec["title"],
                group=group,
                base=spec["base"],
                extra=spec["extra"],
                keys=render(keys, 1 if group == "en" else 2),
            ),
            encoding="utf-8",
        )
        print(f"wrote {target} ({len(keys)} keys)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
