"""Tests for optional private overlay resolution, merging, and Phase 1 fallbacks."""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.generate import render_secrets  # noqa: E402
from scripts.lib import private_overlay  # noqa: E402
from scripts.link_manager import expand_path_template, get_all_links, merge_with_local  # noqa: E402


@pytest.fixture
def isolated_env(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> tuple[Path, Path]:
    home = tmp_path / "home"
    home.mkdir(parents=True)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("USERPROFILE", str(home))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(home / ".config"))
    monkeypatch.setenv("XDG_DATA_HOME", str(home / ".local/share"))
    monkeypatch.delenv("OOOCONF_PRIVATE_DIR", raising=False)
    monkeypatch.delenv("OOODNAKOV_BW_SERVER", raising=False)
    repo = tmp_path / "workspace" / "ooodnakov-config"
    repo.mkdir(parents=True)
    return repo, home


def test_resolve_private_overlay_root_precedence_and_opt_out(
    isolated_env: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    repo, home = isolated_env
    sibling = repo.parent / "ooodnakov-config-private"
    sibling.mkdir()

    # 3) Sibling auto-discovery when env var and pointer files are absent.
    assert private_overlay.resolve_private_overlay_root(repo) == sibling.resolve()

    # 2b) Home pointer overrides sibling, ignoring blank lines and comments.
    custom_home_overlay = repo.parent / "from-home-pointer"
    custom_home_overlay.mkdir()
    home_pointer = home / ".config/ooodnakov/local/private-repo"
    home_pointer.parent.mkdir(parents=True)
    home_pointer.write_text(
        f"# comment\n\n~/../{home.name}/../workspace/from-home-pointer\n",
        encoding="utf-8",
    )
    assert private_overlay.resolve_private_overlay_root(repo) == custom_home_overlay.resolve()

    # 2a) Repo-local pointer overrides home pointer (supports relative path).
    custom_repo_overlay = repo.parent / "from-repo-pointer"
    custom_repo_overlay.mkdir()
    repo_pointer = repo / "home/.config/ooodnakov/local/private-repo"
    repo_pointer.parent.mkdir(parents=True)
    repo_pointer.write_text("# comment\n../from-repo-pointer\n", encoding="utf-8")
    assert private_overlay.resolve_private_overlay_root(repo) == custom_repo_overlay.resolve()

    # 1) OOOCONF_PRIVATE_DIR overrides everything.
    env_overlay = repo.parent / "from-env"
    env_overlay.mkdir()
    monkeypatch.setenv("OOOCONF_PRIVATE_DIR", "../from-env")
    assert private_overlay.resolve_private_overlay_root(repo) == env_overlay.resolve()

    # Missing explicit OOOCONF_PRIVATE_DIR returns None instead of falling back.
    monkeypatch.setenv("OOOCONF_PRIVATE_DIR", str(repo.parent / "does-not-exist"))
    assert private_overlay.resolve_private_overlay_root(repo) is None

    # Empty or "none" (case-insensitive) explicitly opts out.
    for opt_out in ("", "   ", "none", "NONE"):
        monkeypatch.setenv("OOOCONF_PRIVATE_DIR", opt_out)
        assert private_overlay.resolve_private_overlay_root(repo) is None


def test_resolve_private_overlay_root_returns_none_and_cli_exit_codes(
    isolated_env: tuple[Path, Path], capsys: pytest.CaptureFixture[str]
) -> None:
    repo, _home = isolated_env
    assert private_overlay.resolve_private_overlay_root(repo) is None
    assert private_overlay.main(["--repo-root", str(repo)]) == 1
    assert capsys.readouterr().out == ""

    sibling = repo.parent / "ooodnakov-config-private"
    sibling.mkdir()
    assert private_overlay.main(["--repo-root", str(repo)]) == 0
    assert capsys.readouterr().out.strip() == str(sibling.resolve())


def test_expand_and_merge_with_local_private_root_and_platform_filters(
    isolated_env: tuple[Path, Path],
) -> None:
    repo, home = isolated_env
    private_root = repo.parent / "private-overlay"
    private_root.mkdir()

    assert expand_path_template("{PRIVATE_ROOT}/ssh/config", "linux", private_root=private_root) == (
        f"{private_root.as_posix()}/ssh/config"
    )

    overlay_toml = private_root / "links.local.toml"
    overlay_toml.write_text(
        """
[links.omp-config]
source = "{PRIVATE_ROOT}/omp/config.yml"
target = "{HOME}/.omp/agent/config.yml"

[links.linux-only-override]
source = "{PRIVATE_ROOT}/linux/only"
target = "{CONFIG_HOME}/linux-only"
only = "linux"

[links.windows-only-override]
source = "{PRIVATE_ROOT}/win/only"
target = "{CONFIG_HOME}/win-only"
only = "windows"

[links.skip-on-linux]
source = "{PRIVATE_ROOT}/other/file"
target = "{CONFIG_HOME}/other"
except = "linux"
""",
        encoding="utf-8",
    )

    base = [
        {"key": "omp-config", "source": "/base/omp.yml", "target": "/base/target.yml"},
        {"key": "windows-only-override", "source": "/base/win", "target": "/base/win-target"},
    ]
    merged = merge_with_local(base, overlay_toml, platform="linux", private_root=private_root)

    assert merged == [
        {
            "key": "omp-config",
            "source": f"{private_root.as_posix()}/omp/config.yml",
            "target": f"{home.as_posix()}/.omp/agent/config.yml",
        },
        # Non-matching platform override preserves base link unchanged.
        {"key": "windows-only-override", "source": "/base/win", "target": "/base/win-target"},
        # Matching new entry is added with {PRIVATE_ROOT} expanded.
        {
            "key": "linux-only-override",
            "source": f"{private_root.as_posix()}/linux/only",
            "target": f"{home.as_posix()}/.config/linux-only",
        },
    ]


def test_get_all_links_merges_private_overlay_and_machine_local_precedence(
    isolated_env: tuple[Path, Path],
) -> None:
    repo, home = isolated_env
    (repo / "scripts").mkdir(parents=True)
    (repo / "home/.omp/agent").mkdir(parents=True)
    (repo / "home/.omp/agent/config.yml").write_text("base: true\n", encoding="utf-8")
    (repo / "scripts/links.toml").write_text(
        """
[[links]]
key = "omp-config"
source = "home/.omp/agent/config.yml"
target = "{HOME}/.omp/agent/config.yml"
""",
        encoding="utf-8",
    )

    private_root = repo.parent / "ooodnakov-config-private"
    private_root.mkdir()
    (private_root / "links.local.toml").write_text(
        """
[links.omp-config]
source = "{PRIVATE_ROOT}/omp/config.yml"
target = "{HOME}/.omp/agent/config.yml"

[links.ssh-config-local]
source = "{PRIVATE_ROOT}/ssh/config"
target = "{HOME}/.ssh/config.local"

[links.bw-server-local]
source = "{PRIVATE_ROOT}/secrets/bw-server"
target = "{DATA_HOME}/ooodnakov-config/bw-server"
""",
        encoding="utf-8",
    )

    machine_local = repo / "home/.config/ooodnakov/local/links.local.toml"
    machine_local.parent.mkdir(parents=True)
    machine_local.write_text(
        """
[links.ssh-config-local]
source = "{HOME}/machine-ssh-override"
target = "{HOME}/.ssh/config.local"
""",
        encoding="utf-8",
    )

    links = {key: (src, tgt) for src, tgt, key in get_all_links(repo, "linux")}
    assert links["omp-config"] == (
        f"{private_root.resolve().as_posix()}/omp/config.yml",
        f"{home.as_posix()}/.omp/agent/config.yml",
    )
    assert links["ssh-config-local"] == (
        f"{home.as_posix()}/machine-ssh-override",
        f"{home.as_posix()}/.ssh/config.local",
    )
    assert links["bw-server-local"] == (
        f"{private_root.resolve().as_posix()}/secrets/bw-server",
        f"{home.as_posix()}/.local/share/ooodnakov-config/bw-server",
    )


def test_resolve_default_bw_server_precedence(isolated_env: tuple[Path, Path], monkeypatch: pytest.MonkeyPatch) -> None:
    _repo, home = isolated_env

    # 4) Fallback when nothing configured.
    fallback = render_secrets.resolve_default_bw_server()
    assert fallback.startswith("https://")

    # 3) Machine-local file.
    local_file = home / ".config/ooodnakov/local/bw-server"
    local_file.parent.mkdir(parents=True)
    local_file.write_text("# comment\n\nhttps://local.vault.example\n", encoding="utf-8")
    assert render_secrets.resolve_default_bw_server() == "https://local.vault.example"

    # 2) Data-home file overrides local file.
    data_file = home / ".local/share/ooodnakov-config/bw-server"
    data_file.parent.mkdir(parents=True)
    data_file.write_text("# overlay\nhttps://data.vault.example\n", encoding="utf-8")
    assert render_secrets.resolve_default_bw_server() == "https://data.vault.example"

    if os.name != "nt":
        custom_xdg = home / "custom-xdg"
        xdg_file = custom_xdg / "ooodnakov-config/bw-server"
        xdg_file.parent.mkdir(parents=True)
        xdg_file.write_text("https://xdg.vault.example\n", encoding="utf-8")
        monkeypatch.setenv("XDG_DATA_HOME", str(custom_xdg))
        assert render_secrets.resolve_default_bw_server() == "https://xdg.vault.example"

    # 1) Env var overrides everything.
    monkeypatch.setenv("OOODNAKOV_BW_SERVER", "  https://env.vault.example  ")
    assert render_secrets.resolve_default_bw_server() == "https://env.vault.example"
