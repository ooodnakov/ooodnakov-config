#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${HOME}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME_DIR/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME_DIR/.local/share}"
BACKUP_ROOT="${OOODNAKOV_BACKUP_ROOT:-$HOME_DIR/.local/state/ooodnakov-config/backups}"
RESTORE_MODE="${1:-restore}"

remove_managed_link() {
  local source="$1"
  local target="$2"

  if [ -L "$target" ]; then
    local current
    current="$(readlink "$target")"
    if [ "$current" = "$source" ]; then
      rm -f "$target"
      echo "removed $target"
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

  ls -1dt "$backup_dir/${target_name}."* 2>/dev/null | head -n 1
}

restore_backup() {
  local target="$1"
  local backup

  backup="$(latest_backup_for "$target" || true)"
  if [ -n "$backup" ] && [ ! -e "$target" ] && [ ! -L "$target" ]; then
    mv "$backup" "$target"
    echo "restored $target"
  fi
}

remove_font_dir() {
  local font_dir="${XDG_DATA_HOME:-$HOME_DIR/.local/share}/fonts/ooodnakov"
  if [ -d "$font_dir" ]; then
    rm -rf "$font_dir"
    echo "removed $font_dir"
  fi
}

usage() {
  cat <<'EOF'
Usage: ./scripts/delete.sh [restore|remove]

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

remove_managed_link "$REPO_ROOT/home/.zshrc" "$HOME_DIR/.zshrc"
remove_managed_link "$REPO_ROOT/home/.config/zsh" "$CONFIG_HOME/zsh"
remove_managed_link "$REPO_ROOT/home/.config/wezterm" "$CONFIG_HOME/wezterm"
remove_managed_link "$REPO_ROOT/home/.config/ooodnakov" "$CONFIG_HOME/ooodnakov"
remove_managed_link "$REPO_ROOT/home/.config/ohmyposh/ooodnakov.omp.json" "$CONFIG_HOME/ohmyposh/ooodnakov.omp.json"
remove_managed_link "$REPO_ROOT/home/.config/powershell/Microsoft.PowerShell_profile.ps1" "$CONFIG_HOME/powershell/Microsoft.PowerShell_profile.ps1"

remove_font_dir

if [ "$RESTORE_MODE" = "restore" ]; then
  restore_backup "$HOME_DIR/.zshrc"
  restore_backup "$CONFIG_HOME/zsh"
  restore_backup "$CONFIG_HOME/wezterm"
  restore_backup "$CONFIG_HOME/ooodnakov"
  restore_backup "$CONFIG_HOME/ohmyposh/ooodnakov.omp.json"
  restore_backup "$CONFIG_HOME/powershell/Microsoft.PowerShell_profile.ps1"
fi

echo
echo "Managed config removed."
echo "Repo checkout was left in place at $REPO_ROOT."
