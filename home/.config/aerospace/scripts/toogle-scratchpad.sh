#!/usr/bin/env bash
set -euo pipefail

APP_ID="${1:?Bundle ID required}"
APP_NAME="${2:?Application name required}"
SCRATCHPAD_WS="NSP"
CURRENT_WS="$(aerospace list-workspaces --focused)"

LOCK_DIR="${TMPDIR:-/tmp}/aerospace-scratchpad-${APP_ID}.lock"
LAST_ID_FILE="${TMPDIR:-/tmp}/aerospace-scratchpad-${APP_ID}.last"

get_app_ids() {
    aerospace list-windows --all \
        --format '%{window-id}|%{app-bundle-id}' |
        awk -F'|' -v app="$APP_ID" '$2 == app { print $1 }'
}

is_on_current_workspace() {
    aerospace list-windows --workspace "$CURRENT_WS" \
        --format '%{app-bundle-id}' |
        grep -Fxq "$APP_ID"
}

focused_app_id() {
    aerospace list-windows --focused \
        --format '%{window-id}|%{app-bundle-id}' |
        awk -F'|' -v app="$APP_ID" \
            '$2 == app { print $1; exit }'
}

# Prevent concurrent toggle/autohide operations.
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

ids="$(get_app_ids)"
launched=false

if [[ -z "$ids" ]]; then
    open -a "$APP_NAME"
    launched=true

    # Wait for the initial window to become available.
    for ((i = 0; i < 30; i++)); do
        sleep 0.1
        ids="$(get_app_ids)"
        [[ -n "$ids" ]] && break
    done

    if [[ -z "$ids" ]]; then
        echo "No $APP_NAME windows found after launch" >&2
        exit 1
    fi
fi

if [[ "$launched" == false ]] && is_on_current_workspace; then
    # Remember the currently selected tab.
    focused_id="$(focused_app_id)"
    if [[ -n "$focused_id" ]]; then
        printf '%s\n' "$focused_id" > "$LAST_ID_FILE"
    fi

    # Hide ALL tabs.
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        aerospace move-node-to-workspace "$SCRATCHPAD_WS" \
            --window-id "$id"
    done <<< "$ids"

    sketchybar --trigger scratchpad_dot_off >/dev/null 2>&1 || true
else
    # Restore the previously selected tab if it still exists.
    preferred_id="$(cat "$LAST_ID_FILE" 2>/dev/null || true)"
    target_id="${ids%%$'\n'*}"

    if [[ -n "$preferred_id" ]] &&
       grep -Fxq "$preferred_id" <<< "$ids"; then
        target_id="$preferred_id"
    fi

    # Show ALL tabs on the current workspace.
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        aerospace move-node-to-workspace "$CURRENT_WS" \
            --window-id "$id"
    done <<< "$ids"

    aerospace focus --window-id "$target_id"

    sketchybar --trigger scratchpad_dot_on >/dev/null 2>&1 || true
fi