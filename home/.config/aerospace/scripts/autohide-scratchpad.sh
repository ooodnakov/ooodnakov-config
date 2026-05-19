#!/usr/bin/env bash

set -euo pipefail

APP_ID="$1"
CURRENT_WORKSPACE=$(aerospace list-workspaces --focused)

scratchpad_dot_off() {
    sketchybar --trigger scratchpad_dot_off >/dev/null 2>&1 || true
}

get_app_window_on_current_workspace() {
    aerospace list-windows --workspace "$CURRENT_WORKSPACE" --format "%{window-id}|%{app-bundle-id}" |
    awk -F'|' -v app_id="$APP_ID" '
        $2 == app_id {
            print $1
            exit
        }
    '
}

is_app_focused() {
    aerospace list-windows --focused --format "%{app-bundle-id}" |
    grep -Fxq "$APP_ID"
}

main() {
    # If the scratchpad app is still focused, do nothing.
    if is_app_focused; then
        exit 0
    fi

    local app_window_id
    app_window_id=$(get_app_window_on_current_workspace)

    # If scratchpad app is visible on this workspace but no longer focused,
    # move it back to NSP and hide the dot.
    if [[ -n "$app_window_id" ]]; then
        aerospace move-node-to-workspace NSP --window-id "$app_window_id"
        scratchpad_dot_off
    fi
}

main