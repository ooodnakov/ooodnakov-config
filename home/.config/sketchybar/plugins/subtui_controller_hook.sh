#!/usr/bin/env bash

set -euo pipefail

source "$HOME/.config/sketchybar/plugins/colors.sh"

NOWPLAYING_BIN="/opt/homebrew/bin/nowplaying-cli"

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

title="$(clean_value "$("$NOWPLAYING_BIN" get title 2>/dev/null || true)")"
artist="$(clean_value "$("$NOWPLAYING_BIN" get artist 2>/dev/null || true)")"
playback_rate="$(clean_value "$("$NOWPLAYING_BIN" get playbackRate 2>/dev/null || true)")"

if [[ -z "$title" ]]; then
  sketchybar --set subtui \
    drawing=on \
    icon.drawing=on \
    icon.color="$TEXT_GREY" \
    label.drawing=off \
    label=""
  exit 0
fi

label="${artist:+$artist – }$title"

if [[ "$playback_rate" == "0" || "$playback_rate" == "0.0" ]]; then
  sketchybar --set subtui \
    drawing=on \
    icon.drawing=on \
    icon.color="$TEXT_GREY" \
    label.drawing=on \
    label="$label"
else
  sketchybar --set subtui \
    drawing=on \
    icon.drawing=on \
    icon.color="$TEXT_SPOTIFY_GREEN" \
    label.drawing=on \
    label="$label"
fi