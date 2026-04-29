#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

WEZTERM_SCHEME_BY_THEME = {
    "default": "Noctalia",
    "catppuccin": "Catppuccin Mocha",
    "gruvbox": "Gruvbox dark, hard (base16)",
    "nord": "Nord",
    "tokyonight": "tokyonight_night",
    "noctalia": "Noctalia",
}

KOMOREBI_THEME_BY_THEME = {
    "default": {"palette": "Base16", "name": "Ashes", "active_border": "Base0D", "unfocused_border": "Base03", "bar_accent": "Base0D", "accent": "Base0D"},
    "catppuccin": {"palette": "Catppuccin", "name": "Mocha", "active_border": "Blue", "unfocused_border": "Surface0", "bar_accent": "Blue", "accent": "Blue"},
    "gruvbox": {"palette": "Gruvbox", "name": "DarkHard", "active_border": "BrightBlue", "unfocused_border": "Bg2", "bar_accent": "BrightBlue", "accent": "BrightBlue"},
    "nord": {"palette": "Nord", "name": "PolarNight", "active_border": "Frost3", "unfocused_border": "PolarNight3", "bar_accent": "Frost3", "accent": "Frost3"},
    "tokyonight": {"palette": "TokyoNight", "name": "Night", "active_border": "Blue", "unfocused_border": "TerminalBlack", "bar_accent": "Blue", "accent": "Blue"},
    "noctalia": {"palette": "Noctalia", "name": "Noctalia", "active_border": "Accent", "unfocused_border": "Panel", "bar_accent": "Accent", "accent": "Accent"},
}

SKETCHYBAR_COLORS_BY_THEME: dict[str, dict[str, str]] = {
    "default": {
        "TEXT_WHITE": "0xFFFBF1C7",
        "TEXT_GREY": "0xFFEBDBB2",
        "TEXT_SPOTIFY_GREEN": "0xFF1DB954",
        "TEXT_RED": "0xFFFB4934",
        "TEXT_ORANGE": "0xFFFABD2F",
        "BACKGROUND": "0xDA3C3836",
        "BACKGROUND_DARK": "0xFF282828",
        "BACKGROUND_DARK_BLUE": "0xFF2F4346",
        "BACKGROUND_DARK_ORANGE": "0xFF5B4314",
        "BACKGROUND_DARK_GREEN": "0xFF4A5423",
        "BACKGROUND_DARK_RED": "0xFF5A2D28",
        "BACKGROUND_DARKER": "0xFF282828",
        "HIGHLIGHT_BACKGROUND": "0xCFB8BB26",
        "TRANSPARENT": "0x00000000",
    },
    "catppuccin": {
        "TEXT_WHITE": "0xFFCDD6F4",
        "TEXT_GREY": "0xFFA6ADC8",
        "TEXT_SPOTIFY_GREEN": "0xFFA6E3A1",
        "TEXT_RED": "0xFFF38BA8",
        "TEXT_ORANGE": "0xFFFAB387",
        "BACKGROUND": "0xDA1E1E2E",
        "BACKGROUND_DARK": "0xFF181825",
        "BACKGROUND_DARK_BLUE": "0xFF313244",
        "BACKGROUND_DARK_ORANGE": "0xFF3A2B2A",
        "BACKGROUND_DARK_GREEN": "0xFF2A3A2A",
        "BACKGROUND_DARK_RED": "0xFF3A242E",
        "BACKGROUND_DARKER": "0xFF11111B",
        "HIGHLIGHT_BACKGROUND": "0xCF89B4FA",
        "TRANSPARENT": "0x00000000",
    },
    "gruvbox": {
        "TEXT_WHITE": "0xFFEBDBB2",
        "TEXT_GREY": "0xFFD5C4A1",
        "TEXT_SPOTIFY_GREEN": "0xFFB8BB26",
        "TEXT_RED": "0xFFFB4934",
        "TEXT_ORANGE": "0xFFFE8019",
        "BACKGROUND": "0xDA3C3836",
        "BACKGROUND_DARK": "0xFF282828",
        "BACKGROUND_DARK_BLUE": "0xFF2F3A42",
        "BACKGROUND_DARK_ORANGE": "0xFF5B4314",
        "BACKGROUND_DARK_GREEN": "0xFF4A5423",
        "BACKGROUND_DARK_RED": "0xFF5A2D28",
        "BACKGROUND_DARKER": "0xFF1D2021",
        "HIGHLIGHT_BACKGROUND": "0xCFB8BB26",
        "TRANSPARENT": "0x00000000",
    },
    "nord": {
        "TEXT_WHITE": "0xFFECEFF4",
        "TEXT_GREY": "0xFFD8DEE9",
        "TEXT_SPOTIFY_GREEN": "0xFFA3BE8C",
        "TEXT_RED": "0xFFBF616A",
        "TEXT_ORANGE": "0xFFD08770",
        "BACKGROUND": "0xDA2E3440",
        "BACKGROUND_DARK": "0xFF3B4252",
        "BACKGROUND_DARK_BLUE": "0xFF434C5E",
        "BACKGROUND_DARK_ORANGE": "0xFF4C3D3A",
        "BACKGROUND_DARK_GREEN": "0xFF3D4A41",
        "BACKGROUND_DARK_RED": "0xFF4B343C",
        "BACKGROUND_DARKER": "0xFF2E3440",
        "HIGHLIGHT_BACKGROUND": "0xCF88C0D0",
        "TRANSPARENT": "0x00000000",
    },
    "tokyonight": {
        "TEXT_WHITE": "0xFFC0CAF5",
        "TEXT_GREY": "0xFFA9B1D6",
        "TEXT_SPOTIFY_GREEN": "0xFF9ECE6A",
        "TEXT_RED": "0xFFF7768E",
        "TEXT_ORANGE": "0xFFFF9E64",
        "BACKGROUND": "0xDA1A1B26",
        "BACKGROUND_DARK": "0xFF16161E",
        "BACKGROUND_DARK_BLUE": "0xFF2F3549",
        "BACKGROUND_DARK_ORANGE": "0xFF4D3324",
        "BACKGROUND_DARK_GREEN": "0xFF2F4530",
        "BACKGROUND_DARK_RED": "0xFF4A2734",
        "BACKGROUND_DARKER": "0xFF11121B",
        "HIGHLIGHT_BACKGROUND": "0xCF7AA2F7",
        "TRANSPARENT": "0x00000000",
    },
    "noctalia": {
        "TEXT_WHITE": "0xFFD8DEE9",
        "TEXT_GREY": "0xFFBAC3D0",
        "TEXT_SPOTIFY_GREEN": "0xFF99CC99",
        "TEXT_RED": "0xFFF2777A",
        "TEXT_ORANGE": "0xFFF99157",
        "BACKGROUND": "0xDA1C2023",
        "BACKGROUND_DARK": "0xFF15181B",
        "BACKGROUND_DARK_BLUE": "0xFF2A3943",
        "BACKGROUND_DARK_ORANGE": "0xFF4D3A2B",
        "BACKGROUND_DARK_GREEN": "0xFF2E4330",
        "BACKGROUND_DARK_RED": "0xFF4D2B32",
        "BACKGROUND_DARKER": "0xFF101316",
        "HIGHLIGHT_BACKGROUND": "0xCF8EB2C7",
        "TRANSPARENT": "0x00000000",
    },
}

ZEBAR_VARS_BY_THEME: dict[str, dict[str, str]] = {
    "default": {
        "bg": "rgba(28, 32, 35, 0.85)", "fg": "#c0c5ce", "accent": "#8eb2c7", "critical": "#f2777a", "warning": "#f99157", "success": "#99cc99",
        "workspace_hover_bg": "rgba(255, 255, 255, 0.06)", "workspace_hover_border": "rgba(142, 178, 199, 0.28)",
        "workspace_focused_bg": "rgba(142, 178, 199, 0.18)", "workspace_focused_border": "rgba(142, 178, 199, 0.45)",
        "workspace_focused_shadow": "rgba(142, 178, 199, 0.18)", "workspace_label_fg": "#1c2023", "workspace_label_bg": "rgba(192, 197, 206, 0.85)",
    },
    "catppuccin": {
        "bg": "rgba(30, 30, 46, 0.85)", "fg": "#cdd6f4", "accent": "#89b4fa", "critical": "#f38ba8", "warning": "#fab387", "success": "#a6e3a1",
        "workspace_hover_bg": "rgba(255, 255, 255, 0.08)", "workspace_hover_border": "rgba(137, 180, 250, 0.35)",
        "workspace_focused_bg": "rgba(137, 180, 250, 0.22)", "workspace_focused_border": "rgba(137, 180, 250, 0.50)",
        "workspace_focused_shadow": "rgba(137, 180, 250, 0.25)", "workspace_label_fg": "#11111b", "workspace_label_bg": "rgba(205, 214, 244, 0.85)",
    },
    "gruvbox": {
        "bg": "rgba(40, 40, 40, 0.85)", "fg": "#ebdbb2", "accent": "#83a598", "critical": "#fb4934", "warning": "#fe8019", "success": "#b8bb26",
        "workspace_hover_bg": "rgba(255, 255, 255, 0.06)", "workspace_hover_border": "rgba(131, 165, 152, 0.32)",
        "workspace_focused_bg": "rgba(131, 165, 152, 0.20)", "workspace_focused_border": "rgba(131, 165, 152, 0.45)",
        "workspace_focused_shadow": "rgba(131, 165, 152, 0.20)", "workspace_label_fg": "#1d2021", "workspace_label_bg": "rgba(235, 219, 178, 0.88)",
    },
    "nord": {
        "bg": "rgba(46, 52, 64, 0.85)", "fg": "#eceff4", "accent": "#88c0d0", "critical": "#bf616a", "warning": "#d08770", "success": "#a3be8c",
        "workspace_hover_bg": "rgba(255, 255, 255, 0.07)", "workspace_hover_border": "rgba(136, 192, 208, 0.32)",
        "workspace_focused_bg": "rgba(136, 192, 208, 0.20)", "workspace_focused_border": "rgba(136, 192, 208, 0.46)",
        "workspace_focused_shadow": "rgba(136, 192, 208, 0.20)", "workspace_label_fg": "#2e3440", "workspace_label_bg": "rgba(236, 239, 244, 0.88)",
    },
    "tokyonight": {
        "bg": "rgba(26, 27, 38, 0.85)", "fg": "#c0caf5", "accent": "#7aa2f7", "critical": "#f7768e", "warning": "#ff9e64", "success": "#9ece6a",
        "workspace_hover_bg": "rgba(255, 255, 255, 0.08)", "workspace_hover_border": "rgba(122, 162, 247, 0.34)",
        "workspace_focused_bg": "rgba(122, 162, 247, 0.22)", "workspace_focused_border": "rgba(122, 162, 247, 0.48)",
        "workspace_focused_shadow": "rgba(122, 162, 247, 0.22)", "workspace_label_fg": "#1a1b26", "workspace_label_bg": "rgba(192, 202, 245, 0.86)",
    },
    "noctalia": {
        "bg": "rgba(28, 32, 35, 0.85)", "fg": "#c0c5ce", "accent": "#8eb2c7", "critical": "#f2777a", "warning": "#f99157", "success": "#99cc99",
        "workspace_hover_bg": "rgba(255, 255, 255, 0.06)", "workspace_hover_border": "rgba(142, 178, 199, 0.28)",
        "workspace_focused_bg": "rgba(142, 178, 199, 0.18)", "workspace_focused_border": "rgba(142, 178, 199, 0.45)",
        "workspace_focused_shadow": "rgba(142, 178, 199, 0.18)", "workspace_label_fg": "#1c2023", "workspace_label_bg": "rgba(192, 197, 206, 0.85)",
    },
}

OMP_REPLACEMENTS_BY_THEME: dict[str, dict[str, str]] = {
    "default": {"#444444": "#444444", "#eeeeee": "#eeeeee", "#0087af": "#0087af", "#5fdf00": "#5fdf00", "#dfaf00": "#dfaf00"},
    "catppuccin": {"#444444": "#313244", "#eeeeee": "#cdd6f4", "#0087af": "#89b4fa", "#5fdf00": "#a6e3a1", "#dfaf00": "#f9e2af"},
    "gruvbox": {"#444444": "#3c3836", "#eeeeee": "#ebdbb2", "#0087af": "#83a598", "#5fdf00": "#b8bb26", "#dfaf00": "#fabd2f"},
    "nord": {"#444444": "#3b4252", "#eeeeee": "#eceff4", "#0087af": "#88c0d0", "#5fdf00": "#a3be8c", "#dfaf00": "#ebcb8b"},
    "tokyonight": {"#444444": "#2f3549", "#eeeeee": "#c0caf5", "#0087af": "#7aa2f7", "#5fdf00": "#9ece6a", "#dfaf00": "#e0af68"},
    "noctalia": {"#444444": "#2a3036", "#eeeeee": "#c0c5ce", "#0087af": "#8eb2c7", "#5fdf00": "#99cc99", "#dfaf00": "#f99157"},
}


def config_home() -> Path:
    return Path.home() / ".config"


def set_yazi_theme(theme: str) -> str:
    path = config_home() / "ooodnakov" / "local" / "yazi" / "theme.toml"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "# Generated by `oooconf color`.\n"
        "# Local override for Yazi theme selection.\n"
        f"dark = \"{theme}\"\n"
        f"light = \"{theme}\"\n",
        encoding="utf-8",
    )
    return f"yazi: wrote local override ({path})"


def set_wezterm_theme(theme: str) -> str:
    scheme = WEZTERM_SCHEME_BY_THEME.get(theme, WEZTERM_SCHEME_BY_THEME["default"])
    path = config_home() / "ooodnakov" / "local" / "wezterm.lua"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "-- Generated by `oooconf color`.\n"
        "-- This file overrides managed WezTerm options.\n"
        "return {\n"
        f'  color_scheme = "{scheme}",\n'
        "}\n",
        encoding="utf-8",
    )
    return f"wezterm: set local override color_scheme -> {scheme}"


def _set_komorebi_theme_file(path: Path, theme: str) -> str:
    if not path.exists():
        return f"{path.name}: skipped ({path} not found)"
    data = json.loads(path.read_text(encoding="utf-8"))
    theme_spec = KOMOREBI_THEME_BY_THEME.get(theme, KOMOREBI_THEME_BY_THEME["default"])
    if isinstance(data, dict):
        data.setdefault("theme", {})
        if isinstance(data["theme"], dict):
            if path.name.endswith(".bar.json"):
                data["theme"]["palette"] = theme_spec["palette"]
                data["theme"]["name"] = theme_spec["name"]
                data["theme"]["accent"] = theme_spec["accent"]
            else:
                data["theme"]["palette"] = theme_spec["palette"]
                data["theme"]["name"] = theme_spec["name"]
                data["theme"]["active_border"] = theme_spec["active_border"]
                data["theme"]["unfocused_border"] = theme_spec["unfocused_border"]
                data["theme"]["bar_accent"] = theme_spec["bar_accent"]
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return f"{path.name}: set theme -> {theme_spec['palette']}/{theme_spec['name']}"


def set_komorebi_theme(theme: str) -> list[str]:
    candidate_paths = [
        Path.home() / "komorebi.json",
        Path.home() / "komorebi.bar.json",
        config_home() / "komorebi" / "komorebi.json",
        config_home() / "komorebi" / "komorebi.bar.json",
    ]
    seen: set[Path] = set()
    results: list[str] = []
    for path in candidate_paths:
        if path in seen:
            continue
        seen.add(path)
        results.append(_set_komorebi_theme_file(path, theme))
    return results


def set_sketchybar_theme(theme: str) -> str:
    palette = SKETCHYBAR_COLORS_BY_THEME.get(theme, SKETCHYBAR_COLORS_BY_THEME["default"])
    root = config_home() / "ooodnakov" / "local" / "sketchybar"
    root.mkdir(parents=True, exist_ok=True)
    lua_path = root / "colors.lua"
    sh_path = root / "colors.sh"

    lua_lines = ["-- Generated by `oooconf color`.", "return {"]
    lua_lines.extend([f"  {key} = {value}," for key, value in palette.items()])
    lua_lines.append("}")
    lua_path.write_text("\n".join(lua_lines) + "\n", encoding="utf-8")

    sh_lines = ["#!/usr/bin/env bash"]
    sh_lines.extend([f"export {key}={value}" for key, value in palette.items()])
    sh_path.write_text("\n".join(sh_lines) + "\n", encoding="utf-8")
    sh_path.chmod(0o755)
    return f"sketchybar: wrote local overrides ({lua_path}, {sh_path})"


def set_zebar_theme(theme: str) -> str:
    vars_map = ZEBAR_VARS_BY_THEME.get(theme, ZEBAR_VARS_BY_THEME["default"])
    zebar_path = Path.home() / ".glzr" / "zebar" / "ooodnakov" / "theme-overrides.css"
    zebar_path.parent.mkdir(parents=True, exist_ok=True)
    lines = [":root {"]
    lines.extend([f"  --{key}: {value};" for key, value in vars_map.items()])
    lines.append("}")
    zebar_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return f"zebar: wrote theme overrides ({zebar_path})"


def _replace_hex_values(value: Any, replacements: dict[str, str]) -> Any:
    if isinstance(value, dict):
        return {k: _replace_hex_values(v, replacements) for k, v in value.items()}
    if isinstance(value, list):
        return [_replace_hex_values(v, replacements) for v in value]
    if isinstance(value, str):
        out = value
        for old, new in replacements.items():
            out = out.replace(old, new)
        return out
    return value


def set_oh_my_posh_theme(theme: str) -> str:
    source = config_home() / "ohmyposh" / "ooodnakov.omp.json"
    if not source.exists():
        return f"oh-my-posh: skipped ({source} not found)"

    replacements = OMP_REPLACEMENTS_BY_THEME.get(theme, OMP_REPLACEMENTS_BY_THEME["default"])
    data = json.loads(source.read_text(encoding="utf-8"))
    themed = _replace_hex_values(data, replacements)
    output = config_home() / "ooodnakov" / "local" / "ohmyposh" / f"{theme}.omp.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(themed, indent=2) + "\n", encoding="utf-8")
    return f"oh-my-posh: wrote themed config ({output})"


def current_status() -> list[str]:
    lines: list[str] = []
    yazi = config_home() / "yazi" / "theme.toml"
    if yazi.exists():
        text = yazi.read_text(encoding="utf-8")
        dark = re.search(r'(?m)^dark\s*=\s*"([^"]+)"', text)
        light = re.search(r'(?m)^light\s*=\s*"([^"]+)"', text)
        lines.append(f"yazi: dark={dark.group(1) if dark else 'unknown'}, light={light.group(1) if light else 'unknown'}")
    wez = config_home() / "ooodnakov" / "local" / "wezterm.lua"
    lines.append(f"wezterm local override: {'present' if wez.exists() else 'missing'} ({wez})")
    wezterm_main = config_home() / "wezterm" / "wezterm.lua"
    if wezterm_main.exists():
        raw = wezterm_main.read_text(encoding="utf-8")
        match = re.search(r'color_scheme\s*=\s*"([^"]+)"', raw)
        if match:
            lines.append(f"wezterm managed config: color_scheme={match.group(1)}")
    kom = config_home() / "komorebi" / "komorebi.json"
    if kom.exists():
        data = json.loads(kom.read_text(encoding="utf-8"))
        theme_name = data.get("theme", {}).get("name", "unknown") if isinstance(data, dict) else "unknown"
        lines.append(f"komorebi: theme.name={theme_name}")
    nvim = config_home() / "nvim" / "lua" / "plugins" / "colorscheme.lua"
    if nvim.exists():
        raw = nvim.read_text(encoding="utf-8")
        match = re.search(r'colorscheme\s*=\s*"([^"]+)"', raw)
        if match:
            lines.append(f"nvim: colorscheme={match.group(1)}")
    oh_my_posh = config_home() / "ohmyposh" / "ooodnakov.omp.json"
    lines.append(f"oh-my-posh config: {'present' if oh_my_posh.exists() else 'missing'} ({oh_my_posh})")
    oh_my_posh_local = config_home() / "ooodnakov" / "local" / "ohmyposh"
    lines.append(f"oh-my-posh local themes: {'present' if oh_my_posh_local.exists() else 'missing'} ({oh_my_posh_local})")
    sketchybar_local = config_home() / "ooodnakov" / "local" / "sketchybar" / "colors.lua"
    lines.append(f"sketchybar local override: {'present' if sketchybar_local.exists() else 'missing'} ({sketchybar_local})")
    zebar_local = Path.home() / ".glzr" / "zebar" / "ooodnakov" / "theme-overrides.css"
    lines.append(f"zebar theme override: {'present' if zebar_local.exists() else 'missing'} ({zebar_local})")
    return lines


def main() -> int:
    parser = argparse.ArgumentParser(prog="sync_color_theme.py")
    parser.add_argument("action", choices=["apply", "status"])
    parser.add_argument("--theme", default="default")
    args = parser.parse_args()

    if args.action == "status":
        for line in current_status():
            print(line)
        return 0

    print(set_yazi_theme(args.theme))
    print(set_wezterm_theme(args.theme))
    for line in set_komorebi_theme(args.theme):
        print(line)
    print(set_sketchybar_theme(args.theme))
    print(set_zebar_theme(args.theme))
    print(set_oh_my_posh_theme(args.theme))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
