#!/usr/bin/env bash
# Sourced by scripts/setup/ooodnakov.sh; do not execute directly.

handle_wm_command() {
  local subcommand="${1:-}"
  case "$subcommand" in
    ""|-h|--help|help)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf wm [status|set <wm>|start|stop|reload|bar <action>]

Manage window managers and status bars.
Window managers: komorebi, glazewm, aerospace, omniwm
Bars: zebar, yabs, sketchybar
Examples:
  oooconf wm status              # show current WM and bar
  oooconf wm set komorebi        # set default WM
  oooconf wm set aerospace       # set default WM (macOS)
  oooconf wm start               # start default WM
  oooconf wm bar status         # show bar status
EOF
      ;;
    status)
      detect_wm_status
      ;;
    set)
      if [ -z "${2:-}" ]; then
        visible_error "Usage: oooconf wm set <wm>"
        printf '%s\n' "Available: ${KNOWN_WM_MODES[*]}"
        return 1
      fi
      set_default_wm "$2"
      ;;
    start)
      start_default_wm
      ;;
    stop)
      stop_default_wm
      ;;
    reload)
      reload_default_wm
      ;;
    bar)
      shift
      handle_bar_command "$@"
      ;;
    komorebi)
      shift
      handle_komorebi_command "$@"
      ;;
    *)
      suggestion="$(suggest_from_list "$subcommand" "status set start stop reload bar komorebi")"
      report_unknown_command "Unknown wm subcommand: $subcommand" "$suggestion" wm
      return 1
      ;;
  esac
}

detect_wm_status() {
  local wm=""
  if command -v komorebi >/dev/null 2>&1 && pgrep -x komorebi >/dev/null 2>&1; then
    wm="komorebi"
  elif command -v glazewm >/dev/null 2>&1 && pgrep -x glazewm >/dev/null 2>&1; then
    wm="glazewm"
  elif command -v aerospace >/dev/null 2>&1 && pgrep -x aerospace >/dev/null 2>&1; then
    wm="aerospace"
  elif command -v omniwm >/dev/null 2>&1 && pgrep -x omniwm >/dev/null 2>&1; then
    wm="omniwm"
  fi
  if [ -n "$wm" ]; then
    ui_line info "wm: $wm (running)"
  else
    ui_line warn "wm: no managed window manager running"
  fi

  if command -v sketchybar >/dev/null 2>&1 && pgrep -x sketchybar >/dev/null 2>&1; then
    ui_line info "bar: sketchybar (running)"
  elif command -v yabs >/dev/null 2>&1 && pgrep -x yabs >/dev/null 2>&1; then
    ui_line info "bar: yabs (running)"
  elif command -v zebar >/dev/null 2>&1 && pgrep -x zebar >/dev/null 2>&1; then
    ui_line info "bar: zebar (running)"
  else
    ui_line warn "bar: no managed bar running"
  fi
}

set_default_wm() {
  local wm="$1"
  case "$wm" in
    komorebi|glazewm|aerospace|omniwm) ;;
    *)
      visible_error "Unknown window manager: $wm"
      printf '%s\n' "Available: ${KNOWN_WM_MODES[*]}"
      return 1
      ;;
  esac
  local env_zsh="$(shell_local_env_zsh_path)"
  local env_ps1="$(shell_local_env_ps1_path)"
  upsert_override_line "$env_zsh" "OOODNAKOV_DEFAULT_WM" "export OOODNAKOV_DEFAULT_WM=\"$wm\""
  upsert_override_line "$env_ps1" "OOODNAKOV_DEFAULT_WM" "\$env:OOODNAKOV_DEFAULT_WM = '$wm'"
  ui_line ok "default wm set to $wm"
}

get_default_wm() {
  local env_zsh mode
  env_zsh="$(shell_local_env_zsh_path)"
  if [ -f "$env_zsh" ]; then
    mode="$(sed -n "s/^export OOODNAKOV_DEFAULT_WM=\"\([^\"]*\)\"$/\1/p" "$env_zsh" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi
  fi
  printf 'komorebi\n'
}

start_default_wm() {
  local wm
  wm="$(get_default_wm)"
  case "$wm" in
    komorebi)
      if command -v komorebi >/dev/null 2>&1; then
        komorebi &
        ui_line ok "started komorebi"
      else
        visible_error "komorebi not found on PATH"
        return 1
      fi
      ;;
    glazewm)
      if command -v glazewm >/dev/null 2>&1; then
        glazewm &
        ui_line ok "started glazewm"
      else
        visible_error "glazewm not found on PATH"
        return 1
      fi
      ;;
    aerospace)
      if command -v aerospace >/dev/null 2>&1; then
        aerospace launch-service &
        ui_line ok "started aerospace"
      else
        visible_error "aerospace not found on PATH"
        return 1
      fi
      ;;
    omniwm)
      if command -v omniwm >/dev/null 2>&1; then
        omniwm &
        ui_line ok "started omniwm"
      else
        visible_error "omniwm not found on PATH"
        return 1
      fi
      ;;
  esac
}

stop_default_wm() {
  local wm
  wm="$(get_default_wm)"
  case "$wm" in
    komorebi)
      if pgrep -x komorebi >/dev/null 2>&1; then
        pkill -x komorebi && ui_line ok "stopped komorebi" || visible_error "failed to stop komorebi"
      else
        ui_line warn "komorebi not running"
      fi
      ;;
    glazewm)
      if pgrep -x glazewm >/dev/null 2>&1; then
        pkill -x glazewm && ui_line ok "stopped glazewm" || visible_error "failed to stop glazewm"
      else
        ui_line warn "glazewm not running"
      fi
      ;;
    aerospace)
      if pgrep -x aerospace >/dev/null 2>&1; then
        pkill -x aerospace && ui_line ok "stopped aerospace" || visible_error "failed to stop aerospace"
      else
        ui_line warn "aerospace not running"
      fi
      ;;
    omniwm)
      if pgrep -x omniwm >/dev/null 2>&1; then
        pkill -x omniwm && ui_line ok "stopped omniwm" || visible_error "failed to stop omniwm"
      else
        ui_line warn "omniwm not running"
      fi
      ;;
  esac
}

reload_default_wm() {
  local wm
  wm="$(get_default_wm)"
  stop_default_wm
  sleep 0.5
  start_default_wm
}

handle_komorebi_command() {
  local subcommand="${1:-status}"
  case "$subcommand" in
    status)
      if pgrep -x komorebi >/dev/null 2>&1; then
        ui_line ok "komorebi: running"
      else
        ui_line warn "komorebi: not running"
      fi
      ;;
    start)
      if command -v komorebi >/dev/null 2>&1; then
        komorebi &
        ui_line ok "started komorebi"
      else
        visible_error "komorebi not found on PATH"
        return 1
      fi
      ;;
    stop)
      if pgrep -x komorebi >/dev/null 2>&1; then
        pkill -x komorebi && ui_line ok "stopped komorebi" || visible_error "failed to stop komorebi"
      else
        ui_line warn "komorebi not running"
      fi
      ;;
    reload)
      if pgrep -x komorebi >/dev/null 2>&1; then
        pkill -x komorebi
        sleep 0.5
        komorebi &
        ui_line ok "reloaded komorebi"
      else
        ui_line warn "komorebi not running"
      fi
      ;;
    *)
      suggestion="$(suggest_from_list "$subcommand" "${KNOWN_KOMOREBI_COMMANDS[@]}")"
      report_unknown_command "Unknown komorebi action: $subcommand" "$suggestion" komorebi
      return 1
      ;;
  esac
}
