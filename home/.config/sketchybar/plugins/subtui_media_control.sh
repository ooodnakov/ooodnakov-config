#!/usr/bin/env bash

action="$1"

case "$action" in
  playpause)
    osascript -e 'tell application "Music" to playpause'
    ;;
  previous)
    osascript -e 'tell application "Music" to previous track'
    ;;
  next)
    osascript -e 'tell application "Music" to next track'
    ;;
  *)
    exit 1
    ;;
esac
