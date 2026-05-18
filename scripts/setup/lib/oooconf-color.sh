#!/usr/bin/env bash
# Sourced by scripts/setup/ooodnakov.sh; do not execute directly.

get_oooconf_color_mode() {
  local env_zsh mode

  case "${OOOCONF_COLOR_MODE:-}" in
    dark|light)
      printf '%s\n' "$OOOCONF_COLOR_MODE"
      return 0
      ;;
  esac

  env_zsh="$(shell_local_env_zsh_path)"
  if [ -f "$env_zsh" ]; then
    mode="$(sed -n "s/^export ${OOOCONF_COLOR_MODE_VAR}=\"\([^\"]*\)\"$/\1/p" "$env_zsh" | head -n 1)"
    case "$mode" in
      dark|light)
        printf '%s\n' "$mode"
        return 0
        ;;
    esac
  fi

  printf 'dark\n'
}

get_oooconf_theme() {
  local env_zsh mode

  if [ -n "${OOOCONF_THEME:-}" ]; then
    printf '%s\n' "$OOOCONF_THEME"
    return 0
  fi

  env_zsh="$(shell_local_env_zsh_path)"
  if [ -f "$env_zsh" ]; then
    mode="$(sed -n "s/^export ${OOOCONF_THEME_VAR}=\"\\([^\"]*\\)\"$/\\1/p" "$env_zsh" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi
  fi

  if detect_repo_color_theme; then
    return 0
  fi

  printf 'default\n'
}

detect_repo_color_theme() {
  if [ -f "$REPO_ROOT/home/.config/wezterm/wezterm.lua" ] && grep -q 'Noctalia' "$REPO_ROOT/home/.config/wezterm/wezterm.lua"; then
    printf 'noctalia\n'
    return 0
  fi
  if [ -f "$REPO_ROOT/home/.config/wezterm/config/general.lua" ] && grep -qi 'catppuccin' "$REPO_ROOT/home/.config/wezterm/config/general.lua"; then
    printf 'catppuccin\n'
    return 0
  fi
  if [ -f "$REPO_ROOT/home/.config/nvim/lua/plugins/colorscheme.lua" ] && grep -qi 'catppuccin' "$REPO_ROOT/home/.config/nvim/lua/plugins/colorscheme.lua"; then
    printf 'catppuccin\n'
    return 0
  fi
  return 1
}

set_oooconf_theme() {
  local mode="$1"
  local color_mode="${2:-$(get_oooconf_color_mode)}"
  local env_zsh env_ps1 omp_config_path

  case "$mode" in
    default|catppuccin|gruvbox|nord|tokyonight|noctalia) ;;
    *)
      visible_error "Invalid theme: $mode"
      visible_error "Expected one of: ${KNOWN_COLOR_THEMES[*]}"
      return 1
      ;;
  esac

  case "$color_mode" in
    dark|light) ;;
    *)
      visible_error "Invalid color mode: $color_mode"
      visible_error "Expected one of: ${KNOWN_COLOR_MODES[*]}"
      return 1
      ;;
  esac

  env_zsh="$(shell_local_env_zsh_path)"
  env_ps1="$(shell_local_env_ps1_path)"
  omp_config_path="$(shell_config_home)/local/ohmyposh/${mode}-${color_mode}.omp.json"

  upsert_override_line "$env_zsh" "$OOOCONF_THEME_VAR" "export $OOOCONF_THEME_VAR=\"$mode\""
  upsert_override_line "$env_ps1" "$OOOCONF_THEME_VAR" "\$env:$OOOCONF_THEME_VAR = '$mode'"
  upsert_override_line "$env_zsh" "$OOOCONF_COLOR_MODE_VAR" "export $OOOCONF_COLOR_MODE_VAR=\"$color_mode\""
  upsert_override_line "$env_ps1" "$OOOCONF_COLOR_MODE_VAR" "\$env:$OOOCONF_COLOR_MODE_VAR = '$color_mode'"
  upsert_override_line "$env_zsh" "$OOOCONF_OMP_CONFIG_VAR" "export $OOOCONF_OMP_CONFIG_VAR=\"$omp_config_path\""
  upsert_override_line "$env_ps1" "$OOOCONF_OMP_CONFIG_VAR" "\$env:$OOOCONF_OMP_CONFIG_VAR = '$omp_config_path'"

  __OOOCONF_THEME_CACHE="$mode:$color_mode"

  ui_line ok "oooconf theme set to $mode ($color_mode)"
  ui_line info "zsh: $env_zsh"
  ui_line info "pwsh: $env_ps1"
  OOODNAKOV_REPO_ROOT="$REPO_ROOT" run_python "$SYNC_COLOR_THEME" apply --theme "$mode" --mode "$color_mode"
  ui_line hint "Open a new shell session to apply the theme globally."
}

set_oooconf_color_mode() {
  local color_mode="$1"
  case "$color_mode" in
    dark|light) ;;
    *)
      visible_error "Invalid color mode: $color_mode"
      visible_error "Expected one of: ${KNOWN_COLOR_MODES[*]}"
      return 1
      ;;
  esac
  set_oooconf_theme "$(get_oooconf_theme)" "$color_mode"
}

handle_color_command() {
  local action="${1:-status}"
  case "$action" in
    status)
      printf 'theme=%s\n' "$(get_oooconf_theme)"
      printf 'mode=%s\n' "$(get_oooconf_color_mode)"
      OOODNAKOV_REPO_ROOT="$REPO_ROOT" run_python "$SYNC_COLOR_THEME" status || true
      ;;
    list)
      printf '%s\n' "${KNOWN_COLOR_THEMES[@]}" "${KNOWN_COLOR_MODES[@]}"
      ;;
    help|-h|--help)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf color [status|list|<theme>]

Set or inspect the oooconf CLI color theme.
Themes:
  default, catppuccin, gruvbox, nord, tokyonight, noctalia
Available modes:
  dark, light
This also syncs theme-friendly overrides for yazi, wezterm local override, komorebi/komorebi.bar, sketchybar colors, zebar css vars, and themed oh-my-posh config.
Status output also reports detected nvim and oh-my-posh theme config state.
Examples:
  oooconf color status                 # print current theme and synced config state
  oooconf color list                   # list available themes
  oooconf color catppuccin             # switch to Catppuccin colors
  oooconf color noctalia               # switch to Noctalia colors
EOF
      ;;
    dark|light)
      set_oooconf_color_mode "$action"
      ;;
    *)
      set_oooconf_theme "$action"
      ;;
  esac
}
