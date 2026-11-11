#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${OOODNAKOV_CONFIG_REPO_URL:-git@github.com:ooodnakov/ooodnakov-config.git}"
HTTPS_REPO_URL="${OOODNAKOV_CONFIG_HTTPS_REPO_URL:-https://github.com/ooodnakov/ooodnakov-config.git}"
TARGET_DIR="${OOODNAKOV_CONFIG_DIR:-$HOME/src/ooodnakov-config}"
BRANCH="${OOODNAKOV_CONFIG_BRANCH:-main}"
INTERACTIVE="${OOODNAKOV_INTERACTIVE:-auto}"
MINIMAL=0
PASSTHROUGH=()

usage() {
  cat >&2 <<'EOF'
Usage: bootstrap.sh [full|minimal] [--dry-run]

  full       clone the full repository and run the standard install (default)
  minimal    sparse checkout plus the minimal dependency set from [minimal]
             in scripts/optional-deps.toml
  --dry-run  preview install actions without changing the machine

One command for a new machine:
  curl -fsSLo /tmp/ooodnakov-bootstrap.sh https://raw.githubusercontent.com/ooodnakov/ooodnakov-config/main/bootstrap.sh && bash /tmp/ooodnakov-bootstrap.sh minimal

The same script can be inspected before running; never pipe it straight into a shell.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    minimal | --minimal | -m) MINIMAL=1 ;;
    full | install | --full) MINIMAL=0 ;;
    --dry-run) PASSTHROUGH+=("--dry-run") ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

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

collect_missing_bootstrap_dependencies() {
  local cmd
  missing_bootstrap_tools=()

  for cmd in git zsh; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing_bootstrap_tools+=("$cmd")
    fi
  done
}

format_words() {
  local words=("$@")
  local word
  local sep=""

  for word in "${words[@]}"; do
    printf "%s%s" "$sep" "$word"
    sep=", "
  done
}

ensure_bootstrap_dependencies() {
  local manager
  local missing=()
  local still_missing=()

  collect_missing_bootstrap_dependencies
  missing=("${missing_bootstrap_tools[@]}")
  if [ "${#missing[@]}" -eq 0 ]; then
    return 0
  fi

  manager="$(detect_package_manager)"
  if [ "$manager" = "none" ]; then
    echo "Missing required bootstrap tools: $(format_words "${missing[@]}")" >&2
    echo "Install them manually, then re-run bootstrap." >&2
    exit 1
  fi

  if prompt_yes_no "Install missing bootstrap tools ($(format_words "${missing[@]}")) with $manager?"; then
    install_packages "$manager" "${missing[@]}"
  else
    echo "Missing required bootstrap tools: $(format_words "${missing[@]}")" >&2
    echo "Install them manually, then re-run bootstrap." >&2
    exit 1
  fi

  collect_missing_bootstrap_dependencies
  still_missing=("${missing_bootstrap_tools[@]}")
  if [ "${#still_missing[@]}" -ne 0 ]; then
    echo "Bootstrap prerequisites are still missing after install attempt: $(format_words "${still_missing[@]}")" >&2
    exit 1
  fi
}

ensure_bootstrap_dependencies

mkdir -p "$(dirname "$TARGET_DIR")"

if [ ! -d "$TARGET_DIR/.git" ]; then
  if git ls-remote "$REPO_URL" >/dev/null 2>&1; then
    if [ "${MINIMAL:-0}" = "1" ] || [ "${OOODNAKOV_MINIMAL:-0}" = "1" ]; then
      git clone --filter=blob:none --no-checkout --depth 1 "$REPO_URL" "$TARGET_DIR"
      git -C "$TARGET_DIR" sparse-checkout init --cone
      git -C "$TARGET_DIR" sparse-checkout set scripts home/.zshrc home/.config/zsh home/.config/ooodnakov home/.config/ohmyposh home/.config/powershell bootstrap.sh LICENSE
      git -C "$TARGET_DIR" checkout "$BRANCH"
    else
    git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
    fi
  else
    if [ "${MINIMAL:-0}" = "1" ] || [ "${OOODNAKOV_MINIMAL:-0}" = "1" ]; then
      git clone --filter=blob:none --no-checkout --depth 1 "$HTTPS_REPO_URL" "$TARGET_DIR"
      git -C "$TARGET_DIR" sparse-checkout init --cone
      git -C "$TARGET_DIR" sparse-checkout set scripts home/.zshrc home/.config/zsh home/.config/ooodnakov home/.config/ohmyposh home/.config/powershell bootstrap.sh LICENSE
      git -C "$TARGET_DIR" checkout "$BRANCH"
    else
    git clone --branch "$BRANCH" "$HTTPS_REPO_URL" "$TARGET_DIR"
    fi
  fi
else
  git -C "$TARGET_DIR" pull --ff-only
fi

if [ "${MINIMAL:-0}" = "1" ] || [ "${OOODNAKOV_MINIMAL:-0}" = "1" ]; then
  chmod +x "$TARGET_DIR/scripts/setup/minimal-setup.sh"
  install_args=(--yes-optional)
  if [ "${#PASSTHROUGH[@]}" -gt 0 ]; then
    install_args+=("${PASSTHROUGH[@]}")
  fi
  exec "$TARGET_DIR/scripts/setup/minimal-setup.sh" "${install_args[@]}"
else
  chmod +x "$TARGET_DIR/scripts/setup/setup.sh"
  install_args=(install)
  if [ "${#PASSTHROUGH[@]}" -gt 0 ]; then
    install_args+=("${PASSTHROUGH[@]}")
  fi
  exec "$TARGET_DIR/scripts/setup/setup.sh" "${install_args[@]}"
fi
