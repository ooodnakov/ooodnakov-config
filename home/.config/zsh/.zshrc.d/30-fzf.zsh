# ==========================================
# fzf appearance (zsh-fzf-unified)
# ==========================================

# Theme-owned settings for the zsh-fzf-unified Ctrl-R picker. This file is
# sourced before Oh My Zsh loads plugins, so these values win over the
# plugin defaults (the plugin uses `: ${VAR:=default}` semantics).

# Picker height (~N ≈ at most N rows).
ZSH_FZF_HISTORY_SEARCH_FZF_EXTRA_ARGS='--height=~10'

# Base column palette. Values are SGR parameter strings (everything between
# ESC[ and m). 256-color values need the full `38;5;N` form — a bare `N`
# like '214' is either a basic ANSI code (30-37/90-97) or an ignored
# parameter. Set a variable to '' to leave that field uncolored.
ZFZ_HISTORY_COLOR_EVENT='33'   # event number — yellow
ZFZ_HISTORY_COLOR_DATE='90'    # date — bright black
ZFZ_HISTORY_COLOR_TIME='36'    # time — cyan
ZFZ_HISTORY_COLOR_COMMAND=''   # command text — terminal default

# Follow `oooconf color <theme>` (it persists OOOCONF_THEME in
# ~/.config/ooodnakov/local/env.zsh, exported before this file runs).
# Palette mirrors scripts/cli/cli_ui.py THEME_COLORS:
#   event ← section (theme highlight), date ← muted, time ← info.
case "${OOOCONF_THEME:-}" in
  catppuccin)
    ZFZ_HISTORY_COLOR_EVENT='38;5;111'
    ZFZ_HISTORY_COLOR_DATE='38;5;145'
    ZFZ_HISTORY_COLOR_TIME='38;5;117'
    ;;
  gruvbox)
    ZFZ_HISTORY_COLOR_EVENT='38;5;214'
    ZFZ_HISTORY_COLOR_DATE='38;5;248'
    ZFZ_HISTORY_COLOR_TIME='38;5;109'
    ;;
  nord)
    ZFZ_HISTORY_COLOR_EVENT='38;5;110'
    ZFZ_HISTORY_COLOR_DATE='38;5;146'
    ZFZ_HISTORY_COLOR_TIME='38;5;110'
    ;;
  tokyonight)
    ZFZ_HISTORY_COLOR_EVENT='38;5;111'
    ZFZ_HISTORY_COLOR_DATE='38;5;146'
    ZFZ_HISTORY_COLOR_TIME='38;5;117'
    ;;
  noctalia)
    ZFZ_HISTORY_COLOR_EVENT='38;5;141'
    ZFZ_HISTORY_COLOR_DATE='38;5;146'
    ZFZ_HISTORY_COLOR_TIME='38;5;117'
    ;;
esac
