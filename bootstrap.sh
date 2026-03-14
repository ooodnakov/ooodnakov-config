#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${OOODNAKOV_CONFIG_REPO_URL:-git@github.com:ooodnakov/ooodnakov-config.git}"
HTTPS_REPO_URL="${OOODNAKOV_CONFIG_HTTPS_REPO_URL:-https://github.com/ooodnakov/ooodnakov-config.git}"
TARGET_DIR="${OOODNAKOV_CONFIG_DIR:-$HOME/src/ooodnakov-config}"
BRANCH="${OOODNAKOV_CONFIG_BRANCH:-main}"

if ! command -v git >/dev/null 2>&1; then
  echo "git is required" >&2
  exit 1
fi

mkdir -p "$(dirname "$TARGET_DIR")"

if [ ! -d "$TARGET_DIR/.git" ]; then
  if git ls-remote "$REPO_URL" >/dev/null 2>&1; then
    git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
  else
    git clone --branch "$BRANCH" "$HTTPS_REPO_URL" "$TARGET_DIR"
  fi
else
  git -C "$TARGET_DIR" pull --ff-only
fi

chmod +x "$TARGET_DIR/scripts/setup.sh"
exec "$TARGET_DIR/scripts/setup.sh" install
