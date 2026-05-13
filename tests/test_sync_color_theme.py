import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from scripts.sync_color_theme import (
    CSS_MANAGED_BEGIN,
    CSS_MANAGED_END,
    KOMOREBI_THEME_BY_THEME,
    _css_var_block,
    _css_var_lines,
    _set_komorebi_theme_file,
    _write_managed_css_vars,
    _zebar_vars_for_css,
    set_overline_zebar_theme,
    set_wezterm_theme,
    set_yazi_theme,
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


def test_css_var_block_can_wrap_managed_marker() -> None:
    block = _css_var_block({"background": "#282828"}, important=True, managed=True)

    assert block == (f"{CSS_MANAGED_BEGIN}\n:root {{\n  --background: #282828 !important;\n}}\n{CSS_MANAGED_END}\n")


def test_write_managed_css_vars_replaces_existing_block(tmp_path: Path) -> None:
    path = tmp_path / "index.css"
    path.write_text(
        "body{margin:0}\n"
        f"{CSS_MANAGED_BEGIN}\n"
        ":root {\n"
        "  --background: #111111 !important;\n"
        "}\n"
        f"{CSS_MANAGED_END}\n"
        ".bar{height:34px}\n",
        encoding="utf-8",
    )

    _write_managed_css_vars(path, {"background": "#282828"}, important=True)

    text = path.read_text(encoding="utf-8")
    assert text.count(CSS_MANAGED_BEGIN) == 1
    assert "--background: #282828 !important;" in text
    assert "--background: #111111 !important;" not in text
    assert "body{margin:0}" in text
    assert ".bar{height:34px}" in text


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


def test_set_overline_zebar_theme_patches_built_css_when_present(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(Path, "home", lambda: tmp_path)
    pack_path = tmp_path / ".glzr" / "zebar" / "overline-zebar-komorebi"
    source_theme = pack_path / "packages" / "ui" / "src" / "theme.css"
    built_css = pack_path / "widgets" / "main" / "dist" / "assets" / "index.css"
    source_theme.parent.mkdir(parents=True)
    built_css.parent.mkdir(parents=True)
    source_theme.write_text(":root {}\n", encoding="utf-8")
    built_css.write_text("body{margin:0}\n", encoding="utf-8")

    result = set_overline_zebar_theme("gruvbox")

    assert "source=1, built-css=1" in result
    built_text = built_css.read_text(encoding="utf-8")
    assert "body{margin:0}" in built_text
    assert CSS_MANAGED_BEGIN in built_text
    assert "--background: #282828 !important;" in built_text
    assert "--primary: #83a598 !important;" in built_text


def test_set_wezterm_theme_updates_only_existing_color_scheme(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(Path, "home", lambda: tmp_path)
    path = tmp_path / ".config" / "ooodnakov" / "local" / "wezterm.lua"
    path.parent.mkdir(parents=True)
    path.write_text(
        "local overrides = {\n"
        "  font_size = 14,\n"
        '  color_scheme = "Old Theme",\n'
        "  window_background_opacity = 0.95,\n"
        "}\n"
        "return overrides\n",
        encoding="utf-8",
    )

    result = set_wezterm_theme("catppuccin")

    assert result == "wezterm: updated existing color_scheme -> Catppuccin Mocha"
    assert path.read_text(encoding="utf-8") == (
        "local overrides = {\n"
        "  font_size = 14,\n"
        '  color_scheme = "Catppuccin Mocha",\n'
        "  window_background_opacity = 0.95,\n"
        "}\n"
        "return overrides\n"
    )


def test_set_wezterm_theme_inserts_color_scheme_in_existing_returned_table(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(Path, "home", lambda: tmp_path)
    path = tmp_path / ".config" / "ooodnakov" / "local" / "wezterm.lua"
    path.parent.mkdir(parents=True)
    path.write_text(
        "return {\n  font_size = 14,\n}\n",
        encoding="utf-8",
    )

    result = set_wezterm_theme("gruvbox")

    assert result == "wezterm: inserted color_scheme in returned table -> Gruvbox dark, hard (base16)"
    assert path.read_text(encoding="utf-8") == (
        'return {\n  color_scheme = "Gruvbox dark, hard (base16)",\n  font_size = 14,\n}\n'
    )


def test_set_wezterm_theme_preserves_variable_return_local_override(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(Path, "home", lambda: tmp_path)
    path = tmp_path / ".config" / "ooodnakov" / "local" / "wezterm.lua"
    path.parent.mkdir(parents=True)
    path.write_text(
        "local overrides = {\n  font_size = 14,\n}\nreturn overrides\n",
        encoding="utf-8",
    )

    result = set_wezterm_theme("nord")

    assert result == "wezterm: added color_scheme before final return -> Nord"
    assert path.read_text(encoding="utf-8") == (
        "local overrides = {\n"
        "  font_size = 14,\n"
        "}\n"
        "local __oooconf_local_override = overrides\n"
        '__oooconf_local_override.color_scheme = "Nord"\n'
        "return __oooconf_local_override\n"
    )


def test_set_wezterm_theme_creates_missing_local_override(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(Path, "home", lambda: tmp_path)
    path = tmp_path / ".config" / "ooodnakov" / "local" / "wezterm.lua"

    result = set_wezterm_theme("tokyonight")

    assert result == "wezterm: created local override -> tokyonight_night"
    assert path.read_text(encoding="utf-8") == (
        "-- Generated by `oooconf color`.\n"
        "-- This file overrides managed WezTerm options.\n"
        "return {\n"
        '  color_scheme = "tokyonight_night",\n'
        "}\n"
    )


def test_set_wezterm_theme_inserts_color_scheme_in_commented_returned_table(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(Path, "home", lambda: tmp_path)
    path = tmp_path / ".config" / "ooodnakov" / "local" / "wezterm.lua"
    path.parent.mkdir(parents=True)
    path.write_text(
        "return { -- local overrides\n  font_size = 14,\n}\n",
        encoding="utf-8",
    )

    result = set_wezterm_theme("gruvbox")

    assert result == "wezterm: inserted color_scheme in returned table -> Gruvbox dark, hard (base16)"
    assert path.read_text(encoding="utf-8") == (
        'return { -- local overrides\n  color_scheme = "Gruvbox dark, hard (base16)",\n  font_size = 14,\n}\n'
    )


def test_set_wezterm_theme_preserves_commented_variable_return_local_override(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(Path, "home", lambda: tmp_path)
    path = tmp_path / ".config" / "ooodnakov" / "local" / "wezterm.lua"
    path.parent.mkdir(parents=True)
    path.write_text(
        "local overrides = {\n  font_size = 14,\n}\nreturn overrides -- local overrides\n",
        encoding="utf-8",
    )

    result = set_wezterm_theme("nord")

    assert result == "wezterm: added color_scheme before final return -> Nord"
    assert path.read_text(encoding="utf-8") == (
        "local overrides = {\n"
        "  font_size = 14,\n"
        "}\n"
        "local __oooconf_local_override = overrides\n"
        '__oooconf_local_override.color_scheme = "Nord"\n'
        "return __oooconf_local_override\n"
    )


def test_set_wezterm_theme_inserts_color_scheme_in_inline_returned_table(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(Path, "home", lambda: tmp_path)
    path = tmp_path / ".config" / "ooodnakov" / "local" / "wezterm.lua"
    path.parent.mkdir(parents=True)
    path.write_text("return { font_size = 14 } -- local overrides\n", encoding="utf-8")

    result = set_wezterm_theme("tokyonight")

    assert result == "wezterm: inserted color_scheme in inline returned table -> tokyonight_night"
    assert path.read_text(encoding="utf-8") == (
        'return {\n  color_scheme = "tokyonight_night",\n  font_size = 14\n} -- local overrides\n'
    )


def test_set_wezterm_theme_does_not_append_after_unrecognized_return(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(Path, "home", lambda: tmp_path)
    path = tmp_path / ".config" / "ooodnakov" / "local" / "wezterm.lua"
    path.parent.mkdir(parents=True)
    original = "return make_overrides()\n"
    path.write_text(original, encoding="utf-8")

    result = set_wezterm_theme("catppuccin")

    assert result == "wezterm: skipped unrecognized existing return -> Catppuccin Mocha"
    assert path.read_text(encoding="utf-8") == original


def test_set_wezterm_theme_supports_light_mode(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(Path, "home", lambda: tmp_path)

    result = set_wezterm_theme("catppuccin", "light")

    assert result == "wezterm: created local override -> Catppuccin Latte"
    assert 'color_scheme = "Catppuccin Latte"' in (
        tmp_path / ".config" / "ooodnakov" / "local" / "wezterm.lua"
    ).read_text(encoding="utf-8")


def test_zebar_theme_supports_light_mode() -> None:
    vars_map = _zebar_vars_for_css("tokyonight", "light", kebab_case=True)

    assert vars_map["accent"] == "#34548a"
    assert vars_map["workspace-hover-bg"] == "rgba(0, 0, 0, 0.05)"
    assert vars_map["font"] == '"MesloLGSDZ Nerd Font Mono", sans-serif'


def test_set_yazi_theme_forces_selected_light_flavor(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / ".xdg-config"))

    result = set_yazi_theme("catppuccin", "light")

    path = tmp_path / ".xdg-config" / "ooodnakov" / "local" / "yazi" / "theme.toml"
    assert result == f"yazi: wrote local override ({path})"
    assert path.read_text(encoding="utf-8") == (
        "# Generated by `oooconf color`.\n"
        "# Local override for Yazi theme selection.\n"
        "[flavor]\n"
        'dark = "catppuccin-latte"\n'
        'light = "catppuccin-latte"\n'
        '# selected-mode = "light"\n'
    )


def test_set_yazi_theme_forces_selected_dark_flavor(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / ".xdg-config"))

    set_yazi_theme("gruvbox", "dark")

    text = (tmp_path / ".xdg-config" / "ooodnakov" / "local" / "yazi" / "theme.toml").read_text(encoding="utf-8")
    assert 'dark = "gruvbox-dark"' in text
    assert 'light = "gruvbox-dark"' in text
