#!/usr/bin/env bash

set -euo pipefail

NOWPLAYING_BIN="/opt/homebrew/bin/nowplaying-cli"
WEZTERM_BIN="/Applications/WezTerm.app/Contents/MacOS/wezterm"

action="${1:-}"

clean_value() {
  local value="${1:-}"

  case "$value" in
    ""|"null"|"(null)"|"NULL")
      echo ""
      ;;
    *)
      echo "$value"
      ;;
  esac
}

has_nowplaying_track() {
  local title
  title="$(clean_value "$("$NOWPLAYING_BIN" get title 2>/dev/null || true)")"
  [[ -n "$title" ]]
}

open_subtui_in_wezterm() {
  if [[ -x "$WEZTERM_BIN" ]]; then
    "$WEZTERM_BIN" cli spawn -- subtui >/tmp/subtui_wezterm.log 2>&1 || \
      "$WEZTERM_BIN" start -- subtui >/tmp/subtui_wezterm.log 2>&1 &
  else
    open -na WezTerm --args cli spawn -- subtui >/tmp/subtui_wezterm.log 2>&1 || \
      open -na WezTerm --args start -- subtui >/tmp/subtui_wezterm.log 2>&1 &
  fi
}

case "$action" in
  playpause)
    if has_nowplaying_track; then
      "$NOWPLAYING_BIN" togglePlayPause
    else
      open_subtui_in_wezterm
    fi
    ;;
  previous)
    if has_nowplaying_track; then
      "$NOWPLAYING_BIN" previous
    else
      open_subtui_in_wezterm
    fi
    ;;
  next)
    if has_nowplaying_track; then
      "$NOWPLAYING_BIN" next
    else
      open_subtui_in_wezterm
    fi
    ;;
  open)
    open_subtui_in_wezterm
    ;;
  *)
    exit 1
    ;;
esac
