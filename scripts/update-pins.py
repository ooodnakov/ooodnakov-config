#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SETUP_SH = REPO_ROOT / "scripts" / "setup.sh"
REPORT_PATH = REPO_ROOT / "docs" / "imports" / "upstream-audit.md"
GEN_LOCK = REPO_ROOT / "scripts" / "generate-dependency-lock.py"
AUTOMATED_SECTION_HEADER = "## Automated Pin Checks"
PAIR_RE = re.compile(r'^(?P<name>[A-Z0-9_]+)_(?P<kind>REPO|REF)="(?P<value>.+)"$')


def parse_pins(setup_text: str) -> list[dict[str, str]]:
    entries: dict[str, dict[str, str]] = {}
    for raw in setup_text.splitlines():
        match = PAIR_RE.match(raw.strip())
        if not match:
            continue
        entries.setdefault(match.group("name"), {})[match.group("kind")] = match.group("value")

    rows: list[dict[str, str]] = []
    for name in sorted(entries):
        row = entries[name]
        if "REPO" not in row or "REF" not in row:
            continue
        rows.append({"name": name, "repo": row["REPO"], "current": row["REF"]})
    return rows


def resolve_latest(repo: str) -> str:
    result = subprocess.run(
        ["git", "ls-remote", repo, "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.split()[0]


def build_rows(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    enriched: list[dict[str, str]] = []
    for row in rows:
        latest = "unresolved"
        status = "error"
        try:
            latest = resolve_latest(row["repo"])
            status = "up-to-date" if latest == row["current"] else "update-available"
        except Exception:
            pass
        enriched.append({**row, "latest": latest, "status": status})
    return enriched


def apply_updates(setup_text: str, rows: list[dict[str, str]]) -> tuple[str, int]:
    updated = setup_text
    applied = 0
    for row in rows:
        if row["status"] != "update-available":
            continue
        before = f'{row["name"]}_REF="{row["current"]}"'
        after = f'{row["name"]}_REF="{row["latest"]}"'
        if before in updated:
            updated = updated.replace(before, after, 1)
            applied += 1
    return updated, applied


def pin_check_markdown(rows: list[dict[str, str]]) -> str:
    stamp = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()
    lines = [
        AUTOMATED_SECTION_HEADER,
        "",
        f"Last checked (UTC): `{stamp}`",
        "",
        "| Dependency | Status | Current ref | Latest HEAD |",
        "| --- | --- | --- | --- |",
    ]
    for row in rows:
        lines.append(
            f"| `{row['name'].lower()}` | `{row['status']}` | `{row['current']}` | `{row['latest']}` |"
        )
    lines.append("")
    return "\n".join(lines)


def update_report(rows: list[dict[str, str]]) -> None:
    report_text = REPORT_PATH.read_text(encoding="utf-8")
    section = pin_check_markdown(rows)
    if AUTOMATED_SECTION_HEADER in report_text:
        base = report_text.split(AUTOMATED_SECTION_HEADER, 1)[0].rstrip() + "\n\n"
        REPORT_PATH.write_text(base + section, encoding="utf-8")
    else:
        REPORT_PATH.write_text(report_text.rstrip() + "\n\n" + section, encoding="utf-8")


def run_lock_generator() -> None:
    subprocess.run([sys.executable, str(GEN_LOCK)], check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Check/update pinned git refs in scripts/setup.sh")
    parser.add_argument("--apply", action="store_true", help="apply update-available refs into scripts/setup.sh")
    args = parser.parse_args()

    setup_text = SETUP_SH.read_text(encoding="utf-8")
    rows = build_rows(parse_pins(setup_text))

    if args.apply:
        updated_text, applied = apply_updates(setup_text, rows)
        if applied > 0:
            SETUP_SH.write_text(updated_text, encoding="utf-8")
            setup_text = updated_text
            rows = build_rows(parse_pins(setup_text))
        print(f"Applied {applied} ref update(s) to {SETUP_SH}.")

    print("Dependency pin status:")
    print("name\tstatus\tcurrent\tlatest")
    for row in rows:
        print(f"{row['name'].lower()}\t{row['status']}\t{row['current'][:10]}\t{row['latest'][:10]}")

    update_report(rows)
    print(f"Updated automated pin-check section in {REPORT_PATH}.")

    run_lock_generator()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
