#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SETUP_SH = REPO_ROOT / "scripts" / "setup.sh"
JSON_LOCK = REPO_ROOT / "deps.lock.json"
MD_LOCK = REPO_ROOT / "docs" / "dependency-lock.md"

PAIR_RE = re.compile(r'^(?P<name>[A-Z0-9_]+)_(?P<kind>REPO|REF)="(?P<value>.+)"$')


def parse_setup_pins(text: str) -> list[dict[str, str]]:
    entries: dict[str, dict[str, str]] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        match = PAIR_RE.match(line)
        if not match:
            continue
        name = match.group("name")
        kind = match.group("kind").lower()
        entries.setdefault(name, {})[kind] = match.group("value")

    pins = []
    for name in sorted(entries):
        row = entries[name]
        if "repo" not in row or "ref" not in row:
            continue
        pins.append({
            "name": name.lower(),
            "repo": row["repo"],
            "ref": row["ref"],
        })
    return pins


def write_json_lock(pins: list[dict[str, str]]) -> None:
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    if JSON_LOCK.exists():
        try:
            existing = json.loads(JSON_LOCK.read_text(encoding="utf-8"))
            if "generated_at_utc" in existing:
                generated_at = existing["generated_at_utc"]
        except Exception:
            pass

    payload = {
        "generated_at_utc": generated_at,
        "source": "scripts/setup.sh",
        "dependencies": pins,
    }
    JSON_LOCK.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_markdown_lock(pins: list[dict[str, str]]) -> None:
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    if MD_LOCK.exists():
        try:
            content = MD_LOCK.read_text(encoding="utf-8")
            match = re.search(r"Generated at \(UTC\): `(.+?)`", content)
            if match:
                generated_at = match.group(1)
        except Exception:
            pass

    lines = [
        "# Dependency Lock",
        "",
        "Generated from `scripts/setup.sh` pinned dependency refs.",
        "",
        f"Generated at (UTC): `{generated_at}`",
        "",
        "| Dependency | Repository | Pinned ref |",
        "| --- | --- | --- |",
    ]
    for pin in pins:
        lines.append(f"| `{pin['name']}` | `{pin['repo']}` | `{pin['ref']}` |")
    lines.append("")
    MD_LOCK.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    setup_text = SETUP_SH.read_text(encoding="utf-8")
    pins = parse_setup_pins(setup_text)
    write_json_lock(pins)
    write_markdown_lock(pins)
    print(f"Wrote {JSON_LOCK}")
    print(f"Wrote {MD_LOCK}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
