"""Unit tests for scripts/generate/render_secrets.py (fully isolated, no network or vault)."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.generate import render_secrets  # noqa: E402


def _isolate_home(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> Path:
    home = tmp_path / "home"
    home.mkdir(parents=True, exist_ok=True)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("USERPROFILE", str(home))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(home / ".config"))
    monkeypatch.setenv("XDG_DATA_HOME", str(home / ".local/share"))
    monkeypatch.delenv("BW_SESSION", raising=False)
    monkeypatch.delenv("BW_CLIENTID", raising=False)
    monkeypatch.delenv("BW_CLIENTSECRET", raising=False)
    monkeypatch.delenv("BW_PASSWORD", raising=False)
    monkeypatch.delenv("OOODNAKOV_BW_SERVER", raising=False)
    monkeypatch.setenv("OOOCONF_COLOR", "never")
    return home


def test_parse_template_and_strip_quotes(tmp_path: Path) -> None:
    template = tmp_path / "env.template"
    template.write_text(
        "# comment\n\nPLAIN=abc\nSINGLE='one two'\nDOUBLE=\"three four\"\nINNER=a=b=c\n",
        encoding="utf-8",
    )
    entries = render_secrets.parse_template(template)
    assert [(e.key, e.value, e.line_number) for e in entries] == [
        ("PLAIN", "abc", 3),
        ("SINGLE", "one two", 4),
        ("DOUBLE", "three four", 5),
        ("INNER", "a=b=c", 6),
    ]
    assert render_secrets.strip_matching_quotes("'x") == "'x"

    bad_no_eq = tmp_path / "bad1.template"
    bad_no_eq.write_text("NO_EQUALS\n", encoding="utf-8")
    with pytest.raises(ValueError, match="expected KEY=VALUE"):
        render_secrets.parse_template(bad_no_eq)

    bad_empty_key = tmp_path / "bad2.template"
    bad_empty_key.write_text("=value\n", encoding="utf-8")
    with pytest.raises(ValueError, match="missing variable name"):
        render_secrets.parse_template(bad_empty_key)


def test_cli_helpers_normalize_suggest_shell_and_paths(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    normalized, cmd = render_secrets.normalize_subcommand_argv(["--repo-root", str(tmp_path), "ls", "--resolved"])
    assert cmd == "ls"
    assert normalized == ["--repo-root", str(tmp_path), "list", "--resolved"]

    normalized_rm, cmd_rm = render_secrets.normalize_subcommand_argv(["--help", "rm"])
    assert cmd_rm == "rm"
    assert normalized_rm == ["--help", "remove"]

    assert render_secrets.normalize_subcommand_argv(["--help"]) == (["--help"], None)
    assert render_secrets.suggest_subcommand("synk") == "sync"
    assert render_secrets.suggest_subcommand("zzzzzzzzzz") is None

    monkeypatch.setenv("SHELL", "/bin/zsh")
    assert render_secrets.detect_shell_kind() == "zsh"
    monkeypatch.setenv("SHELL", "/usr/bin/pwsh")
    assert render_secrets.detect_shell_kind() == "pwsh"
    monkeypatch.setenv("SHELL", "")
    assert render_secrets.detect_shell_kind() == "sh"

    assert render_secrets.resolve_repo_root(str(tmp_path)) == tmp_path.resolve()
    custom_tpl = tmp_path / "custom.tpl"
    assert render_secrets.resolve_template_path(tmp_path, str(custom_tpl)) == custom_tpl.resolve()
    assert (
        render_secrets.resolve_template_path(tmp_path, None)
        == (tmp_path / render_secrets.DEFAULT_TEMPLATE_RELATIVE_PATH).resolve()
    )


def test_quoting_escaping_and_local_overrides_preservation(tmp_path: Path) -> None:
    assert render_secrets.shell_assignment("API_KEY", "a 'b' $c") == "export API_KEY='a '\"'\"'b'\"'\"' $c'"
    assert render_secrets.powershell_assignment("API_KEY", "it's ok") == "$env:API_KEY = 'it''s ok'"

    multiline_ps = render_secrets.powershell_assignment("CERT", "line1\nline2")
    assert "FromBase64String(" in multiline_ps
    curly_ps = render_secrets.powershell_assignment("QUOTE", "bad\u2019quote")
    assert "FromBase64String(" in curly_ps

    content_with_overrides = (
        "export A=1\n"
        f"{render_secrets.LOCAL_OVERRIDES_START}\n"
        f"{render_secrets._LOCAL_DEFAULT_COMMENT}\n"
        "export LOCAL_ONLY=keep\n"
        "export ANOTHER='v'\n"
        f"{render_secrets.LOCAL_OVERRIDES_END}\n"
    )
    assert render_secrets.extract_local_overrides(content_with_overrides) == [
        "export LOCAL_ONLY=keep",
        "export ANOTHER='v'",
    ]
    assert render_secrets.extract_local_overrides("no markers") == []
    assert render_secrets.extract_local_overrides(f"{render_secrets.LOCAL_OVERRIDES_START}\nno end") == []
    assert (
        render_secrets.extract_local_overrides(
            f"{render_secrets.LOCAL_OVERRIDES_START}\n\n{render_secrets.LOCAL_OVERRIDES_END}"
        )
        == []
    )

    target = tmp_path / "env.zsh"
    tpl = tmp_path / "env.template"
    rendered_v1 = render_secrets.render_zsh([("A", "1")], "bw", tpl)
    assert render_secrets.write_file(target, rendered_v1, force=False) == "created"
    assert render_secrets.write_file(target, rendered_v1, force=False) == "unchanged"
    assert render_secrets.write_file(target, rendered_v1, force=True) == "updated"

    # Inject user local override line and verify it survives re-sync.
    existing = target.read_text(encoding="utf-8").replace(
        render_secrets.LOCAL_OVERRIDES_END,
        f"export MACHINE_ONLY=42\n{render_secrets.LOCAL_OVERRIDES_END}",
    )
    target.write_text(existing, encoding="utf-8")
    rendered_v2 = render_secrets.render_zsh([("A", "2")], "bw", tpl)
    assert render_secrets.write_file(target, rendered_v2, force=False) == "updated"
    updated_text = target.read_text(encoding="utf-8")
    assert "export A=2" in updated_text
    assert "export MACHINE_ONLY=42" in updated_text

    ps_rendered = render_secrets.render_ps1([("A", "2")], "bw", tpl)
    assert "$env:A = '2'" in ps_rendered


def test_resolve_entries_and_missing_bw_references(monkeypatch: pytest.MonkeyPatch) -> None:
    plain_entry = render_secrets.SecretEntry("PLAIN", "hello", 1)
    assert render_secrets.resolve_value(plain_entry, "bw") == "hello"

    bw_entry = render_secrets.SecretEntry("TOKEN", "bw://item/id-1/password", 2)
    with pytest.raises(ValueError, match="unsupported backend"):
        render_secrets.resolve_value(bw_entry, "vault")

    monkeypatch.setattr(render_secrets.bw_cli, "fetch_items", lambda ids: {"id-1": {"login": {"password": "s3cr3t"}}})
    monkeypatch.setattr(
        render_secrets.bw_cli,
        "resolve_reference",
        lambda ref, key, cache: cache["id-1"]["login"]["password"],
    )
    resolved = render_secrets.resolve_entries_for_sync([plain_entry, bw_entry], "bw")
    assert resolved == [("PLAIN", "hello"), ("TOKEN", "s3cr3t")]

    # Missing Bitwarden item ID triggers descriptive error without leaking secrets.
    monkeypatch.setattr(render_secrets.bw_cli, "fetch_items", lambda ids: {})
    with pytest.raises(RuntimeError, match="not found in the current vault") as exc_info:
        render_secrets.resolve_entries_for_sync([bw_entry], "bw")
    assert "TOKEN: id-1" in str(exc_info.value)


def test_sync_command_dry_run_missing_template_and_full_sync(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    home = _isolate_home(monkeypatch, tmp_path)
    repo = tmp_path / "repo"
    tpl = repo / render_secrets.DEFAULT_TEMPLATE_RELATIVE_PATH

    missing_args = argparse.Namespace(backend="bw", template=None, force=False, dry_run=False)
    assert render_secrets.sync_command(missing_args, repo) == 1
    assert "Template not found" in capsys.readouterr().out

    tpl.parent.mkdir(parents=True)
    tpl.write_text("PLAIN_KEY=plain_val\nSECRET_KEY=bw://item/item-1/password\n", encoding="utf-8")

    monkeypatch.setattr(
        render_secrets.bw_cli,
        "fetch_items",
        lambda ids: {"item-1": {"id": "item-1", "login": {"password": "top-secret-value"}}},
    )
    monkeypatch.setattr(
        render_secrets.bw_cli,
        "resolve_reference",
        lambda ref, key, cache: cache["item-1"]["login"]["password"],
    )

    dry_args = argparse.Namespace(backend="bw", template=None, force=False, dry_run=True)
    assert render_secrets.sync_command(dry_args, repo) == 0
    dry_out = capsys.readouterr().out
    assert "Dry run complete." in dry_out
    assert "top-secret-value" not in dry_out
    assert not (home / ".config/ooodnakov/local/env.zsh").exists()

    sync_args = argparse.Namespace(backend="bw", template=None, force=False, dry_run=False)
    assert render_secrets.sync_command(sync_args, repo) == 0
    zsh_file = home / ".config/ooodnakov/local/env.zsh"
    ps1_file = home / ".config/ooodnakov/local/env.ps1"
    assert "export SECRET_KEY=top-secret-value" in zsh_file.read_text(encoding="utf-8")
    assert "$env:SECRET_KEY = 'top-secret-value'" in ps1_file.read_text(encoding="utf-8")


def test_list_status_add_remove_and_doctor_commands(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    home = _isolate_home(monkeypatch, tmp_path)
    repo = tmp_path / "repo"
    tpl = repo / render_secrets.DEFAULT_TEMPLATE_RELATIVE_PATH
    tpl.parent.mkdir(parents=True)
    tpl.write_text("# Header\n", encoding="utf-8")

    # Empty list
    assert render_secrets.list_command(argparse.Namespace(template=None, resolved=False, backend="bw"), repo) == 0
    assert "No secrets defined" in capsys.readouterr().out

    # Add invalid, valid, duplicate, remove missing/valid
    assert render_secrets.add_command(argparse.Namespace(key="bad-key", value="v", template=None), repo) == 1
    assert render_secrets.add_command(argparse.Namespace(key="TOKEN_A", value="plain", template=None), repo) == 0
    assert (
        render_secrets.add_command(
            argparse.Namespace(key="TOKEN_B", value="bw://item/abc/password", template=None), repo
        )
        == 0
    )
    assert render_secrets.add_command(argparse.Namespace(key="TOKEN_A", value="dup", template=None), repo) == 1

    # List resolved with masking + error redaction
    def fake_resolve(entry: render_secrets.SecretEntry, backend: str, cache=None) -> str:
        if entry.key == "TOKEN_B":
            return "supersecret123"
        return entry.value

    monkeypatch.setattr(render_secrets, "resolve_value", fake_resolve)
    assert render_secrets.list_command(argparse.Namespace(template=None, resolved=True, backend="bw"), repo) == 0
    list_out = capsys.readouterr().out
    assert "TOKEN_A=plain" in list_out
    assert "TOKEN_B=************  (resolved)" in list_out
    assert "supersecret123" not in list_out

    assert render_secrets.remove_command(argparse.Namespace(key="MISSING", template=None), repo) == 1
    assert render_secrets.remove_command(argparse.Namespace(key="TOKEN_A", template=None), repo) == 0

    # Status missing files -> 1
    assert render_secrets.status_command(argparse.Namespace(template=None), repo) == 1

    # Create local files newer than template -> 0
    local_dir = home / ".config/ooodnakov/local"
    local_dir.mkdir(parents=True)
    (local_dir / "env.zsh").write_text("export X=1\n", encoding="utf-8")
    (local_dir / "env.ps1").write_text("$env:X = '1'\n", encoding="utf-8")
    monkeypatch.setattr(render_secrets.bw_cli, "which_bw", lambda: "/usr/bin/bw")
    monkeypatch.setattr(render_secrets.bw_cli, "status", lambda: {"status": "unlocked", "serverUrl": ""})
    monkeypatch.setenv("BW_SESSION", "tok")
    assert render_secrets.status_command(argparse.Namespace(template=None), repo) == 0

    # Stale local file when template mtime is newer -> 1
    stale_time = tpl.stat().st_mtime - 100
    os.utime(local_dir / "env.zsh", (stale_time, stale_time))
    assert render_secrets.status_command(argparse.Namespace(template=None), repo) == 1

    # Doctor checks: plaintext in repo fails, clean state passes
    monkeypatch.setattr(render_secrets, "check_bw_status", lambda: [])
    assert render_secrets.doctor_command(argparse.Namespace(backend="bw", template=None), repo) == 0

    tracked_leak = repo / "home/.config/ooodnakov/local/env.zsh"
    tracked_leak.parent.mkdir(parents=True)
    tracked_leak.write_text("SECRET=leak\n", encoding="utf-8")
    assert render_secrets.doctor_command(argparse.Namespace(backend="bw", template=None), repo) == 1


def test_bw_status_login_unlock_logout_and_main_dispatch(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    home = _isolate_home(monkeypatch, tmp_path)
    monkeypatch.setenv("OOODNAKOV_BW_SERVER", "https://vault.expected")
    monkeypatch.setattr(render_secrets.bw_cli, "which_bw", lambda: "/usr/bin/bw")

    monkeypatch.setattr(
        render_secrets.bw_cli,
        "status",
        lambda: {"serverUrl": "https://vault.other", "status": "locked"},
    )
    problems = render_secrets.check_bw_status()
    assert len(problems) == 2

    monkeypatch.setattr(render_secrets.bw_cli, "status", lambda: {"status": "unauthenticated"})
    assert any("not logged in" in p for p in render_secrets.check_bw_status())

    monkeypatch.setattr(render_secrets.bw_cli, "status", lambda: {"status": "unlocked"})
    assert any("no BW_SESSION" in p for p in render_secrets.check_bw_status())

    # Login without server fails cleanly
    monkeypatch.delenv("OOODNAKOV_BW_SERVER", raising=False)
    assert (
        render_secrets.login_command(argparse.Namespace(server="", method="auto", client_id=None, client_secret=None))
        == 1
    )

    # Login with apikey in non-interactive mode
    monkeypatch.setattr(render_secrets.sys.stdin, "isatty", lambda: False)
    monkeypatch.setattr(render_secrets.sys.stdout, "isatty", lambda: False)
    monkeypatch.setattr(render_secrets.bw_cli, "config_server", lambda url: 0)
    monkeypatch.setattr(render_secrets.bw_cli, "login_apikey", lambda env: 0)
    assert (
        render_secrets.login_command(
            argparse.Namespace(
                server="https://vault.example/",
                method="apikey",
                client_id="cid",
                client_secret="csec",
            )
        )
        == 0
    )
    assert "process lists" in capsys.readouterr().out

    # Unlock --raw and --shell pwsh
    monkeypatch.setattr(render_secrets.bw_cli, "unlock_raw", lambda password=None: "tok-123")
    assert (
        render_secrets.unlock_command(
            argparse.Namespace(password=None, shell="sh", raw=True, explicit_shell=False, explicit_raw=True)
        )
        == 0
    )
    assert capsys.readouterr().out.strip() == "tok-123"

    assert (
        render_secrets.unlock_command(
            argparse.Namespace(password=None, shell="pwsh", raw=False, explicit_shell=True, explicit_raw=False)
        )
        == 0
    )
    assert "$env:BW_SESSION = 'tok-123'" in capsys.readouterr().out

    # Persist password unlock
    saved_session = home / ".config/ooodnakov/local/bw-session"
    monkeypatch.setattr(render_secrets.bw_cli, "write_session", lambda tok: saved_session)
    assert (
        render_secrets.unlock_command(
            argparse.Namespace(password="pw", shell="sh", raw=False, explicit_shell=False, explicit_raw=False)
        )
        == 0
    )

    # Logout calls lock, logout, clear_session
    called: list[str] = []
    monkeypatch.setattr(render_secrets.bw_cli, "lock", lambda: called.append("lock") or 0)
    monkeypatch.setattr(render_secrets.bw_cli, "logout", lambda: called.append("logout") or 0)
    monkeypatch.setattr(render_secrets.bw_cli, "clear_session", lambda: called.append("clear"))
    assert render_secrets.logout_command() == 0
    assert called == ["lock", "logout", "clear"]

    # main() dispatch
    repo = tmp_path / "repo2"
    tpl = repo / render_secrets.DEFAULT_TEMPLATE_RELATIVE_PATH
    tpl.parent.mkdir(parents=True)
    tpl.write_text("DEMO=1\n", encoding="utf-8")
    monkeypatch.setattr(sys, "argv", ["render_secrets.py", "--repo-root", str(repo), "sync", "--dry-run"])
    assert render_secrets.main() == 0

    monkeypatch.setattr(sys, "argv", ["render_secrets.py", "--repo-root", str(repo), "synk"])
    with pytest.raises(SystemExit) as exit_info:
        render_secrets.parse_args()
    assert exit_info.value.code == 2
