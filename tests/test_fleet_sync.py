"""Tests for `oooconf fleet sync`: host discovery, per-host pipeline, and reporting.

No network and no `ssh`: every remote call goes through a fake transport.
"""

from __future__ import annotations

import io
import json
import re
import sys
import threading
import time
from pathlib import Path
from types import SimpleNamespace

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from scripts.cli import fleet_sync  # noqa: E402

REMOTE_REPO = "/home/tester/src/ooodnakov-config"
CONFLICT_FILE = "home/.config/zsh/.zshrc"


def _result(returncode: int = 0, stdout: str = "", stderr: str = "") -> fleet_sync.CommandResult:
    return fleet_sync.CommandResult(returncode, stdout, stderr)


PREFLIGHT_OUTPUT = "hostname=fleet-node-1\nuser=tester\nrepo=yes\n"

# First matching fragment wins; overrides are prepended by `handler_for`.
DEFAULT_RULES: list[tuple[str, object]] = [
    ("printf 'hostname=", _result(0, PREFLIGHT_OUTPUT)),
    ("--print-repo-root", _result(0, REMOTE_REPO + "\n")),
    ("@{u}", _result(1, "", "fatal: no upstream configured")),
    ("rev-parse --git-dir", _result(0, ".git\n")),
    ("symbolic-ref --short HEAD", _result(0, "main\n")),
    ("status --porcelain", _result(0)),
    ("fetch --prune origin", _result(0)),
    ("rev-list --left-right --count", _result(0, "0\t0\n")),
    ("stash push", _result(0)),
    ("pull --rebase origin", _result(0)),
    ("--diff-filter=U", _result(0)),
    ("stash pop", _result(0)),
    ("push origin", _result(0)),
    ("oooconf update --no-deps", _result(0)),
]


def handler_for(overrides=(), default=None):
    rules = [*overrides, *DEFAULT_RULES]

    def handler(host: str, script: str) -> fleet_sync.CommandResult:
        for fragment, value in rules:
            if fragment in script:
                return value(host, script) if callable(value) else value
        if default is not None:
            return default
        raise AssertionError(f"unexpected remote script for {host}: {script!r}")

    return handler


class FakeTransport:
    def __init__(self, handler) -> None:
        self._handler = handler
        self.calls: list[tuple[str, str]] = []
        self._lock = threading.Lock()

    def run(self, host: str, script: str, on_line: object | None = None) -> fleet_sync.CommandResult:
        with self._lock:
            self.calls.append((host, script))
        return self._handler(host, script)

    def close(self) -> None:
        return None

    def scripts(self, host: str | None = None) -> list[str]:
        with self._lock:
            return [script for call_host, script in self.calls if host is None or call_host == host]

    def find(self, fragment: str, host: str | None = None) -> list[str]:
        return [script for script in self.scripts(host) if fragment in script]

    def issued(self, fragment: str, host: str | None = None) -> bool:
        return bool(self.find(fragment, host))


class _FakeAgentProcess:
    def __init__(self, argv: list[str], output: bytes, returncode: int) -> None:
        self.argv = argv
        self.stdout = io.BytesIO(output)
        self._returncode = returncode

    def wait(self, timeout=None) -> int:
        return self._returncode


def fake_popen(calls: list[dict], output: bytes = b"agent output\n", returncode: int = 0):
    def factory(argv, **kwargs):
        process = _FakeAgentProcess(list(argv), output, returncode)
        calls.append({"argv": list(argv), **kwargs, "process": process})
        return process

    return factory


def _index(scripts: list[str], fragment: str) -> int:
    for position, script in enumerate(scripts):
        if fragment in script:
            return position
    raise AssertionError(f"{fragment!r} was never issued; scripts: {scripts!r}")


def _write_ssh_home(home: Path) -> None:
    ssh = home / ".ssh"
    (ssh / "conf.d").mkdir(parents=True)
    (ssh / "config").write_text(
        "# leading comment\n"
        "Host alpha beta\n"
        "    HostName 10.0.0.1\n"
        "Host *.wild\n"
        "    User nobody\n"
        "Host gamma? !nope\n"
        "Include ~/.ssh/conf.d/extra\n"
        "Include ~/.ssh/conf.d/absent\n"
        "Host zeta # trailing comment\n"
        "Host alpha\n",
        encoding="utf-8",
    )
    (ssh / "conf.d" / "extra").write_text(
        "Host beta delta\nInclude ~/.ssh/conf.d/deep\n",
        encoding="utf-8",
    )
    (ssh / "conf.d" / "deep").write_text("Host epsilon\n", encoding="utf-8")
    (ssh / "config.local").write_text("Host local\n", encoding="utf-8")


# --- discover_hosts -----------------------------------------------------------------


def test_discover_hosts_reads_hosts_comments_and_includes(tmp_path: Path) -> None:
    home = tmp_path / "home"
    _write_ssh_home(home)

    hosts = fleet_sync.discover_hosts(home)

    # `config` is read first, so its aliases keep first-seen order; includes and
    # `config.local` may be queued either before or after each other.
    assert hosts[:2] == ["alpha", "beta"]
    assert sorted(hosts) == sorted(["alpha", "beta", "delta", "epsilon", "zeta", "local"])
    assert len(hosts) == len(set(hosts))


def test_discover_hosts_missing_files_are_empty(tmp_path: Path) -> None:
    home = tmp_path / "home"
    home.mkdir()

    assert fleet_sync.discover_hosts(home) == []


# --- preflight ----------------------------------------------------------------------


def _probe(**fields: str) -> str:
    return "".join(f"{key}={value}\n" for key, value in fields.items())


def _preflight_transport(probe: str = PREFLIGHT_OUTPUT, *, returncode: int = 0, stderr: str = "") -> FakeTransport:
    """Fake transport whose only preflight reply is the given key=value probe output."""
    return FakeTransport(handler_for([("printf 'hostname=", _result(returncode, probe, stderr))]))


def test_preflight_runs_first_and_probes_identity_and_repo() -> None:
    transport = FakeTransport(handler_for())

    result = fleet_sync.sync_host("alpha", fleet_sync.SyncOptions(repo_path=REMOTE_REPO), transport)

    assert result.status == fleet_sync.STATUS_OK
    assert result.skip_reason is None
    first = transport.scripts()[0]
    assert "printf 'hostname=" in first
    assert "printf 'user=" in first
    assert "echo yes || echo no" in first
    assert REMOTE_REPO in first
    # Preflight must precede even the repository probe and all git commands.
    assert _index(transport.scripts(), "printf 'hostname=") == 0
    assert _index(transport.scripts(), "printf 'hostname=") < _index(transport.scripts(), "git -C")


def test_preflight_ssh_failure_marks_host_failed() -> None:
    transport = _preflight_transport(returncode=255, stderr="ssh: connect to host alpha port 22: refused")

    result = fleet_sync.sync_host("alpha", fleet_sync.SyncOptions(repo_path=REMOTE_REPO), transport)

    assert result.status == fleet_sync.STATUS_FAILED
    assert result.error is not None
    assert result.error.startswith("ssh alpha: ")
    assert result.skip_reason is None
    assert not transport.issued("git -C")
    assert fleet_sync.exit_code([result]) == 1


def test_preflight_skips_root_user() -> None:
    transport = _preflight_transport(_probe(hostname="fleet-node-1", user="root", repo="no"))

    result = fleet_sync.sync_host("alpha", fleet_sync.SyncOptions(repo_path=REMOTE_REPO), transport)

    assert result.status == fleet_sync.STATUS_SKIPPED
    assert result.skip_reason == "root user"
    assert result.error is None
    assert not transport.issued("git -C")
    assert not transport.issued("oooconf update")
    assert fleet_sync.exit_code([result]) == 0


def test_preflight_skips_missing_repo() -> None:
    transport = _preflight_transport(_probe(hostname="fleet-node-1", user="tester", repo="no"))

    result = fleet_sync.sync_host("alpha", fleet_sync.SyncOptions(repo_path=REMOTE_REPO), transport)

    assert result.status == fleet_sync.STATUS_SKIPPED
    assert result.skip_reason == f"{REMOTE_REPO} not found"
    assert not transport.issued("git -C")
    assert fleet_sync.exit_code([result]) == 0


def test_preflight_reports_default_repo_path_when_missing() -> None:
    transport = _preflight_transport(_probe(hostname="fleet-node-1", user="tester", repo="no"))

    result = fleet_sync.sync_host("alpha", fleet_sync.SyncOptions(), transport)

    assert result.status == fleet_sync.STATUS_SKIPPED
    assert result.skip_reason == f"{fleet_sync.DEFAULT_REPO_PATH} not found"
    assert not transport.issued("--print-repo-root")


def test_preflight_skips_local_machine_case_and_domain_insensitive(monkeypatch) -> None:
    monkeypatch.setattr(fleet_sync.socket, "gethostname", lambda: "Build-01.corp.example")
    transport = _preflight_transport(_probe(hostname="build-01", user="tester", repo="yes"))

    result = fleet_sync.sync_host("alpha", fleet_sync.SyncOptions(repo_path=REMOTE_REPO), transport)

    assert result.status == fleet_sync.STATUS_SKIPPED
    assert result.skip_reason == "local machine"
    assert not transport.issued("git -C")
    assert fleet_sync.exit_code([result]) == 0


def test_preflight_skips_loopback_hostnames() -> None:
    for hostname in ("localhost", "127.0.0.1"):
        transport = _preflight_transport(_probe(hostname=hostname, user="tester", repo="yes"))

        result = fleet_sync.sync_host("alpha", fleet_sync.SyncOptions(repo_path=REMOTE_REPO), transport)

        assert result.status == fleet_sync.STATUS_SKIPPED
        assert result.skip_reason == "local machine"
        assert not transport.issued("git -C")


def test_preflight_continues_when_remote_machine_differs(monkeypatch) -> None:
    monkeypatch.setattr(fleet_sync.socket, "gethostname", lambda: "build-01")
    transport = _preflight_transport(_probe(hostname="build-02", user="tester", repo="yes"))

    result = fleet_sync.sync_host("alpha", fleet_sync.SyncOptions(repo_path=REMOTE_REPO), transport)

    assert result.status == fleet_sync.STATUS_OK
    assert result.linked is True


# --- host dedupe --------------------------------------------------------------------


def _target(alias: str, hostname: str | None = None, port: str | None = None) -> fleet_sync.SshTarget:
    return fleet_sync.SshTarget(alias=alias, hostname=hostname, port=port)


def test_dedupe_hosts_keeps_first_alias_per_machine() -> None:
    targets = [
        _target("one", "shared.example", "22"),
        _target("two", "SHARED.example", "22"),
        _target("three", "shared.example", "2222"),
        _target("four", "other.example", "22"),
    ]

    kept, duplicates = fleet_sync.dedupe_hosts(["one", "two", "three", "four"], targets)

    assert kept == ["one", "three", "four"]
    assert duplicates == {"two": "one"}


def test_dedupe_hosts_keeps_distinct_aliases_without_hostname() -> None:
    targets = [_target("one"), _target("two")]

    kept, duplicates = fleet_sync.dedupe_hosts(["one", "two"], targets)

    assert kept == ["one", "two"]
    assert duplicates == {}


def test_main_reports_duplicate_aliases_as_skipped(monkeypatch, capsys) -> None:
    transport = FakeTransport(handler_for())
    monkeypatch.setattr(fleet_sync, "SshTransport", lambda *args, **kwargs: transport)
    monkeypatch.setattr(
        fleet_sync,
        "parse_ssh_targets",
        lambda home=None: [_target("one", "shared.example", "22"), _target("two", "shared.example", "22")],
    )

    code = fleet_sync.main(["sync", "one", "two", "--repo-path", REMOTE_REPO, "--format", "json"])

    document = json.loads(capsys.readouterr().out)
    assert code == 0
    assert [entry["host"] for entry in document["hosts"]] == ["one", "two"]
    assert document["hosts"][0]["status"] == fleet_sync.STATUS_OK
    assert document["hosts"][1]["status"] == fleet_sync.STATUS_SKIPPED
    assert document["hosts"][1]["skip_reason"] == "duplicate of one"
    assert document["summary"] == {"ok": 1, "conflict": 0, "failed": 0, "dry_run": 0, "skipped": 1}
    assert {host for host, _script in transport.calls} == {"one"}


# --- clean and dirty hosts ----------------------------------------------------------


def test_clean_host_runs_fetch_pull_and_link_refresh() -> None:
    transport = FakeTransport(handler_for())

    result = fleet_sync.sync_host("alpha", fleet_sync.SyncOptions(repo_path=REMOTE_REPO), transport)

    assert result.status == fleet_sync.STATUS_OK
    assert result.repo == REMOTE_REPO
    assert result.branch == "main"
    assert result.linked is True
    assert result.stashed is False
    assert result.pushed is False
    assert result.conflicts == []
    assert result.error is None

    scripts = transport.scripts()
    assert _index(scripts, "fetch --prune origin main") < _index(scripts, "pull --rebase origin main")
    assert _index(scripts, "pull --rebase origin main") < _index(scripts, "oooconf update --no-deps")
    assert not transport.issued("stash")
    assert not transport.issued("push origin")
    assert not transport.issued("--print-repo-root")


def test_repo_path_is_discovered_when_not_given() -> None:
    transport = FakeTransport(handler_for())

    result = fleet_sync.sync_host("alpha", fleet_sync.SyncOptions(), transport)

    assert transport.issued("oooconf --print-repo-root")
    assert result.repo == REMOTE_REPO
    assert result.status == fleet_sync.STATUS_OK


def test_dirty_host_stashes_pulls_then_restores() -> None:
    transport = FakeTransport(handler_for([("status --porcelain", _result(0, f" M {CONFLICT_FILE}\n"))]))

    result = fleet_sync.sync_host("alpha", fleet_sync.SyncOptions(repo_path=REMOTE_REPO), transport)

    assert result.status == fleet_sync.STATUS_OK
    assert result.dirty is True
    assert result.stashed is True
    scripts = transport.scripts()
    stash_push = _index(scripts, "stash push")
    assert stash_push < _index(scripts, "pull --rebase origin main")
    assert _index(scripts, "pull --rebase origin main") < _index(scripts, "stash pop")
    assert _index(scripts, "stash pop") < _index(scripts, "oooconf update --no-deps")


# --- conflicts ----------------------------------------------------------------------


def test_pull_conflict_without_resolve_keeps_stash_and_stops() -> None:
    transport = FakeTransport(
        handler_for(
            [
                ("status --porcelain", _result(0, f" M {CONFLICT_FILE}\n")),
                ("pull --rebase origin", _result(1, "", "error: could not apply 1234abc\n")),
                ("--diff-filter=U", _result(0, CONFLICT_FILE + "\n")),
            ]
        )
    )

    result = fleet_sync.sync_host("alpha", fleet_sync.SyncOptions(repo_path=REMOTE_REPO), transport)

    assert result.status == fleet_sync.STATUS_CONFLICT
    assert result.conflicts == [CONFLICT_FILE]
    assert result.stashed is True
    assert result.resolved is False
    assert result.pushed is False
    assert result.linked is False
    assert not transport.issued("stash pop")
    assert not transport.issued("push origin")
    assert not transport.issued("oooconf update")
    assert not transport.issued("omp -p")
    assert fleet_sync.exit_code([result]) == 2


def test_single_pending_host_runs_remote_agent_then_completes(monkeypatch) -> None:
    transport = FakeTransport(
        handler_for(
            [
                ("omp -p", _result(0)),
                ("status --porcelain", _result(0, f" M {CONFLICT_FILE}\n")),
                ("pull --rebase origin", _result(1, "", "error: could not apply 1234abc\n")),
                ("--diff-filter=U", _result(0, CONFLICT_FILE + "\n")),
            ]
        )
    )
    local_calls: list[dict] = []
    monkeypatch.setattr(fleet_sync.subprocess, "Popen", fake_popen(local_calls))

    options = fleet_sync.SyncOptions(repo_path=REMOTE_REPO, resolve=True)
    result = fleet_sync.sync_host("alpha", options, transport)

    # The per-host pipeline reports the conflict and never spawns an agent itself.
    assert result.status == fleet_sync.STATUS_CONFLICT
    assert result.stashed is True
    assert not transport.issued("omp -p")

    results = fleet_sync.apply_fixes([result], options, transport, REPO_ROOT)

    scripts = transport.scripts()
    assert _index(scripts, "pull --rebase") < _index(scripts, "omp -p")
    agent_scripts = transport.find("omp -p")
    assert len(agent_scripts) == 1
    assert f"cd {REMOTE_REPO} && omp -p" in agent_scripts[0]
    assert "host=alpha status=conflict" in agent_scripts[0]

    assert results[0].status == fleet_sync.STATUS_OK
    assert results[0].resolved is True
    assert results[0].fix == "remote-agent"
    assert results[0].conflicts == []
    assert transport.issued("stash pop")
    assert transport.issued("oooconf update --no-deps")
    assert not transport.issued("push origin")
    assert local_calls == []
    assert "fix=remote-agent" in fleet_sync.render_text(results, options)
    assert fleet_sync.exit_code(results) == 0


def test_stash_pop_conflict_is_reported_as_conflict() -> None:
    transport = FakeTransport(
        handler_for(
            [
                ("status --porcelain", _result(0, f" M {CONFLICT_FILE}\n")),
                ("stash pop", _result(1, "", f"CONFLICT (content): Merge conflict in {CONFLICT_FILE}\n")),
                ("--diff-filter=U", _result(0, CONFLICT_FILE + "\n")),
            ]
        )
    )

    result = fleet_sync.sync_host("alpha", fleet_sync.SyncOptions(repo_path=REMOTE_REPO), transport)

    assert result.status == fleet_sync.STATUS_CONFLICT
    assert result.conflicts == [CONFLICT_FILE]
    assert not transport.issued("push origin")
    assert not transport.issued("oooconf update")
    assert fleet_sync.exit_code([result]) == 2


# --- two-phase fixing ---------------------------------------------------------------


def test_several_pending_hosts_run_exactly_one_local_agent(monkeypatch) -> None:
    transport = FakeTransport(
        handler_for(
            [
                ("status --porcelain", _result(0, f" M {CONFLICT_FILE}\n")),
                ("pull --rebase origin", _result(1, "", "error: could not apply 1234abc\n")),
                ("--diff-filter=U", _result(0, CONFLICT_FILE + "\n")),
            ]
        )
    )
    calls: list[dict] = []
    monkeypatch.setattr(fleet_sync.subprocess, "Popen", fake_popen(calls))

    options = fleet_sync.SyncOptions(repo_path=REMOTE_REPO, resolve=True)
    results = fleet_sync.sync_hosts(["alpha", "beta"], options, transport, jobs=1)
    assert [result.status for result in results] == [fleet_sync.STATUS_CONFLICT] * 2

    fleet_sync.apply_fixes(results, options, transport, REPO_ROOT)

    assert len(calls) == 1
    command = calls[0]["argv"]
    assert command[:2] == ["omp", "-p"]
    prompt = command[2]
    assert "host=alpha" in prompt
    assert "host=beta" in prompt
    assert prompt.count("status=conflict") == 2
    assert calls[0]["cwd"] == str(REPO_ROOT)
    assert calls[0]["stdin"] == fleet_sync.subprocess.DEVNULL
    assert calls[0]["stderr"] == fleet_sync.subprocess.STDOUT
    assert calls[0]["stdout"] == fleet_sync.subprocess.PIPE
    assert "capture_output" not in calls[0]
    assert "text" not in calls[0]
    assert not transport.issued("omp -p")
    assert [result.fix for result in results] == ["local-agent", "local-agent"]
    assert [result.status for result in results] == [fleet_sync.STATUS_OK] * 2
    assert all(result.resolved for result in results)


def test_resolve_with_dry_run_spawns_no_agent(monkeypatch) -> None:
    transport = FakeTransport(handler_for([("rev-list --left-right --count", _result(0, "2\t1\n"))]))
    calls: list[dict] = []
    monkeypatch.setattr(fleet_sync.subprocess, "Popen", fake_popen(calls))

    options = fleet_sync.SyncOptions(repo_path=REMOTE_REPO, resolve=True, dry_run=True)
    results = fleet_sync.sync_hosts(["alpha", "beta"], options, transport, jobs=1)
    fleet_sync.apply_fixes(results, options, transport, REPO_ROOT)

    assert [result.status for result in results] == [fleet_sync.STATUS_DRY_RUN] * 2
    assert calls == []
    assert not transport.issued("omp -p")
    assert all(result.fix is None for result in results)


def test_needs_fix_includes_conflicts_and_reachable_failures_only() -> None:
    conflict = fleet_sync.HostResult(host="alpha", status=fleet_sync.STATUS_CONFLICT, reachable=True)
    unreachable = fleet_sync.HostResult(host="beta", status=fleet_sync.STATUS_FAILED, reachable=False)
    reachable = fleet_sync.HostResult(host="gamma", status=fleet_sync.STATUS_FAILED, reachable=True)
    ok = fleet_sync.HostResult(host="delta", status=fleet_sync.STATUS_OK, reachable=True)

    assert fleet_sync.needs_fix([conflict, unreachable, reachable, ok]) == [conflict, reachable]


def test_stash_pop_failure_after_fix_stays_conflict(monkeypatch) -> None:
    transport = FakeTransport(
        handler_for(
            [
                ("omp -p", _result(0)),
                ("status --porcelain", _result(0, f" M {CONFLICT_FILE}\n")),
                ("pull --rebase origin", _result(1, "", "error: could not apply 1234abc\n")),
                ("--diff-filter=U", _result(0, CONFLICT_FILE + "\n")),
                ("stash pop", _result(1, "", f"CONFLICT (content): Merge conflict in {CONFLICT_FILE}\n")),
            ]
        )
    )
    monkeypatch.setattr(fleet_sync.subprocess, "Popen", fake_popen([]))

    options = fleet_sync.SyncOptions(repo_path=REMOTE_REPO, resolve=True)
    result = fleet_sync.sync_host("alpha", options, transport)
    fleet_sync.apply_fixes([result], options, transport, REPO_ROOT)

    assert result.status == fleet_sync.STATUS_CONFLICT
    assert result.resolved is False
    assert result.fix == "remote-agent"
    assert result.conflicts == [CONFLICT_FILE]
    assert not transport.issued("push origin")
    assert not transport.issued("oooconf update")


# --- push behaviour -----------------------------------------------------------------


def test_ahead_commits_are_pushed() -> None:
    transport = FakeTransport(handler_for([("rev-list --left-right --count", _result(0, "0\t2\n"))]))

    result = fleet_sync.sync_host("alpha", fleet_sync.SyncOptions(repo_path=REMOTE_REPO), transport)

    assert result.status == fleet_sync.STATUS_OK
    assert result.ahead == 2
    assert result.pushed is True
    scripts = transport.scripts()
    assert _index(scripts, "push origin main") < _index(scripts, "oooconf update --no-deps")


def test_no_push_leaves_commits_unpushed() -> None:
    transport = FakeTransport(handler_for([("rev-list --left-right --count", _result(0, "0\t2\n"))]))

    result = fleet_sync.sync_host("alpha", fleet_sync.SyncOptions(repo_path=REMOTE_REPO, push=False), transport)

    assert result.status == fleet_sync.STATUS_OK
    assert result.ahead == 2
    assert result.pushed is False
    assert not transport.issued("push origin")


# --- dry run and reporting ----------------------------------------------------------


def test_dry_run_issues_no_mutating_commands() -> None:
    transport = FakeTransport(
        handler_for(
            [
                ("status --porcelain", _result(0, f" M {CONFLICT_FILE}\n")),
                ("rev-list --left-right --count", _result(0, "3\t1\n")),
            ]
        )
    )

    result = fleet_sync.sync_host(
        "alpha",
        fleet_sync.SyncOptions(repo_path=REMOTE_REPO, dry_run=True),
        transport,
    )

    assert result.status == fleet_sync.STATUS_DRY_RUN
    assert result.repo == REMOTE_REPO
    assert result.branch == "main"
    assert result.dirty is True
    assert result.behind == 3
    assert result.ahead == 1
    assert transport.issued("rev-list --left-right --count")
    for fragment in ("fetch", "stash", "pull --rebase", "push origin", "oooconf update"):
        assert not transport.issued(fragment), fragment
    assert fleet_sync.exit_code([result]) == 0


def test_render_text_hints_resolve_only_for_conflicts_without_it() -> None:
    results = [
        fleet_sync.HostResult(
            host="alpha", status=fleet_sync.STATUS_CONFLICT, repo=REMOTE_REPO, branch="main", conflicts=[CONFLICT_FILE]
        ),
    ]

    without = fleet_sync.render_text(results, fleet_sync.SyncOptions())
    with_resolve = fleet_sync.render_text(results, fleet_sync.SyncOptions(resolve=True))

    assert "alpha" in without
    assert "conflict" in without.lower()
    assert CONFLICT_FILE in without
    assert "re-run with --resolve" in without
    assert "re-run with --resolve" not in with_resolve


def test_render_text_reports_skipped_reason_and_summary() -> None:
    results = [
        fleet_sync.HostResult(host="alpha", status=fleet_sync.STATUS_OK, repo=REMOTE_REPO, branch="main"),
        fleet_sync.HostResult(host="beta", status=fleet_sync.STATUS_SKIPPED, skip_reason="duplicate of alpha"),
    ]

    text = fleet_sync.render_text(results, fleet_sync.SyncOptions())

    assert "beta" in text
    assert "reason=duplicate of alpha" in text
    assert "ok=1" in text
    assert "skipped=1" in text


def test_exit_codes_follow_result_statuses() -> None:
    def results(*statuses: str) -> list[fleet_sync.HostResult]:
        return [fleet_sync.HostResult(host=f"host{index}", status=status) for index, status in enumerate(statuses)]

    assert fleet_sync.exit_code(results(fleet_sync.STATUS_OK, fleet_sync.STATUS_OK)) == 0
    assert fleet_sync.exit_code(results(fleet_sync.STATUS_OK, fleet_sync.STATUS_DRY_RUN)) == 0
    assert fleet_sync.exit_code(results(fleet_sync.STATUS_OK, fleet_sync.STATUS_SKIPPED)) == 0
    assert fleet_sync.exit_code(results(fleet_sync.STATUS_SKIPPED, fleet_sync.STATUS_DRY_RUN)) == 0
    assert fleet_sync.exit_code(results(fleet_sync.STATUS_OK, fleet_sync.STATUS_CONFLICT)) == 2
    assert fleet_sync.exit_code(results(fleet_sync.STATUS_SKIPPED, fleet_sync.STATUS_CONFLICT)) == 2
    assert fleet_sync.exit_code(results(fleet_sync.STATUS_OK, fleet_sync.STATUS_FAILED)) == 1
    assert fleet_sync.exit_code(results(fleet_sync.STATUS_SKIPPED, fleet_sync.STATUS_FAILED)) == 1


def test_sync_hosts_preserves_input_order_with_parallel_jobs() -> None:
    transport = FakeTransport(handler_for())

    results = fleet_sync.sync_hosts(
        ["alpha", "beta"],
        fleet_sync.SyncOptions(repo_path=REMOTE_REPO),
        transport,
        jobs=2,
    )

    assert [result.host for result in results] == ["alpha", "beta"]
    assert {host for host, _script in transport.calls} == {"alpha", "beta"}
    assert all(result.status == fleet_sync.STATUS_OK for result in results)


def test_json_format_document_shape(monkeypatch, capsys) -> None:
    transport = FakeTransport(handler_for())
    monkeypatch.setattr(fleet_sync, "SshTransport", lambda *args, **kwargs: transport)
    monkeypatch.setattr(fleet_sync, "parse_ssh_targets", lambda home=None: [])

    code = fleet_sync.main(
        [
            "--repo-root",
            str(REPO_ROOT),
            "sync",
            "alpha",
            "beta",
            "--repo-path",
            REMOTE_REPO,
            "--format",
            "json",
        ]
    )

    document = json.loads(capsys.readouterr().out)
    assert code == 0
    assert document["schema_version"] == 1
    assert document["summary"] == {"ok": 2, "conflict": 0, "failed": 0, "dry_run": 0, "skipped": 0}
    assert [entry["host"] for entry in document["hosts"]] == ["alpha", "beta"]
    for entry in document["hosts"]:
        assert entry["status"] == fleet_sync.STATUS_OK
        assert entry["repo"] == REMOTE_REPO
        assert entry["branch"] == "main"
        assert entry["linked"] is True
        assert entry["reachable"] is True
        assert entry["fix"] is None
        assert entry["skip_reason"] is None


def test_remote_git_commands_disable_terminal_prompts() -> None:
    transport = FakeTransport(handler_for())

    fleet_sync.sync_host("alpha", fleet_sync.SyncOptions(repo_path=REMOTE_REPO), transport)

    git_scripts = [script for script in transport.scripts() if "git -C" in script]
    assert git_scripts
    for script in git_scripts:
        assert "GIT_TERMINAL_PROMPT=0" in script


def test_main_applies_two_phase_fixes_after_the_fan_out(monkeypatch, capsys) -> None:
    transport = FakeTransport(
        handler_for(
            [
                ("status --porcelain", _result(0, f" M {CONFLICT_FILE}\n")),
                ("pull --rebase origin", _result(1, "", "error: could not apply 1234abc\n")),
                ("--diff-filter=U", _result(0, CONFLICT_FILE + "\n")),
            ]
        )
    )
    monkeypatch.setattr(fleet_sync, "SshTransport", lambda *args, **kwargs: transport)
    monkeypatch.setattr(fleet_sync, "parse_ssh_targets", lambda home=None: [])
    agent_calls: list[dict] = []
    monkeypatch.setattr(fleet_sync.subprocess, "Popen", fake_popen(agent_calls))

    code = fleet_sync.main(
        ["--repo-root", str(REPO_ROOT), "sync", "alpha", "beta", "--repo-path", REMOTE_REPO, "--resolve"]
    )

    out = capsys.readouterr().out
    assert code == 0
    # One local agent covers both hosts and receives their status.
    assert len(agent_calls) == 1
    assert agent_calls[0]["argv"][:2] == ["omp", "-p"]
    prompt = agent_calls[0]["argv"][2]
    assert "host=alpha" in prompt
    assert "host=beta" in prompt
    # The per-host status is printed before the agent runs, the final summary after it.
    assert " conflict " in out
    assert out.count("fix=local-agent") == 2
    assert "ok=2 conflict=0" in out
    assert not transport.issued("omp -p")


# --- persistent ssh session ---------------------------------------------------------


class _FakeStdin:
    """Binary stdin that answers each written script with the next scripted reply."""

    def __init__(self, process: "_FakeProcess") -> None:
        self._process = process
        self.closed = False

    def write(self, data: bytes) -> int:
        self._process.written.append(data)
        self._process.answer(data)
        return len(data)

    def flush(self) -> None:
        return None

    def close(self) -> None:
        self.closed = True


class _FakeStdout:
    """Pipe-like reader: `readline` drains one LF-terminated line, never rewinding."""

    def __init__(self) -> None:
        self.pending = bytearray()

    def feed(self, data: bytes) -> None:
        self.pending.extend(data)

    def readline(self) -> bytes:
        index = self.pending.find(b"\n")
        if index < 0:
            return b""
        line = bytes(self.pending[: index + 1])
        del self.pending[: index + 1]
        return line


class _FakeProcess:
    """Stands in for `Popen` around one persistent `ssh <host> sh -l` session."""

    def __init__(self, replies: list[tuple[str, int]]) -> None:
        self.replies = list(replies)
        self.written: list[bytes] = []
        self.stdin = _FakeStdin(self)
        self.stdout = _FakeStdout()
        self.killed = False
        self.waited: float | None = None

    def answer(self, payload: bytes) -> None:
        match = re.search(rb"printf '([^']+?)%s", payload)
        if not self.replies or match is None:
            return
        output, code = self.replies.pop(0)
        token = match.group(1)
        self.stdout.feed(output.encode("utf-8") + token + str(code).encode("ascii") + b"\n")

    def poll(self) -> None:
        return None

    def wait(self, timeout: float | None = None) -> int:
        self.waited = timeout
        return 0

    def kill(self) -> None:
        self.killed = True


class FakePopen:
    """Records every spawn and hands out one scripted session per call."""

    def __init__(self, sessions: list[list[tuple[str, int]]]) -> None:
        self.sessions = [list(replies) for replies in sessions]
        self.calls: list[list[str]] = []
        self.kwargs: list[dict] = []
        self.processes: list[_FakeProcess] = []

    def __call__(self, argv, **kwargs):
        self.calls.append(list(argv))
        self.kwargs.append(dict(kwargs))
        process = _FakeProcess(self.sessions.pop(0) if self.sessions else [])
        self.processes.append(process)
        return process


def _session_transport(popen: FakePopen, *, connect_timeout: float = 10.0, retries: int = 2):
    return fleet_sync.SshTransport(connect_timeout=connect_timeout, ssh="ssh", retries=retries, popen=popen)


def test_transport_command_uses_login_shell_and_keepalive_options() -> None:
    transport = _session_transport(FakePopen([]), connect_timeout=7.5)

    assert transport.command_for("alpha") == [
        "ssh",
        "-o",
        "ConnectTimeout=7.5",
        "-o",
        "ServerAliveInterval=15",
        "-o",
        "ServerAliveCountMax=4",
        "--",
        "alpha",
        "sh",
        "-l",
    ]
    assert transport.command_for("alpha")[-1] == "-l"


def test_transport_spawns_binary_merged_pipes() -> None:
    popen = FakePopen([[("ok\n", 0)]])
    transport = _session_transport(popen, retries=0)

    transport.run("alpha", "echo ok")

    assert popen.kwargs[0] == {
        "stdin": fleet_sync.subprocess.PIPE,
        "stdout": fleet_sync.subprocess.PIPE,
        "stderr": fleet_sync.subprocess.STDOUT,
        "bufsize": 0,
    }
    assert "text" not in popen.kwargs[0]
    assert "encoding" not in popen.kwargs[0]


def test_transport_reuses_one_session_for_every_script() -> None:
    popen = FakePopen([[("hello\n", 0), ("conflict details\n", 7)]])
    transport = _session_transport(popen, retries=0)

    first = transport.run("alpha", "echo hello")
    second = transport.run("alpha", "git status --porcelain")

    assert len(popen.calls) == 1
    assert first.returncode == 0
    assert first.stdout == "hello\n"
    assert second.returncode == 7
    assert second.stdout == "conflict details\n"
    assert "OOOCONF_FLEET_DONE" not in first.stdout + second.stdout
    assert first.stderr == ""
    payloads = b"".join(popen.processes[0].written)
    assert b"echo hello" in payloads
    assert b"git status --porcelain" in payloads
    assert b"</dev/null" in payloads
    assert b"\nprintf '" in payloads
    assert b'"$?"' in payloads
    # Binary pipes keep the protocol LF-only on Windows too.
    assert b"\r" not in payloads


def test_transport_retries_a_dropped_connection_on_a_fresh_session(monkeypatch) -> None:
    sleeps: list[float] = []
    monkeypatch.setattr(fleet_sync.time, "sleep", sleeps.append)
    popen = FakePopen([[("ssh: connect to host alpha port 22: Connection refused\n", 255)], [("recovered\n", 0)]])
    transport = _session_transport(popen, retries=2)

    result = transport.run("alpha", "echo hi")

    assert result.returncode == 0
    assert result.stdout == "recovered\n"
    assert len(popen.calls) == 2
    assert popen.calls[0] == popen.calls[1]
    assert sleeps == [0.4]
    assert popen.processes[0].stdin.closed is True
    assert transport._sessions["alpha"].process is popen.processes[1]


def test_transport_does_not_retry_ordinary_remote_failures() -> None:
    popen = FakePopen([[("fatal: not a git repository (or any of the parent directories)\n", 128)]])
    transport = _session_transport(popen, retries=3)

    result = transport.run("alpha", "git status --porcelain")

    assert result.returncode == 128
    assert result.stdout == "fatal: not a git repository (or any of the parent directories)\n"
    assert len(popen.calls) == 1


def test_zero_connect_retries_makes_a_single_attempt() -> None:
    popen = FakePopen([[("ssh: connect to host alpha port 22: connection timed out\n", 255)]])
    transport = _session_transport(popen, retries=0)

    result = transport.run("alpha", "echo hi")

    assert result.returncode == 255
    assert "connection timed out" in result.stdout
    assert len(popen.calls) == 1


def test_build_transport_forwards_connect_retries(monkeypatch) -> None:
    captured: dict[str, object] = {}

    def fake_transport(**kwargs):
        captured.update(kwargs)
        return SimpleNamespace(close=lambda: None)

    monkeypatch.setattr(fleet_sync, "SshTransport", fake_transport)

    fleet_sync.build_transport(fleet_sync.SyncOptions(connect_timeout=4.0, connect_retries=0))

    assert captured == {"connect_timeout": 4.0, "retries": 0}


def test_transport_close_waits_then_reopens_on_demand() -> None:
    popen = FakePopen([[("ok\n", 0)], [("again\n", 0)]])
    transport = _session_transport(popen, retries=0)
    transport.run("alpha", "echo ok")

    transport.close()

    process = popen.processes[0]
    assert process.stdin.closed is True
    assert process.waited == 5
    assert process.killed is False
    result = transport.run("alpha", "echo again")
    assert len(popen.calls) == 2
    assert result.stdout == "again\n"


def test_resolve_repo_takes_the_last_absolute_path_after_banners() -> None:
    transport = FakeTransport(
        handler_for([("--print-repo-root", _result(0, "welcome to alpha\n/opt/stale/repo\n/home/tester/src/repo\n"))])
    )
    result = fleet_sync.HostResult(host="alpha", status=fleet_sync.STATUS_OK)

    repo = fleet_sync._resolve_repo("alpha", fleet_sync.SyncOptions(), transport, result)

    assert repo == "/home/tester/src/repo"
    assert not any("defaulting to" in entry for entry in result.log)


# --- live progress ------------------------------------------------------------------


def test_sync_hosts_reports_each_host_once_and_keeps_input_order() -> None:
    transport = FakeTransport(handler_for())
    seen: list[fleet_sync.HostResult] = []

    results = fleet_sync.sync_hosts(
        ["alpha", "beta"],
        fleet_sync.SyncOptions(repo_path=REMOTE_REPO),
        transport,
        jobs=2,
        on_result=seen.append,
    )

    assert [result.host for result in results] == ["alpha", "beta"]
    assert len(seen) == 2
    assert sorted(result.host for result in seen) == ["alpha", "beta"]
    assert all(result.status == fleet_sync.STATUS_OK for result in seen)


def test_apply_fixes_reports_every_repaired_host(monkeypatch) -> None:
    transport = FakeTransport(
        handler_for(
            [
                ("status --porcelain", _result(0, f" M {CONFLICT_FILE}\n")),
                ("pull --rebase origin", _result(1, "", "error: could not apply 1234abc\n")),
                ("--diff-filter=U", _result(0, CONFLICT_FILE + "\n")),
            ]
        )
    )
    monkeypatch.setattr(fleet_sync.subprocess, "Popen", fake_popen([]))
    options = fleet_sync.SyncOptions(repo_path=REMOTE_REPO, resolve=True)
    results = fleet_sync.sync_hosts(["alpha", "beta"], options, transport, jobs=1)
    assert [result.status for result in results] == [fleet_sync.STATUS_CONFLICT] * 2
    seen: list[fleet_sync.HostResult] = []

    fleet_sync.apply_fixes(results, options, transport, REPO_ROOT, on_result=seen.append)

    assert seen == results
    assert [result.status for result in seen] == [fleet_sync.STATUS_OK] * 2
    assert [result.fix for result in seen] == ["local-agent", "local-agent"]


def test_main_text_output_streams_one_line_per_host_before_the_summary(monkeypatch, capsys) -> None:
    transport = FakeTransport(handler_for())
    monkeypatch.setattr(fleet_sync, "SshTransport", lambda *args, **kwargs: transport)
    monkeypatch.setattr(fleet_sync, "parse_ssh_targets", lambda home=None: [])

    code = fleet_sync.main(["sync", "alpha", "beta", "--repo-path", REMOTE_REPO])

    out = capsys.readouterr().out
    summary = "fleet sync: ok=2 conflict=0 failed=0 skipped=0 dry-run=0"
    assert code == 0
    assert "fleet sync: 2 host(s), jobs=2" in out
    assert summary in out
    assert out.index("alpha") < out.index(summary)
    assert out.index("beta") < out.index(summary)
    # One progress line per host, then the summary: the per-host table is never reprinted.
    assert out.count("branch=main") == 2
    assert out.count("dirty=no") == 2
    assert out.count("fleet sync:") == 2
    assert out.count(summary) == 1
    assert fleet_sync.cli_ui.icon("ok") in out
    assert "[ok]" in out
    assert "-" * 54 in out
    assert "re-run with --resolve" not in out


def test_main_json_output_streams_no_progress(monkeypatch, capsys) -> None:
    transport = FakeTransport(handler_for())
    monkeypatch.setattr(fleet_sync, "SshTransport", lambda *args, **kwargs: transport)
    monkeypatch.setattr(fleet_sync, "parse_ssh_targets", lambda home=None: [])

    code = fleet_sync.main(["sync", "alpha", "--repo-path", REMOTE_REPO, "--format", "json"])

    out = capsys.readouterr().out
    document = json.loads(out)
    assert code == 0
    assert "fleet sync:" not in out
    assert "[ok]" not in out
    assert document["summary"]["ok"] == 1


# --- per-step progress --------------------------------------------------------------


class _Stream:
    def __init__(self, tty: bool) -> None:
        self.chunks: list[str] = []
        self._tty = tty

    def isatty(self) -> bool:
        return self._tty

    def write(self, text: str) -> None:
        self.chunks.append(text)

    def flush(self) -> None:
        return None

    def text(self) -> str:
        return "".join(self.chunks)


def test_sync_host_reports_each_step_in_order() -> None:
    transport = FakeTransport(handler_for([("status --porcelain", _result(0, f" M {CONFLICT_FILE}\n"))]))
    events: list[str] = []

    fleet_sync.sync_host(
        "alpha",
        fleet_sync.SyncOptions(repo_path=REMOTE_REPO),
        transport,
        on_event=events.append,
    )

    expected = [
        "connecting to alpha",
        "checking ssh, user and checkout",
        "preflight ok",
        "resolving repo path",
        "reading branch and working tree",
        "fetching origin/main",
        "stashing local changes",
        "pulling --rebase origin/main",
        "restoring stash",
        "running oooconf update --no-deps",
    ]
    assert events == expected


def test_reporter_prints_plain_step_lines_when_piped(monkeypatch) -> None:
    stream = _Stream(tty=False)
    reporter = fleet_sync.ProgressReporter(stream)
    reporter.start()
    reporter.event("alpha", "fetching origin/main")
    reporter.close()

    text = stream.text()
    assert "alpha: fetching origin/main" in text
    assert "\r" not in text
    assert "\x1b[K" not in text


def test_reporter_spins_in_place_on_a_tty(capsys) -> None:
    stream = _Stream(tty=True)
    reporter = fleet_sync.ProgressReporter(stream)
    reporter.start()
    reporter.event("alpha", "fetching origin/main")
    time.sleep(0.15)
    reporter.event("beta", "pulling --rebase origin/main")
    time.sleep(0.15)
    reporter.finish(fleet_sync.HostResult(host="alpha", status=fleet_sync.STATUS_OK))
    reporter.close()

    assert reporter.interactive is True
    spinner = stream.text()
    assert "\r" in spinner
    assert "\x1b[K" in spinner
    assert "fetching origin/main" in spinner
    assert any(frame in spinner for frame in fleet_sync.SPINNER_FRAMES + fleet_sync.ASCII_SPINNER_FRAMES)
    assert "alpha" in spinner


def test_main_streams_step_lines_before_results(monkeypatch, capsys) -> None:
    transport = FakeTransport(handler_for())
    monkeypatch.setattr(fleet_sync, "SshTransport", lambda *args, **kwargs: transport)
    monkeypatch.setattr(fleet_sync, "parse_ssh_targets", lambda home=None: [])

    code = fleet_sync.main(["--repo-root", str(REPO_ROOT), "sync", "alpha", "--repo-path", REMOTE_REPO])

    out = capsys.readouterr().out
    assert code == 0
    assert "alpha: preflight ok" in out
    assert out.index("alpha: preflight ok") < out.index("branch=main")
    assert "fleet sync:" in out


def test_apply_fixes_reports_spawn_streams_agent_output_and_waits(monkeypatch) -> None:
    transport = FakeTransport(
        handler_for(
            [
                ("status --porcelain", _result(0, f" M {CONFLICT_FILE}\n")),
                ("pull --rebase origin", _result(1, "", "error: could not apply 1234abc\n")),
                ("--diff-filter=U", _result(0, CONFLICT_FILE + "\n")),
            ]
        )
    )
    calls: list[dict] = []
    monkeypatch.setattr(
        fleet_sync.subprocess,
        "Popen",
        fake_popen(calls, output=b"# Fix report\n\n- fixed a.txt\n", returncode=0),
    )
    options = fleet_sync.SyncOptions(repo_path=REMOTE_REPO, resolve=True)
    results = fleet_sync.sync_hosts(["alpha", "beta"], options, transport, jobs=1)
    lines: list[str] = []

    fleet_sync.apply_fixes(
        results,
        options,
        transport,
        REPO_ROOT,
        line=lines.append,
    )

    assert any("spawning one local omp agent for 2 host(s)" in line for line in lines)
    joined = "\n".join(lines)
    assert "Fix report" in joined
    assert "# Fix report" not in joined  # rendered, not raw markdown
    assert "fixed a.txt" in joined
    assert any("omp agent finished (exit 0)" in line for line in lines)
    # The agent is waited on and its exit status is recorded before completion runs.
    assert calls[0]["process"].stdout.tell() == len(b"# Fix report\n\n- fixed a.txt\n")
    assert [result.status for result in results] == [fleet_sync.STATUS_OK] * 2


def test_remote_scripts_get_the_user_bin_path() -> None:
    script = fleet_sync._script("git status")
    assert 'export PATH="$HOME/.local/bin:' in script
    assert script.index("export PATH=") < script.index("git status")


def test_remote_agent_missing_omp_prints_a_hint(monkeypatch) -> None:
    transport = FakeTransport(
        handler_for(
            [
                ("omp -p", _result(127, "sh: line 60: omp: command not found\n")),
                ("status --porcelain", _result(0, f" M {CONFLICT_FILE}\n")),
                ("pull --rebase origin", _result(1, "", "error: could not apply 1234abc\n")),
                ("--diff-filter=U", _result(0, CONFLICT_FILE + "\n")),
            ]
        )
    )
    monkeypatch.setattr(fleet_sync.subprocess, "Popen", fake_popen([]))
    options = fleet_sync.SyncOptions(repo_path=REMOTE_REPO, resolve=True)
    results = fleet_sync.sync_hosts(["alpha"], options, transport, jobs=1)
    lines: list[str] = []

    fleet_sync.apply_fixes(results, options, transport, REPO_ROOT, line=lines.append)

    assert any("not on that host's login PATH" in line for line in lines)
    assert any("omp agent finished (exit 127)" in line for line in lines)
