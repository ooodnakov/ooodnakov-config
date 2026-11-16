#!/usr/bin/env python3
"""Synchronize this repository across SSH fleet hosts.

Per host: stash local work, rebase onto the remote branch (optionally letting an
`omp` agent resolve conflicts), restore the stash, push machine-local commits,
then re-apply managed links with `oooconf update --no-deps`.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import shlex
import shutil
import socket
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

STATUS_OK = "ok"
STATUS_CONFLICT = "conflict"
STATUS_FAILED = "failed"
STATUS_DRY_RUN = "dry-run"
STATUS_SKIPPED = "skipped"

SCHEMA_VERSION = 1
DEFAULT_BRANCH = "main"
DEFAULT_REPO_PATH = "~/src/ooodnakov-config"
DEFAULT_JOBS = 4
STASH_PREFIX = "oooconf fleet sync "
LINK_FALLBACK = "./home/.config/ooodnakov/bin/oooconf update --no-deps"
CONFLICT_HINT = "re-run with --resolve to let an omp agent resolve them"


@dataclass
class CommandResult:
    returncode: int
    stdout: str = ""
    stderr: str = ""


@dataclass
class SyncOptions:
    repo_path: str | None = None
    branch: str | None = None
    resolve: bool = False
    push: bool = True
    dry_run: bool = False
    agent_command: tuple[str, ...] = ("omp", "-p")
    connect_timeout: float = 10.0


@dataclass
class HostResult:
    host: str
    status: str
    repo: str | None = None
    branch: str | None = None
    dirty: bool = False
    stashed: bool = False
    behind: int = 0
    ahead: int = 0
    pushed: bool = False
    linked: bool = False
    resolved: bool = False
    conflicts: list[str] = field(default_factory=list)
    log: list[str] = field(default_factory=list)
    error: str | None = None
    skip_reason: str | None = None

    def to_dict(self) -> dict[str, object]:
        return {
            "host": self.host,
            "status": self.status,
            "repo": self.repo,
            "branch": self.branch,
            "dirty": self.dirty,
            "stashed": self.stashed,
            "behind": self.behind,
            "ahead": self.ahead,
            "pushed": self.pushed,
            "linked": self.linked,
            "resolved": self.resolved,
            "conflicts": list(self.conflicts),
            "log": list(self.log),
            "error": self.error,
            "skip_reason": self.skip_reason,
        }


def _ssh_executable() -> str:
    """Prefer native Windows OpenSSH: managed PATH shims can shadow it with an ssh that ignores ~/.ssh/config."""
    if sys.platform == "win32":
        native = Path(os.environ.get("WINDIR", r"C:\Windows")) / "System32" / "OpenSSH" / "ssh.exe"
        if native.is_file():
            return str(native)
    found = shutil.which("ssh")
    return found or "ssh"


class SshTransport:
    """Runs one POSIX shell script per call on a remote host over ssh."""

    def __init__(self, connect_timeout: float = 10.0, ssh: str | None = None) -> None:
        self.connect_timeout = connect_timeout
        self.ssh = ssh or _ssh_executable()

    def run(self, host: str, script: str) -> CommandResult:
        timeout = f"{self.connect_timeout:g}"
        command = [self.ssh, "-o", f"ConnectTimeout={timeout}", "--", host, "sh -lc " + shlex.quote(script)]
        try:
            completed = subprocess.run(command, capture_output=True, text=True, check=False)
        except OSError as exc:
            return CommandResult(returncode=127, stderr=str(exc))
        return CommandResult(returncode=completed.returncode, stdout=completed.stdout, stderr=completed.stderr)


def _script(*commands: str) -> str:
    return "\n".join(("export GIT_TERMINAL_PROMPT=0", *commands))


def _quote_repo(repo: str) -> str:
    if repo == "~":
        return '"$HOME"'
    if repo.startswith("~/"):
        return '"$HOME"/' + shlex.quote(repo[2:])
    return shlex.quote(repo)


def _git(repo: str, *args: str) -> str:
    return " ".join(("git", "-C", _quote_repo(repo), *args))


def _first_line(text: str) -> str:
    for line in text.splitlines():
        stripped = line.strip()
        if stripped:
            return stripped
    return ""


def _compact(text: str, limit: int = 400) -> str:
    collapsed = " | ".join(part.strip() for part in text.splitlines() if part.strip())
    if len(collapsed) > limit:
        return collapsed[: limit - 3] + "..."
    return collapsed


def _parse_counts(text: str) -> tuple[int, int]:
    """Parse `git rev-list --left-right --count` output as (behind, ahead)."""
    for line in reversed(text.splitlines()):
        parts = line.split()
        if len(parts) == 2 and all(part.lstrip("-").isdigit() for part in parts):
            return int(parts[0]), int(parts[1])
    return 0, 0


def _include_paths(home: Path, base: Path, token: str) -> list[Path]:
    """Resolve one `Include` token, expanding `~` against the given home directory."""
    if token == "~":
        candidate = home
    elif token.startswith("~/"):
        candidate = home / token[2:]
    elif token.startswith("~"):
        candidate = Path(token).expanduser()
    else:
        candidate = base / token
    matches = [Path(match) for match in sorted(glob.glob(str(candidate)))]
    return matches or [candidate]


@dataclass
class SshTarget:
    """One concrete `Host` alias plus the directives that decide machine identity."""

    alias: str
    hostname: str | None = None
    port: str | None = None
    user: str | None = None

    def identity(self) -> tuple[str, str]:
        return ((self.hostname or self.alias).strip().lower(), self.port or "22")


def parse_ssh_targets(home: Path | None = None) -> list[SshTarget]:
    """Collect concrete `Host` aliases and their HostName/Port/User from the ssh config chain."""
    home_dir = (home or Path.home()).expanduser()
    base = home_dir / ".ssh"
    targets: list[SshTarget] = []
    by_alias: dict[str, SshTarget] = {}
    visited: set[Path] = set()
    current: list[SshTarget] = []
    active = True

    def visit(path: Path) -> None:
        nonlocal current, active
        try:
            resolved = path.expanduser().resolve()
        except OSError:
            return
        if resolved in visited or not resolved.is_file():
            return
        visited.add(resolved)
        try:
            lines = resolved.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            return
        for raw in lines:
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            parts = line.split()
            keyword = parts[0].lower()
            values = parts[1:]
            if keyword == "match":
                # Match blocks never define concrete aliases we can reason about.
                active = False
                current = []
                continue
            if keyword == "host":
                active = True
                current = []
                for token in values:
                    if "*" in token or "?" in token or token.startswith("!"):
                        continue
                    target = by_alias.get(token)
                    if target is None:
                        target = SshTarget(alias=token)
                        by_alias[token] = target
                        targets.append(target)
                    current.append(target)
                continue
            if not active:
                continue
            if keyword == "include":
                for token in values:
                    for candidate in _include_paths(home_dir, base, token):
                        visit(candidate)
                continue
            if not values:
                continue
            if keyword == "hostname":
                for target in current:
                    target.hostname = values[0]
            elif keyword == "port":
                for target in current:
                    target.port = values[0]
            elif keyword == "user":
                for target in current:
                    target.user = values[0]

    visit(base / "config")
    visit(base / "config.local")
    return targets


def discover_hosts(home: Path | None = None) -> list[str]:
    """Collect concrete `Host` aliases from ssh config files and their Includes."""
    return [target.alias for target in parse_ssh_targets(home)]


def dedupe_hosts(hosts: list[str], targets: list[SshTarget] | None = None) -> tuple[list[str], dict[str, str]]:
    """Drop aliases that reach a machine already selected; return (kept, {alias: original alias})."""
    by_alias = {target.alias: target for target in (targets if targets is not None else parse_ssh_targets())}
    kept: list[str] = []
    duplicates: dict[str, str] = {}
    seen_aliases: set[str] = set()
    seen: dict[tuple[str, str], str] = {}
    for host in hosts:
        if host in seen_aliases:
            continue
        seen_aliases.add(host)
        target = by_alias.get(host)
        identity = target.identity() if target else (host.lower(), "22")
        first = seen.get(identity)
        if first is not None:
            duplicates[host] = first
            continue
        seen[identity] = host
        kept.append(host)
    return kept, duplicates


def _local_hostnames() -> set[str]:
    candidates = {socket.gethostname(), os.environ.get("COMPUTERNAME", "")}
    names: set[str] = set()
    for candidate in candidates:
        value = candidate.strip().lower()
        if not value:
            continue
        names.add(value)
        names.add(value.split(".")[0])
    names.update({"localhost", "127.0.0.1", "::1"})
    return names


def _is_local_hostname(value: str) -> bool:
    remote = value.strip().lower()
    if not remote:
        return False
    local = _local_hostnames()
    return remote in local or remote.split(".")[0] in local


def _probe_fields(text: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for line in text.splitlines():
        key, separator, value = line.partition("=")
        if separator:
            fields[key.strip()] = value.strip()
    return fields


def _preflight(host: str, options: SyncOptions, transport: object, result: HostResult) -> bool:
    """Verify ssh works, the user is not root, the repo exists, and the machine is not this one."""
    probe_path = options.repo_path or DEFAULT_REPO_PATH
    outcome = _run(
        transport,
        host,
        _script(
            "printf 'hostname=%s\\n' \"$(hostname 2>/dev/null || uname -n)\"",
            "printf 'user=%s\\n' \"$(id -un 2>/dev/null || whoami)\"",
            f"printf 'repo=%s\\n' \"$([ -d {_quote_repo(probe_path)} ] && echo yes || echo no)\"",
        ),
    )
    if outcome.returncode != 0:
        _fail(result, f"ssh {host}", outcome)
        return False

    fields = _probe_fields(outcome.stdout)
    remote_host = fields.get("hostname", "").strip().lower()
    user = fields.get("user", "").strip()

    def skip(reason: str) -> bool:
        result.status = STATUS_SKIPPED
        result.skip_reason = reason
        result.log.append(f"skipped: {reason}")
        return False

    if user == "root":
        return skip("root user")
    if fields.get("repo") != "yes":
        return skip(f"{probe_path} not found")
    if _is_local_hostname(remote_host):
        return skip("local machine")
    result.log.append(f"preflight ok: user={user or '?'} host={remote_host or '?'}")
    return True


def _run(transport: object, host: str, script: str) -> CommandResult:
    return transport.run(host, script)  # type: ignore[attr-defined]


def _fail(result: HostResult, step: str, outcome: CommandResult) -> HostResult:
    detail = _compact(outcome.stderr or outcome.stdout)
    if not detail:
        detail = f"exit code {outcome.returncode}"
    result.status = STATUS_FAILED
    result.log.append(f"{step} failed: {detail}")
    result.error = f"{step}: {detail}"
    return result


def _unmerged_files(host: str, repo: str, transport: object) -> list[str]:
    outcome = _run(transport, host, _script(_git(repo, "diff", "--name-only", "--diff-filter=U")))
    if outcome.returncode != 0:
        return []
    return [line.strip() for line in outcome.stdout.splitlines() if line.strip()]


def _resolve_prompt(host: str, repo: str) -> str:
    return (
        f"Resolve the git merge/rebase conflicts in {repo} on host {host}. "
        f"List them with `git -C {repo} diff --name-only --diff-filter=U`, edit each file into a correct merge, "
        f"`git -C {repo} add` every resolved file, then run `git -C {repo} rebase --continue` if a rebase is in "
        f"progress, otherwise finish the pending `git -C {repo} stash pop`. Leave the working tree clean. "
        "Never run `git reset --hard`, never discard commits, and never push."
    )


def _try_resolve(host: str, repo: str, options: SyncOptions, transport: object, result: HostResult) -> bool:
    """Ask an omp agent to finish the interrupted operation; True when the tree is unblocked."""
    if not options.resolve:
        return False
    agent = " ".join(shlex.quote(part) for part in (*options.agent_command, _resolve_prompt(host, repo)))
    outcome = _run(transport, host, _script(f"cd {_quote_repo(repo)} && {agent}"))
    result.log.append(f"spawned {' '.join(options.agent_command)} agent to resolve conflicts")
    if outcome.returncode != 0:
        detail = _compact(outcome.stderr or outcome.stdout) or f"exit code {outcome.returncode}"
        result.log.append(f"resolve agent failed: {detail}")
    remaining = _unmerged_files(host, repo, transport)
    if remaining:
        result.conflicts = remaining
        return False
    result.conflicts = []
    result.resolved = True
    result.log.append("conflicts resolved by agent")
    return True


def _detect_branch(host: str, repo: str, options: SyncOptions, transport: object, result: HostResult) -> str:
    if options.branch:
        return options.branch
    outcome = _run(
        transport,
        host,
        _script(_git(repo, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")),
    )
    detected = _first_line(outcome.stdout) if outcome.returncode == 0 else ""
    if detected.startswith("origin/"):
        return detected[len("origin/") :]
    if detected and "/" in detected:
        # Non-origin upstream: use its branch name because remotes here are always `origin`.
        return detected.rsplit("/", 1)[-1]
    if detected:
        return detected
    result.log.append(f"no upstream configured; assuming branch {DEFAULT_BRANCH}")
    return DEFAULT_BRANCH


def _resolve_repo(host: str, options: SyncOptions, transport: object, result: HostResult) -> str:
    if options.repo_path is not None:
        return options.repo_path
    outcome = _run(transport, host, _script("oooconf --print-repo-root"))
    found = _first_line(outcome.stdout) if outcome.returncode == 0 else ""
    if found:
        return found
    result.log.append(f"repo path lookup failed; defaulting to {DEFAULT_REPO_PATH}")
    return DEFAULT_REPO_PATH


def sync_host(host: str, options: SyncOptions, transport: object) -> HostResult:
    result = HostResult(host=host, status=STATUS_OK)
    if not _preflight(host, options, transport, result):
        return result
    repo = _resolve_repo(host, options, transport, result)
    result.repo = repo

    check = _run(transport, host, _script(_git(repo, "rev-parse", "--git-dir")))
    if check.returncode != 0:
        return _fail(result, "git rev-parse --git-dir", check)

    head = _run(transport, host, _script(_git(repo, "symbolic-ref", "--short", "HEAD")))
    current = _first_line(head.stdout) if head.returncode == 0 else ""
    if current:
        result.log.append(f"current branch {current}")

    branch = _detect_branch(host, repo, options, transport, result)
    result.branch = branch

    status = _run(transport, host, _script(_git(repo, "status", "--porcelain")))
    if status.returncode != 0:
        return _fail(result, "git status --porcelain", status)
    result.dirty = bool(status.stdout.strip())

    remote_range = shlex.quote(f"origin/{branch}...HEAD")

    if options.dry_run:
        counts = _run(transport, host, _script(_git(repo, "rev-list", "--left-right", "--count", remote_range)))
        if counts.returncode == 0:
            result.behind, result.ahead = _parse_counts(counts.stdout)
        result.status = STATUS_DRY_RUN
        result.log.append("dry-run: no fetch, stash, pull, push, or update issued")
        return result

    fetch = _run(transport, host, _script(_git(repo, "fetch", "--prune", "origin", shlex.quote(branch))))
    if fetch.returncode != 0:
        return _fail(result, "git fetch --prune", fetch)

    before = _run(transport, host, _script(_git(repo, "rev-list", "--left-right", "--count", remote_range)))
    if before.returncode == 0:
        result.behind, result.ahead = _parse_counts(before.stdout)

    if result.dirty:
        stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        message = shlex.quote(f"{STASH_PREFIX}{stamp} {host}")
        stash = _run(transport, host, _script(_git(repo, "stash", "push", "-u", "-m", message)))
        if stash.returncode != 0:
            return _fail(result, "git stash push", stash)
        result.stashed = True
        result.log.append("stashed local changes")

    pull = _run(transport, host, _script(_git(repo, "pull", "--rebase", "origin", shlex.quote(branch))))
    if pull.returncode != 0:
        files = _unmerged_files(host, repo, transport)
        if files:
            result.conflicts = files
            if not _try_resolve(host, repo, options, transport, result):
                result.status = STATUS_CONFLICT
                detail = _compact(pull.stderr or pull.stdout)
                if detail:
                    result.log.append(f"git pull --rebase: {detail}")
                return result
        else:
            return _fail(result, "git pull --rebase", pull)

    if result.stashed:
        pop = _run(transport, host, _script(_git(repo, "stash", "pop")))
        if pop.returncode != 0:
            files = _unmerged_files(host, repo, transport)
            if files:
                result.conflicts = files
            if not _try_resolve(host, repo, options, transport, result):
                result.status = STATUS_CONFLICT
                detail = _compact(pop.stderr or pop.stdout)
                if detail:
                    result.log.append(f"git stash pop: {detail}")
                return result

    after = _run(transport, host, _script(_git(repo, "rev-list", "--left-right", "--count", remote_range)))
    if after.returncode == 0:
        result.behind, result.ahead = _parse_counts(after.stdout)
    if result.ahead > 0 and options.push:
        push = _run(transport, host, _script(_git(repo, "push", "origin", shlex.quote(branch))))
        if push.returncode != 0:
            return _fail(result, "git push origin", push)
        result.pushed = True
        result.log.append(f"pushed {result.ahead} commit(s)")
    elif result.ahead > 0:
        result.log.append(f"{result.ahead} commit(s) left unpushed (--no-push)")

    link = _run(transport, host, _script(f"cd {_quote_repo(repo)} && oooconf update --no-deps"))
    if link.returncode != 0:
        link = _run(transport, host, _script(f"cd {_quote_repo(repo)} && {LINK_FALLBACK}"))
        if link.returncode != 0:
            return _fail(result, "oooconf update --no-deps", link)
    result.linked = True
    result.status = STATUS_OK
    return result


def sync_hosts(hosts: list[str], options: SyncOptions, transport: object, jobs: int = DEFAULT_JOBS) -> list[HostResult]:
    if not hosts:
        return []
    workers = max(1, jobs)
    if workers == 1 or len(hosts) == 1:
        return [sync_host(host, options, transport) for host in hosts]
    with ThreadPoolExecutor(max_workers=min(workers, len(hosts))) as pool:
        return list(pool.map(lambda host: sync_host(host, options, transport), hosts))


def _summarize(results: list[HostResult]) -> dict[str, int]:
    return {
        "ok": sum(1 for result in results if result.status == STATUS_OK),
        "conflict": sum(1 for result in results if result.status == STATUS_CONFLICT),
        "failed": sum(1 for result in results if result.status == STATUS_FAILED),
        "dry_run": sum(1 for result in results if result.status == STATUS_DRY_RUN),
        "skipped": sum(1 for result in results if result.status == STATUS_SKIPPED),
    }


def _flag(value: bool) -> str:
    return "yes" if value else "no"


def render_text(results: list[HostResult], options: SyncOptions) -> str:
    lines: list[str] = []
    for result in results:
        line = (
            f"{result.host:<18} {result.status:<8} branch={result.branch or '-'} repo={result.repo or '-'} "
            f"dirty={_flag(result.dirty)} stashed={_flag(result.stashed)} behind={result.behind} "
            f"ahead={result.ahead} pushed={_flag(result.pushed)} linked={_flag(result.linked)}"
        )
        if result.resolved:
            line += " resolved=yes"
        if result.conflicts:
            line += " conflicts=" + ",".join(result.conflicts)
        if result.skip_reason:
            line += " reason=" + result.skip_reason
        lines.append(line)
        if result.error:
            lines.append(f"  error: {result.error}")

    summary = _summarize(results)
    prefix = " (dry-run)" if options.dry_run else ""
    lines.append("")
    lines.append(
        f"fleet sync{prefix}: ok={summary['ok']} conflict={summary['conflict']} "
        f"failed={summary['failed']} skipped={summary['skipped']} dry-run={summary['dry_run']}"
    )
    if summary["conflict"] and not options.resolve:
        lines.append(f"hint: {CONFLICT_HINT}")
    return "\n".join(lines)


def exit_code(results: list[HostResult]) -> int:
    if not results:
        return 1
    if any(result.status == STATUS_CONFLICT for result in results):
        return 2
    if any(result.status not in (STATUS_OK, STATUS_DRY_RUN, STATUS_SKIPPED) for result in results):
        return 1
    return 0


def build_transport(options: SyncOptions) -> SshTransport:
    return SshTransport(connect_timeout=options.connect_timeout)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="oooconf fleet",
        description="Synchronize this repository across SSH fleet hosts.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "examples:\n"
            "  oooconf fleet sync orange site\n"
            "  oooconf fleet sync --all --format json\n"
            "  oooconf fleet sync --all --resolve\n"
            "  oooconf fleet sync --all --no-push --dry-run\n"
        ),
    )
    parser.add_argument("--repo-root", default=None, help="Local repository root (validated, otherwise unused).")
    subparsers = parser.add_subparsers(dest="command", required=False)

    sync_parser = subparsers.add_parser(
        "sync",
        help="Stash, pull, optionally resolve conflicts, push, then re-link on SSH hosts.",
        description=(
            "For each host: stash local changes, rebase onto the remote branch, optionally let an omp agent "
            "resolve conflicts (--resolve), restore the stash, push machine-local commits, then run "
            "`oooconf update --no-deps`."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "examples:\n"
            "  oooconf fleet sync orange site\n"
            "  oooconf fleet sync --all --format json\n"
            "  oooconf fleet sync --all --resolve\n"
        ),
    )
    sync_parser.add_argument("hosts", nargs="*", metavar="HOST", help="SSH config host aliases.")
    sync_parser.add_argument("--all", action="store_true", help="Sync every host alias found in the ssh config.")
    sync_parser.add_argument("--repo-path", default=None, help="Remote repository path on each host.")
    sync_parser.add_argument("--branch", default=None, help="Remote branch to rebase onto (default: upstream or main).")
    sync_parser.add_argument("--jobs", type=int, default=DEFAULT_JOBS, help="Parallel hosts (default: 4).")
    sync_parser.add_argument(
        "--resolve",
        action="store_true",
        help="Spawn an omp agent on the host to resolve conflicts (default: off).",
    )
    sync_parser.add_argument("--no-push", action="store_true", help="Never push machine-local commits.")
    sync_parser.add_argument("--format", choices=("text", "json"), default="text", help="Output format.")
    sync_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Inspect repo/branch/dirty/ahead/behind only; no fetch, stash, pull, push, or update.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command is None:
        parser.print_help()
        return 2

    if args.repo_root is not None:
        root = Path(args.repo_root).expanduser()
        if not root.is_dir():
            print(f"oooconf fleet sync: --repo-root is not a directory: {args.repo_root}", file=sys.stderr)
            return 2

    requested = list(dict.fromkeys(args.hosts))
    if args.all:
        for host in discover_hosts():
            if host not in requested:
                requested.append(host)
    if not requested:
        print("oooconf fleet sync: no hosts given; pass SSH host aliases or --all", file=sys.stderr)
        return 2

    options = SyncOptions(
        repo_path=args.repo_path,
        branch=args.branch,
        resolve=args.resolve,
        push=not args.no_push,
        dry_run=args.dry_run,
    )
    live, duplicates = dedupe_hosts(requested)
    transport = build_transport(options)
    results = sync_hosts(live, options, transport, jobs=args.jobs)
    by_host = {result.host: result for result in results}
    ordered: list[HostResult] = []
    for host in requested:
        if host in duplicates:
            ordered.append(HostResult(host=host, status=STATUS_SKIPPED, skip_reason=f"duplicate of {duplicates[host]}"))
        else:
            ordered.append(by_host[host])

    if args.format == "json":
        document = {
            "schema_version": SCHEMA_VERSION,
            "hosts": [result.to_dict() for result in ordered],
            "summary": _summarize(ordered),
        }
        print(json.dumps(document, indent=2))
    else:
        print(render_text(ordered, options))
    return exit_code(ordered)


if __name__ == "__main__":
    raise SystemExit(main())
