import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from scripts.link_manager import get_all_links, merge_with_local


def test_merge_with_local_expands_templates_for_overrides(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "xdg-config"))
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "xdg-data"))

    local = tmp_path / "links.local.toml"
    local.write_text(
        """
[links.wezterm]
target = "{CONFIG_HOME}/wezterm-work"

[links.custom-bin]
source = "{HOME}/bin/oooconf"
target = "{LOCAL_BIN}/oooconf"
""",
        encoding="utf-8",
    )

    merged = merge_with_local(
        [
            {
                "key": "wezterm",
                "source": "/repo/home/.config/wezterm",
                "target": "/original/.config/wezterm",
            }
        ],
        local,
        platform="linux",
    )

    assert merged == [
        {
            "key": "wezterm",
            "source": "/repo/home/.config/wezterm",
            "target": f"{tmp_path}/xdg-config/wezterm-work",
        },
        {
            "key": "custom-bin",
            "source": f"{tmp_path}/home/bin/oooconf",
            "target": f"{tmp_path}/home/.local/bin/oooconf",
        },
    ]


def test_get_all_links_honors_explicit_platform(monkeypatch) -> None:
    repo_root = Path(__file__).parent.parent
    monkeypatch.setenv("HOME", "/tmp/oooconf-platform-test")

    linux_keys = {key for _source, _target, key in get_all_links(repo_root, "linux")}
    windows_keys = {key for _source, _target, key in get_all_links(repo_root, "windows")}

    assert {"hypr", "pypr", "noctalia"} <= linux_keys
    assert "komorebi-config" not in linux_keys
    assert {"komorebi-config", "glazewm", "zebar"} <= windows_keys
    assert "hypr" not in windows_keys
