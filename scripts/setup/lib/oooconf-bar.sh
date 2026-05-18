#!/usr/bin/env bash
# Sourced by scripts/setup/ooodnakov.sh; do not execute directly.

handle_bar_command() {
  local action="${1:-status}"
  case "$action" in
    status)
      detect_bar_status
      ;;
    set)
      if [ -z "${2:-}" ]; then
        visible_error "Usage: oooconf wm bar set <bar>"
        printf '%s\n' "Available: ${KNOWN_BAR_TYPES[*]}"
        return 1
      fi
      set_default_bar "$2"
      ;;
    start)
      start_default_bar
      ;;
    stop)
      stop_default_bar
      ;;
    reload)
      reload_default_bar
      ;;
    *)
      suggestion="$(suggest_from_list "$action" "status set start stop reload")"
      report_unknown_command "Unknown bar action: $action" "$suggestion" wm.bar
      return 1
      ;;
  esac
}

detect_bar_status() {
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

set_default_bar() {
  local bar="$1"
  case "$bar" in
    zebar|yabs|sketchybar) ;;
    *)
      visible_error "Unknown bar type: $bar"
      printf '%s\n' "Available: ${KNOWN_BAR_TYPES[*]}"
      return 1
      ;;
  esac
  local env_zsh="$(shell_local_env_zsh_path)"
  local env_ps1="$(shell_local_env_ps1_path)"
  upsert_override_line "$env_zsh" "OOODNAKOV_DEFAULT_BAR" "export OOODNAKOV_DEFAULT_BAR=\"$bar\""
  upsert_override_line "$env_ps1" "OOODNAKOV_DEFAULT_BAR" "\$env:OOODNAKOV_DEFAULT_BAR = '$bar'"
  ui_line ok "default bar set to $bar"
}

get_default_bar() {
  local env_zsh mode
  env_zsh="$(shell_local_env_zsh_path)"
  if [ -f "$env_zsh" ]; then
    mode="$(sed -n "s/^export OOODNAKOV_DEFAULT_BAR=\"\([^\"]*\)\"$/\1/p" "$env_zsh" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi
  fi
  printf 'sketchybar\n'
}

start_default_bar() {
  local bar
  bar="$(get_default_bar)"
  case "$bar" in
    sketchybar)
      if command -v sketchybar >/dev/null 2>&1; then
        sketchybar --restart && ui_line ok "started sketchybar" || visible_error "failed to start sketchybar"
      else
        visible_error "sketchybar not found on PATH"
        return 1
      fi
      ;;
    yabs)
      if command -v yabs >/dev/null 2>&1; then
        yabs &
        ui_line ok "started yabs"
      else
        visible_error "yabs not found on PATH"
        return 1
      fi
      ;;
    zebar)
      if command -v zebar >/dev/null 2>&1; then
        zebar &
        ui_line ok "started zebar"
      else
        visible_error "zebar not found on PATH"
        return 1
      fi
      ;;
  esac
}

stop_default_bar() {
  local bar
  bar="$(get_default_bar)"
  case "$bar" in
    sketchybar)
      if pgrep -x sketchybar >/dev/null 2>&1; then
        pkill -x sketchybar && ui_line ok "stopped sketchybar" || visible_error "failed to stop sketchybar"
      else
        ui_line warn "sketchybar not running"
      fi
      ;;
    yabs)
      if pgrep -x yabs >/dev/null 2>&1; then
        pkill -x yabs && ui_line ok "stopped yabs" || visible_error "failed to stop yabs"
      else
        ui_line warn "yabs not running"
      fi
      ;;
    zebar)
      if pgrep -x zebar >/dev/null 2>&1; then
        pkill -x zebar && ui_line ok "stopped zebar" || visible_error "failed to stop zebar"
      else
        ui_line warn "zebar not running"
      fi
      ;;
  esac
}

reload_default_bar() {
  stop_default_bar
  sleep 0.3
  start_default_bar
}
