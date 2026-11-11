"""Path formatting: $HOME abbreviation and cross-shell parity."""

from __future__ import annotations

import importlib.util
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASH_UI = ROOT / "scripts/setup/lib/oooconf-ui.sh"
PYTHON_UI = ROOT / "scripts/cli/cli_ui.py"


def _load_cli_ui():
    spec = importlib.util.spec_from_file_location("cli_ui_path_test", PYTHON_UI)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _plain(monkeypatch, home: Path) -> None:
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("OOOCONF_COLOR", "never")
    monkeypatch.delenv("NO_COLOR", raising=False)
    monkeypatch.delenv("FORCE_COLOR", raising=False)


def test_home_is_abbreviated(monkeypatch, tmp_path: Path) -> None:
    _plain(monkeypatch, tmp_path)
    cli_ui = _load_cli_ui()
    assert cli_ui.path(tmp_path) == "~"
    assert cli_ui.path(tmp_path / ".config" / "nvim") == "~/.config/nvim"


def test_foreign_and_relative_paths_are_untouched(monkeypatch, tmp_path: Path) -> None:
    _plain(monkeypatch, tmp_path / "home")
    cli_ui = _load_cli_ui()
    assert cli_ui.path(Path("/etc/hosts")) == "/etc/hosts"
    assert cli_ui.path(Path("home/.config/nvim")) == "home/.config/nvim"


def test_leaf_is_colored_and_directories_are_muted(monkeypatch, tmp_path: Path) -> None:
    _plain(monkeypatch, tmp_path)
    monkeypatch.setenv("OOOCONF_COLOR", "always")
    cli_ui = _load_cli_ui()
    rendered = cli_ui.path(tmp_path / "a" / "b.txt")
    assert "\033[0m" in rendered
    assert "b.txt" in rendered
    assert rendered.endswith("\033[0m")
    plain = cli_ui.path(tmp_path / "a" / "b.txt").replace("\033", "")
    assert "~/" in plain


def test_bash_and_python_agree(monkeypatch, tmp_path: Path) -> None:
    _plain(monkeypatch, tmp_path)
    cli_ui = _load_cli_ui()
    cases = [
        str(tmp_path),
        str(tmp_path / ".config" / "nvim"),
        str(tmp_path / ".local" / "share" / "fonts" / "ooodnakov"),
        "/etc/hosts",
        "relative/dir/file.toml",
    ]
    script = 'source "$1"; shift; for value in "$@"; do ui_path "$value"; printf \'\\n\'; done'
    result = subprocess.run(
        ["bash", "-c", script, "_", str(BASH_UI), *cases],
        capture_output=True,
        text=True,
        check=True,
        env={"HOME": str(tmp_path), "OOOCONF_COLOR": "never", "OOOCONF_ASCII": "1", "PATH": "/usr/bin:/bin"},
    )
    bash_lines = result.stdout.splitlines()
    assert bash_lines == [cli_ui.path(case) for case in cases]
