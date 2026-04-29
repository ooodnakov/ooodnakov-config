#!/usr/bin/env bash

source "$HOME/.config/sketchybar/plugins/colors.sh"

# Expected to be triggered by an external subtui hook service.
# - SUBTUI_STATE: playing, paused, stopped
# - SUBTUI_ARTIST: Artist name
# - SUBTUI_TITLE: Track title
state="${SUBTUI_STATE:-}"
artist="${SUBTUI_ARTIST:-}"
title="${SUBTUI_TITLE:-}"

if [ -z "$title" ]; then
  sketchybar --set subtui drawing=off
  exit 0
fi

label="${artist:+$artist – }$title"

if [ "$state" = "paused" ] || [ "$state" = "stopped" ]; then
  sketchybar --set subtui drawing=on icon.color="$TEXT_GREY" label="$label"
  exit 0
fi

sketchybar --set subtui drawing=on icon.color="$TEXT_SPOTIFY_GREEN" label="$label"
