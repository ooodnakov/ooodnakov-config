#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

# Make local scripts importable (cli_ui, etc.)
sys.path.insert(0, str(Path(__file__).parent))
from cli_ui import status

REPO_ROOT = Path(__file__).resolve().parent.parent
JSON_LOCK = REPO_ROOT / "deps.lock.json"
MD_LOCK = REPO_ROOT / "docs" / "dependency-lock.md"


def parse_managed_tools() -> list[dict[str, str]]:
    """Parse from optional-deps.toml managed-tools section (sole source of truth)."""
    import subprocess
    data = subprocess.run(
        ["uv", "run", "scripts/read_optional_deps.py", "managed-tools"],
        capture_output=True,
        text=True,
        check=True,
    )
    import json
    tools = json.loads(data.stdout)
    pins = []
    for name, info in sorted(tools.items()):
        if isinstance(info, dict) and "repo" in info and "ref" in info:
            pins.append({
                "name": name,
                "repo": info["repo"],
                "ref": info["ref"],
            })
    return pins


def write_json_lock(pins: list[dict[str, str]], generated_at: str) -> None:
    payload = {
        "generated_at_utc": generated_at,
        "source": "scripts/optional-deps.toml",
        "dependencies": pins,
    }
    JSON_LOCK.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_markdown_lock(pins: list[dict[str, str]], generated_at: str) -> None:
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
    pins = parse_managed_tools()

    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    if JSON_LOCK.exists():
        try:
            old_lock = json.loads(JSON_LOCK.read_text(encoding="utf-8"))
            if old_lock.get("dependencies") == pins:
                generated_at = old_lock.get("generated_at_utc", generated_at)
        except Exception:
            pass

    write_json_lock(pins, generated_at)
    write_markdown_lock(pins, generated_at)
    status("ok", f"Wrote {JSON_LOCK} (from optional-deps.toml managed-tools)")
    status("ok", f"Wrote {MD_LOCK}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
