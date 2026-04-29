#!/usr/bin/env bash

source "$HOME/.config/sketchybar/plugins/colors.sh"

if ! command -v playerctl >/dev/null 2>&1; then
  sketchybar --set subtui drawing=off
  exit 0
fi

state="$(playerctl --player=subtui status 2>/dev/null | tr '[:upper:]' '[:lower:]')"
artist="$(playerctl --player=subtui metadata xesam:artist 2>/dev/null | head -n1)"
title="$(playerctl --player=subtui metadata xesam:title 2>/dev/null)"

if [ -z "$title" ]; then
  sketchybar --set subtui drawing=off
  exit 0
fi

label="$artist – $title"

if [ "$state" = "paused" ] || [ "$state" = "stopped" ]; then
  sketchybar --set subtui drawing=on icon.color="$TEXT_GREY" label="$label"
  exit 0
fi

sketchybar --set subtui drawing=on icon.color="$TEXT_CYAN" label="$label"
