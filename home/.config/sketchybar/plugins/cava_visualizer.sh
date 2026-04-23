#!/usr/bin/env bash
set -euo pipefail

PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:$PATH"

GRAPH_NAME="${1:-audio}"

cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
state_dir="$cache_home/ooodnakov-config/sketchybar"
pid_file="$state_dir/cava-visualizer.pid"

mkdir -p "$state_dir"

if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
  exit 0
fi

if ! command -v cava >/dev/null 2>&1 || ! command -v sketchybar >/dev/null 2>&1; then
  exit 0
fi

cava_config="${XDG_CONFIG_HOME:-$HOME/.config}/cava/config"

(
  trap 'rm -f "$pid_file"' EXIT

  while true; do
    if cava -p "$cava_config" | while IFS= read -r line; do
      [ -n "$line" ] || continue

      values=()
      IFS=';' read -r -a raw_values <<< "$line"
      for raw_value in "${raw_values[@]}"; do
        [ -n "$raw_value" ] || continue
        normalized="$(awk -v value="$raw_value" 'BEGIN { if (value < 0) value = 0; if (value > 7) value = 7; printf "%.3f", value / 7.0 }')"
        values+=("$normalized")
      done

      if [ "${#values[@]}" -gt 0 ]; then
        sketchybar --push "$GRAPH_NAME" "${values[@]}"
      fi
    done; then
      :
    fi

    sleep 1
  done
) >/dev/null 2>&1 &

echo $! > "$pid_file"
