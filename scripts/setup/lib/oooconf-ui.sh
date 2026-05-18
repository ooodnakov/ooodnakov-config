#!/usr/bin/env bash
# Sourced by scripts/setup/ooodnakov.sh; do not execute directly.

load_known_commands() {
  local fallback_commands=(bootstrap install deps update doctor dry-run delete remove lock update-pins completions agents secrets shell color version check preview upgrade minimal)
  local line

  KNOWN_COMMANDS=()
  if [ -f "$COMMANDS_FILE" ]; then
    while IFS= read -r line; do
      case "$line" in
        ""|\#*) continue ;;
      esac
      KNOWN_COMMANDS+=("$line")
    done < "$COMMANDS_FILE"
  fi

  if [ "${#KNOWN_COMMANDS[@]}" -eq 0 ]; then
    KNOWN_COMMANDS=("${fallback_commands[@]}")
  fi
}

ui_is_interactive() {
  [ -t 1 ]
}

ui_use_nerd_font() {
  if [ "${OOOCONF_ASCII:-0}" = "1" ] || ! ui_is_interactive; then
    return 1
  fi
  case "$(ui_stdout_charmap)" in
    utf-8|utf8) return 0 ;;
    *) return 1 ;;
  esac
}

ui_use_color() {
  case "${OOOCONF_COLOR:-auto}" in
    0|false|never) return 1 ;;
    1|true|always) return 0 ;;
  esac
  [ -z "${NO_COLOR:-}" ] && ui_is_interactive
}

ui_stdout_charmap() {
  local map
  map="$(locale charmap 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
  if [ -n "$map" ]; then
    printf '%s\n' "$map"
    return 0
  fi
  printf '%s\n' "unknown"
}

ui_icon() {
  local name="$1"
  case "$name" in
    section) printf '▸' ;;
    ok) printf '✓' ;;
    warn) printf '⚠' ;;
    fail) printf '✗' ;;
    missing) printf '✗' ;;
    info) printf 'ℹ' ;;
    hint) printf '→' ;;
    *) printf '•' ;;
  esac
}

ui_cmd_icon() {
  local name="$1"
  if ui_use_nerd_font; then
    case "$name" in
      bootstrap) printf '󰌠' ;;
      install) printf '󰗠' ;;
      deps) printf '󰏖' ;;
      update) printf '󰚰' ;;
      doctor) printf '󰓙' ;;
      dry-run) printf '󰜉' ;;
      version) printf '󰎆' ;;
      delete) printf '󰩺' ;;
      remove) printf '󱈸' ;;
      lock) printf '󰌾' ;;
      update-pins) printf '󱥂' ;;
      completions) printf '󰩫' ;;
      link) printf '🔗' ;;
      shell) printf '󱆃' ;;
      color) printf '󰏘' ;;
      secrets) printf '󰠮' ;;
      agents) printf '󰭹' ;;
      check) printf '󰓙' ;;
      preview) printf '󰜉' ;;
      upgrade) printf '󰚰' ;;
      *) printf '󰘍' ;;
    esac
  else
    case "$name" in
      bootstrap) printf '[boot]' ;;
      install) printf '[inst]' ;;
      deps) printf '[deps]' ;;
      update) printf '[up]' ;;
      doctor) printf '[doc]' ;;
      dry-run) printf '[dry]' ;;
      version) printf '[ver]' ;;
      delete) printf '[del]' ;;
      remove) printf '[rm]' ;;
      lock) printf '[lock]' ;;
      update-pins) printf '[pins]' ;;
      completions) printf '[comp]' ;;
      link) printf '[link]' ;;
      shell) printf '[sh]' ;;
      color) printf '[clr]' ;;
      secrets) printf '[sec]' ;;
      agents) printf '[agt]' ;;
      check) printf '[doc]' ;;
      preview) printf '[dry]' ;;
      upgrade) printf '[up]' ;;
      *) printf '[cmd]' ;;
    esac
  fi
}

ui_colorize() {
  local role="$1"
  local text="$2"
  local code=""
  local theme
  if ! ui_use_color; then
    printf '%s' "$text"
    return 0
  fi
  if [ -z "${__OOOCONF_THEME_CACHE:-}" ]; then
    __OOOCONF_THEME_CACHE="$(get_oooconf_theme):$(get_oooconf_color_mode)"
  fi
  theme="$__OOOCONF_THEME_CACHE"
  case "$role" in
    section)
      case "$theme" in
        catppuccin:dark) code='1;38;5;111' ;;
        gruvbox:dark) code='1;38;5;214' ;;
        nord:dark) code='1;38;5;110' ;;
        tokyonight:dark) code='1;38;5;111' ;;
        noctalia:dark) code='1;38;5;141' ;;
        catppuccin:light|tokyonight:light|default:light|noctalia:light) code='1;38;5;25' ;;
        gruvbox:light) code='1;38;5;94' ;;
        nord:light) code='1;38;5;24' ;;
        *) code='1;38;5;111' ;;
      esac
      ;;
    ok)
      case "$theme" in
        catppuccin:dark) code='1;38;5;150' ;;
        gruvbox:dark) code='1;38;5;142' ;;
        nord:dark) code='1;38;5;108' ;;
        tokyonight:dark) code='1;38;5;114' ;;
        noctalia:dark) code='1;38;5;110' ;;
        catppuccin:light|gruvbox:light|default:light|noctalia:light) code='1;38;5;64' ;;
        nord:light|tokyonight:light) code='1;38;5;31' ;;
        *) code='1;38;5;78' ;;
      esac
      ;;
    warn)
      case "$theme" in
        catppuccin:dark) code='1;38;5;223' ;;
        gruvbox:dark) code='1;38;5;214' ;;
        nord:dark) code='1;38;5;180' ;;
        tokyonight:dark) code='1;38;5;221' ;;
        noctalia:dark) code='1;38;5;180' ;;
        catppuccin:light|gruvbox:light|tokyonight:light|default:light|noctalia:light) code='1;38;5;130' ;;
        nord:light) code='1;38;5;131' ;;
        *) code='1;38;5;221' ;;
      esac
      ;;
    fail|missing)
      case "$theme" in
        catppuccin:dark) code='1;38;5;203' ;;
        gruvbox:dark) code='1;38;5;167' ;;
        nord:dark) code='1;38;5;174' ;;
        tokyonight:dark) code='1;38;5;203' ;;
        noctalia:dark) code='1;38;5;174' ;;
        catppuccin:light|gruvbox:light|tokyonight:light|default:light|noctalia:light) code='1;38;5;124' ;;
        nord:light) code='1;38;5;131' ;;
        *) code='1;38;5;203' ;;
      esac
      ;;
    outdated)
      case "$theme" in
        catppuccin:dark) code='1;38;5;181' ;;
        gruvbox:dark) code='1;38;5;214' ;;
        nord:dark) code='1;38;5;109' ;;
        tokyonight:dark) code='1;38;5;180' ;;
        noctalia:dark) code='1;38;5;109' ;;
        catppuccin:light|gruvbox:light|tokyonight:light|default:light|noctalia:light) code='1;38;5;130' ;;
        nord:light) code='1;38;5;131' ;;
        *) code='1;38;5;215' ;;
      esac
      ;;
    info)
      case "$theme" in
        catppuccin:dark) code='1;38;5;117' ;;
        gruvbox:dark) code='1;38;5;109' ;;
        nord:dark) code='1;38;5;110' ;;
        tokyonight:dark) code='1;38;5;117' ;;
        noctalia:dark) code='1;38;5;117' ;;
        catppuccin:light|tokyonight:light|default:light|noctalia:light) code='1;38;5;25' ;;
        gruvbox:light) code='1;38;5;24' ;;
        nord:light) code='1;38;5;25' ;;
        *) code='1;38;5;117' ;;
      esac
      ;;
    hint|muted)
      case "$theme" in
        catppuccin:dark) code='38;5;145' ;;
        gruvbox:dark) code='38;5;248' ;;
        nord:dark) code='38;5;146' ;;
        tokyonight:dark) code='38;5;146' ;;
        noctalia:dark) code='38;5;146' ;;
        catppuccin:light|gruvbox:light|nord:light|tokyonight:light|default:light|noctalia:light) code='38;5;59' ;;
        *) code='38;5;245' ;;
      esac
      ;;
    *) code='' ;;
  esac
  if [ -n "$code" ]; then
    printf '\033[%sm%s\033[0m' "$code" "$text"
  else
    printf '%s' "$text"
  fi
}

ui_line() {
  local role="$1"
  shift
  printf '%s %s\n' "$(ui_colorize "$role" "$(ui_icon "$role")")" "$*"
}

ui_repeat_char() {
  local char="$1"
  local count="$2"
  local i

  for ((i = 0; i < count; i += 1)); do
    printf '%s' "$char"
  done
}

ui_banner_row() {
  local text="$1"
  local width="$2"
  local left="$3"
  local right="$4"
  local padding left_padding right_padding

  padding=$((width - ${#text}))
  if [ "$padding" -lt 0 ]; then
    padding=0
  fi
  left_padding=$((padding / 2))
  right_padding=$((padding - left_padding))
  ui_colorize "section" "${left}$(ui_repeat_char ' ' "$left_padding")${text}$(ui_repeat_char ' ' "$right_padding")${right}"
  printf '\n'
}

ui_banner() {
  local width=58
  local horizontal='-'
  local top_left='+'
  local top_right='+'
  local bottom_left='+'
  local bottom_right='+'
  local left='|'
  local right='|'
  local platform_line='Linux / Windows / macOS'

  if ui_use_nerd_font; then
    horizontal='─'
    top_left='┌'
    top_right='┐'
    bottom_left='└'
    bottom_right='┘'
    left='│'
    right='│'
    platform_line='Linux • Windows • macOS'
  fi

  ui_colorize "section" "${top_left}$(ui_repeat_char "$horizontal" "$width")${top_right}"
  printf '\n'
  ui_banner_row "oooconf" "$width" "$left" "$right"
  ui_banner_row "reproducible dotfiles manager" "$width" "$left" "$right"
  ui_banner_row "$platform_line" "$width" "$left" "$right"
  ui_colorize "section" "${bottom_left}$(ui_repeat_char "$horizontal" "$width")${bottom_right}"
  printf '\n'
}

ui_separator() {
  local rule_char='-'
  ui_use_nerd_font && rule_char='─'
  ui_colorize "muted" "$(ui_repeat_char "$rule_char" 54)"
  printf '\n'
}

ui_spacer() {
  printf '\n'
}

ui_section() {
  local title="$1"
  local rule_char='-'
  ui_use_nerd_font && rule_char='─'
  ui_line section "$title"
  ui_colorize muted "$(ui_repeat_char "$rule_char" "$((${#title}+3))")"
  printf '\n'
}

ui_section_fancy() {
  local icon_name="$1"
  local title="$2"
  local rule_char='-'
  local icon_text title_text rule

  ui_use_nerd_font && rule_char='─'
  icon_text="$(ui_colorize "hint" "$(ui_cmd_icon "$icon_name")")"
  title_text="$(ui_colorize "section" "$title")"
  printf '  %s  %s\n' "$icon_text" "$title_text"
  rule="$(ui_repeat_char "$rule_char" "$((${#title}+6))")"
  printf '  %s\n' "$(ui_colorize "muted" "$rule")"
}

ui_command_row() {
  local command_name="$1"
  local description="$2"
  local icon_text command_text description_text padded_command padded_icon

  padded_icon="$(printf '%-6s' "$(ui_cmd_icon "$command_name")")"
  icon_text="$(ui_colorize "hint" "$padded_icon")"
  padded_command="$(printf '%-16s' "$command_name")"
  command_text="$(ui_colorize "info" "$padded_command")"
  description_text="$(ui_colorize "muted" "$description")"
  printf '    %s %s %s\n' "$icon_text" "$command_text" "$description_text"
}

ui_render_help_block() {
  local line
  while IFS= read -r line; do
    case "$line" in
      Usage:*)
        printf '%s\n' "$(ui_colorize "section" "$line")"
        ;;
      Examples:|Environment\ overrides:|Subcommands:|Global\ options:|Mode\ values:|Aliases:|Note:|Getting\ help:|Common\ workflows:|Repo\ root:|UI\ controls:|Themes:|Forgit\ alias\ modes:|Typo\ handling\ modes:|PSFzf\ options:|Prompt\ options:|Auto\ UV\ environment\ options:)
        printf '%s\n' "$(ui_colorize "info" "$line")"
        ;;
      "  oooconf "*|"       oooconf "*|"  OOODNAKOV_"*|"  OOOCONF_"*|"  eval \"\$(oooconf "*|"  ./scripts/"*)
        printf '%s\n' "$(ui_colorize "hint" "$line")"
        ;;
      *)
        printf '%s\n' "$line"
        ;;
    esac
  done
}

visible_error() {
  if [ -t 1 ]; then
    ui_line fail "$*"
  else
    printf '%s\n' "$*" >&2
  fi
}
