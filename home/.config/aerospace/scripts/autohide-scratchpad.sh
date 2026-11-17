#!/usr/bin/env bash
set -euo pipefail

APP_ID="${1:?Bundle ID required}"
SCRATCHPAD_WS="NSP"

LOCK_DIR="${TMPDIR:-/tmp}/aerospace-scratchpad-${APP_ID}.lock"
LAST_ID_FILE="${TMPDIR:-/tmp}/aerospace-scratchpad-${APP_ID}.last"

# Allow native Ghostty tab focus transitions to settle.
sleep 0.15

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

focused_id="$(
    aerospace list-windows --focused \
        --format '%{window-id}|%{app-bundle-id}' |
        awk -F'|' -v app="$APP_ID" \
            '$2 == app { print $1; exit }'
)"

# Still focused on Ghostty: remember the active tab.
if [[ -n "$focused_id" ]]; then
    printf '%s\n' "$focused_id" > "$LAST_ID_FILE"
    exit 0
fi

# Focus moved away: hide all Ghostty tabs outside NSP.
ids="$(
    aerospace list-windows --all \
        --format '%{window-id}|%{app-bundle-id}|%{workspace}' |
        awk -F'|' -v app="$APP_ID" -v scratch="$SCRATCHPAD_WS" \
            '$2 == app && $3 != scratch { print $1 }'
)"

while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    aerospace move-node-to-workspace "$SCRATCHPAD_WS" \
        --window-id "$id"
done <<< "$ids"

sketchybar --trigger scratchpad_dot_off >/dev/null 2>&1 || true