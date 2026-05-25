#!/usr/bin/env bash

set -euo pipefail

APP_ID="$1"
APP_NAME="$2"
CURRENT_WORKSPACE=$(aerospace list-workspaces --focused)

scratchpad_dot_on() {
    sketchybar --trigger scratchpad_dot_on >/dev/null 2>&1 || true
}

scratchpad_dot_off() {
    sketchybar --trigger scratchpad_dot_off >/dev/null 2>&1 || true
}

get_window_id() {
    aerospace list-windows --all --format "%{window-id}|%{app-bundle-id}|%{app-name}" |
    awk -F'|' -v app_id="$APP_ID" -v app_name="$APP_NAME" '
        $2 == app_id || $3 == app_name {
            print $1
            exit
        }
    '
}

get_window_id_in_current_workspace() {
    aerospace list-windows --workspace "$CURRENT_WORKSPACE" --format "%{window-id}|%{app-bundle-id}|%{app-name}" |
    awk -F'|' -v app_id="$APP_ID" -v app_name="$APP_NAME" '
        $2 == app_id || $3 == app_name {
            print $1
            exit
        }
    '
}

is_app_closed() {
    ! aerospace list-windows --all --format "%{app-bundle-id}" | grep -Fxq "$APP_ID"
}

is_app_on_current_workspace() {
    aerospace list-windows --workspace "$CURRENT_WORKSPACE" --format "%{app-bundle-id}" |
    grep -Fxq "$APP_ID"
}

focus_app() {
    local app_window_id
    app_window_id=$(get_window_id)

    if [[ -z "$app_window_id" ]]; then
        return 1
    fi

    aerospace move-node-to-workspace "$CURRENT_WORKSPACE" --window-id "$app_window_id"
    aerospace focus --window-id "$app_window_id"

    # Scratchpad is now open/visible.
    scratchpad_dot_on
}

move_app_to_scratchpad() {
    local app_window_id
    app_window_id=$(get_window_id_in_current_workspace)

    if [[ -z "$app_window_id" ]]; then
        return 1
    fi

    aerospace move-node-to-workspace NSP --window-id "$app_window_id"

    # Scratchpad is now hidden.
    scratchpad_dot_off
}

main() {
    if is_app_closed; then
        open -a "$APP_NAME"
        sleep 0.8
        focus_app
    elif is_app_on_current_workspace; then
        move_app_to_scratchpad
    else
        focus_app
    fi
}

main
