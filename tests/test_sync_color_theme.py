import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from scripts.sync_color_theme import (
    KOMOREBI_THEME_BY_THEME,
    _css_var_lines,
    _set_komorebi_theme_file,
    _zebar_vars_for_css,
    set_overline_zebar_theme,
    set_zebar_theme,
)


def test_komorebi_theme_sync_writes_schema_safe_main_theme(tmp_path: Path) -> None:
    path = tmp_path / "komorebi.json"

    for theme, expected in KOMOREBI_THEME_BY_THEME.items():
        path.write_text(
            json.dumps(
                {
                    "border": True,
                    "theme": {
                        "palette": "Base16",
                        "name": "Ashes",
                        "active_border": "Base0D",
                        "accent": "Base0D",
                    },
                }
            ),
            encoding="utf-8",
        )

        _set_komorebi_theme_file(path, theme)

        data = json.loads(path.read_text(encoding="utf-8"))
        assert data["theme"] == {
            "palette": expected["palette"],
            "name": expected["name"],
            "single_border": expected["single_border"],
            "unfocused_border": expected["unfocused_border"],
            "bar_accent": expected["bar_accent"],
        }
        assert "active_border" not in data["theme"]
        assert "accent" not in data["theme"]


def test_komorebi_theme_sync_writes_schema_safe_bar_theme(tmp_path: Path) -> None:
    path = tmp_path / "komorebi.bar.json"

    for theme, expected in KOMOREBI_THEME_BY_THEME.items():
        path.write_text(
            json.dumps(
                {
                    "left_widgets": [],
                    "right_widgets": [],
                    "theme": {
                        "palette": "Base16",
                        "name": "Ashes",
                        "bar_accent": "Base0D",
                        "active_border": "Base0D",
                    },
                }
            ),
            encoding="utf-8",
        )

        _set_komorebi_theme_file(path, theme)

        data = json.loads(path.read_text(encoding="utf-8"))
        assert data["theme"] == {
            "palette": expected["palette"],
            "name": expected["name"],
            "accent": expected["accent"],
        }
        assert "bar_accent" not in data["theme"]
        assert "active_border" not in data["theme"]


def test_komorebi_theme_sync_skips_invalid_json(tmp_path: Path) -> None:
    path = tmp_path / "komorebi.json"
    path.write_text('{"theme": {"name": "Ashes"} // comment\n}', encoding="utf-8")

    result = _set_komorebi_theme_file(path, "gruvbox")

    assert result.startswith("komorebi.json: skipped (invalid JSON at line 1, column")
    assert path.read_text(encoding="utf-8") == '{"theme": {"name": "Ashes"} // comment\n}'


def test_zebar_theme_vars_use_css_variable_names() -> None:
    vars_map = _zebar_vars_for_css("gruvbox", kebab_case=True)

    assert vars_map["workspace-hover-bg"] == "rgba(255, 255, 255, 0.06)"
    assert vars_map["workspace-focused-border"] == "rgba(131, 165, 152, 0.45)"
    assert vars_map["workspace-label-bg"] == "rgba(235, 219, 178, 0.88)"
    assert vars_map["font"] == '"MesloLGSDZ Nerd Font Mono", sans-serif'
    assert "workspace_hover_bg" not in vars_map


def test_css_var_lines_can_mark_values_important() -> None:
    lines = _css_var_lines({"background": "#1e1e2e"}, important=True)

    assert lines == [
        ":root {",
        "  --background: #1e1e2e !important;",
        "}",
    ]


def test_set_zebar_theme_writes_managed_variants(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(Path, "home", lambda: tmp_path)

    set_zebar_theme("tokyonight")

    for pack in ("ooodnakov", "ooodnakov-komorebi"):
        text = (tmp_path / ".glzr" / "zebar" / pack / "theme-overrides.css").read_text(encoding="utf-8")
        assert "--accent: #7aa2f7;" in text
        assert "--workspace-hover-bg: rgba(255, 255, 255, 0.08);" in text


def test_set_overline_zebar_theme_writes_installed_pack_theme_css(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(Path, "home", lambda: tmp_path)
    theme_path = tmp_path / ".glzr" / "zebar" / "overline-zebar-komorebi" / "packages" / "ui" / "src" / "theme.css"
    theme_path.parent.mkdir(parents=True)
    theme_path.write_text(":root {}\n", encoding="utf-8")

    set_overline_zebar_theme("catppuccin")

    text = theme_path.read_text(encoding="utf-8")
    assert "--background: #1e1e2e !important;" in text
    assert "--primary: #89b4fa !important;" in text
    assert "--danger: #f38ba8 !important;" in text
