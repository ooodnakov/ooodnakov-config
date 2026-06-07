#!/bin/sh
set -eu

lock() {
    exec hyprlock --config /home/odnakov/.config/hypr/hyprlock.conf --grace 0 --immediate-render --no-fade-in
}

if [ "${1-}" = "--force" ]; then
    lock
fi

if hyprctl activewindow -j 2>/dev/null | jq -e '((.fullscreen // 0) != 0) or ((.fullscreenClient // 0) != 0) or ((.class // "") | test("^steam_app_"))' >/dev/null 2>&1; then
    [ "${1-}" = "--check" ] && printf '%s\n' 'skip: active fullscreen/game window'
    exit 0
fi

playing=0
statuses=$(playerctl -a status 2>/dev/null || true)
while IFS= read -r status; do
    if [ "$status" = "Playing" ]; then
        playing=1
        break
    fi
done <<EOF
$statuses
EOF

if [ "$playing" -eq 1 ]; then
    [ "${1-}" = "--check" ] && printf '%s\n' 'skip: media playing'
    exit 0
fi

if [ "${1-}" = "--check" ]; then
    printf '%s\n' 'lock: idle allowed'
    exit 0
fi

lock
