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

oooconf_is_windows_host() {
  case "$(uname -s 2>/dev/null || printf unknown)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

wm_process_running() {
  local process_name="$1"
  if oooconf_is_windows_host; then
    local image_name="$process_name"
    case "$image_name" in
      *.exe) ;;
      *) image_name="$image_name.exe" ;;
    esac
    command -v tasklist >/dev/null 2>&1 && tasklist //FI "IMAGENAME eq $image_name" 2>/dev/null | grep -Fqi "$image_name"
    return $?
  fi
  command -v pgrep >/dev/null 2>&1 && pgrep -x "$process_name" >/dev/null 2>&1
}

wm_stop_process() {
  local process_name="$1"
  if oooconf_is_windows_host; then
    local image_name="$process_name"
    case "$image_name" in
      *.exe) ;;
      *) image_name="$image_name.exe" ;;
    esac
    command -v taskkill >/dev/null 2>&1 && taskkill //IM "$image_name" //F >/dev/null 2>&1
    return $?
  fi
  command -v pkill >/dev/null 2>&1 && pkill -x "$process_name"
}

start_komorebi_wm() {
  if oooconf_is_windows_host; then
    if command -v komorebic >/dev/null 2>&1; then
      komorebic start --whkd
      ui_line ok "started komorebi"
      return 0
    fi
    visible_error "komorebic not found on PATH"
    return 1
  fi
  if command -v komorebi >/dev/null 2>&1; then
    komorebi &
    ui_line ok "started komorebi"
    return 0
  fi
  visible_error "komorebi not found on PATH"
  return 1
}

stop_komorebi_wm() {
  if oooconf_is_windows_host && command -v komorebic >/dev/null 2>&1; then
    if komorebic stop >/dev/null 2>&1; then
      ui_line ok "stopped komorebi"
      return 0
    fi
  fi
  if wm_process_running komorebi; then
    if wm_stop_process komorebi; then
      ui_line ok "stopped komorebi"
    else
      visible_error "failed to stop komorebi"
    fi
  else
    ui_line warn "komorebi not running"
  fi
}

detect_wm_status() {
  local wm=""
  if wm_process_running komorebi; then
    wm="komorebi"
  elif wm_process_running glazewm; then
    wm="glazewm"
  elif wm_process_running aerospace; then
    wm="aerospace"
  elif wm_process_running omniwm; then
    wm="omniwm"
  fi
  if [ -n "$wm" ]; then
    ui_line info "wm: $wm (running)"
  else
    ui_line warn "wm: no managed window manager running"
  fi

  if wm_process_running sketchybar; then
    ui_line info "bar: sketchybar (running)"
  elif wm_process_running yabs; then
    ui_line info "bar: yabs (running)"
  elif wm_process_running zebar; then
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
  local env_zsh env_ps1
  env_zsh="$(shell_local_env_zsh_path)"
  env_ps1="$(shell_local_env_ps1_path)"
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
      start_komorebi_wm
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
      stop_komorebi_wm
      ;;
    glazewm)
      if wm_process_running glazewm; then
        if wm_stop_process glazewm; then
          ui_line ok "stopped glazewm"
        else
          visible_error "failed to stop glazewm"
        fi
      else
        ui_line warn "glazewm not running"
      fi
      ;;
    aerospace)
      if wm_process_running aerospace; then
        if wm_stop_process aerospace; then
          ui_line ok "stopped aerospace"
        else
          visible_error "failed to stop aerospace"
        fi
      else
        ui_line warn "aerospace not running"
      fi
      ;;
    omniwm)
      if wm_process_running omniwm; then
        if wm_stop_process omniwm; then
          ui_line ok "stopped omniwm"
        else
          visible_error "failed to stop omniwm"
        fi
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
      if wm_process_running komorebi; then
        ui_line ok "komorebi: running"
      else
        ui_line warn "komorebi: not running"
      fi
      ;;
    start)
      start_komorebi_wm
      ;;
    stop)
      stop_komorebi_wm
      ;;
    reload)
      if wm_process_running komorebi; then
        stop_komorebi_wm
        sleep 0.5
        start_komorebi_wm
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
