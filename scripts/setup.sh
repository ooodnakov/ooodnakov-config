#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${HOME}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME_DIR/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME_DIR/.local/share}"
STATE_HOME="$DATA_HOME/ooodnakov-config"
FONT_TARGET_DIR="${XDG_DATA_HOME:-$HOME_DIR/.local/share}/fonts/ooodnakov"
COMMAND="${1:-install}"
DRY_RUN=0
BACKUP_ROOT="${OOODNAKOV_BACKUP_ROOT:-$HOME_DIR/.local/state/ooodnakov-config/backups}"
LOG_ROOT="${OOODNAKOV_LOG_ROOT:-$HOME_DIR/.local/state/ooodnakov-config/logs}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
INTERACTIVE="${OOODNAKOV_INTERACTIVE:-auto}"
INSTALL_OPTIONAL="${OOODNAKOV_INSTALL_OPTIONAL:-prompt}"
DEPENDENCY_SUMMARY=()
TOOL_SUMMARY=()
FAILURES=()
PACKAGE_MANAGER=""
APT_UPDATED=0
LOG_FILE=""
LOG_LATEST=""

OH_MY_ZSH_REPO="https://github.com/ohmyzsh/ohmyzsh.git"
OH_MY_ZSH_REF="8df5c1b18b1393dc5046c729094f897bd3636a9b"
P10K_REPO="https://github.com/romkatv/powerlevel10k.git"
P10K_REF="604f19a9eaa18e76db2e60b8d446d5f879065f90"
ZSH_AUTOSUGGESTIONS_REPO="https://github.com/zsh-users/zsh-autosuggestions.git"
ZSH_AUTOSUGGESTIONS_REF="85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5"
ZSH_HIGHLIGHTING_REPO="https://github.com/zsh-users/zsh-syntax-highlighting.git"
ZSH_HIGHLIGHTING_REF="1d85c692615a25fe2293bdd44b34c217d5d2bf04"
ZSH_HISTORY_REPO="https://github.com/zsh-users/zsh-history-substring-search.git"
ZSH_HISTORY_REF="14c8d2e0ffaee98f2df9850b19944f32546fdea5"
ZSH_AUTOCOMPLETE_REPO="https://github.com/marlonrichert/zsh-autocomplete.git"
ZSH_AUTOCOMPLETE_REF="2be4e7f0b435138b0237d4f068b2a882fb06edc4"
FZF_TAB_REPO="https://github.com/Aloxaf/fzf-tab.git"
FZF_TAB_REF="0983009f8666f11e91a2ee1f88cfdb748d14f656"
FORGIT_REPO="https://github.com/wfxr/forgit.git"
FORGIT_REF="7663f3a809bdd19837eb67e4ce607a8162518dee"
YOU_SHOULD_USE_REPO="https://github.com/MichaelAquilina/zsh-you-should-use.git"
YOU_SHOULD_USE_REF="ff371d6a11b653e1fa8dda4e61c896c78de26bfa"
AUTO_UV_ENV_REPO="https://github.com/ashwch/auto-uv-env.git"
AUTO_UV_ENV_REF="76589a0fe4a3eaba9817b7195b9fc05ef4139289"
NVM_REPO="https://github.com/nvm-sh/nvm.git"
NVM_REF="6b307d0c75041ce5f25829b225470540f2711882"
K_REPO="https://github.com/supercrabtree/k.git"
K_REF="e2bfbaf3b8ca92d6ffc4280211805ce4b8a8c19e"
MARKER_REPO="https://github.com/jotyGill/marker.git"
MARKER_REF="c123085891228e51cfa58d555708bad67ed98f02"
TODO_REPO="https://github.com/todotxt/todo.txt-cli.git"
TODO_REF="b20f9b45e210129ef020d3ba212d86b9ba9cf70d"
NEOVIM_MIN_VERSION="0.11.0"
NEOVIM_LINUX_VERSION="0.11.5"
PNPM_VERSION="10.18.3"
BW_VERSION="1.22.1"

is_interactive() {
  case "$INTERACTIVE" in
    always) return 0 ;;
    never) return 1 ;;
    auto) [ -t 1 ] && [ -r /dev/tty ] ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<'EOF'
Usage: ./scripts/setup.sh [install|update|doctor] [--dry-run]

Commands:
  install   apply managed config and dependencies
  update    git pull this repo, then run install flow
  doctor    validate managed links and required tools

Options:
  --dry-run print actions without mutating filesystem
  --yes-optional auto-accept optional dependency installs
EOF
}

initialize_logging() {
  local active_log_root="$LOG_ROOT"

  if ! mkdir -p "$active_log_root" 2>/dev/null; then
    active_log_root="${TMPDIR:-/tmp}/ooodnakov-config-logs"
    mkdir -p "$active_log_root" || {
      LOG_FILE=""
      LOG_LATEST=""
      echo "warning: failed to create log directory under $LOG_ROOT or $active_log_root" >&2
      return 0
    }
  fi

  LOG_FILE="$active_log_root/setup-${COMMAND}-${TIMESTAMP}.log"
  LOG_LATEST="$active_log_root/setup-latest.log"

  if command -v tee >/dev/null 2>&1; then
    exec > >(tee -a "$LOG_FILE") 2>&1
  else
    exec >>"$LOG_FILE" 2>&1
  fi

  ln -sfn "$LOG_FILE" "$LOG_LATEST" 2>/dev/null || cp -f "$LOG_FILE" "$LOG_LATEST"
  echo "Logging to $LOG_FILE"
}

run_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

prompt_yes_no() {
  local prompt="$1"
  local reply

  case "$INSTALL_OPTIONAL" in
    always) return 0 ;;
    never) return 1 ;;
    prompt) ;;
    *) ;;
  esac

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

run_with_spinner() {
  local label="$1"
  shift
  if [ "$DRY_RUN" -eq 1 ]; then
    printf "[dry-run] %s: %s\n" "$label" "$*"
    return 0
  fi
  local logfile pid spinner_index=0
  local -a frames=('-' "\\" '|' '/')

  logfile="$(mktemp)"
  (
    "$@"
  ) >"$logfile" 2>&1 &
  pid=$!

  if is_interactive; then
    while kill -0 "$pid" 2>/dev/null; do
      printf "\r[%s] %s" "${frames[$spinner_index]}" "$label" > /dev/tty
      spinner_index=$(((spinner_index + 1) % ${#frames[@]}))
      sleep 0.12
    done
    printf "\r" > /dev/tty
  fi

  wait "$pid"
  local status=$?

  if [ $status -eq 0 ]; then
    if is_interactive; then
      printf "[ok] %s\n" "$label" > /dev/tty
    else
      printf "[ok] %s\n" "$label"
    fi
  else
    if is_interactive; then
      printf "[failed] %s\n" "$label" > /dev/tty
    else
      printf "[failed] %s\n" "$label"
    fi
    cat "$logfile" >&2
    FAILURES+=("$label")
  fi

  rm -f "$logfile"
  return $status
}

record_failure() {
  local label="$1"
  FAILURES+=("$label")
  printf "[failed] %s\n" "$label" >&2
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
      if [ "$APT_UPDATED" -eq 0 ]; then
        run_with_spinner "Updating apt package index" sudo apt-get -qq update
        APT_UPDATED=1
      fi
      run_with_spinner "Installing packages: $*" sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"
      ;;
    dnf)
      run_with_spinner "Installing packages: $*" sudo dnf install -y "$@"
      ;;
    pacman)
      run_with_spinner "Installing packages: $*" sudo pacman -Sy --needed --noconfirm "$@"
      ;;
    zypper)
      run_with_spinner "Installing packages: $*" sudo zypper install -y "$@"
      ;;
    brew)
      run_with_spinner "Installing packages: $*" env HOMEBREW_NO_AUTO_UPDATE=1 brew install "$@"
      ;;
    *)
      return 1
      ;;
  esac
}

apt_package_available() {
  local package_name="$1"

  if ! command -v apt-cache >/dev/null 2>&1; then
    return 1
  fi

  apt-cache show "$package_name" >/dev/null 2>&1
}

maybe_install_dependency() {
  local manager="$1"
  local command_name="$2"
  local package_name="$3"
  local description="$4"

  if command -v "$command_name" >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("$command_name: present")
    return 0
  fi

  if [ "$manager" = "none" ]; then
    echo "missing optional dependency: $command_name ($description)" >&2
    DEPENDENCY_SUMMARY+=("$command_name: missing (no supported package manager)")
    return 1
  fi

  if [ "$manager" = "apt" ] && ! apt_package_available "$package_name"; then
    if is_interactive; then
      echo "APT package not available: $package_name ($description); skipping automatic install." > /dev/tty
    fi
    DEPENDENCY_SUMMARY+=("$command_name: missing (apt package unavailable)")
    return 0
  fi

  if prompt_yes_no "Install $package_name for $description?"; then
    install_packages "$manager" "$package_name"
    if command -v "$command_name" >/dev/null 2>&1; then
      DEPENDENCY_SUMMARY+=("$command_name: installed")
    else
      DEPENDENCY_SUMMARY+=("$command_name: install attempted")
    fi
  else
    echo "skipping $package_name" >&2
    DEPENDENCY_SUMMARY+=("$command_name: skipped")
  fi
}

normalize_semver() {
  local version="${1#v}"
  version="${version%%-*}"
  printf '%s\n' "$version"
}

version_gte() {
  local left right
  local -a left_parts right_parts
  local i left_value right_value

  left="$(normalize_semver "$1")"
  right="$(normalize_semver "$2")"
  IFS=. read -r -a left_parts <<< "$left"
  IFS=. read -r -a right_parts <<< "$right"

  for i in 0 1 2 3; do
    left_value="${left_parts[$i]:-0}"
    right_value="${right_parts[$i]:-0}"
    if (( left_value > right_value )); then
      return 0
    fi
    if (( left_value < right_value )); then
      return 1
    fi
  done

  return 0
}

get_nvim_version() {
  local nvim_cmd
  nvim_cmd="$(resolve_nvim_command)" || return 1
  "$nvim_cmd" --version 2>/dev/null | awk 'NR == 1 { sub(/^NVIM v/, "", $0); print $0; exit }'
}

resolve_nvim_command() {
  if [ -x "$STATE_HOME/bin/nvim" ]; then
    printf '%s\n' "$STATE_HOME/bin/nvim"
    return 0
  fi

  if command -v nvim >/dev/null 2>&1; then
    command -v nvim
    return 0
  fi

  return 1
}

have_supported_nvim() {
  local version
  version="$(get_nvim_version 2>/dev/null)" || return 1
  [ -n "$version" ] && version_gte "$version" "$NEOVIM_MIN_VERSION"
}

download_to_file() {
  local url="$1"
  local output="$2"

  if command -v curl >/dev/null 2>&1; then
    run_with_spinner "Downloading $(basename "$output")" curl -fL --retry 3 -o "$output" "$url"
  elif command -v wget >/dev/null 2>&1; then
    run_with_spinner "Downloading $(basename "$output")" wget -qO "$output" "$url"
  else
    echo "Neither curl nor wget is available for downloading $url" >&2
    return 1
  fi
}

install_pinned_neovim_linux() {
  local asset_name extracted_dir release_url
  local tools_root install_root bin_dir archive_path

  case "$(uname -m)" in
    x86_64|amd64)
      asset_name="nvim-linux-x86_64.tar.gz"
      extracted_dir="nvim-linux-x86_64"
      ;;
    aarch64|arm64)
      asset_name="nvim-linux-arm64.tar.gz"
      extracted_dir="nvim-linux-arm64"
      ;;
    *)
      echo "Unsupported Linux architecture for pinned Neovim install: $(uname -m)" >&2
      return 1
      ;;
  esac

  release_url="https://github.com/neovim/neovim/releases/download/v${NEOVIM_LINUX_VERSION}/${asset_name}"
  tools_root="$STATE_HOME/tools/neovim"
  install_root="$tools_root/v${NEOVIM_LINUX_VERSION}"
  bin_dir="$STATE_HOME/bin"
  archive_path="${TMPDIR:-/tmp}/${asset_name}"

  run_cmd mkdir -p "$install_root" "$bin_dir" || return 1

  if [ ! -x "$install_root/$extracted_dir/bin/nvim" ]; then
    download_to_file "$release_url" "$archive_path" || return 1
    run_with_spinner "Extracting pinned Neovim v${NEOVIM_LINUX_VERSION}" tar -xzf "$archive_path" -C "$install_root" || return 1
  fi

  run_cmd ln -sfn "$install_root/$extracted_dir/bin/nvim" "$bin_dir/nvim" || return 1
}

maybe_install_neovim() {
  local manager="$1"
  local version_before version_after attempted_package_install=0

  if have_supported_nvim; then
    DEPENDENCY_SUMMARY+=("nvim: present ($(get_nvim_version))")
    return 0
  fi

  version_before="$(get_nvim_version 2>/dev/null || true)"
  if [ -n "$version_before" ] && is_interactive; then
    echo "Detected Neovim $version_before, but LazyVim requires >= $NEOVIM_MIN_VERSION." > /dev/tty
  fi

  if [ "$manager" != "none" ]; then
    if [ "$manager" = "apt" ] && ! apt_package_available "neovim"; then
      if is_interactive; then
        echo "APT package not available: neovim (Neovim runtime for LazyVim); skipping automatic package install." > /dev/tty
      fi
    elif prompt_yes_no "Install neovim package for LazyVim?"; then
      attempted_package_install=1
      install_packages "$manager" neovim
      if have_supported_nvim; then
        DEPENDENCY_SUMMARY+=("nvim: installed ($(get_nvim_version))")
        return 0
      fi
    else
      echo "skipping neovim package" >&2
    fi
  fi

  if [ "$(uname -s)" = "Linux" ]; then
    if [ "$attempted_package_install" -eq 1 ] || prompt_yes_no "Install pinned Neovim v${NEOVIM_LINUX_VERSION} from the official release?"; then
      if install_pinned_neovim_linux && have_supported_nvim; then
        DEPENDENCY_SUMMARY+=("nvim: installed official v$(get_nvim_version)")
        return 0
      fi
      DEPENDENCY_SUMMARY+=("nvim: official install attempted")
      return 1
    fi
  fi

  version_after="$(get_nvim_version 2>/dev/null || true)"
  if [ -n "$version_after" ]; then
    DEPENDENCY_SUMMARY+=("nvim: present but too old ($version_after < $NEOVIM_MIN_VERSION)")
  else
    DEPENDENCY_SUMMARY+=("nvim: missing")
  fi
  return 1
}

maybe_note_dependency() {
  local command_name="$1"
  local description="$2"

  if command -v "$command_name" >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("$command_name: present")
    return 0
  fi

  if is_interactive; then
    echo "Optional tool not found: $command_name ($description)." >&2
  fi
  DEPENDENCY_SUMMARY+=("$command_name: missing (manual install)")
}

maybe_install_eza() {
  local manager="$1"

  if command -v eza >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("eza: present")
    return 0
  fi

  case "$manager" in
    brew|pacman|zypper)
      if prompt_yes_no "Install eza for modern ls aliases?"; then
        install_packages "$manager" eza
        if command -v eza >/dev/null 2>&1; then
          DEPENDENCY_SUMMARY+=("eza: installed")
        else
          DEPENDENCY_SUMMARY+=("eza: install attempted")
        fi
      else
        DEPENDENCY_SUMMARY+=("eza: skipped")
      fi
      ;;
    dnf)
      DEPENDENCY_SUMMARY+=("eza: manual install recommended on Fedora 42+")
      if is_interactive; then
        echo "eza upstream notes Fedora 42+ may require manual install or cargo; skipping automatic dnf install." > /dev/tty
      fi
      ;;
    apt)
      DEPENDENCY_SUMMARY+=("eza: manual apt repo setup required")
      if is_interactive; then
        echo "eza on Debian/Ubuntu uses an upstream APT repo; skipping automatic apt install." > /dev/tty
      fi
      ;;
    *)
      DEPENDENCY_SUMMARY+=("eza: missing (manual install)")
      ;;
  esac
}

q_apt_repo_configured() {
  [ -f /etc/apt/keyrings/natesales.gpg ] || return 1
  [ -f /etc/apt/sources.list.d/natesales.list ] || return 1
  grep -Fq "deb [signed-by=/etc/apt/keyrings/natesales.gpg] https://repo.natesales.net/apt * *" \
    /etc/apt/sources.list.d/natesales.list 2>/dev/null
}

setup_q_apt_repo() {
  if q_apt_repo_configured; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    if prompt_yes_no "q Debian/Ubuntu install needs curl. Install curl first?"; then
      install_packages apt curl
    else
      DEPENDENCY_SUMMARY+=("q: missing (requires curl for Debian/Ubuntu repo setup)")
      return 1
    fi
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    if prompt_yes_no "q Debian/Ubuntu install needs gpg. Install gpg first?"; then
      install_packages apt gpg
    else
      DEPENDENCY_SUMMARY+=("q: missing (requires gpg for Debian/Ubuntu repo setup)")
      return 1
    fi
  fi

  run_with_spinner "Creating natesales APT keyring directory for q" sudo mkdir -p /etc/apt/keyrings || return 1
  run_with_spinner "Installing natesales APT signing key for q" \
    sh -c 'curl -fsSL https://repo.natesales.net/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/natesales.gpg' || return 1
  run_with_spinner "Adding natesales APT source for q" \
    sh -c 'echo "deb [signed-by=/etc/apt/keyrings/natesales.gpg] https://repo.natesales.net/apt * *" | sudo tee /etc/apt/sources.list.d/natesales.list >/dev/null' || return 1
  APT_UPDATED=0
  return 0
}

maybe_install_q() {
  local manager="$1"

  if command -v q >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("q: present")
    return 0
  fi

  case "$manager" in
    apt)
      if ! prompt_yes_no "Install q text-as-data CLI via the natesales Debian/Ubuntu APT repo?"; then
        DEPENDENCY_SUMMARY+=("q: skipped")
        return 0
      fi

      if ! setup_q_apt_repo; then
        DEPENDENCY_SUMMARY+=("q: install attempted")
        return 0
      fi

      install_packages apt q
      if command -v q >/dev/null 2>&1; then
        DEPENDENCY_SUMMARY+=("q: installed")
      else
        DEPENDENCY_SUMMARY+=("q: install attempted")
      fi
      ;;
    none)
      DEPENDENCY_SUMMARY+=("q: missing (no supported package manager)")
      ;;
    *)
      maybe_install_dependency "$manager" q q "q text-as-data CLI"
      ;;
  esac
}

maybe_install_uv() {
  if command -v uv >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("uv: present")
    return 0
  fi

  if ! prompt_yes_no "Install uv for Python package manager (official installer)?"; then
    echo "skipping uv" >&2
    DEPENDENCY_SUMMARY+=("uv: skipped")
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    run_with_spinner "Installing uv via official installer" sh -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
  elif command -v wget >/dev/null 2>&1; then
    run_with_spinner "Installing uv via official installer" sh -c 'wget -qO- https://astral.sh/uv/install.sh | sh'
  else
    if [ "$PACKAGE_MANAGER" != "none" ] && prompt_yes_no "uv installer needs curl or wget. Install curl and retry?"; then
      install_packages "$PACKAGE_MANAGER" curl
      run_with_spinner "Installing uv via official installer" sh -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
    else
      DEPENDENCY_SUMMARY+=("uv: missing (requires curl or wget)")
      return 0
    fi
  fi

  if command -v uv >/dev/null 2>&1 || [ -x "$HOME_DIR/.local/bin/uv" ]; then
    DEPENDENCY_SUMMARY+=("uv: installed")
  else
    DEPENDENCY_SUMMARY+=("uv: install attempted")
  fi
}

extract_zip_archive() {
  local archive_path="$1"
  local destination_dir="$2"

  if command -v unzip >/dev/null 2>&1; then
    run_with_spinner "Extracting $(basename "$archive_path")" unzip -oq "$archive_path" -d "$destination_dir"
  elif command -v bsdtar >/dev/null 2>&1; then
    run_with_spinner "Extracting $(basename "$archive_path")" bsdtar -xf "$archive_path" -C "$destination_dir"
  else
    echo "Neither unzip nor bsdtar is available for extracting $archive_path" >&2
    return 1
  fi
}

maybe_install_bw() {
  local archive_path release_url install_root bin_dir extracted_binary target_binary

  if command -v bw >/dev/null 2>&1 || [ -x "$STATE_HOME/bin/bw" ]; then
    DEPENDENCY_SUMMARY+=("bw: present")
    return 0
  fi

  if ! prompt_yes_no "Install Bitwarden CLI from the official native executable archive?"; then
    echo "skipping bw" >&2
    DEPENDENCY_SUMMARY+=("bw: skipped")
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    if [ "$PACKAGE_MANAGER" != "none" ] && prompt_yes_no "Bitwarden CLI installer needs curl or wget. Install curl and retry?"; then
      install_packages "$PACKAGE_MANAGER" curl
    else
      DEPENDENCY_SUMMARY+=("bw: missing (requires curl or wget)")
      return 0
    fi
  fi

  if ! command -v unzip >/dev/null 2>&1 && ! command -v bsdtar >/dev/null 2>&1; then
    if [ "$PACKAGE_MANAGER" != "none" ] && prompt_yes_no "Bitwarden CLI archive extraction needs unzip or bsdtar. Install unzip and retry?"; then
      install_packages "$PACKAGE_MANAGER" unzip
    else
      DEPENDENCY_SUMMARY+=("bw: missing (requires unzip or bsdtar)")
      return 0
    fi
  fi

  release_url="https://github.com/bitwarden/cli/releases/download/v${BW_VERSION}/bw-linux-${BW_VERSION}.zip"
  archive_path="${TMPDIR:-/tmp}/bw-linux-${BW_VERSION}.zip"
  install_root="$STATE_HOME/tools/bitwarden-cli/v${BW_VERSION}"
  bin_dir="$STATE_HOME/bin"
  extracted_binary="$install_root/bw"
  target_binary="$bin_dir/bw"

  run_cmd mkdir -p "$install_root" "$bin_dir" || {
    DEPENDENCY_SUMMARY+=("bw: install attempted")
    return 1
  }

  if [ ! -x "$extracted_binary" ]; then
    download_to_file "$release_url" "$archive_path" || {
      DEPENDENCY_SUMMARY+=("bw: install attempted")
      return 1
    }
    extract_zip_archive "$archive_path" "$install_root" || {
      DEPENDENCY_SUMMARY+=("bw: install attempted")
      return 1
    }
    run_cmd chmod u=rwx,go=rx "$extracted_binary" || true
  fi

  run_cmd ln -sfn "$extracted_binary" "$target_binary" || {
    DEPENDENCY_SUMMARY+=("bw: install attempted")
    return 1
  }

  if command -v bw >/dev/null 2>&1 || [ -x "$target_binary" ]; then
    DEPENDENCY_SUMMARY+=("bw: installed official v$BW_VERSION")
  else
    DEPENDENCY_SUMMARY+=("bw: install attempted")
  fi
}

maybe_install_dua_cli() {
  local manager="$1"
  local repo_url="https://github.com/byron/dua-cli.git"

  if command -v dua >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("dua: present")
    return 0
  fi

  if ! prompt_yes_no "Install dua-cli for disk usage analysis from byron/dua-cli via cargo?"; then
    echo "skipping dua-cli" >&2
    DEPENDENCY_SUMMARY+=("dua: skipped")
    return 0
  fi

  if ! command -v cargo >/dev/null 2>&1; then
    maybe_install_dependency "$manager" cargo cargo "Rust package manager required for dua-cli"
  fi

  if ! command -v cargo >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("dua: missing (cargo unavailable)")
    return 0
  fi

  run_with_spinner "Installing dua-cli from GitHub via cargo" cargo install --locked --git "$repo_url" dua-cli
  if command -v dua >/dev/null 2>&1 || [ -x "$HOME_DIR/.cargo/bin/dua" ]; then
    DEPENDENCY_SUMMARY+=("dua: installed")
  else
    DEPENDENCY_SUMMARY+=("dua: install attempted")
  fi
}

maybe_install_pnpm() {
  local pnpm_home="${PNPM_HOME:-$HOME_DIR/.local/share/pnpm}"

  if command -v pnpm >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("pnpm: present")
    return 0
  fi

  if ! prompt_yes_no "Install pnpm package manager?"; then
    echo "skipping pnpm" >&2
    DEPENDENCY_SUMMARY+=("pnpm: skipped")
    return 0
  fi

  export PNPM_HOME="$pnpm_home"
  export PATH="$PNPM_HOME:$PATH"
  run_cmd mkdir -p "$PNPM_HOME"

  if command -v corepack >/dev/null 2>&1; then
    run_with_spinner "Enabling pnpm@$PNPM_VERSION via corepack" \
      corepack enable --install-directory "$PNPM_HOME" pnpm
    run_with_spinner "Preparing pnpm@$PNPM_VERSION via corepack" \
      corepack prepare "pnpm@$PNPM_VERSION" --activate
  elif command -v npm >/dev/null 2>&1; then
    run_with_spinner "Installing pnpm@$PNPM_VERSION via npm" \
      npm install --global "pnpm@$PNPM_VERSION" --prefix "$PNPM_HOME"
    if [ -x "$PNPM_HOME/bin/pnpm" ]; then
      run_cmd ln -sfn "$PNPM_HOME/bin/pnpm" "$PNPM_HOME/pnpm"
    fi
    if [ -x "$PNPM_HOME/bin/pnpx" ]; then
      run_cmd ln -sfn "$PNPM_HOME/bin/pnpx" "$PNPM_HOME/pnpx"
    fi
  else
    DEPENDENCY_SUMMARY+=("pnpm: missing (requires corepack or npm)")
    return 0
  fi

  if command -v pnpm >/dev/null 2>&1 || [ -x "$PNPM_HOME/pnpm" ] || [ -x "$PNPM_HOME/bin/pnpm" ]; then
    DEPENDENCY_SUMMARY+=("pnpm: installed")
  else
    DEPENDENCY_SUMMARY+=("pnpm: install attempted")
  fi
}

link_file() {
  local source="$1"
  local target="$2"
  run_cmd mkdir -p "$(dirname "$target")"
  backup_target "$source" "$target" || {
    record_failure "Backing up $target"
    return 1
  }
  run_cmd ln -sfn "$source" "$target" || {
    record_failure "Linking $target"
    return 1
  }
  echo "linked $target"
}

backup_target() {
  local source="$1"
  local target="$2"
  local target_dir target_name backup_dir

  if [ -L "$target" ]; then
    local current
    current="$(readlink "$target")"
    if [ "$current" = "$source" ]; then
      return
    fi
  fi

  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    return
  fi

  target_dir="$(dirname "$target")"
  target_name="$(basename "$target")"
  backup_dir="$BACKUP_ROOT$target_dir"
  run_cmd mkdir -p "$backup_dir"

  if [ -d "$target" ] && [ ! -L "$target" ]; then
    run_cmd mv "$target" "$backup_dir/${target_name}.${TIMESTAMP}"
  else
    run_cmd mv "$target" "$backup_dir/${target_name}.${TIMESTAMP}"
  fi
  echo "backed up $target -> $backup_dir/${target_name}.${TIMESTAMP}"
}

sync_repo() {
  local repo_url="$1"
  local ref="$2"
  local target="$3"

  if [ ! -d "$target/.git" ]; then
    run_with_spinner "Cloning $(basename "$target")" git clone "$repo_url" "$target" || return 1
  fi

  run_with_spinner "Updating $(basename "$target")" git -C "$target" fetch origin "$ref" || return 1
  run_with_spinner "Pinning $(basename "$target")" git -c advice.detachedHead=false -C "$target" checkout "$ref" || return 1
}

normalize_tree_permissions() {
  local target="$1"

  [ -e "$target" ] || return 0

  find "$target" -type d -exec chmod u=rwx,go=rx {} + || return 1
  find "$target" -type f -exec chmod u=rw,go=r {} + || return 1
}

ensure_oh_my_zsh_permissions() {
  local omz_root="$STATE_HOME/oh-my-zsh"

  if normalize_tree_permissions "$omz_root"; then
    TOOL_SUMMARY+=("oh-my-zsh permissions: normalized")
  else
    TOOL_SUMMARY+=("oh-my-zsh permissions: failed")
    record_failure "Normalizing oh-my-zsh permissions"
    return 1
  fi
}

ensure_ssh_include() {
  local ssh_dir="$HOME_DIR/.ssh"
  local ssh_config="$ssh_dir/config"
  local include_line="Include ~/.config/ooodnakov/ssh/config"

  run_cmd mkdir -p "$ssh_dir"
  run_cmd touch "$ssh_config"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] ensure SSH include in %s\n' "$ssh_config"
    return 0
  fi

  if ! grep -Fqx "$include_line" "$ssh_config"; then
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '[dry-run] prepend SSH include in %s\n' "$ssh_config"
    elif printf "%s\n\n" "$include_line" | cat - "$ssh_config" > "$ssh_config.tmp" && mv "$ssh_config.tmp" "$ssh_config"; then
      :
    else
      record_failure "Updating SSH include config"
      return 1
    fi
  fi
}

install_fonts() {
  local source_dir="$REPO_ROOT/fonts/meslo"

  if [ -d "$source_dir" ]; then
    run_cmd mkdir -p "$FONT_TARGET_DIR"
    run_cmd cp "$source_dir"/*.ttf "$FONT_TARGET_DIR"/ || record_failure "Copying bundled fonts"
    if command -v fc-cache >/dev/null 2>&1; then
      run_with_spinner "Refreshing font cache" fc-cache -f "$FONT_TARGET_DIR" >/dev/null 2>&1 || true
    fi
  fi
}

install_managed_tools() {
  local bin_dir="$STATE_HOME/bin"

  sync_repo "$NVM_REPO" "$NVM_REF" "$HOME_DIR/.nvm" && TOOL_SUMMARY+=("nvm: synced") || TOOL_SUMMARY+=("nvm: failed")
  sync_repo "$K_REPO" "$K_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/k" && TOOL_SUMMARY+=("k: synced") || TOOL_SUMMARY+=("k: failed")
  sync_repo "$MARKER_REPO" "$MARKER_REF" "$STATE_HOME/marker" && TOOL_SUMMARY+=("marker: synced") || TOOL_SUMMARY+=("marker: failed")
  sync_repo "$TODO_REPO" "$TODO_REF" "$STATE_HOME/todo" && TOOL_SUMMARY+=("todo.txt-cli: synced") || TOOL_SUMMARY+=("todo.txt-cli: failed")

  run_cmd mkdir -p "$bin_dir"
  run_cmd ln -sfn "$STATE_HOME/todo/todo.sh" "$bin_dir/todo.sh" && TOOL_SUMMARY+=("todo.sh: linked into $bin_dir") || TOOL_SUMMARY+=("todo.sh: link failed")

  if command -v python3 >/dev/null 2>&1 && [ -f "$STATE_HOME/marker/install.py" ]; then
    if python3 "$STATE_HOME/marker/install.py" >/dev/null 2>&1; then
      TOOL_SUMMARY+=("marker: install.py succeeded")
    else
      TOOL_SUMMARY+=("marker: install.py failed")
      if [ "$PACKAGE_MANAGER" = "apt" ] && prompt_yes_no "marker install failed. Install python-is-python3 and retry?"; then
        install_packages "$PACKAGE_MANAGER" python-is-python3
        if python3 "$STATE_HOME/marker/install.py" >/dev/null 2>&1; then
          TOOL_SUMMARY+=("marker: retry succeeded after python-is-python3")
        else
          TOOL_SUMMARY+=("marker: retry failed after python-is-python3")
        fi
      fi
    fi
  else
    TOOL_SUMMARY+=("marker: install.py skipped")
  fi
}

install_auto_uv_env() {
  local source_dir="$STATE_HOME/src/auto-uv-env"
  local legacy_dir="$STATE_HOME/auto-uv-env"
  local share_dir="$STATE_HOME/auto-uv-env"
  local bin_dir="$STATE_HOME/bin"

  if [ -d "$legacy_dir/.git" ] && [ ! -e "$source_dir" ]; then
    run_cmd mkdir -p "$(dirname "$source_dir")"
    if run_cmd mv "$legacy_dir" "$source_dir"; then
      TOOL_SUMMARY+=("auto-uv-env: migrated legacy checkout to $source_dir")
    else
      TOOL_SUMMARY+=("auto-uv-env: failed to migrate legacy checkout")
      record_failure "Migrating auto-uv-env checkout"
      return 1
    fi
  fi

  sync_repo "$AUTO_UV_ENV_REPO" "$AUTO_UV_ENV_REF" "$source_dir" || {
    TOOL_SUMMARY+=("auto-uv-env: failed")
    return 1
  }

  if [ "$DRY_RUN" -eq 1 ]; then
    TOOL_SUMMARY+=("auto-uv-env: dry-run preview")
    return 0
  fi

  if [ ! -f "$source_dir/auto-uv-env" ] || [ ! -d "$source_dir/share/auto-uv-env" ]; then
    TOOL_SUMMARY+=("auto-uv-env: install payload missing from source checkout")
    record_failure "Installing auto-uv-env payload"
    return 1
  fi

  run_cmd mkdir -p "$bin_dir"
  run_cmd mkdir -p "$share_dir"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] install auto-uv-env share files into %s\n' "$share_dir"
  elif ! find "$source_dir/share/auto-uv-env" -maxdepth 1 -type f -exec install -m 0644 {} "$share_dir/" \;; then
    TOOL_SUMMARY+=("auto-uv-env: failed to install share files")
    record_failure "Installing auto-uv-env share files"
    return 1
  fi

  run_cmd ln -sfn "$source_dir/auto-uv-env" "$bin_dir/auto-uv-env" || {
    TOOL_SUMMARY+=("auto-uv-env: failed to link executable")
    record_failure "Linking auto-uv-env executable"
    return 1
  }

  run_cmd chmod u=rwx,go=rx "$source_dir/auto-uv-env" || true
  TOOL_SUMMARY+=("auto-uv-env: installed to $share_dir and linked into $bin_dir")
}

print_summary() {
  local item

  echo
  echo "Dependency summary:"
  for item in "${DEPENDENCY_SUMMARY[@]}"; do
    echo "  - $item"
  done

  echo "Managed tools:"
  for item in "${TOOL_SUMMARY[@]}"; do
    echo "  - $item"
  done

  if [ "${#FAILURES[@]}" -gt 0 ]; then
    echo "Failures:"
    for item in "${FAILURES[@]}"; do
      echo "  - $item"
    done
  fi
}

update_repo() {
  run_cmd git -C "$REPO_ROOT" pull --ff-only
}

doctor_check_link() {
  local source="$1"
  local target="$2"
  if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    echo "[ok] $target -> $source"
  else
    echo "[missing] $target (expected symlink to $source)"
    FAILURES+=("doctor link $target")
  fi
}

doctor_check_command() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    echo "[ok] command: $name"
  else
    echo "[missing] command: $name"
    FAILURES+=("doctor command $name")
  fi
}

doctor_check_nvim() {
  local version
  if ! command -v nvim >/dev/null 2>&1; then
    echo "[missing] command: nvim"
    FAILURES+=("doctor command nvim")
    return 1
  fi

  version="$(get_nvim_version 2>/dev/null || true)"
  if [ -n "$version" ] && version_gte "$version" "$NEOVIM_MIN_VERSION"; then
    echo "[ok] command: nvim ($version)"
  else
    echo "[missing] command: nvim >= $NEOVIM_MIN_VERSION (found ${version:-unknown})"
    FAILURES+=("doctor command nvim version")
    return 1
  fi
}

run_doctor() {
  echo "Running doctor checks..."
  doctor_check_link "$REPO_ROOT/home/.zshrc" "$HOME_DIR/.zshrc"
  doctor_check_link "$REPO_ROOT/home/.config/zsh" "$CONFIG_HOME/zsh"
  doctor_check_link "$REPO_ROOT/home/.config/wezterm" "$CONFIG_HOME/wezterm"
  doctor_check_link "$REPO_ROOT/home/.config/nvim" "$CONFIG_HOME/nvim"
  doctor_check_link "$REPO_ROOT/home/.config/ooodnakov" "$CONFIG_HOME/ooodnakov"
  doctor_check_link "$REPO_ROOT/home/.config/ohmyposh/ooodnakov.omp.json" "$CONFIG_HOME/ohmyposh/ooodnakov.omp.json"
  doctor_check_link "$REPO_ROOT/home/.config/powershell/Microsoft.PowerShell_profile.ps1" "$CONFIG_HOME/powershell/Microsoft.PowerShell_profile.ps1"
  doctor_check_command git
  doctor_check_command zsh
  doctor_check_command wezterm
  doctor_check_nvim
  doctor_check_command oooconf
  if [ -d "$FONT_TARGET_DIR" ]; then
    echo "[ok] fonts dir: $FONT_TARGET_DIR"
  else
    echo "[missing] fonts dir: $FONT_TARGET_DIR"
    FAILURES+=("doctor fonts")
  fi

  if [ "${#FAILURES[@]}" -gt 0 ]; then
    echo "Doctor found ${#FAILURES[@]} issue(s)."
    return 1
  fi
  echo "Doctor checks passed."
}

install_optional_dependencies() {
  local manager
  manager="$(detect_package_manager)"
  PACKAGE_MANAGER="$manager"

  echo "Dependency check:"
  maybe_install_dependency "$manager" wget wget "downloading auxiliary assets and parity with ezsh tooling"
  maybe_install_dependency "$manager" zsh zsh "default shell support"
  maybe_install_dependency "$manager" direnv direnv "direnv shell integration"
  maybe_install_dependency "$manager" fzf fzf "fzf shell integration"
  maybe_install_dependency "$manager" bat bat "cat alternative with syntax highlighting"
  maybe_install_dependency "$manager" delta git-delta "Git diff pager with syntax highlighting"
  maybe_install_dependency "$manager" glow glow "terminal Markdown reader"
  maybe_install_dependency "$manager" zoxide zoxide "smart directory jumping with z/zi"
  maybe_install_q "$manager"
  maybe_install_eza "$manager"
  maybe_install_uv
  maybe_install_bw
  maybe_install_dependency "$manager" node nodejs "Node.js runtime"
  maybe_install_dependency "$manager" npm npm "Node package manager"
  maybe_install_pnpm
  maybe_install_dependency "$manager" autoconf autoconf "building optional ezsh native components"
  maybe_install_dependency "$manager" fc-cache fontconfig "refreshing installed font caches"
  maybe_install_dependency "$manager" cargo cargo "Rust package manager"
  maybe_install_dua_cli "$manager"
  maybe_install_neovim "$manager"
  maybe_note_dependency k "manual install if you want the standalone k command"
  maybe_install_dependency "$manager" python3 python3 "Python runtime and helper scripts"
}

shift || true
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes-optional) INSTALL_OPTIONAL=always ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

case "$COMMAND" in
  install) ;;
  update) update_repo ;;
  doctor) run_doctor; exit $? ;;
  *) usage >&2; exit 1 ;;
esac

initialize_logging
run_cmd mkdir -p "$CONFIG_HOME" "$DATA_HOME" "$STATE_HOME"

install_optional_dependencies

sync_repo "$OH_MY_ZSH_REPO" "$OH_MY_ZSH_REF" "$STATE_HOME/oh-my-zsh" || TOOL_SUMMARY+=("oh-my-zsh: failed")
sync_repo "$P10K_REPO" "$P10K_REF" "$STATE_HOME/powerlevel10k" || TOOL_SUMMARY+=("powerlevel10k: failed")
sync_repo "$ZSH_AUTOSUGGESTIONS_REPO" "$ZSH_AUTOSUGGESTIONS_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-autosuggestions" || TOOL_SUMMARY+=("zsh-autosuggestions: failed")
sync_repo "$ZSH_HIGHLIGHTING_REPO" "$ZSH_HIGHLIGHTING_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-syntax-highlighting" || TOOL_SUMMARY+=("zsh-syntax-highlighting: failed")
sync_repo "$ZSH_HISTORY_REPO" "$ZSH_HISTORY_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-history-substring-search" || TOOL_SUMMARY+=("zsh-history-substring-search: failed")
sync_repo "$ZSH_AUTOCOMPLETE_REPO" "$ZSH_AUTOCOMPLETE_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-autocomplete" || TOOL_SUMMARY+=("zsh-autocomplete: failed")
sync_repo "$FZF_TAB_REPO" "$FZF_TAB_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/fzf-tab" || TOOL_SUMMARY+=("fzf-tab: failed")
sync_repo "$FORGIT_REPO" "$FORGIT_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/forgit" || TOOL_SUMMARY+=("forgit: failed")
sync_repo "$YOU_SHOULD_USE_REPO" "$YOU_SHOULD_USE_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/you-should-use" || TOOL_SUMMARY+=("you-should-use: failed")
install_auto_uv_env
ensure_oh_my_zsh_permissions || true
install_managed_tools

link_file "$REPO_ROOT/home/.zshrc" "$HOME_DIR/.zshrc" || true
link_file "$REPO_ROOT/home/.config/zsh" "$CONFIG_HOME/zsh" || true
link_file "$REPO_ROOT/home/.config/wezterm" "$CONFIG_HOME/wezterm" || true
link_file "$REPO_ROOT/home/.config/nvim" "$CONFIG_HOME/nvim" || true
link_file "$REPO_ROOT/home/.config/ooodnakov" "$CONFIG_HOME/ooodnakov" || true
run_cmd mkdir -p "$HOME_DIR/.local/bin"
link_file "$REPO_ROOT/home/.config/ooodnakov/bin/oooconf" "$HOME_DIR/.local/bin/oooconf" || true

run_cmd mkdir -p "$CONFIG_HOME/ohmyposh" "$CONFIG_HOME/powershell"
link_file "$REPO_ROOT/home/.config/ohmyposh/ooodnakov.omp.json" "$CONFIG_HOME/ohmyposh/ooodnakov.omp.json" || true
link_file "$REPO_ROOT/home/.config/powershell/Microsoft.PowerShell_profile.ps1" "$CONFIG_HOME/powershell/Microsoft.PowerShell_profile.ps1" || true

ensure_ssh_include || true
install_fonts

if is_interactive && [ -f "$HOME_DIR/.zshrc" ]; then
  # This only updates the current setup process; it cannot mutate the parent shell session.
  # shellcheck disable=SC1090,SC1091
  . "$HOME_DIR/.zshrc" || true
fi

print_summary

echo
echo "Bootstrap complete."
echo "If needed, create local overrides in $CONFIG_HOME/ooodnakov/local."
if [ -n "$LOG_FILE" ]; then
  echo "Log file: $LOG_FILE"
fi
