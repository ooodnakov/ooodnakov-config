#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import re
import subprocess
import sys
import tomllib
from pathlib import Path

SCRIPTS_CLI_DIR = Path(__file__).resolve().parents[1] / "cli"
if str(SCRIPTS_CLI_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_CLI_DIR))

from cli_ui import bullet, section, status  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
OPTIONAL_DEPS = REPO_ROOT / "scripts" / "optional-deps.toml"
REPORT_PATH = REPO_ROOT / "docs" / "imports" / "upstream-audit.md"
GEN_LOCK = REPO_ROOT / "scripts" / "generate" / "generate_dependency_lock.py"
AUTOMATED_SECTION_HEADER = "## Automated Pin Checks"


def parse_pins(catalog_text: str) -> list[dict[str, str]]:
    catalog = tomllib.loads(catalog_text)
    managed_tools = catalog.get("managed-tools", {})

    rows: list[dict[str, str]] = []
    for name, tool in sorted(managed_tools.items()):
        if not isinstance(tool, dict):
            continue
        repo = tool.get("repo")
        ref = tool.get("ref")
        if not isinstance(repo, str) or not isinstance(ref, str):
            continue
        rows.append({"name": name, "repo": repo, "current": ref})
    return rows


def resolve_latest(repo: str) -> str:
    result = subprocess.run(
        ["git", "ls-remote", repo, "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.split()[0]


def build_rows(rows: list[dict[str, str]], *, offline: bool = False) -> list[dict[str, str]]:
    enriched: list[dict[str, str]] = []
    for row in rows:
        latest = row["current"] if offline else "unresolved"
        status = "not-checked" if offline else "error"
        if not offline:
            try:
                latest = resolve_latest(row["repo"])
                status = "up-to-date" if latest == row["current"] else "update-available"
            except Exception:
                pass
        enriched.append({**row, "latest": latest, "status": status})
    return enriched


def apply_updates(catalog_text: str, rows: list[dict[str, str]]) -> tuple[str, int]:
    updated = catalog_text
    applied = 0
    for row in rows:
        if row["status"] != "update-available":
            continue
        line_re = re.compile(
            rf'^(?P<prefix>{re.escape(row["name"])}\s*=\s*\{{[^}}\n]*?\bref\s*=\s*"){re.escape(row["current"])}(?P<suffix>"[^}}\n]*\}}\s*)$',
            re.MULTILINE,
        )
        updated, count = line_re.subn(rf"\g<prefix>{row['latest']}\g<suffix>", updated, count=1)
        applied += count
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
        lines.append(f"| `{row['name'].lower()}` | `{row['status']}` | `{row['current']}` | `{row['latest']}` |")
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
    parser = argparse.ArgumentParser(description="Check/update pinned git refs in scripts/optional-deps.toml")
    parser.add_argument(
        "--apply", action="store_true", help="apply update-available refs into scripts/optional-deps.toml"
    )
    parser.add_argument("--offline", action="store_true", help="parse pins without resolving remote HEAD commits")
    parser.add_argument("--dry-run", action="store_true", help="do not write report or lock artifacts")
    args = parser.parse_args()
    if args.apply and args.offline:
        parser.error("--apply cannot be combined with --offline")

    catalog_text = OPTIONAL_DEPS.read_text(encoding="utf-8")
    rows = build_rows(parse_pins(catalog_text), offline=args.offline)

    if args.apply:
        updated_text, applied = apply_updates(catalog_text, rows)
        if applied > 0:
            OPTIONAL_DEPS.write_text(updated_text, encoding="utf-8")
            catalog_text = updated_text
            rows = build_rows(parse_pins(catalog_text), offline=args.offline)
        status("ok", f"Applied {applied} ref update(s) to {OPTIONAL_DEPS}.")

    section("Dependency Pin Status")
    for row in rows:
        role = (
            "ok"
            if row["status"] in {"up-to-date", "not-checked"}
            else "warn"
            if row["status"] == "update-available"
            else "fail"
        )
        status(role, f"{row['name'].lower():<20} {row['status']:<16} {row['current'][:10]} -> {row['latest'][:10]}")

    if args.dry_run:
        print()
        bullet("Dry run: skipped report and lock artifact writes.")
    else:
        update_report(rows)
        print()
        bullet(f"Updated automated pin-check section in {REPORT_PATH}.")

        run_lock_generator()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
