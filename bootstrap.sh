#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${OOODNAKOV_CONFIG_REPO_URL:-git@github.com:ooodnakov/ooodnakov-config.git}"
HTTPS_REPO_URL="${OOODNAKOV_CONFIG_HTTPS_REPO_URL:-https://github.com/ooodnakov/ooodnakov-config.git}"
TARGET_DIR="${OOODNAKOV_CONFIG_DIR:-$HOME/src/ooodnakov-config}"
BRANCH="${OOODNAKOV_CONFIG_BRANCH:-main}"
INTERACTIVE="${OOODNAKOV_INTERACTIVE:-auto}"

is_interactive() {
  case "$INTERACTIVE" in
    always) return 0 ;;
    never) return 1 ;;
    auto) [ -t 1 ] && [ -r /dev/tty ] ;;
    *) return 1 ;;
  esac
}

prompt_yes_no() {
  local prompt="$1"
  local reply

  if ! is_interactive; then
    return 1
  fi

  printf "%s [y/N] " "$prompt" > /dev/tty
  read -r reply < /dev/tty
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo apt
  elif command -v dnf >/dev/null 2>&1; then
    echo dnf
  elif command -v pacman >/dev/null 2>&1; then
    echo pacman
  elif command -v zypper >/dev/null 2>&1; then
    echo zypper
  elif command -v brew >/dev/null 2>&1; then
    echo brew
  else
    echo none
  fi
}

install_packages() {
  local manager="$1"
  shift
  case "$manager" in
    apt)
      sudo apt-get update
      sudo apt-get install -y "$@"
      ;;
    dnf)
      sudo dnf install -y "$@"
      ;;
    pacman)
      sudo pacman -Sy --needed --noconfirm "$@"
      ;;
    zypper)
      sudo zypper install -y "$@"
      ;;
    brew)
      HOMEBREW_NO_AUTO_UPDATE=1 brew install "$@"
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_bootstrap_dependencies() {
  local manager
  manager="$(detect_package_manager)"

  if command -v git >/dev/null 2>&1; then
    return 0
  fi

  if [ "$manager" = "none" ]; then
    echo "git is required" >&2
    exit 1
  fi

  if prompt_yes_no "Install git, zsh, and wget before bootstrap?"; then
    install_packages "$manager" git zsh wget
  fi

  if ! command -v git >/dev/null 2>&1; then
    echo "git is required" >&2
    exit 1
  fi
}

ensure_bootstrap_dependencies

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
