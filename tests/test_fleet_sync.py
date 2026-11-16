"""Tests for `oooconf fleet sync`: host discovery, per-host pipeline, and reporting.

No network and no `ssh`: every remote call goes through a fake transport.
"""

from __future__ import annotations

import json
import sys
import threading
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

    def run(self, host: str, script: str) -> fleet_sync.CommandResult:
        with self._lock:
            self.calls.append((host, script))
        return self._handler(host, script)

    def scripts(self, host: str | None = None) -> list[str]:
        with self._lock:
            return [script for call_host, script in self.calls if host is None or call_host == host]

    def find(self, fragment: str, host: str | None = None) -> list[str]:
        return [script for script in self.scripts(host) if fragment in script]

    def issued(self, fragment: str, host: str | None = None) -> bool:
        return bool(self.find(fragment, host))


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
    local_calls: list[object] = []
    monkeypatch.setattr(fleet_sync.subprocess, "run", lambda *args, **kwargs: local_calls.append(args))

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

    def fake_run(argv, **kwargs):
        calls.append({"argv": list(argv), **kwargs})
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(fleet_sync.subprocess, "run", fake_run)

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
    assert calls[0]["capture_output"] is True
    assert calls[0]["text"] is True
    assert calls[0]["check"] is False
    assert not transport.issued("omp -p")
    assert [result.fix for result in results] == ["local-agent", "local-agent"]
    assert [result.status for result in results] == [fleet_sync.STATUS_OK] * 2
    assert all(result.resolved for result in results)


def test_resolve_with_dry_run_spawns_no_agent(monkeypatch) -> None:
    transport = FakeTransport(handler_for([("rev-list --left-right --count", _result(0, "2\t1\n"))]))
    calls: list[object] = []
    monkeypatch.setattr(fleet_sync.subprocess, "run", lambda *args, **kwargs: calls.append(args))

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
    monkeypatch.setattr(fleet_sync.subprocess, "run", lambda *args, **kwargs: None)

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
    agent_calls: list[list[str]] = []

    def fake_run(argv, **kwargs):
        agent_calls.append(list(argv))
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(fleet_sync.subprocess, "run", fake_run)

    code = fleet_sync.main(
        ["--repo-root", str(REPO_ROOT), "sync", "alpha", "beta", "--repo-path", REMOTE_REPO, "--resolve"]
    )

    out = capsys.readouterr().out
    assert code == 0
    # One local agent covers both hosts and receives their status.
    assert len(agent_calls) == 1
    assert agent_calls[0][:2] == ["omp", "-p"]
    assert "host=alpha" in agent_calls[0][2]
    assert "host=beta" in agent_calls[0][2]
    # The per-host status is printed before the agent runs, the final summary after it.
    assert " conflict " in out
    assert out.count("fix=local-agent") == 2
    assert "ok=2 conflict=0" in out
    assert not transport.issued("omp -p")
