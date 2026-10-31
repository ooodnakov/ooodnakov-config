#!/usr/bin/env bash
# Mirror the focused output into a window.
#
# Umbriel exposes no "focused output" query, so the connector is taken from
# `umbriel workspaces`, which marks the focused workspace with "(focused)" and
# prefixes its output name.

set -euo pipefail

focused_line="$(umbriel workspaces | grep -m1 '(focused)' || true)"

if [[ -z "$focused_line" ]]; then
  echo "umbriel-mirror: umbriel did not report a focused output" >&2
  exit 1
fi

output="${focused_line%%:*}"
output="${output#\*}"
output="${output#"${output%%[![:space:]]*}"}"
output="${output%"${output##*[![:space:]]}"}"

if [[ -z "$output" ]]; then
  echo "umbriel-mirror: could not parse the focused output name" >&2
  exit 1
fi

exec wl-mirror "$output"
