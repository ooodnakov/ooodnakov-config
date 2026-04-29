#!/usr/bin/env bash

action="$1"

case "$action" in
  playpause)
    osascript -e 'tell application "System Events" to key code 16'
    ;;
  previous)
    osascript -e 'tell application "System Events" to key code 18'
    ;;
  next)
    osascript -e 'tell application "System Events" to key code 19'
    ;;
  *)
    exit 1
    ;;
esac
