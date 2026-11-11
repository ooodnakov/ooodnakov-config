#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOME_DIR="${HOME}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME_DIR/.config}"
BACKUP_ROOT="${OOODNAKOV_BACKUP_ROOT:-$HOME_DIR/.local/state/ooodnakov-config/backups}"
RESTORE_MODE="restore"
DRY_RUN="0"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    restore|remove)
      RESTORE_MODE="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

__DELETE_UI_TTY=0
if [ -t 1 ]; then
  __DELETE_UI_TTY=1
fi

ui_is_interactive() {
  [ "$__DELETE_UI_TTY" = "1" ]
}

ui_use_nerd_font() {
  if [ "${OOOCONF_ASCII:-0}" = "1" ]; then
    return 1
  fi
  if ! ui_is_interactive; then
    return 1
  fi
  if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    return 1
  fi
  if [ "${BASH_VERSINFO[0]:-0}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -lt 2 ]; then
    return 1
  fi
  case "$(locale charmap 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)" in
    utf-8|utf8) return 0 ;;
    *) return 1 ;;
  esac
}

ui_icon() {
  local name="$1"
  if ui_use_nerd_font; then
    case "$name" in
      section) printf '\U0000F054' ;;
      ok) printf '\U0000F00C' ;;
      info) printf '\U0000F05A' ;;
      hint) printf '\U0000F061' ;;
      *) printf '\U0000F057' ;;
    esac
    return 0
  fi
  case "$name" in
    section) printf '%s' '==' ;;
    ok) printf '%s' '[ok]' ;;
    info) printf '%s' '[info]' ;;
    hint) printf '%s' '->' ;;
    *) printf '%s' '[fail]' ;;
  esac
}

ui_colorize() {
  local role="$1"
  local text="$2"
  if [ -n "${NO_COLOR:-}" ] || ! ui_is_interactive; then
    printf '%s' "$text"
    return 0
  fi
  case "$role" in
    ok) printf '\033[1;38;5;78m%s\033[0m' "$text" ;;
    info) printf '\033[1;38;5;117m%s\033[0m' "$text" ;;
    section) printf '\033[1;38;5;111m%s\033[0m' "$text" ;;
    hint) printf '\033[38;5;245m%s\033[0m' "$text" ;;
    muted) printf '\033[38;5;245m%s\033[0m' "$text" ;;
    *) printf '\033[1;38;5;203m%s\033[0m' "$text" ;;
  esac
}

ui_path() {
  local value="$1" role="${2:-info}" leaf dir home_marker='~'
  case "$value" in
    "$HOME_DIR") value="$home_marker" ;;
    "$HOME_DIR"/*) printf -v value '%s/%s' "$home_marker" "${value#"$HOME_DIR"/}" ;;
  esac
  leaf="${value##*/}"
  dir="${value%"$leaf"}"
  if [ -z "$leaf" ] || [ -z "$dir" ]; then
    ui_colorize "$role" "$value"
    return 0
  fi
  printf '%s%s' "$(ui_colorize muted "$dir")" "$(ui_colorize "$role" "$leaf")"
}

ui_line() {
  local role="$1"
  shift
  printf '%s %s\n' "$(ui_colorize "$role" "$(ui_icon "$role")")" "$*"
}

remove_managed_link() {
  local source="$1"
  local target="$2"

  if [ -L "$target" ]; then
    local current
    current="$(readlink "$target")"
    if [ "$current" = "$source" ]; then
      if [ "$DRY_RUN" = "1" ]; then
        ui_line info "[dry-run] Would remove $(ui_path "$target" hint)"
        return 0
      fi
      rm -f "$target"
      ui_line ok "removed $(ui_path "$target" ok)"
    fi
  fi
}

latest_backup_for() {
  local target="$1"
  local target_dir target_name backup_dir

  target_dir="$(dirname "$target")"
  target_name="$(basename "$target")"
  backup_dir="$BACKUP_ROOT$target_dir"

  if [ ! -d "$backup_dir" ]; then
    return 1
  fi

  # shellcheck disable=SC2012
  ls -1dt "$backup_dir/${target_name}."* 2>/dev/null | head -n 1
}

restore_backup() {
  local target="$1"
  local backup

  backup="$(latest_backup_for "$target" || true)"
  if [ -n "$backup" ] && [ ! -e "$target" ] && [ ! -L "$target" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      ui_line info "[dry-run] Would restore $(ui_path "$target" hint) from $(ui_path "$backup" hint)"
      return 0
    fi
    mv "$backup" "$target"
    ui_line ok "restored $(ui_path "$target" ok)"
  fi
}

remove_font_dir() {
  local font_dir="${XDG_DATA_HOME:-$HOME_DIR/.local/share}/fonts/ooodnakov"
  if [ -d "$font_dir" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      ui_line info "[dry-run] Would remove $(ui_path "$font_dir" hint)"
      return 0
    fi
    rm -rf "$font_dir"
    ui_line ok "removed $(ui_path "$font_dir" ok)"
  fi
}

usage() {
  ui_line section "delete"
  cat <<'EOF'
Usage: ./scripts/setup/delete.sh [restore|remove]

Modes:
  restore  remove managed symlinks and restore the latest backups when available
  remove   remove managed symlinks only
EOF
}

case "$RESTORE_MODE" in
  restore|remove)
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

if command -v py > /dev/null 2>&1; then
  while IFS='|' read -r _ source target; do
    [ -z "$target" ] && continue
    remove_managed_link "$source" "$target"
  done < <(py scripts/link_manager.py --repo-root "$REPO_ROOT" --format text 2>/dev/null) || true
else
  # Fallback to hardcoded pairs
  remove_managed_link "$REPO_ROOT/home/.zshrc" "$HOME_DIR/.zshrc"
  remove_managed_link "$REPO_ROOT/home/.config/zsh" "$CONFIG_HOME/zsh"
  remove_managed_link "$REPO_ROOT/home/.config/wezterm" "$CONFIG_HOME/wezterm"
  remove_managed_link "$REPO_ROOT/home/.config/yazi" "$CONFIG_HOME/yazi"
  remove_managed_link "$REPO_ROOT/home/.config/niri" "$CONFIG_HOME/niri"
  remove_managed_link "$REPO_ROOT/home/.config/ooodnakov" "$CONFIG_HOME/ooodnakov"
  remove_managed_link "$REPO_ROOT/home/.config/ohmyposh/ooodnakov.omp.json" "$CONFIG_HOME/ohmyposh/ooodnakov.omp.json"
  remove_managed_link "$REPO_ROOT/home/.config/powershell/Microsoft.PowerShell_profile.ps1" "$CONFIG_HOME/powershell/Microsoft.PowerShell_profile.ps1"
  remove_managed_link "$REPO_ROOT/home/.config/ooodnakov/bin/oooconf" "$HOME_DIR/.local/bin/oooconf"
  remove_managed_link "$REPO_ROOT/home/.config/ooodnakov/bin/o" "$HOME_DIR/.local/bin/o"
fi

remove_font_dir

if [ "$RESTORE_MODE" = "restore" ]; then
  if command -v py > /dev/null 2>&1; then
    while IFS='|' read -r _ source target; do
      [ -z "$target" ] && continue
      restore_backup "$target"
    done < <(py scripts/link_manager.py --repo-root "$REPO_ROOT" --format text 2>/dev/null) || true
  else
    # Fallback to hardcoded targets
    restore_backup "$HOME_DIR/.zshrc"
    restore_backup "$CONFIG_HOME/zsh"
    restore_backup "$CONFIG_HOME/wezterm"
    restore_backup "$CONFIG_HOME/yazi"
    restore_backup "$CONFIG_HOME/niri"
    restore_backup "$CONFIG_HOME/ooodnakov"
    restore_backup "$CONFIG_HOME/ohmyposh/ooodnakov.omp.json"
    restore_backup "$CONFIG_HOME/powershell/Microsoft.PowerShell_profile.ps1"
  fi
fi

echo
ui_line ok "Managed config removed."
ui_line info "Repo checkout was left in place at $(ui_path "$REPO_ROOT" info)."
