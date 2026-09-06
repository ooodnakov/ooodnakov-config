"""Prevent machine-generated and sensitive local files from entering git."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path, PurePosixPath

REPO_ROOT = Path(__file__).resolve().parent.parent

# Keep exceptions rare, exact, and reviewable. Add a path only when a tracked fixture
# must intentionally resemble runtime state; never allow real credentials or secrets.
TRACKED_ARTIFACT_ALLOWLIST: frozenset[str] = frozenset()

TIMESTAMPED_BACKUP = re.compile(r"\.backup-\d{8}-\d{6}$")
DEPENDENCY_DIRECTORIES = frozenset({"node_modules", ".venv", "vendor"})
RUNTIME_FILENAMES = frozenset(
    {
        ".zsh_history",
        "bw-session",
        "errors.log",
        "mcp-cache.json",
        "mcp-npx-cache.json",
        "run-history.jsonl",
        "runtime-state.json",
        "sessionstart.log",
    }
)
SENSITIVE_LOCAL_PATHS = frozenset(
    {
        "home/.config/ooodnakov/local/agents/data.json",
        "home/.config/ooodnakov/local/env.ps1",
        "home/.config/ooodnakov/local/env.zsh",
        "home/.config/ooodnakov/local/links.local.toml",
        "home/.config/task/local/taskrc",
        "home/.pi/agent/auth.json",
    }
)


def _tracked_paths() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
    )
    return [path.decode() for path in result.stdout.split(b"\0") if path]


def _artifact_reason(path: str) -> str | None:
    parsed = PurePosixPath(path)
    if TIMESTAMPED_BACKUP.search(parsed.name):
        return "timestamped backup"
    if DEPENDENCY_DIRECTORIES.intersection(parsed.parts):
        return "dependency directory"
    if parsed.name in RUNTIME_FILENAMES or parsed.name.startswith(".zcompdump"):
        return "runtime state"
    if path in SENSITIVE_LOCAL_PATHS:
        return "plaintext local or credential file"
    return None


def test_git_does_not_track_runtime_or_sensitive_artifacts() -> None:
    """Reject common local artifacts while keeping intentional fixtures explicit."""
    violations = {
        path: reason
        for path in _tracked_paths()
        if path not in TRACKED_ARTIFACT_ALLOWLIST
        if (reason := _artifact_reason(path)) is not None
    }

    details = "\n".join(f"- {path}: {reason}" for path, reason in sorted(violations.items()))
    assert not violations, f"Tracked local artifacts detected:\n{details}"


def test_dependency_lock_is_tracked_and_not_ignored() -> None:
    """Keep the generated dependency lock visible to drift checks and reviews."""
    tracked = set(_tracked_paths())
    assert "deps.lock.json" in tracked

    result = subprocess.run(
        ["git", "check-ignore", "--no-index", "--quiet", "deps.lock.json"],
        cwd=REPO_ROOT,
        check=False,
    )
    assert result.returncode == 1, "deps.lock.json is tracked but also ignored"
