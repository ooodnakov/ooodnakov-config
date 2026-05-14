#!/usr/bin/env bash
set -euo pipefail

DEFAULT_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_ROOT="${OOODNAKOV_REPO_ROOT:-$DEFAULT_REPO_ROOT}"
PYTHON_LIB="$REPO_ROOT/scripts/lib/python.sh"
SETUP="$REPO_ROOT/scripts/setup/setup.sh"
DELETE="$REPO_ROOT/scripts/setup/delete.sh"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"
GEN_LOCK="$REPO_ROOT/scripts/generate/generate_dependency_lock.py"
UPDATE_PINS="$REPO_ROOT/scripts/update/update-pins.sh"
RENDER_SECRETS="$REPO_ROOT/scripts/generate/render_secrets.py"
AGENTS_TOOL="$REPO_ROOT/scripts/cli/agents_tool.py"
SYNC_COLOR_THEME="$REPO_ROOT/scripts/lib/sync_color_theme.py"
COMMANDS_FILE="$REPO_ROOT/scripts/cli/oooconf-commands.txt"
KNOWN_COMMANDS=()
KNOWN_SHELL_SUBCOMMANDS=(status prompt prompt-style forgit-aliases typo-handling psfzf-tab psfzf-git auto-uv-env)
KNOWN_SHELL_FORGIT_MODES=(plain forgit status)
KNOWN_SHELL_TYPO_MODES=(silent suggest help status)
KNOWN_SHELL_PSFZF_MODES=(enabled disabled status)
KNOWN_SHELL_AUTO_UV_MODES=(enabled quiet status)
KNOWN_SHELL_PROMPT_MODES=(p10k ohmyposh status)
KNOWN_SHELL_PROMPT_STYLE_MODES=(verbose concise status)
KNOWN_COLOR_THEMES=(default catppuccin gruvbox nord tokyonight noctalia)
KNOWN_COLOR_MODES=(dark light)
LOCAL_OVERRIDES_START="# --- LOCAL OVERRIDES START ---"
LOCAL_OVERRIDES_END="# --- LOCAL OVERRIDES END ---"
FORGIT_ALIAS_VAR="OOODNAKOV_FORGIT_ALIAS_MODE"
TYPO_HANDLING_VAR="OOODNAKOV_TYPO_HANDLING_MODE"
PSFZF_TAB_VAR="OOODNAKOV_PSFZF_TAB"
PSFZF_GIT_VAR="OOODNAKOV_PSFZF_GIT"
AUTO_UV_ENV_VAR="AUTO_UV_ENV_QUIET"
OOOCONF_THEME_VAR="OOOCONF_THEME"
OOOCONF_COLOR_MODE_VAR="OOOCONF_COLOR_MODE"
OOOCONF_OMP_CONFIG_VAR="OOOCONF_OMP_CONFIG"
OOOCONF_ZSH_PROMPT_VAR="OOOCONF_ZSH_PROMPT"
OOOCONF_PROMPT_STYLE_VAR="OOOCONF_PROMPT_STYLE"

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

load_known_commands

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
    fail)
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

# shellcheck source=/dev/null
source "$PYTHON_LIB"

run_python() {
  oooconf_run_python "$REPO_ROOT" "$@"
}

visible_error() {
  if [ -t 1 ]; then
    ui_line fail "$*"
  else
    printf '%s\n' "$*" >&2
  fi
}

shell_config_home() {
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/ooodnakov"
}

shell_local_env_zsh_path() {
  printf '%s\n' "$(shell_config_home)/local/env.zsh"
}

shell_local_env_ps1_path() {
  printf '%s\n' "$(shell_config_home)/local/env.ps1"
}

ensure_local_override_file() {
  local target="$1"
  local start_marker="$2"
  local end_marker="$3"

  mkdir -p "$(dirname "$target")"

  if [ ! -f "$target" ]; then
    cat >"$target" <<EOF
$start_marker
# Add machine-specific env vars here. This section is preserved across syncs.
$end_marker
EOF
    return 0
  fi

  if ! grep -Fq "$start_marker" "$target"; then
    cat >>"$target" <<EOF

$start_marker
# Add machine-specific env vars here. This section is preserved across syncs.
$end_marker
EOF
  fi
}

upsert_override_line() {
  local target="$1"
  local variable_name="$2"
  local replacement_line="$3"
  local tmp_file

  ensure_local_override_file "$target" "$LOCAL_OVERRIDES_START" "$LOCAL_OVERRIDES_END"

  tmp_file="$(mktemp)"
  awk \
    -v start="$LOCAL_OVERRIDES_START" \
    -v end="$LOCAL_OVERRIDES_END" \
    -v variable_name="$variable_name" \
    -v replacement_line="$replacement_line" '
      BEGIN {
        in_block = 0
        inserted = 0
      }
      index($0, start) == 1 {
        in_block = 1
        print
        next
      }
      index($0, end) == 1 {
        if (in_block && !inserted) {
          print replacement_line
          inserted = 1
        }
        in_block = 0
        print
        next
      }
      in_block && $0 ~ ("(^export " variable_name "=)|(^\\$env:" variable_name " = )") {
        if (!inserted) {
          print replacement_line
          inserted = 1
        }
        next
      }
      { print }
      END {
        if (!inserted) {
          if (NR > 0) {
            print ""
          }
          print start
          print replacement_line
          print end
        }
      }
    ' "$target" >"$tmp_file"
  mv "$tmp_file" "$target"
}

get_zsh_prompt_mode() {
  local env_zsh mode

  if [ -n "${OOOCONF_ZSH_PROMPT:-}" ]; then
    printf '%s\n' "$OOOCONF_ZSH_PROMPT"
    return 0
  fi

  env_zsh="$(shell_local_env_zsh_path)"
  if [ -f "$env_zsh" ]; then
    mode="$(sed -n "s/^export ${OOOCONF_ZSH_PROMPT_VAR}=\"\([^\"]*\)\"$/\1/p" "$env_zsh" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi
  fi

  printf 'p10k\n'
}

get_prompt_style_mode() {
  local env_zsh env_ps1 mode

  if [ -n "${OOOCONF_PROMPT_STYLE:-}" ]; then
    printf '%s\n' "$OOOCONF_PROMPT_STYLE"
    return 0
  fi

  env_zsh="$(shell_local_env_zsh_path)"
  if [ -f "$env_zsh" ]; then
    mode="$(sed -n "s/^export ${OOOCONF_PROMPT_STYLE_VAR}=\"\([^\"]*\)\"$/\1/p" "$env_zsh" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi
  fi

  env_ps1="$(shell_local_env_ps1_path)"
  if [ -f "$env_ps1" ]; then
    mode="$(sed -n "s/^\$env:${OOOCONF_PROMPT_STYLE_VAR} = '\([^']*\)'$/\1/p" "$env_ps1" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi
  fi

  printf 'verbose\n'
}

get_forgit_alias_mode() {
  local env_zsh mode
  env_zsh="$(shell_local_env_zsh_path)"

  if [ -f "$env_zsh" ]; then
    mode="$(sed -n "s/^export ${FORGIT_ALIAS_VAR}=\"\\([^\"]*\\)\"$/\\1/p" "$env_zsh" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi
  fi

  printf 'plain\n'
}

get_typo_handling_mode() {
  local env_zsh mode

  if [ -n "${OOODNAKOV_TYPO_HANDLING_MODE:-}" ]; then
    printf '%s\n' "$OOODNAKOV_TYPO_HANDLING_MODE"
    return 0
  fi

  env_zsh="$(shell_local_env_zsh_path)"

  if [ -f "$env_zsh" ]; then
    mode="$(sed -n "s/^export ${TYPO_HANDLING_VAR}=\"\\([^\"]*\\)\"$/\\1/p" "$env_zsh" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi
  fi

  printf 'help\n'
}

get_psfzf_tab_mode() {
  local env_ps1 mode
  env_ps1="$(shell_local_env_ps1_path)"

  if [ -f "$env_ps1" ]; then
    mode="$(sed -n "s/^\$env:${PSFZF_TAB_VAR} = '\\([^']*\\)'$/\\1/p" "$env_ps1" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi
  fi

  printf 'enabled\n'
}

get_psfzf_git_mode() {
  local env_ps1 mode
  env_ps1="$(shell_local_env_ps1_path)"

  if [ -f "$env_ps1" ]; then
    mode="$(sed -n "s/^\$env:${PSFZF_GIT_VAR} = '\\([^']*\\)'$/\\1/p" "$env_ps1" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi
  fi

  printf 'enabled\n'
}

get_auto_uv_env_mode() {
  local env_ps1 mode
  env_ps1="$(shell_local_env_ps1_path)"

  if [ -f "$env_ps1" ]; then
    if grep -q "^\$env:${AUTO_UV_ENV_VAR} = 1$" "$env_ps1"; then
      printf 'quiet\n'
      return 0
    fi
  fi
  printf 'enabled\n'
}

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

set_zsh_prompt_mode() {
  local mode="$1"
  local env_zsh

  case "$mode" in
    p10k|ohmyposh) ;;
    *)
      visible_error "Invalid zsh prompt mode: $mode"
      visible_error "Expected one of: p10k, ohmyposh"
      return 1
      ;;
  esac

  env_zsh="$(shell_local_env_zsh_path)"
  upsert_override_line "$env_zsh" "$OOOCONF_ZSH_PROMPT_VAR" "export $OOOCONF_ZSH_PROMPT_VAR=\"$mode\""

  ui_line ok "zsh prompt set to $mode"
  ui_line info "zsh: $env_zsh"
  ui_line hint "Open a new zsh session or run: exec zsh"
}

set_prompt_style_mode() {
  local mode="$1"
  local env_zsh env_ps1

  case "$mode" in
    verbose|concise) ;;
    *)
      visible_error "Invalid prompt style: $mode"
      visible_error "Expected one of: verbose, concise"
      return 1
      ;;
  esac

  env_zsh="$(shell_local_env_zsh_path)"
  env_ps1="$(shell_local_env_ps1_path)"

  upsert_override_line "$env_zsh" "$OOOCONF_PROMPT_STYLE_VAR" "export $OOOCONF_PROMPT_STYLE_VAR=\"$mode\""
  upsert_override_line "$env_ps1" "$OOOCONF_PROMPT_STYLE_VAR" "\$env:$OOOCONF_PROMPT_STYLE_VAR = '$mode'"

  ui_line ok "prompt style set to $mode"
  ui_line info "zsh: $env_zsh"
  ui_line info "pwsh: $env_ps1"
  ui_line hint "Open a new shell session to apply the change."
}

set_auto_uv_env_mode() {
  local mode="$1"
  local env_zsh env_ps1 val

  case "$mode" in
    enabled|quiet) ;;
    *)
      visible_error "Invalid auto-uv-env mode: $mode"
      visible_error "Expected one of: enabled, quiet"
      return 1
      ;;
  esac

  env_zsh="$(shell_local_env_zsh_path)"
  env_ps1="$(shell_local_env_ps1_path)"
  [ "$mode" = "quiet" ] && val=1 || val=0

  upsert_override_line "$env_zsh" "$AUTO_UV_ENV_VAR" "export $AUTO_UV_ENV_VAR=\"$val\""
  upsert_override_line "$env_ps1" "$AUTO_UV_ENV_VAR" "\$env:$AUTO_UV_ENV_VAR = $val"

  ui_line ok "auto-uv-env mode set to $mode"
  ui_line info "zsh: $env_zsh"
  ui_line info "pwsh: $env_ps1"
  ui_line hint "Open a new shell session to apply the change."
}

set_forgit_alias_mode() {
  local mode="$1"
  local env_zsh env_ps1

  case "$mode" in
    plain|forgit) ;;
    *)
      visible_error "Invalid forgit alias mode: $mode"
      visible_error "Expected one of: plain, forgit"
      return 1
      ;;
  esac

  env_zsh="$(shell_local_env_zsh_path)"
  env_ps1="$(shell_local_env_ps1_path)"

  upsert_override_line "$env_zsh" "$FORGIT_ALIAS_VAR" "export $FORGIT_ALIAS_VAR=\"$mode\""
  upsert_override_line "$env_ps1" "$FORGIT_ALIAS_VAR" "\$env:$FORGIT_ALIAS_VAR = '$mode'"

  ui_line ok "forgit alias mode set to $mode"
  ui_line info "zsh: $env_zsh"
  ui_line info "pwsh: $env_ps1"
  ui_line hint "Open a new shell or run: exec zsh"
}

set_typo_handling_mode() {
  local mode="$1"
  local env_zsh env_ps1

  case "$mode" in
    silent|suggest|help) ;;
    *)
      visible_error "Invalid typo handling mode: $mode"
      visible_error "Expected one of: silent, suggest, help"
      return 1
      ;;
  esac

  env_zsh="$(shell_local_env_zsh_path)"
  env_ps1="$(shell_local_env_ps1_path)"

  upsert_override_line "$env_zsh" "$TYPO_HANDLING_VAR" "export $TYPO_HANDLING_VAR=\"$mode\""
  upsert_override_line "$env_ps1" "$TYPO_HANDLING_VAR" "\$env:$TYPO_HANDLING_VAR = '$mode'"

  ui_line ok "typo handling mode set to $mode"
  ui_line info "zsh: $env_zsh"
  ui_line info "pwsh: $env_ps1"
  ui_line hint "Open a new shell or run: exec zsh"
}

set_psfzf_tab_mode() {
  local mode="$1"
  local env_ps1

  case "$mode" in
    enabled|disabled) ;;
    *)
      visible_error "Invalid psfzf-tab mode: $mode"
      visible_error "Expected one of: enabled, disabled"
      return 1
      ;;
  esac

  env_ps1="$(shell_local_env_ps1_path)"
  upsert_override_line "$env_ps1" "$PSFZF_TAB_VAR" "\$env:$PSFZF_TAB_VAR = '$mode'"

  ui_line ok "psfzf-tab mode set to $mode"
  ui_line info "pwsh: $env_ps1"
  ui_line hint "Open a new shell session to apply the change."
}

set_psfzf_git_mode() {
  local mode="$1"
  local env_ps1

  case "$mode" in
    enabled|disabled) ;;
    *)
      visible_error "Invalid psfzf-git mode: $mode"
      visible_error "Expected one of: enabled, disabled"
      return 1
      ;;
  esac

  env_ps1="$(shell_local_env_ps1_path)"
  upsert_override_line "$env_ps1" "$PSFZF_GIT_VAR" "\$env:$PSFZF_GIT_VAR = '$mode'"

  ui_line ok "psfzf-git mode set to $mode"
  ui_line info "pwsh: $env_ps1"
  ui_line hint "Open a new shell session to apply the change."
}

print_shell_status() {
  ui_line info "forgit-aliases: $(get_forgit_alias_mode)"
  ui_line info "typo-handling: $(get_typo_handling_mode)"
  ui_line info "psfzf-tab: $(get_psfzf_tab_mode)"
  ui_line info "psfzf-git: $(get_psfzf_git_mode)"
  ui_line info "prompt: $(get_zsh_prompt_mode)"
  ui_line info "prompt-style: $(get_prompt_style_mode)"
  ui_line info "auto-uv-env: $(get_auto_uv_env_mode)"
}

print_help_for_scope() {
  local scope="${1:-main}"

  case "$scope" in
    shell)
      handle_shell_command help
      ;;
    color)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf color [status|list|<theme>|dark|light]

Set or inspect the oooconf CLI color theme and dark/light mode.
Themes:
  default, catppuccin, gruvbox, nord, tokyonight, noctalia
Modes:
  dark, light
Examples:
  oooconf color status
  oooconf color list
  oooconf color catppuccin
  oooconf color noctalia
  oooconf color light
EOF
      ;;
    *)
      usage
      ;;
  esac
}

report_unknown_command() {
  local subject="$1"
  local suggestion="${2:-}"
  local scope="${3:-main}"
  local mode

  mode="$(get_typo_handling_mode)"
  case "$mode" in
    silent)
      ;;
    suggest)
      if [ -n "$suggestion" ]; then
        visible_error "Did you mean: $suggestion"
      else
        visible_error "$subject"
      fi
      ;;
    help|*)
      visible_error "$subject"
      if [ -n "$suggestion" ]; then
        visible_error "Did you mean: $suggestion"
      fi
      print_help_for_scope "$scope"
      ;;
  esac
}

handle_shell_command() {
  local subcommand="${1:-}"
  local suggestion=""

  case "$subcommand" in
    ""|-h|--help|help)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf shell status
       oooconf shell prompt [p10k|ohmyposh|status]
       oooconf shell prompt-style [verbose|concise|status]
       oooconf shell forgit-aliases [plain|forgit|status]
       oooconf shell typo-handling [silent|suggest|help|status]
       oooconf shell psfzf-tab [enabled|disabled|status]
       oooconf shell psfzf-git [enabled|disabled|status]
       oooconf shell auto-uv-env [enabled|quiet|status]

Manage local shell preferences that live in the preserved LOCAL OVERRIDES block.
Forgit alias modes:
  plain   keep plain git aliases like gd/gco and define glo as git log
  forgit  enable upstream forgit aliases like glo/gd/gco
  status  show the currently configured mode
Typo handling modes:
  silent   exit 1 without printing anything for wrong commands
  suggest  print only the closest suggestion when available
  help     print the unknown command, suggestion, and full help
PSFzf options:
  psfzf-tab  enable or disable fzf-based tab completion in PowerShell
  psfzf-git  enable or disable fzf-based git keybindings in PowerShell
  status     show the currently configured mode
Prompt options:
  prompt        switch only the zsh prompt engine between Powerlevel10k and Oh My Posh
  prompt-style  switch all managed prompts between verbose and concise layouts
  status        show the currently configured mode
Auto UV environment options:
  enabled   show activation/deactivation messages for Python venvs
  quiet     suppress activation/deactivation messages
  status    show the currently configured mode
Examples:
  oooconf shell status
  oooconf shell prompt status
  oooconf shell prompt ohmyposh
  oooconf shell prompt p10k
  oooconf shell prompt-style concise
  oooconf shell forgit-aliases status
  oooconf shell forgit-aliases plain
  oooconf shell forgit-aliases forgit
  oooconf shell typo-handling status
  oooconf shell typo-handling suggest
  oooconf shell typo-handling silent
  oooconf shell psfzf-tab enabled
  oooconf shell psfzf-tab disabled
  oooconf shell psfzf-git status
  oooconf shell auto-uv-env quiet
EOF
      ;;
    status)
      print_shell_status
      ;;

    prompt)
      case "${2:-status}" in
        status)
          get_zsh_prompt_mode
          ;;
        p10k|ohmyposh)
          set_zsh_prompt_mode "$2"
          ;;
        *)
          suggestion="$(suggest_from_list "${2:-}" "${KNOWN_SHELL_PROMPT_MODES[@]}")"
          report_unknown_command "Unknown shell option: ${2:-}" "$suggestion" shell
          return 1
          ;;
      esac
      ;;
    prompt-style)
      case "${2:-status}" in
        status)
          get_prompt_style_mode
          ;;
        verbose|concise)
          set_prompt_style_mode "$2"
          ;;
        *)
          suggestion="$(suggest_from_list "${2:-}" "${KNOWN_SHELL_PROMPT_STYLE_MODES[@]}")"
          report_unknown_command "Unknown shell option: ${2:-}" "$suggestion" shell
          return 1
          ;;
      esac
      ;;
    forgit-aliases)
      case "${2:-status}" in
        status)
          printf '%s\n' "$(get_forgit_alias_mode)"
          ;;
        plain|forgit)
          set_forgit_alias_mode "$2"
          ;;
        *)
          suggestion="$(suggest_from_list "${2:-}" "${KNOWN_SHELL_FORGIT_MODES[@]}")"
          report_unknown_command "Unknown shell option: ${2:-}" "$suggestion" shell
          return 1
          ;;
      esac
      ;;
    typo-handling)
      case "${2:-status}" in
        status)
          printf '%s\n' "$(get_typo_handling_mode)"
          ;;
        silent|suggest|help)
          set_typo_handling_mode "$2"
          ;;
        *)
          suggestion="$(suggest_from_list "${2:-}" "${KNOWN_SHELL_TYPO_MODES[@]}")"
          report_unknown_command "Unknown shell option: ${2:-}" "$suggestion" shell
          return 1
          ;;
      esac
      ;;
    psfzf-tab)
      case "${2:-status}" in
        status)
          get_psfzf_tab_mode
          ;;
        enabled|disabled)
          set_psfzf_tab_mode "$2"
          ;;
        *)
          suggestion="$(suggest_from_list "${2:-}" "${KNOWN_SHELL_PSFZF_MODES[@]}")"
          report_unknown_command "Unknown shell option: ${2:-}" "$suggestion" shell
          return 1
          ;;
      esac
      ;;
    psfzf-git)
      case "${2:-status}" in
        status)
          get_psfzf_git_mode
          ;;
        enabled|disabled)
          set_psfzf_git_mode "$2"
          ;;
        *)
          suggestion="$(suggest_from_list "${2:-}" "${KNOWN_SHELL_PSFZF_MODES[@]}")"
          report_unknown_command "Unknown shell option: ${2:-}" "$suggestion" shell
          return 1
          ;;
      esac
      ;;
    auto-uv-env)
      case "${2:-status}" in
        status)
          get_auto_uv_env_mode
          ;;
        enabled|quiet)
          set_auto_uv_env_mode "$2"
          ;;
        *)
          suggestion="$(suggest_from_list "${2:-}" "${KNOWN_SHELL_AUTO_UV_MODES[@]}")"
          report_unknown_command "Unknown shell option: ${2:-}" "$suggestion" shell
          return 1
          ;;
      esac
      ;;
    *)
      suggestion="$(suggest_from_list "$subcommand" "${KNOWN_SHELL_SUBCOMMANDS[@]}")"
      report_unknown_command "Unknown shell subcommand: $subcommand" "$suggestion" shell
      return 1
      ;;
  esac
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

resolve_command_alias() {
  case "$1" in
    check) printf 'doctor\n' ;;
    preview) printf 'dry-run\n' ;;
    upgrade) printf 'update\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

command_distance() {
  local left="$1"
  local right="$2"

  awk -v left="$left" -v right="$right" '
    BEGIN {
      left_len = length(left)
      right_len = length(right)

      for (i = 0; i <= left_len; i++) {
        dist[i, 0] = i
      }
      for (j = 0; j <= right_len; j++) {
        dist[0, j] = j
      }

      for (i = 1; i <= left_len; i++) {
        left_char = substr(left, i, 1)
        for (j = 1; j <= right_len; j++) {
          right_char = substr(right, j, 1)
          cost = (left_char == right_char) ? 0 : 1

          deletion = dist[i - 1, j] + 1
          insertion = dist[i, j - 1] + 1
          substitution = dist[i - 1, j - 1] + cost

          best = deletion
          if (insertion < best) {
            best = insertion
          }
          if (substitution < best) {
            best = substitution
          }
          dist[i, j] = best
        }
      }

      print dist[left_len, right_len]
    }
  '
}

suggest_command() {
  local input="$1"
  local best_command=""
  local best_distance=999
  local candidate distance threshold

  for candidate in "${KNOWN_COMMANDS[@]}"; do
    distance="$(command_distance "$input" "$candidate")"
    if [ "$distance" -lt "$best_distance" ]; then
      best_distance="$distance"
      best_command="$candidate"
    fi
  done

  threshold=3
  if [ "${#input}" -le 4 ] && [ "$threshold" -gt 2 ]; then
    threshold=2
  fi

  if [ "$best_distance" -le "$threshold" ]; then
    printf '%s\n' "$best_command"
  fi

  return 0
}

suggest_from_list() {
  local input="$1"
  shift
  local candidates=("$@")
  local best_match=""
  local best_distance=999
  local candidate distance threshold

  for candidate in "${candidates[@]}"; do
    distance="$(command_distance "$input" "$candidate")"
    if [ "$distance" -lt "$best_distance" ]; then
      best_distance="$distance"
      best_match="$candidate"
    fi
  done

  threshold=3
  if [ "${#input}" -le 4 ] && [ "$threshold" -gt 2 ]; then
    threshold=2
  fi

  if [ "$best_distance" -le "$threshold" ]; then
    printf '%s\n' "$best_match"
  fi

  return 0
}

print_version() {
  if command -v git >/dev/null 2>&1 && [ -d "$REPO_ROOT/.git" ]; then
    git -C "$REPO_ROOT" describe --always --dirty --tags 2>/dev/null || git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

usage() {
  ui_banner
  ui_spacer
  printf '%s\n' "$(ui_colorize "section" "Usage: oooconf [global options] <command> [command options]")"
  printf '%s\n' "$(ui_colorize "muted" "A reproducible cross-platform dotfiles manager with setup, health checks, secrets, and shell tooling.")"

  ui_spacer
  ui_separator
  ui_section_fancy "version" "Global options"
  cat <<EOF
  -C, --repo-root PATH  run against a specific repo checkout
  -h, --help            show this help
  -n, --dry-run         add --dry-run to install or update
      --yes-optional    auto-accept optional dependency installs
      --skip-deps       skip dependency installation
  -V, --version         show CLI version information
      --print-repo-root print the resolved repo root and exit
EOF

  ui_spacer
  ui_separator
  ui_section_fancy "install" "Setup"
  ui_command_row "bootstrap" "clone/update repo then run install"
  ui_command_row "install" "apply managed config and optional dependency installs"
  ui_command_row "deps" "install optional dependencies only"
  ui_command_row "update" "pull repo with --ff-only, then re-run install"

  ui_spacer
  ui_section_fancy "doctor" "Inspect & Validate"
  ui_command_row "doctor" "validate managed symlinks, shell runtimes, and required commands"
  ui_command_row "dry-run" "preview install flow without mutating filesystem"
  ui_command_row "version" "print CLI version and repo root"

  ui_spacer
  ui_section_fancy "lock" "Manage State"
  ui_command_row "delete" "remove managed links and restore latest backups"
  ui_command_row "remove" "remove managed links only (no backup restore)"
  ui_command_row "lock" "regenerate dependency lock artifacts from pinned refs"
  ui_command_row "update-pins" "compare/update pinned refs and refresh lock artifacts"
  ui_command_row "completions" "regenerate tracked shell completions (autogen + oooconf)"
  ui_command_row "link" "inspect or manage links from the symlink manifest"

  ui_spacer
  ui_section_fancy "shell" "Shell / Secrets / Agents"
  ui_command_row "shell" "manage local shell preferences such as forgit aliases"
  ui_command_row "color" "set a unified oooconf CLI color theme"
  ui_command_row "secrets" "sync or validate local secret env files"
  ui_command_row "agents" "detect/sync/doctor/update AGENTS.md and agent CLI workflows"

  ui_spacer
  ui_separator
  cat <<EOF | ui_render_help_block
Aliases:
  check -> doctor
  preview -> dry-run
  upgrade -> update
Getting help:
  oooconf --help                     show this message
  oooconf help <command>             show command-specific help
  oooconf help secrets               show secrets subcommand help
UI controls:
  OOOCONF_COLOR=always|never|auto    override color output
  OOOCONF_ASCII=1                    force ASCII icons and borders
  OOOCONF_THEME=<theme>              set the CLI color theme for this run
Common workflows:
  # Initial setup on a new machine:
  oooconf bootstrap
  # Preview what install would do:
  oooconf dry-run
  # Apply config and install dependencies:
  oooconf install
  oooconf deps
  # Check if everything is set up correctly:
  oooconf doctor
  # Update to latest config:
  oooconf update
Repo root:
  $REPO_ROOT
EOF
}

command_usage() {
  local command="$1"
  command="$(resolve_command_alias "$command")"
  ui_section "oooconf $command"

  case "$command" in
    bootstrap)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf bootstrap

Clone or update the configured repo checkout, then run the install flow.
This is the recommended first command on a new machine. It handles repo
cloning (if missing), pulls latest changes, and runs the full install.
Environment overrides:
  OOODNAKOV_CONFIG_DIR          custom config directory
  OOODNAKOV_CONFIG_BRANCH       git branch to checkout (default: main)
  OOODNAKOV_CONFIG_REPO_URL     SSH repo URL for git clone
  OOODNAKOV_CONFIG_HTTPS_REPO_URL HTTPS repo URL for git clone
  OOODNAKOV_INTERACTIVE         set to "never" to skip all prompts
Examples:
  oooconf bootstrap
  OOODNAKOV_INTERACTIVE=never oooconf bootstrap
EOF
      ;;
    install)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf install [--dry-run] [--yes-optional] [--skip-deps]

Apply managed config and optional dependency installation.
Creates symlinks from tracked config in home/ to their target locations,
backing up any replaced files. Optionally installs dependencies when
allowed.
Examples:
  oooconf install                      # interactive dependency prompts
  oooconf install --yes-optional       # auto-accept all optional installs
  oooconf install --skip-deps          # apply config without dependency installs
  oooconf install --dry-run            # preview without making changes
EOF
      ;;
    deps)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf deps [--dry-run] [--all] [dependency-key...]

Install optional dependencies only. Without dependency keys, an interactive
gum-based multi-select picker is used when available.
Dependency keys match those defined in deps.lock.json. Common keys include:
bat, delta, eza, fd, fzf, gum, glow, rg, yazi, ffmpeg, jq, p7zip, poppler, zoxide, and others.
Examples:
  oooconf deps                         # interactive picker (when gum available)
  oooconf deps <key...>                # specific tools (see optional-deps.toml for keys)
  oooconf deps --dry-run               # preview installation
  oooconf deps --all                   # install all dependency keys
EOF
      ;;
    update)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf update [--dry-run] [--yes-optional]

Pull the repo with --ff-only, then re-run the install flow.
Use this to update your config to the latest tracked state. It performs
a fast-forward pull only, failing if local changes would prevent it.
Examples:
  oooconf update                       # pull and reinstall
  oooconf update --yes-optional        # also install missing dependencies
  oooconf update --dry-run             # preview pull and install
EOF
      ;;
    doctor)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf doctor

Validate managed symlinks, shell runtimes, and required commands.
Checks that managed config links point to valid targets, key tools are
available on PATH, and pinned zsh runtime checkouts are complete.
Examples:
  oooconf doctor                       # run all checks
EOF
      ;;
    dry-run)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf dry-run

Preview the install flow without mutating the filesystem.
Shows what links would be created, what files would be backed up, and
what dependencies would be installed, without making any changes.
Examples:
  oooconf dry-run                      # preview install
  oooconf --yes-optional dry-run       # preview with dependency installs
EOF
      ;;
    delete)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf delete

Remove managed links and restore the latest backups when available.
Use this to undo the managed config and return to your previous state.
Backup files are stored in ~/.local/state/ooodnakov-config/backups/.
Examples:
  oooconf delete                       # restore from backups
EOF
      ;;
    remove)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf remove

Remove managed links without restoring backups.
Use this when you want to cleanly remove the managed config without
attempting to restore previous configurations.
Examples:
  oooconf remove                       # clean removal
EOF
      ;;
    lock)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf lock

Regenerate dependency lock artifacts from managed tool refs.
Reads pinned versions from scripts/optional-deps.toml and writes
the resolved lock file to deps.lock.json.
Examples:
  oooconf lock                         # regenerate lock artifact
EOF
      ;;
    update-pins)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf update-pins [--apply] [--offline] [--dry-run]

Compare pinned git refs in scripts/optional-deps.toml to upstream HEAD.
Without --apply, reports differences and refreshes lock artifacts. With --apply,
updates pinned refs in the catalog and regenerates lock artifacts.
Examples:
  oooconf update-pins                  # check for pin drift
  oooconf update-pins --apply          # update pins and regenerate lock
  oooconf update-pins --offline --dry-run # validate local catalog parsing
EOF
      ;;
    completions)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf completions [--dry-run]

Regenerate tracked shell completion files:
  - autogen zsh completions under home/.config/ooodnakov/zsh/completions/autogen
  - oooconf command completions for zsh and PowerShell
This does not install dependencies; it only rebuilds completion files.
Examples:
  oooconf completions                  # rebuild tracked completion files
  oooconf completions --dry-run        # preview generation actions
EOF
      ;;
    link)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf link [--dry-run]

Create or update symlinks from tracked config in home/ to their target
locations, backing up any replaced files. Reads from links.toml manifest
with auto-discovery for home/.config, home/.local, and home/.glzr.
Examples:
  oooconf link                       # create/update all manifest links
  oooconf link --dry-run            # preview without making changes
EOF
      ;;
    agents)
      cat <<'EOF' | ui_render_help_block

Usage: oooconf agents <detect|sync|doctor|install|provider|update|mcp|rtk|skills> [options]

Manage shared AGENTS.md instructions and validate configured agent tooling.
Subcommands:
  detect [--json]       detect configured agent CLIs on PATH
  sync [--check] [--materialize-secrets]
                        append/update shared AGENTS.md managed block
  doctor [--strict-config-paths]
                        verify AGENTS.md managed block and default agent config paths
  install [<agent> ...] [--all|--missing] [--check]
                        install missing, selected, or all configured agent CLIs
  update [--check]      update installed agent CLIs (pnpm-based tools use pnpm)
  provider sync minimax [--check] [--region global|china] [--materialize-secrets]
                        configure MiniMax-M2.7 backends for Claude Code, OpenCode, and Codex CLI
  mcp sync|status       synchronize or inspect managed MCP servers
  rtk init [--check]    initialize RTK hooks for detected agents
  mcp add [--name N] [--json JSON] [--multi] [--preview] [--sync-now]
                        add one MCP JSON server entry to shared config
  skills sync [--check] sync configured skill specs across agents
  skills view [--check] [--json]
                        list global shared skills catalog via pnpm dlx
  skills add <source> [--agent gemini] [--sync-now]
                        add one shared skill source (e.g. vercel-labs/agent-skills)
Examples:
  oooconf agents detect                 # list available agent CLIs
  oooconf agents sync --check           # verify AGENTS.md managed sections
  oooconf agents install --check        # preview missing agent CLI installs
  oooconf agents install codex gemini   # install selected agent CLIs
  oooconf agents mcp status             # show managed MCP server status
  oooconf agents provider sync minimax   # configure MiniMax-M2.7 provider backends
  oooconf agents skills view --json     # show shared skills catalog as JSON
EOF
      ;;
    secrets)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf secrets <sync|doctor|list|status|login|unlock|logout|add|remove> [options]

Render or validate local secret env files from the tracked template.
Examples:
  oooconf secrets                      # show current sync/session status
  oooconf secrets login                # choose login method interactively
  oooconf secrets login --method apikey
  oooconf secrets unlock               # prompt for password and save session
  oooconf secrets unlock 'your-password'
  eval "$(oooconf secrets unlock --shell zsh)"
  oooconf secrets sync
  oooconf secrets sync --dry-run
  oooconf secrets ls                   # alias for list
  oooconf secrets list
  oooconf secrets list --resolved
  oooconf secrets status
  oooconf secrets doctor
  oooconf secrets logout
  oooconf secrets add GITHUB_TOKEN bw://item/abc123/password
  oooconf secrets add SOME_URL https://example.com
  oooconf secrets rm GITHUB_TOKEN      # alias for remove
  oooconf secrets remove GITHUB_TOKEN
Environment overrides:
  OOODNAKOV_SECRETS_BACKEND
  OOODNAKOV_BW_SERVER
EOF
      ;;
    shell)
      handle_shell_command help
      ;;
    color)
      handle_color_command help
      ;;
    version)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf version

Print the CLI version (git describe or commit SHA) and resolved repo root.
Examples:
  oooconf version                      # show version and repo path
EOF
      ;;
    ""|-h|--help|help)
      usage
      ;;
    *)
      suggestion="$(suggest_command "$command")"
      report_unknown_command "Unknown command: $command" "$suggestion"
      return 1
      ;;
  esac
}

require_repo_script() {
  local script_path="$1"
  if [ ! -x "$script_path" ]; then
    echo "Required script is missing or not executable: $script_path" >&2
    exit 1
  fi
}

dry_run_requested=0
yes_optional_requested=0
skip_deps_requested=0
all_deps_requested=0
command=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -C|--repo-root)
      [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 1; }
      REPO_ROOT="$2"
      SETUP="$REPO_ROOT/scripts/setup/setup.sh"
      DELETE="$REPO_ROOT/scripts/setup/delete.sh"
      BOOTSTRAP="$REPO_ROOT/bootstrap.sh"
      GEN_LOCK="$REPO_ROOT/scripts/generate/generate_dependency_lock.py"
      UPDATE_PINS="$REPO_ROOT/scripts/update/update-pins.sh"
      RENDER_SECRETS="$REPO_ROOT/scripts/generate/render_secrets.py"
      AGENTS_TOOL="$REPO_ROOT/scripts/cli/agents_tool.py"
      SYNC_COLOR_THEME="$REPO_ROOT/scripts/lib/sync_color_theme.py"
      shift 2
      ;;
    --print-repo-root)
      ui_line info "$REPO_ROOT"
      exit 0
      ;;
    -V|--version)
      ui_line info "oooconf $(print_version)"
      ui_line info "$REPO_ROOT"
      exit 0
      ;;
    -h|--help)
      if [ -n "${2:-}" ] && [[ "${2:-}" != -* ]]; then
        command_usage "$2"
      else
        usage
      fi
      exit 0
      ;;
    -n|--dry-run)
      dry_run_requested=1
      shift
      ;;
    --yes-optional)
      yes_optional_requested=1
      shift
      ;;
    --all)
      all_deps_requested=1
      shift
      ;;
    --skip-deps)
      skip_deps_requested=1
      shift
      ;;
    help)
      command_usage "$(resolve_command_alias "${2:-}")"
      exit 0
      ;;
    version)
      ui_line info "oooconf $(print_version)"
      ui_line info "$REPO_ROOT"
      exit 0
      ;;
    -*)
      visible_error "Unknown option: $1"
      usage >&2
      exit 1
      ;;
    *)
      command="$(resolve_command_alias "$1")"
      shift
      break
      ;;
  esac
done

if [ -z "$command" ]; then
  if [ "$dry_run_requested" -eq 1 ]; then
    command="install"
  else
    usage
    exit 0
  fi
fi

should_normalize_global_flags() {
  case "$1" in
    bootstrap|install|deps|update|doctor|completions|dry-run|delete|remove|lock|update-pins|agents|minimal)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if should_normalize_global_flags "$command"; then
  normalized_args=()
  for arg in "$@"; do
    case "$arg" in
      -n|--dry-run)
        dry_run_requested=1
        ;;
      --yes-optional)
        yes_optional_requested=1
        ;;
      --skip-deps)
        skip_deps_requested=1
        ;;
      --all)        all_deps_requested=1        ;;
      *)
        normalized_args+=("$arg")
        ;;
    esac
  done
  if [ ${#normalized_args[@]} -gt 0 ]; then
    set -- "${normalized_args[@]}"
  else
    set --
  fi
fi

exec_setup_command() {
  local setup_command="$1"
  local supports_dry_run="$2"
  shift 2
  local setup_args=()
  [ "$all_deps_requested" -eq 1 ] && [ "$setup_command" = "deps" ] && setup_args+=("--all")
  setup_args+=("$@")

  require_repo_script "$SETUP"
  if [ "$dry_run_requested" -eq 1 ]; then
    if [ "$supports_dry_run" -ne 1 ]; then
      echo "--dry-run is not supported for $setup_command" >&2
      exit 1
    fi
    if [ "$yes_optional_requested" -eq 1 ]; then
      exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" OOODNAKOV_INSTALL_OPTIONAL=always OOODNAKOV_SKIP_DEPS="$skip_deps_requested" "$SETUP" "$setup_command" --dry-run "${setup_args[@]}"
    fi
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" OOODNAKOV_SKIP_DEPS="$skip_deps_requested" "$SETUP" "$setup_command" --dry-run "${setup_args[@]}"
  fi

  if [ "$yes_optional_requested" -eq 1 ]; then
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" OOODNAKOV_INSTALL_OPTIONAL=always OOODNAKOV_SKIP_DEPS="$skip_deps_requested" "$SETUP" "$setup_command" "${setup_args[@]}"
  fi
  exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" OOODNAKOV_SKIP_DEPS="$skip_deps_requested" "$SETUP" "$setup_command" "${setup_args[@]}"
}

require_no_dry_run() {
  local command_name="$1"
  if [ "$dry_run_requested" -eq 1 ]; then
    echo "--dry-run is not supported for $command_name" >&2
    exit 1
  fi
}

exec_delete_command() {
  local command_name="$1"
  local delete_mode="$2"
  shift 2
  require_no_dry_run "$command_name"
  require_repo_script "$DELETE"
  exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" "$DELETE" "$delete_mode" "$@"
}

case "$command" in
  bootstrap)
    require_no_dry_run bootstrap
    require_repo_script "$BOOTSTRAP"
    exec "$BOOTSTRAP" "$@"
    ;;
  install)
    exec_setup_command install 1 "$@"
    ;;
  deps)
    exec_setup_command deps 1 "$@"
  ;;
  minimal)
    exec "$REPO_ROOT/scripts/setup/minimal-setup.sh"
  ;;

  update)
    exec_setup_command update 1 "$@"
    ;;
  doctor)
    exec_setup_command doctor 0 "$@"
    ;;
  completions)
    exec_setup_command completions 1 "$@"
    ;;
  link)
    run_python "$REPO_ROOT/scripts/link_manager.py" "$@"
    ;;
  dry-run)
    if [ "$dry_run_requested" -eq 1 ]; then
      echo "Use either dry-run or --dry-run, not both" >&2
      exit 1
    fi
    require_repo_script "$SETUP"
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" "$SETUP" install --dry-run "$@"
    ;;
  delete)
    exec_delete_command delete restore "$@"
    ;;
  remove)
    exec_delete_command remove remove "$@"
    ;;
  lock)
    require_no_dry_run lock
    OOODNAKOV_REPO_ROOT="$REPO_ROOT" run_python "$GEN_LOCK" "$@"
    exit $?
    ;;
  update-pins)
    require_no_dry_run update-pins
    require_repo_script "$UPDATE_PINS"
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" "$UPDATE_PINS" "$@"
    ;;
  agents)
    require_no_dry_run agents
    if ! command -v python3 >/dev/null 2>&1; then
      echo "python3 is required for agents command." >&2
      exit 1
    fi
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" python3 "$AGENTS_TOOL" --repo-root "$REPO_ROOT" "$@"
    ;;
  secrets)
    OOODNAKOV_REPO_ROOT="$REPO_ROOT" run_python "$RENDER_SECRETS" --repo-root "$REPO_ROOT" "$@"
    exit $?
    ;;
  shell)
    handle_shell_command "$@"
    ;;
  color)
    handle_color_command "$@"
    ;;
  *)
    suggestion="$(suggest_command "$command")"
    report_unknown_command "Unknown command: $command" "$suggestion"
    exit 1
    ;;
esac
