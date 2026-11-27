"""Tests for scripts/cli/render_help.py."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts/cli"))

import render_help  # noqa: E402
from oooconf_cli_spec import load_cli_spec  # noqa: E402

SPEC_PATH = REPO_ROOT / "scripts/cli/oooconf-cli-spec.toml"


def _plain_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OOOCONF_COLOR", "never")
    monkeypatch.setenv("OOOCONF_ASCII", "1")
    monkeypatch.delenv("FORCE_COLOR", raising=False)


def test_render_main_includes_commands_aliases_and_repo_root(monkeypatch: pytest.MonkeyPatch) -> None:
    _plain_env(monkeypatch)
    spec = load_cli_spec(SPEC_PATH)

    unix_out = render_help.render_main(spec, REPO_ROOT, platform="unix")
    win_out = render_help.render_main(spec, REPO_ROOT, platform="windows")

    assert "Usage: oooconf [global options] <command> [command options]" in unix_out
    assert str(REPO_ROOT) in unix_out
    assert "check -> doctor" in unix_out
    assert "preview -> dry-run" in unix_out
    assert "upgrade -> update" in unix_out
    assert "OOOCONF_COLOR=always|never|auto" in unix_out
    assert "oooconf bootstrap" in unix_out

    assert "bootstrap is Unix-only in this wrapper." in win_out
    assert "$env:OOOCONF_COLOR='always'" in win_out
    assert "./scripts/setup/setup.ps1 install" in win_out

    for name in ("install", "deps", "update", "doctor", "status", "plan", "agents", "fleet", "secrets", "wm"):
        assert name in unix_out
        assert name in win_out


def test_render_command_covers_every_top_level_spec_command(monkeypatch: pytest.MonkeyPatch) -> None:
    _plain_env(monkeypatch)
    spec = load_cli_spec(SPEC_PATH)

    for cmd_name, cmd in spec.commands.items():
        rendered = render_help.render_command(spec, cmd_name, REPO_ROOT, platform="unix")
        assert rendered is not None, f"Missing help output for command: {cmd_name}"
        assert "Usage:" in rendered
        if cmd_name not in {"help"}:
            target = cmd.alias_for or cmd_name
            assert f"oooconf {target}" in rendered

    wm_bar = render_help.render_command(spec, "wm bar", REPO_ROOT, platform="windows")
    assert wm_bar is not None
    assert "oooconf wm bar" in wm_bar


@pytest.mark.parametrize(
    ("alias", "target"),
    [
        ("check", "doctor"),
        ("preview", "dry-run"),
        ("upgrade", "update"),
    ],
)
def test_render_command_resolves_aliases(monkeypatch: pytest.MonkeyPatch, alias: str, target: str) -> None:
    _plain_env(monkeypatch)
    spec = load_cli_spec(SPEC_PATH)

    alias_output = render_help.render_command(spec, alias, REPO_ROOT, platform="unix")
    target_output = render_help.render_command(spec, target, REPO_ROOT, platform="unix")
    assert alias_output == target_output


def test_render_command_help_and_empty_fall_back_to_main(monkeypatch: pytest.MonkeyPatch) -> None:
    _plain_env(monkeypatch)
    spec = load_cli_spec(SPEC_PATH)
    main_out = render_help.render_main(spec, REPO_ROOT, platform="unix")

    for token in ("", "help", "-h", "--help"):
        assert render_help.render_command(spec, token, REPO_ROOT, platform="unix") == main_out


def test_render_command_supports_positional_and_unknown(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    _plain_env(monkeypatch)

    rc = render_help.main(["--mode", "command", "--repo-root", str(REPO_ROOT), "install"])
    assert rc == 0
    out = capsys.readouterr().out
    assert "Usage: oooconf install" in out

    rc_unknown = render_help.main(["--mode", "command", "--repo-root", str(REPO_ROOT), "--command", "instal"])
    captured = capsys.readouterr()
    assert rc_unknown == 2
    assert "Unknown command: instal" in captured.err
    assert "Did you mean: install" in captured.err

    rc_quiet = render_help.main(
        ["--mode", "command", "--repo-root", str(REPO_ROOT), "--command", "boguscmd", "--quiet-unknown"]
    )
    captured_quiet = capsys.readouterr()
    assert rc_quiet == 2
    assert captured_quiet.out == ""
    assert captured_quiet.err == ""


@pytest.mark.parametrize(
    ("typo", "expected"),
    [
        ("instal", "install"),
        ("doctro", "doctor"),
        ("statsu", "status"),
        ("chek", "check"),
        ("upgrde", "upgrade"),
        ("updat", "update"),
        ("screts", "secrets"),
        ("flet", "fleet"),
        ("completely-invalid-command", ""),
        ("", ""),
    ],
)
def test_suggest_mode(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str], typo: str, expected: str
) -> None:
    _plain_env(monkeypatch)

    rc = render_help.main(["--mode", "suggest", "--repo-root", str(REPO_ROOT), "--input", typo])
    assert rc == 0
    out = capsys.readouterr().out.strip()
    assert out == expected


def test_suggest_mode_with_custom_candidates(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    _plain_env(monkeypatch)

    rc = render_help.main(
        [
            "--mode",
            "suggest",
            "--repo-root",
            str(REPO_ROOT),
            "--input",
            "staus",
            "--candidates",
            "status set start stop reload",
        ]
    )
    assert rc == 0
    assert capsys.readouterr().out.strip() == "status"


def test_spec_fallback_renders_command_without_curated_block(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    _plain_env(monkeypatch)
    spec_file = tmp_path / "scripts/cli/oooconf-cli-spec.toml"
    spec_file.parent.mkdir(parents=True)
    spec_file.write_text(
        """
[meta]
schema_version = 1
minimum_reader_version = 1

[commands.custom-cmd]
handler_id = "test.custom"
platforms = ["linux", "windows"]
description = "run custom workflow"
options = { "--dry-run" = "preview changes" }

[commands.custom-cmd.subcommands.run]
handler_id = "test.custom.run"
platforms = ["linux", "windows"]
description = "execute custom step"
""",
        encoding="utf-8",
    )
    spec = render_help.load_spec(tmp_path)
    rendered = render_help.render_command(spec, "custom-cmd", tmp_path, platform="unix")
    assert rendered is not None
    assert "Usage: oooconf custom-cmd <run> [options]" in rendered
    assert "run custom workflow" in rendered
    assert "--dry-run" in rendered
    assert "execute custom step" in rendered


def test_color_output_enabled_when_forced(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OOOCONF_COLOR", "always")
    monkeypatch.setenv("OOOCONF_ASCII", "1")
    spec = load_cli_spec(SPEC_PATH)
    rendered = render_help.render_command(spec, "version", REPO_ROOT, platform="unix")
    assert rendered is not None
    assert "\033[" in rendered
