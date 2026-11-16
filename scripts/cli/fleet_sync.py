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
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

_CLI_DIR = str(Path(__file__).resolve().parent)
if _CLI_DIR not in sys.path:
    sys.path.insert(0, _CLI_DIR)

import cli_ui  # noqa: E402  (shared Nerd Font icon/color helpers live beside this script)

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
    connect_retries: int = 1


@dataclass
class HostResult:
    host: str
    status: str
    repo: str | None = None
    branch: str | None = None
    dirty: bool = False
    stashed: bool = False
    stash_pending: bool = False
    behind: int = 0
    ahead: int = 0
    pushed: bool = False
    linked: bool = False
    resolved: bool = False
    reachable: bool = False
    fix: str | None = None
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
            "reachable": self.reachable,
            "fix": self.fix,
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


CONNECTION_ERROR_MARKERS = (
    "ssh: connect to host",
    "connection timed out",
    "operation timed out",
    "connection refused",
    "connection reset",
    "no route to host",
    "network is unreachable",
    "kex_exchange_identification",
    "ssh_exchange_identification",
    "timeout, server",
    "banner exchange",
    "broken pipe",
    "client_loop",
    "connection to ",
    "connection closed",
    "session closed",
)


def _is_connection_error(text: str) -> bool:
    lowered = text.lower()
    return any(marker in lowered for marker in CONNECTION_ERROR_MARKERS)


class _SshSession:
    """One persistent `ssh <host> sh`, reused for every remote call to that host."""

    def __init__(self, transport: "SshTransport", host: str) -> None:
        self.token = f"__OOOCONF_FLEET_DONE_{uuid.uuid4().hex}__ "
        self.process = transport.spawn(host)

    def execute(self, script: str, on_line: object | None = None) -> CommandResult:
        process = self.process
        if process is None or process.stdin is None or process.stdout is None:
            return CommandResult(255, "", "ssh session closed")
        payload = f"{{ {script}\n}} </dev/null 2>&1\nprintf '{self.token}%s\\n' \"$?\"\n"
        try:
            # Binary pipes keep the wire protocol LF-only on every platform.
            process.stdin.write(payload.encode("utf-8"))
            process.stdin.flush()
        except (OSError, ValueError):
            return CommandResult(255, "", "ssh session closed")

        lines: list[str] = []
        while True:
            try:
                raw = process.stdout.readline()
            except (OSError, ValueError):
                return CommandResult(255, "".join(lines), "ssh session closed")
            if not raw:
                code = process.poll()
                return CommandResult(255 if code is None else code, "".join(lines), "ssh session closed")
            line = raw.decode("utf-8", "replace")
            if line.startswith(self.token):
                try:
                    status = int(line[len(self.token) :].strip())
                except ValueError:
                    status = 255
                return CommandResult(status, "".join(lines), "")
            lines.append(line)
            if on_line is not None:
                on_line(line.rstrip("\n"))  # type: ignore[operator]

    def close(self) -> None:
        process, self.process = self.process, None
        if process is None:
            return
        try:
            if process.stdin is not None:
                process.stdin.close()
        except OSError:
            pass
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()


class SshTransport:
    """Runs every remote script inside one persistent shell per host, retrying a dropped connection."""

    def __init__(
        self,
        connect_timeout: float = 10.0,
        ssh: str | None = None,
        retries: int = 1,
        popen: object | None = None,
    ) -> None:
        self.connect_timeout = connect_timeout
        self.ssh = ssh or _ssh_executable()
        self.retries = max(0, retries)
        self.popen = popen or subprocess.Popen
        self._sessions: dict[str, _SshSession] = {}
        self._lock = threading.Lock()

    def command_for(self, host: str) -> list[str]:
        return [
            self.ssh,
            "-o",
            f"ConnectTimeout={self.connect_timeout:g}",
            "-o",
            "ServerAliveInterval=15",
            "-o",
            "ServerAliveCountMax=4",
            "--",
            host,
            "sh",
            "-l",
        ]

    def spawn(self, host: str) -> object:
        return self.popen(
            self.command_for(host),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=0,
        )

    def _session(self, host: str) -> _SshSession:
        with self._lock:
            session = self._sessions.get(host)
            if session is None:
                session = _SshSession(self, host)
                self._sessions[host] = session
            return session

    def _drop(self, host: str) -> None:
        with self._lock:
            session = self._sessions.pop(host, None)
        if session is not None:
            session.close()

    def run(self, host: str, script: str, on_line: object | None = None) -> CommandResult:
        result = CommandResult(255, "", "ssh session closed")
        for attempt in range(self.retries + 1):
            try:
                result = self._session(host).execute(script, on_line)
            except OSError as exc:
                return CommandResult(127, "", str(exc))
            if not _is_connection_error(result.stdout + result.stderr):
                return result
            self._drop(host)
            if attempt < self.retries:
                time.sleep(0.4 * (attempt + 1))
        return result

    def close(self) -> None:
        for host in list(self._sessions):
            self._drop(host)


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
    result.reachable = True
    result.log.append(f"preflight ok: user={user or '?'} host={remote_host or '?'}")
    return True


def _run(transport: object, host: str, script: str, on_line: object | None = None) -> CommandResult:
    if on_line is None:
        return transport.run(host, script)  # type: ignore[attr-defined]
    return transport.run(host, script, on_line)  # type: ignore[attr-defined]


def _fail(result: HostResult, step: str, outcome: CommandResult) -> HostResult:
    # Merged stderr streams put the useful ssh/git text in stdout; keep both when they differ.
    combined = "\n".join(part.strip() for part in (outcome.stdout, outcome.stderr) if part.strip())
    detail = _compact(combined)
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


def _status_lines(result: HostResult) -> list[str]:
    """The sync state an agent needs to know before touching a host."""
    lines = [
        f"host={result.host} status={result.status} branch={result.branch or '-'} repo={result.repo or '-'}",
        f"dirty={'yes' if result.dirty else 'no'} stashed={'yes' if result.stashed else 'no'} "
        f"behind={result.behind} ahead={result.ahead} pushed={'yes' if result.pushed else 'no'} "
        f"linked={'yes' if result.linked else 'no'}",
    ]
    if result.error:
        lines.append(f"error: {result.error}")
    if result.conflicts:
        lines.append("conflicts: " + ", ".join(result.conflicts))
    for entry in result.log[-8:]:
        lines.append(f"- {entry}")
    return lines


def _remote_fix_prompt(result: HostResult) -> str:
    return " ".join(
        [
            f"You are repairing {result.repo or DEFAULT_REPO_PATH} on this machine after `oooconf fleet sync`",
            "stopped there.",
            "Status reported by the sync:",
            "; ".join(_status_lines(result)),
            f"Inspect with `git -C {result.repo} status`, resolve every conflict into a correct merge,",
            f"`git -C {result.repo} add` each resolved file, finish the in-progress rebase with",
            f"`git -C {result.repo} rebase --continue` or the pending `git -C {result.repo} stash pop`, then push",
            "the branch to origin if it is ahead. Leave a clean working tree. Never run `git reset --hard`,",
            "never force-push, and never discard commits.",
        ]
    )


def _local_fix_prompt(pending: list[HostResult]) -> str:
    lines = [
        "You are repairing fleet hosts that `oooconf fleet sync` could not finish.",
        "Run every remote command over ssh, for example: ssh <host> 'sh -lc \"...\"'.",
        "Status reported by the sync:",
    ]
    for result in pending:
        lines.append(f"- {'; '.join(_status_lines(result))}")
    lines.extend(
        [
            "For each host: cd to its repo, inspect with `git status`, resolve every conflict into a correct merge,",
            "`git add` each resolved file, finish the in-progress rebase (`git rebase --continue`) or the pending",
            "`git stash pop`, push the branch to origin when it is ahead, then run `oooconf update --no-deps` in",
            "that checkout. Leave clean working trees. Never run `git reset --hard`, never force-push, and never",
            "discard commits. Finish by printing one status line per host.",
        ]
    )
    return " ".join(lines)


def _run_remote_agent(
    result: HostResult,
    options: SyncOptions,
    transport: object,
    on_line: object | None = None,
) -> CommandResult:
    command = " ".join(shlex.quote(part) for part in (*options.agent_command, _remote_fix_prompt(result)))
    outcome = _run(
        transport,
        result.host,
        _script(f"cd {_quote_repo(result.repo or DEFAULT_REPO_PATH)} && {command}"),
        on_line,
    )
    if outcome.returncode != 0:
        detail = _compact(outcome.stderr or outcome.stdout) or f"exit code {outcome.returncode}"
        result.log.append(f"remote fix agent failed: {detail}")
    else:
        result.log.append("remote fix agent finished")
    return outcome


def _run_local_agent(
    pending: list[HostResult],
    options: SyncOptions,
    repo_root: Path,
    on_line: object | None = None,
) -> CommandResult:
    command = [*options.agent_command, _local_fix_prompt(pending)]
    try:
        process = subprocess.Popen(
            command,
            cwd=str(repo_root),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=0,
        )
    except OSError as exc:
        return CommandResult(returncode=127, stderr=str(exc))
    collected: list[str] = []
    assert process.stdout is not None
    while True:
        raw = process.stdout.readline()
        if not raw:
            break
        line = raw.decode("utf-8", "replace")
        collected.append(line)
        if on_line is not None:
            on_line(line.rstrip("\n"))  # type: ignore[operator]
    return CommandResult(returncode=process.wait(), stdout="".join(collected))


def needs_fix(results: list[HostResult]) -> list[HostResult]:
    """Hosts an agent can still repair: conflicts, or a reachable host that failed mid-pipeline."""
    return [
        result
        for result in results
        if result.status == STATUS_CONFLICT or (result.status == STATUS_FAILED and result.reachable)
    ]


def _complete_after_fix(result: HostResult, options: SyncOptions, transport: object) -> HostResult:
    """Finish a host after an agent repaired it: restore the stash, push host commits, re-link."""
    repo, branch = result.repo, result.branch
    if repo is None or branch is None:
        return result
    host = result.host
    if result.stash_pending:
        pop = _run(transport, host, _script(_git(repo, "stash", "pop")))
        already_popped = "No stash entries" in (pop.stdout + pop.stderr)
        if pop.returncode != 0 and not already_popped:
            files = _unmerged_files(host, repo, transport)
            result.conflicts = files or result.conflicts
            detail = _compact(pop.stderr or pop.stdout)
            if detail:
                result.log.append(f"git stash pop after fix: {detail}")
            result.status = STATUS_CONFLICT
            return result
        result.stash_pending = False
        result.log.append("stash restored after fix" if not already_popped else "stash already restored by the agent")

    counts = _run(
        transport,
        host,
        _script(_git(repo, "rev-list", "--left-right", "--count", shlex.quote(f"origin/{branch}...HEAD"))),
    )
    if counts.returncode == 0:
        result.behind, result.ahead = _parse_counts(counts.stdout)
    if result.ahead > 0 and options.push:
        push = _run(transport, host, _script(_git(repo, "push", "origin", shlex.quote(branch))))
        if push.returncode != 0:
            return _fail(result, "git push origin", push)
        result.pushed = True
        result.log.append(f"pushed {result.ahead} commit(s) after fix")

    link = _run(transport, host, _script(f"cd {_quote_repo(repo)} && oooconf update --no-deps"))
    if link.returncode != 0:
        link = _run(transport, host, _script(f"cd {_quote_repo(repo)} && {LINK_FALLBACK}"))
        if link.returncode != 0:
            return _fail(result, "oooconf update --no-deps", link)
    result.linked = True
    result.conflicts = []
    result.status = STATUS_OK
    return result


def apply_fixes(
    results: list[HostResult],
    options: SyncOptions,
    transport: object,
    repo_root: Path,
    on_result: object | None = None,
    on_event: object | None = None,
    line: object | None = None,
) -> list[HostResult]:
    """Spawn one omp agent on the single broken host, or one local agent for several, then finish them."""
    pending = needs_fix(results)
    if not pending or not options.resolve or options.dry_run:
        return results

    write = line or _write
    mode = "remote-agent" if len(pending) == 1 else "local-agent"
    if mode == "remote-agent":
        write(
            f"{cli_ui.colorize(cli_ui.icon('hint'), 'hint')} spawning omp agent on {pending[0].host} (default settings)"
        )
        outcome = _run_remote_agent(pending[0], options, transport, on_line=write)
    else:
        write(
            f"{cli_ui.colorize(cli_ui.icon('hint'), 'hint')} spawning one local omp agent for "
            f"{len(pending)} host(s) (default settings)"
        )
        outcome = _run_local_agent(pending, options, repo_root, on_line=write)
        detail = _compact(outcome.stderr or outcome.stdout)
        for result in pending:
            result.log.append(
                f"local fix agent exit={outcome.returncode}" + (f": {detail}" if detail and outcome.returncode else "")
            )
    write(f"{cli_ui.colorize(cli_ui.icon('info'), 'info')} omp agent finished (exit {outcome.returncode})")
    for result in pending:
        result.fix = mode

    for result in pending:
        _notify(on_event, result.host, "finishing after the agent")
        _complete_after_fix(result, options, transport)
        if result.status == STATUS_OK:
            result.resolved = True
        if on_result is not None:
            on_result(result)  # type: ignore[operator]
    return results


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
    found = ""
    if outcome.returncode == 0:
        # Login-shell banners can precede the path, so take the last absolute-path line.
        for line in outcome.stdout.splitlines():
            candidate = line.strip()
            if candidate.startswith("/"):
                found = candidate
    if found:
        return found
    result.log.append(f"repo path lookup failed; defaulting to {DEFAULT_REPO_PATH}")
    return DEFAULT_REPO_PATH


def sync_host(
    host: str,
    options: SyncOptions,
    transport: object,
    on_event: object | None = None,
) -> HostResult:
    def step(message: str) -> None:
        _notify(on_event, message)

    result = HostResult(host=host, status=STATUS_OK)
    step(f"connecting to {host}")
    step("checking ssh, user and checkout")
    if not _preflight(host, options, transport, result):
        return result
    step("preflight ok")
    step("resolving repo path")
    repo = _resolve_repo(host, options, transport, result)
    result.repo = repo

    step("reading branch and working tree")
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
        step("reading ahead/behind")
        counts = _run(transport, host, _script(_git(repo, "rev-list", "--left-right", "--count", remote_range)))
        if counts.returncode == 0:
            result.behind, result.ahead = _parse_counts(counts.stdout)
        result.status = STATUS_DRY_RUN
        result.log.append("dry-run: no fetch, stash, pull, push, or update issued")
        return result

    step(f"fetching origin/{branch}")
    fetch = _run(transport, host, _script(_git(repo, "fetch", "--prune", "origin", shlex.quote(branch))))
    if fetch.returncode != 0:
        return _fail(result, "git fetch --prune", fetch)

    before = _run(transport, host, _script(_git(repo, "rev-list", "--left-right", "--count", remote_range)))
    if before.returncode == 0:
        result.behind, result.ahead = _parse_counts(before.stdout)

    if result.dirty:
        step("stashing local changes")
        stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        message = shlex.quote(f"{STASH_PREFIX}{stamp} {host}")
        stash = _run(transport, host, _script(_git(repo, "stash", "push", "-u", "-m", message)))
        if stash.returncode != 0:
            return _fail(result, "git stash push", stash)
        if "No local changes to save" in stash.stdout + stash.stderr:
            # A retried attempt can see the tree already stashed; treat it as a no-op.
            result.log.append("nothing left to stash")
        else:
            result.stashed = True
            result.stash_pending = True
            result.log.append("stashed local changes")

    step(f"pulling --rebase origin/{branch}")
    pull = _run(transport, host, _script(_git(repo, "pull", "--rebase", "origin", shlex.quote(branch))))
    if pull.returncode != 0:
        files = _unmerged_files(host, repo, transport)
        if not files:
            return _fail(result, "git pull --rebase", pull)
        result.conflicts = files
        result.status = STATUS_CONFLICT
        detail = _compact(pull.stderr or pull.stdout)
        if detail:
            result.log.append(f"git pull --rebase: {detail}")
        return result

    if result.stashed:
        step("restoring stash")
        pop = _run(transport, host, _script(_git(repo, "stash", "pop")))
        already_popped = "No stash entries" in (pop.stdout + pop.stderr)
        if pop.returncode != 0 and not already_popped:
            result.conflicts = _unmerged_files(host, repo, transport) or result.conflicts
            result.status = STATUS_CONFLICT
            detail = _compact(pop.stderr or pop.stdout)
            if detail:
                result.log.append(f"git stash pop: {detail}")
            return result
        result.stash_pending = False
        result.log.append("restored stash" if not already_popped else "stash already restored")

    after = _run(transport, host, _script(_git(repo, "rev-list", "--left-right", "--count", remote_range)))
    if after.returncode == 0:
        result.behind, result.ahead = _parse_counts(after.stdout)
    if result.ahead > 0 and options.push:
        step(f"pushing {result.ahead} commit(s)")
        push = _run(transport, host, _script(_git(repo, "push", "origin", shlex.quote(branch))))
        if push.returncode != 0:
            return _fail(result, "git push origin", push)
        result.pushed = True
        result.log.append(f"pushed {result.ahead} commit(s)")
    elif result.ahead > 0:
        result.log.append(f"{result.ahead} commit(s) left unpushed (--no-push)")

    step("running oooconf update --no-deps")
    link = _run(transport, host, _script(f"cd {_quote_repo(repo)} && oooconf update --no-deps"))
    if link.returncode != 0:
        link = _run(transport, host, _script(f"cd {_quote_repo(repo)} && {LINK_FALLBACK}"))
        if link.returncode != 0:
            return _fail(result, "oooconf update --no-deps", link)
    result.linked = True
    result.status = STATUS_OK
    return result


def sync_hosts(
    hosts: list[str],
    options: SyncOptions,
    transport: object,
    jobs: int = DEFAULT_JOBS,
    on_result: object | None = None,
    on_event: object | None = None,
) -> list[HostResult]:
    """Sync hosts in parallel, reporting each as it finishes; the returned list keeps input order."""
    if not hosts:
        return []
    workers = max(1, jobs)
    results: dict[int, HostResult] = {}

    def report(index: int, host: str) -> None:
        results[index] = sync_host(
            host,
            options,
            transport,
            on_event=(lambda message: on_event(host, message)) if on_event is not None else None,  # type: ignore[operator]
        )
        if on_result is not None:
            on_result(results[index])  # type: ignore[operator]

    if workers == 1 or len(hosts) == 1:
        for index, host in enumerate(hosts):
            report(index, host)
        return [results[index] for index in range(len(hosts))]

    with ThreadPoolExecutor(max_workers=min(workers, len(hosts))) as pool:
        futures = {pool.submit(report, index, host): index for index, host in enumerate(hosts)}
        for future in as_completed(futures):
            future.result()
    return [results[index] for index in range(len(hosts))]


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


_STATUS_ROLES = {
    STATUS_OK: "ok",
    STATUS_CONFLICT: "warn",
    STATUS_FAILED: "fail",
    STATUS_SKIPPED: "missing",
    STATUS_DRY_RUN: "info",
}


def host_line(result: HostResult) -> str:
    line = (
        f"{result.host:<18} {result.status:<8} branch={result.branch or '-'} repo={result.repo or '-'} "
        f"dirty={_flag(result.dirty)} stashed={_flag(result.stashed)} behind={result.behind} "
        f"ahead={result.ahead} pushed={_flag(result.pushed)} linked={_flag(result.linked)}"
    )
    if result.resolved:
        line += " resolved=yes"
    if result.fix:
        line += " fix=" + result.fix
    if result.conflicts:
        line += " conflicts=" + ",".join(result.conflicts)
    if result.skip_reason:
        line += " reason=" + result.skip_reason
    return line


def _write(text: str) -> None:
    """Write straight to the interactive stream and flush, so PowerShell pipelines stay live."""
    stream = cli_ui.console_stream()
    stream.write(text)
    stream.flush()


def _status(role: str, message: str) -> None:
    _write(f"{cli_ui.colorize(cli_ui.icon(role), role, bold=True)} {message}\n")


def _separator() -> None:
    char = "─" if cli_ui.supports_nerd_font_output() else "-"
    _write(cli_ui.colorize(char * 54, "muted") + "\n")


def result_text(result: HostResult) -> str:
    """Status line(s) for one host, with the shared icon/color helpers."""
    role = _STATUS_ROLES.get(result.status, "info")
    lines = [f"{cli_ui.colorize(cli_ui.icon(role), role, bold=True)} {host_line(result)}"]
    if result.error:
        lines.append(f"{cli_ui.colorize(cli_ui.icon('fail'), 'fail', bold=True)}   error: {result.error}")
    return "\n".join(lines)


def emit_result(result: HostResult) -> None:
    _write(result_text(result) + "\n")


SPINNER_FRAMES = ("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")
ASCII_SPINNER_FRAMES = ("|", "/", "-", "\\")


def _notify(on_event: object | None, *event: object) -> None:
    if on_event is not None:
        on_event(*event)  # type: ignore[operator]


class ProgressReporter:
    """Per-step activity while hosts run: an animated spinner on a TTY, plain step lines otherwise."""

    def __init__(self, stream: object | None = None) -> None:
        self.stream = stream or cli_ui.console_stream()
        self._interactive = bool(getattr(self.stream, "isatty", lambda: False)())
        self._frames = SPINNER_FRAMES if cli_ui.can_encode(SPINNER_FRAMES[0]) else ASCII_SPINNER_FRAMES
        self._lock = threading.Lock()
        self._active: dict[str, str] = {}
        self._last: tuple[str, str] | None = None
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._frame = 0
        self._line_open = False

    @property
    def interactive(self) -> bool:
        return self._interactive

    def start(self) -> None:
        if not self._interactive or self._thread is not None:
            return
        self._thread = threading.Thread(target=self._spin, name="fleet-sync-spinner", daemon=True)
        self._thread.start()

    def event(self, host: str, step: str) -> None:
        if self._interactive:
            with self._lock:
                self._active[host] = step
                self._last = (host, step)
            return
        self._write(f"{cli_ui.icon('hint')} {host}: {step}\n")

    def line(self, text: str) -> None:
        """Print one complete line without letting the spinner overwrite it."""
        with self._lock:
            self._clear_locked()
            self._write(text + "\n")

    def finish(self, result: HostResult) -> None:
        with self._lock:
            self._active.pop(result.host, None)
            if self._last is not None and self._last[0] == result.host:
                self._last = None
            self._clear_locked()
        self._write(result_text(result) + "\n")

    def close(self) -> None:
        self._stop.set()
        thread, self._thread = self._thread, None
        if thread is not None:
            thread.join(timeout=1)
        with self._lock:
            self._clear_locked()

    def _spin(self) -> None:
        while not self._stop.wait(0.1):
            with self._lock:
                self._render_locked()

    def _render_locked(self) -> None:
        entry = self._last if self._last is not None else next(iter(self._active.items()), None)
        if entry is None or entry[0] not in self._active:
            self._clear_locked()
            return
        host, step = entry
        frame = self._frames[self._frame % len(self._frames)]
        self._frame += 1
        text = (
            f"{cli_ui.colorize(frame, 'hint')} "
            f"{cli_ui.colorize(host, 'info', bold=True)} "
            f"{cli_ui.colorize(step, 'muted')}"
        )
        self._write(f"\r{text}\x1b[K")
        self._line_open = True

    def _clear_locked(self) -> None:
        if self._line_open:
            self._write("\r\x1b[K")
            self._line_open = False

    def _write(self, text: str) -> None:
        self.stream.write(text)
        self.stream.flush()


def summary_line(results: list[HostResult], options: SyncOptions) -> str:
    summary = _summarize(results)
    prefix = " (dry-run)" if options.dry_run else ""
    return (
        f"fleet sync{prefix}: ok={summary['ok']} conflict={summary['conflict']} "
        f"failed={summary['failed']} skipped={summary['skipped']} dry-run={summary['dry_run']}"
    )


def summary_role(results: list[HostResult]) -> str:
    summary = _summarize(results)
    if summary["failed"]:
        return "fail"
    if summary["conflict"]:
        return "warn"
    return "ok"


def render_text(results: list[HostResult], options: SyncOptions) -> str:
    lines: list[str] = []
    for result in results:
        lines.append(host_line(result))
        if result.error:
            lines.append(f"  error: {result.error}")
    lines.append("")
    lines.append(summary_line(results, options))
    if _summarize(results)["conflict"] and not options.resolve:
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
    return SshTransport(connect_timeout=options.connect_timeout, retries=options.connect_retries)


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
        help="Stash, pull, fix unfinished hosts with omp, push, then re-link on SSH hosts.",
        description=(
            "For each host: stash local changes, rebase onto the remote branch, restore the stash, push "
            "machine-local commits, then run `oooconf update --no-deps`. With --resolve the per-host status "
            "is printed first and unfinished hosts are handed to omp: one host gets an agent on that "
            "machine, several get a single local agent that ssh's out with each host's status."
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
        help=(
            "Fix unfinished hosts with omp after the run: a remote agent for one host, one local agent for "
            "several (default: off)."
        ),
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
    stream = args.format != "json"
    repo_root = Path(args.repo_root).expanduser() if args.repo_root else Path.cwd()
    if stream and cli_ui.console_stream() is not sys.stdout:
        # PowerShell pipes a native command's stdout; keep colors/icons for the attached console.
        cli_ui.set_ui_override(True)
    reporter = ProgressReporter() if stream else None

    def handle_event(host: str, step: str) -> None:
        if reporter is not None:
            reporter.event(host, step)

    def handle_result(result: HostResult) -> None:
        if reporter is not None:
            reporter.finish(result)
        elif stream:
            emit_result(result)

    if reporter is not None:
        reporter.start()
    try:
        if stream:
            mode = " (dry-run)" if options.dry_run else ""
            workers = max(1, min(args.jobs, len(live)))
            _status("info", f"fleet sync: {len(live)} host(s), jobs={workers}{mode}")
        results = sync_hosts(
            live,
            options,
            transport,
            jobs=args.jobs,
            on_result=handle_result,
            on_event=handle_event,
        )
        pending = needs_fix(results)
        if pending and options.resolve and not options.dry_run:
            if stream:
                agent = "a remote omp agent" if len(pending) == 1 else "one local omp agent"
                _status("hint", f"fixing {len(pending)} host(s) with {agent}")
            results = apply_fixes(
                results,
                options,
                transport,
                repo_root,
                on_result=handle_result,
                on_event=handle_event,
                line=reporter.line if reporter is not None else _write,
            )
    finally:
        transport.close()
        if reporter is not None:
            reporter.close()
    by_host = {result.host: result for result in results}
    ordered: list[HostResult] = []
    for host in requested:
        if host in duplicates:
            placeholder = HostResult(host=host, status=STATUS_SKIPPED, skip_reason=f"duplicate of {duplicates[host]}")
            ordered.append(placeholder)
            if stream:
                handle_result(placeholder)
        else:
            ordered.append(by_host[host])

    if stream:
        _separator()
        _status(summary_role(ordered), summary_line(ordered, options))
        if _summarize(ordered)["conflict"] and not options.resolve:
            _status("hint", CONFLICT_HINT)
    else:
        document = {
            "schema_version": SCHEMA_VERSION,
            "hosts": [result.to_dict() for result in ordered],
            "summary": _summarize(ordered),
        }
        print(json.dumps(document, indent=2))
    return exit_code(ordered)


if __name__ == "__main__":
    raise SystemExit(main())
