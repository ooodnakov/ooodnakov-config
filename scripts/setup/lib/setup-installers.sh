#!/usr/bin/env bash
# Sourced by scripts/setup/setup.sh; do not execute directly.

gum_apt_repo_configured() {
  [ -f /etc/apt/keyrings/charm.gpg ] || return 1
  [ -f /etc/apt/sources.list.d/charm.list ] || return 1
  grep -Fq "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
    /etc/apt/sources.list.d/charm.list 2>/dev/null
}

setup_gum_apt_repo() {
  if gum_apt_repo_configured; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    if prompt_yes_no "gum Debian/Ubuntu install needs curl. Install curl first?"; then
      install_packages apt curl
    else
      DEPENDENCY_SUMMARY+=("gum: missing (requires curl for Debian/Ubuntu repo setup)")
      return 1
    fi
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    if prompt_yes_no "gum Debian/Ubuntu install needs gpg. Install gpg first?"; then
      install_packages apt gpg
    else
      DEPENDENCY_SUMMARY+=("gum: missing (requires gpg for Debian/Ubuntu repo setup)")
      return 1
    fi
  fi

  run_with_spinner "Creating Charm APT keyring directory for gum" sudo mkdir -p /etc/apt/keyrings || return 1
  run_with_spinner "Installing Charm APT signing key for gum" \
    sh -c 'curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg' || return 1
  run_with_spinner "Adding Charm APT source for gum" \
    sh -c 'echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list >/dev/null' || return 1
  APT_UPDATED=0
  return 0
}

gum_rpm_repo_configured() {
  [ -f /etc/yum.repos.d/charm.repo ]
}

setup_gum_rpm_repo() {
  if gum_rpm_repo_configured; then
    return 0
  fi

  run_with_spinner "Installing Charm RPM repo for gum" \
    sh -c "cat <<'EOF' | sudo tee /etc/yum.repos.d/charm.repo >/dev/null
[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key
EOF" || return 1
  run_with_spinner "Importing Charm RPM signing key for gum" sudo rpm --import https://repo.charm.sh/yum/gpg.key || return 1
  return 0
}

install_gum_package() {
  local manager
  manager="$1"

  case "$manager" in
  brew | pacman)
    install_packages "$manager" gum
    ;;
  apt)
    setup_gum_apt_repo || return 1
    install_packages apt gum
    ;;
  dnf | zypper)
    setup_gum_rpm_repo || return 1
    install_packages "$manager" gum
    ;;
  *)
    return 1
    ;;
  esac
}

maybe_install_gum() {
  local manager
  manager="$1"

  if check_dependency_status "gum" "gum"; then
    return 0
  fi

  if [ "$manager" = "none" ]; then
    DEPENDENCY_SUMMARY+=("gum: missing (no supported package manager)")
    return 1
  fi

  if ! prompt_yes_no "Install gum for interactive terminal selectors and prompts?"; then
    DEPENDENCY_SUMMARY+=("gum: skipped")
    return 0
  fi

  if install_gum_package "$manager" && command -v gum >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("gum: installed")
    return 0
  fi

  DEPENDENCY_SUMMARY+=("gum: install attempted")
  return 1
}

maybe_install_fastfetch() {
  local manager
  manager="$1"

  if check_dependency_status "fastfetch" "fastfetch"; then
    return 0
  fi

  case "$manager" in
  apt)
    if apt_package_available "fastfetch"; then
      maybe_install_dependency apt fastfetch fastfetch "system information tool"
    elif command -v brew >/dev/null 2>&1; then
      if prompt_yes_no "fastfetch not found in APT. Install via Homebrew instead?"; then
        maybe_install_dependency brew fastfetch fastfetch "system information tool"
      else
        DEPENDENCY_SUMMARY+=("fastfetch: skipped (APT package unavailable and brew install declined)")
      fi
    else
      DEPENDENCY_SUMMARY+=("fastfetch: missing (APT package unavailable and brew not found)")
    fi
    ;;
  *)
    maybe_install_dependency "$manager" fastfetch fastfetch "system information tool"
    ;;
  esac
}

maybe_install_k() {
  maybe_note_dependency k "manual install if you want the standalone k command"
}

add_homebrew_to_current_path() {
  local brew_bin
  for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    if [ -x "$brew_bin" ]; then
      eval "$("$brew_bin" shellenv)"
      return 0
    fi
  done
  return 1
}

maybe_install_brew() {
  local _manager
  _manager="$1"

  if check_dependency_status "brew" "brew"; then
    return 0
  fi

  case "$(detect_platform)" in
  linux | macos) ;;
  *)
    DEPENDENCY_SUMMARY+=("brew: skipped (macOS/Linux only)")
    return 0
    ;;
  esac

  if ! prompt_yes_no "Install Homebrew package manager with the official install script?"; then
    is_verbose && echo "skipping Homebrew" >&2
    DEPENDENCY_SUMMARY+=("brew: skipped")
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    local manager
    manager="$(detect_package_manager)"
    if [ "$manager" != "none" ] && [ "$manager" != "brew" ]; then
      install_packages "$manager" curl || true
    fi
  fi

  if ! command -v curl >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("brew: missing (curl unavailable)")
    return 1
  fi

  if [ ! -x /bin/bash ]; then
    DEPENDENCY_SUMMARY+=("brew: missing (/bin/bash unavailable)")
    return 1
  fi

  run_with_spinner "Installing Homebrew" \
    env NONINTERACTIVE=1 /bin/bash -c '$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)'

  if [ "$DRY_RUN" -eq 1 ]; then
    DEPENDENCY_SUMMARY+=("brew: install preview")
    return 0
  fi

  add_homebrew_to_current_path >/dev/null 2>&1 || true

  if command -v brew >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("brew: installed")
    return 0
  fi

  DEPENDENCY_SUMMARY+=("brew: install attempted")
  return 1
}

maybe_install_dua() {
  maybe_install_dua_cli "$1"
}

maybe_install_nvim() {
  maybe_install_neovim "$1"
}

maybe_install_tectonic() {
  maybe_install_dependency "$1" tectonic tectonic "Modern LaTeX engine (required by Snacks.image for LaTeX)"
}

systemd_unit_exists() {
  local unit
  unit="$1"

  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl list-unit-files "$unit" --no-legend 2>/dev/null | awk '{ print $1 }' | grep -Fxq "$unit"
}

enable_docker_systemd_unit() {
  local unit
  unit="$1"

  if ! systemd_unit_exists "$unit"; then
    DEPENDENCY_SUMMARY+=("$unit: skipped (systemd unit not found)")
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    run_with_spinner "Enabling $unit at boot" sudo systemctl enable --now "$unit"
    DEPENDENCY_SUMMARY+=("$unit: enable preview")
    return 0
  fi

  if run_with_spinner "Enabling $unit at boot" sudo systemctl enable --now "$unit"; then
    DEPENDENCY_SUMMARY+=("$unit: enabled and started")
    return 0
  fi

  DEPENDENCY_SUMMARY+=("$unit: enable attempted")
  return 1
}

maybe_install_docker() {
  local _manager
  _manager="$1"

  if [ "$(detect_platform)" != "linux" ]; then
    DEPENDENCY_SUMMARY+=("docker: skipped (Docker daemon auto-start is managed here only on systemd Linux)")
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    ui_line hint "docker daemon: no docker, continuing"
    DEPENDENCY_SUMMARY+=("docker: no docker, continuing")
    return 0
  fi

  DEPENDENCY_SUMMARY+=("docker: present")

  if ! command -v systemctl >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("docker daemon: skipped (systemctl unavailable)")
    return 0
  fi

  enable_docker_systemd_unit docker.service || true
  enable_docker_systemd_unit containerd.service || true
}

resolve_pnpm_command() {
  if command -v pnpm >/dev/null 2>&1; then
    command -v pnpm
    return 0
  fi

  local pnpm_home
  pnpm_home="${PNPM_HOME:-$HOME_DIR/.local/share/pnpm}"
  if [ -x "$pnpm_home/pnpm" ]; then
    printf '%s\n' "$pnpm_home/pnpm"
    return 0
  fi
  if [ -x "$pnpm_home/bin/pnpm" ]; then
    printf '%s\n' "$pnpm_home/bin/pnpm"
    return 0
  fi

  return 1
}

ensure_pnpm_available() {
  if resolve_pnpm_command >/dev/null 2>&1; then
    return 0
  fi

  maybe_install_pnpm "custom" >/dev/null 2>&1 || true
  resolve_pnpm_command >/dev/null 2>&1
}

python_has_pip() {
  local python_cmd
  python_cmd="$1"
  "$python_cmd" -m pip --version >/dev/null 2>&1
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
  local manager
  manager="$1"
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
  local package_name
  package_name="$1"

  if ! command -v apt-cache >/dev/null 2>&1; then
    return 1
  fi

  apt-cache show "$package_name" >/dev/null 2>&1
}

check_pip_dependency_status() {
  local command_name
  command_name="$1"
  local python_cmd
  python_cmd="$2"
  local check_cmd

  check_cmd="$(optional_dependency_check_command "$command_name")"
  if [[ "$check_cmd" == python\ * ]]; then
    check_cmd="$python_cmd ${check_cmd#python }"
  fi

  if eval "$check_cmd" >/dev/null 2>&1; then
    if [ "$DRY_RUN" -ne 1 ]; then
      ui_line ok "$command_name is present"
    fi
    DEPENDENCY_SUMMARY+=("$command_name: present")
    return 0
  fi

  return 1
}

check_dependency_status() {
  local command_name
  command_name="$1"
  local log_name
  log_name="${2:-$1}"

  if [ "$DRY_RUN" -ne 1 ] && is_interactive && is_verbose; then
    printf "[-] %s...\r" "$log_name" >/dev/tty
  fi

  # Use check command from central TOML if available, fallback to command -v.
  local check_cmd
  check_cmd="$(optional_dependency_check_command "$command_name")"

  # Prefer a fast PATH lookup only for the default binary-presence check. Richer
  # TOML checks can validate compound requirements (for example node+npm) and
  # must still run even when the main binary is present.
  if [ "$check_cmd" = "command -v $command_name" ] && command -v "$command_name" >/dev/null 2>&1; then
    if [ "$DRY_RUN" -ne 1 ]; then
      if is_interactive && is_verbose; then
        printf "\r" >/dev/tty
        ui_line ok "$log_name is present"
      else
        ui_line ok "$log_name is present"
      fi
    fi
    DEPENDENCY_SUMMARY+=("$log_name: present")
    return 0
  fi

  if eval "$check_cmd" >/dev/null 2>&1; then
    if [ "$DRY_RUN" -ne 1 ]; then
      if is_interactive && is_verbose; then
        printf "\r" >/dev/tty
        ui_line ok "$log_name is present"
      else
        ui_line ok "$log_name is present"
      fi
    fi
    DEPENDENCY_SUMMARY+=("$log_name: present")
    return 0
  fi

  if [ "$DRY_RUN" -ne 1 ] && is_interactive && is_verbose; then
    printf "\r" >/dev/tty
  fi
  return 1
}

maybe_install_dependency() {
  local manager
  manager="$1"
  local command_name
  command_name="$2"
  local package_name
  package_name="$3"
  local description
  description="$4"

  if check_dependency_status "$command_name"; then
    return 0
  fi

  if [ "$manager" = "none" ]; then
    ui_line missing "optional dependency: $command_name ($description)"
    DEPENDENCY_SUMMARY+=("$command_name: missing (no supported package manager)")
    return 1
  fi

  if [ "$INSTALL_OPTIONAL" != "always" ] && ! is_interactive; then
    DEPENDENCY_SUMMARY+=("$command_name: skipped")
    return 0
  fi

  if [ "$manager" = "cargo" ]; then
    if ! command -v cargo >/dev/null 2>&1; then
      maybe_install_cargo
    fi
    if ! command -v cargo >/dev/null 2>&1; then
      if [ -x "$HOME_DIR/.cargo/bin/cargo" ]; then
        export PATH="$HOME_DIR/.cargo/bin:$PATH"
      else
        DEPENDENCY_SUMMARY+=("$command_name: missing (cargo unavailable)")
        return 0
      fi
    fi
    if prompt_yes_no "Install $command_name for $description via cargo?"; then
      case "$package_name" in
      http* | git@*)
        run_with_spinner "Installing $command_name from Git via cargo" cargo install --locked --git "$package_name"
        ;;
      *)
        run_with_spinner "Installing $command_name via cargo" cargo install "$package_name"
        ;;
      esac
      if command -v "$command_name" >/dev/null 2>&1 || [ -x "$HOME_DIR/.cargo/bin/$command_name" ]; then
        DEPENDENCY_SUMMARY+=("$command_name: installed")
      else
        DEPENDENCY_SUMMARY+=("$command_name: install attempted")
      fi
    else
      is_verbose && echo "skipping $command_name" >&2
      DEPENDENCY_SUMMARY+=("$command_name: skipped")
    fi
    return 0
  fi

  if [ "$manager" = "apt" ] && ! apt_package_available "$package_name"; then
    if is_interactive; then
      echo "APT package not available: $package_name ($description); skipping automatic install." >/dev/tty
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
    is_verbose && echo "skipping $package_name" >&2
    DEPENDENCY_SUMMARY+=("$command_name: skipped")
  fi
}

normalize_semver() {
  local version
  version="${1#v}"
  version="${version%%-*}"
  printf '%s\n' "$version"
}

version_gte() {
  local left right
  local -a left_parts right_parts
  local i left_value right_value

  left="$(normalize_semver "$1")"
  right="$(normalize_semver "$2")"
  IFS=. read -r -a left_parts <<<"$left"
  IFS=. read -r -a right_parts <<<"$right"

  for i in 0 1 2 3; do
    left_value="${left_parts[$i]:-0}"
    right_value="${right_parts[$i]:-0}"
    if ((left_value > right_value)); then
      return 0
    fi
    if ((left_value < right_value)); then
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
  local url
  url="$1"
  local output
  output="$2"

  if command -v curl >/dev/null 2>&1; then
    run_with_spinner "Downloading $(basename "$output")" curl -fL --retry 3 -o "$output" "$url"
  elif command -v wget >/dev/null 2>&1; then
    run_with_spinner "Downloading $(basename "$output")" wget -qO "$output" "$url"
  else
    echo "Neither curl nor wget is available for downloading $url" >&2
    return 1
  fi
}

github_release_system() {
  case "$(uname -s)" in
  Linux) printf '%s\n' linux ;;
  Darwin) printf '%s\n' darwin ;;
  *) return 1 ;;
  esac
}

github_release_arch() {
  case "$(uname -m)" in
  x86_64 | amd64) printf '%s\n' x86_64 ;;
  aarch64 | arm64) printf '%s\n' aarch64 ;;
  i386 | i686) printf '%s\n' i686 ;;
  *) return 1 ;;
  esac
}

expand_github_release_template() {
  local template="$1"
  local version="$2"
  local system="$3"
  local arch="$4"

  template="${template//\$\{ver\}/$version}"
  template="${template//\$\{system\}/$system}"
  template="${template//\$\{arch\}/$arch}"
  printf '%s\n' "$template"
}

archive_stem() {
  local name="$1"
  name="${name##*/}"
  case "$name" in
  *.tar.gz) name="${name%.tar.gz}" ;;
  *.tgz) name="${name%.tgz}" ;;
  *.zip) name="${name%.zip}" ;;
  *.tar.xz) name="${name%.tar.xz}" ;;
  *.tar.bz2) name="${name%.tar.bz2}" ;;
  *) name="${name%.*}" ;;
  esac
  printf '%s\n' "$name"
}

maybe_install_github_release() {
  local key="$1"
  local description="$2"
  local repo="$3"
  local command_name="$4"
  local url_template="$5"
  local asset_template="$6"
  local version system arch asset_name release_url archive_path install_root bin_dir extracted_binary target_binary

  if check_dependency_status "$command_name" "$command_name"; then
    return 0
  fi

  version="$(get_dep_field "$key" ver)"
  if [ -z "$version" ] || [ -z "$repo" ]; then
    DEPENDENCY_SUMMARY+=("$command_name: missing (github-release metadata incomplete)")
    return 1
  fi

  system="$(github_release_system)" || {
    DEPENDENCY_SUMMARY+=("$command_name: unsupported OS $(uname -s)")
    return 1
  }
  arch="$(github_release_arch)" || {
    DEPENDENCY_SUMMARY+=("$command_name: unsupported architecture $(uname -m)")
    return 1
  }

  if [ -z "$asset_template" ] && [ -z "$url_template" ]; then
    DEPENDENCY_SUMMARY+=("$command_name: missing (github-release asset metadata incomplete)")
    return 1
  fi

  asset_name="$(expand_github_release_template "${asset_template:-${url_template##*/}}" "$version" "$system" "$arch")"
  if [ -n "$url_template" ]; then
    release_url="$(expand_github_release_template "$url_template" "$version" "$system" "$arch")"
  else
    release_url="https://github.com/${repo}/releases/download/v${version}/${asset_name}"
  fi

  if ! prompt_yes_no "Install $command_name for $description from the GitHub release archive?"; then
    DEPENDENCY_SUMMARY+=("$command_name: skipped")
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    if [ "$PACKAGE_MANAGER" != "none" ] && prompt_yes_no "$command_name installer needs curl or wget. Install curl and retry?"; then
      install_packages "$PACKAGE_MANAGER" curl
    else
      DEPENDENCY_SUMMARY+=("$command_name: missing (requires curl or wget)")
      return 1
    fi
  fi

  case "$asset_name" in
  *.zip)
    if ! command -v unzip >/dev/null 2>&1 && ! command -v bsdtar >/dev/null 2>&1; then
      if [ "$PACKAGE_MANAGER" != "none" ] && prompt_yes_no "$command_name archive extraction needs unzip or bsdtar. Install unzip and retry?"; then
        install_packages "$PACKAGE_MANAGER" unzip
      else
        DEPENDENCY_SUMMARY+=("$command_name: missing (requires unzip or bsdtar)")
        return 1
      fi
    fi
    ;;
  *.tar.gz | *.tgz | *.tar.xz | *.tar.bz2)
    if ! command -v tar >/dev/null 2>&1; then
      if [ "$PACKAGE_MANAGER" != "none" ] && prompt_yes_no "$command_name archive extraction needs tar. Install tar and retry?"; then
        install_packages "$PACKAGE_MANAGER" tar
      else
        DEPENDENCY_SUMMARY+=("$command_name: missing (requires tar)")
        return 1
      fi
    fi
    ;;
  esac

  install_root="$STATE_HOME/tools/$key/v${version}"
  bin_dir="$STATE_HOME/bin"
  archive_path="${TMPDIR:-/tmp}/${asset_name}"
  target_binary="$bin_dir/$command_name"

  run_cmd mkdir -p "$install_root" "$bin_dir" || return 1

  if [ ! -x "$target_binary" ]; then
    download_to_file "$release_url" "$archive_path" || {
      DEPENDENCY_SUMMARY+=("$command_name: install attempted")
      return 1
    }

    case "$asset_name" in
    *.zip) extract_zip_archive "$archive_path" "$install_root" || return 1 ;;
    *) run_with_spinner "Extracting $asset_name" tar -xf "$archive_path" -C "$install_root" || return 1 ;;
    esac

    if [ "$DRY_RUN" -eq 1 ]; then
      DEPENDENCY_SUMMARY+=("$command_name: install preview via GitHub release")
      return 0
    fi

    extracted_binary="$(find "$install_root" -type f -name "$command_name" -perm -u=x 2>/dev/null | head -n 1)"
    if [ -z "$extracted_binary" ] && [ -f "$install_root/$(archive_stem "$asset_name")/$command_name" ]; then
      extracted_binary="$install_root/$(archive_stem "$asset_name")/$command_name"
    fi
    if [ -z "$extracted_binary" ]; then
      DEPENDENCY_SUMMARY+=("$command_name: install attempted")
      return 1
    fi

    run_cmd chmod u=rwx,go=rx "$extracted_binary" || true
    run_cmd ln -sfn "$extracted_binary" "$target_binary" || return 1
  fi

  if command -v "$command_name" >/dev/null 2>&1 || [ -x "$target_binary" ]; then
    DEPENDENCY_SUMMARY+=("$command_name: installed official v${version}")
  else
    DEPENDENCY_SUMMARY+=("$command_name: install attempted")
  fi
}

get_neovim_release_version() {
  local version
  version="${NEOVIM_VERSION:-$(get_dep_field nvim ver)}"
  printf '%s\n' "${version:-0.12.1}"
}

install_pinned_neovim_unix() {
  local version asset_name extracted_dir release_url os
  local tools_root install_root bin_dir archive_path

  version="$(get_neovim_release_version)"
  os="$(uname -s)"

  case "$os:$(uname -m)" in
  Linux:x86_64 | Linux:amd64)
    asset_name="nvim-linux-x86_64.tar.gz"
    extracted_dir="nvim-linux-x86_64"
    ;;
  Linux:aarch64 | Linux:arm64)
    asset_name="nvim-linux-arm64.tar.gz"
    extracted_dir="nvim-linux-arm64"
    ;;
  Darwin:x86_64 | Darwin:amd64)
    asset_name="nvim-macos-x86_64.tar.gz"
    extracted_dir="nvim-macos-x86_64"
    ;;
  Darwin:aarch64 | Darwin:arm64)
    asset_name="nvim-macos-arm64.tar.gz"
    extracted_dir="nvim-macos-arm64"
    ;;
  *)
    echo "Unsupported platform for pinned Neovim install: $os $(uname -m)" >&2
    return 1
    ;;
  esac

  release_url="https://github.com/neovim/neovim/releases/download/v${version}/${asset_name}"
  tools_root="$STATE_HOME/tools/neovim"
  install_root="$tools_root/v${version}"
  bin_dir="$STATE_HOME/bin"
  archive_path="${TMPDIR:-/tmp}/${asset_name}"

  run_cmd mkdir -p "$install_root" "$bin_dir" || return 1

  if [ ! -x "$install_root/$extracted_dir/bin/nvim" ]; then
    download_to_file "$release_url" "$archive_path" || return 1
    run_with_spinner "Extracting pinned Neovim v${version}" tar -xzf "$archive_path" -C "$install_root" || return 1
  fi

  run_cmd ln -sfn "$install_root/$extracted_dir/bin/nvim" "$bin_dir/nvim" || return 1
}

maybe_install_neovim() {
  local _manager="$1"
  local version version_before version_after

  version="$(get_neovim_release_version)"

  if have_supported_nvim; then
    DEPENDENCY_SUMMARY+=("nvim: present ($(get_nvim_version))")
    return 0
  fi

  version_before="$(get_nvim_version 2>/dev/null || true)"
  if [ -n "$version_before" ] && is_interactive; then
    echo "Detected Neovim $version_before, but LazyVim requires >= $NEOVIM_MIN_VERSION." >/dev/tty
  fi

  case "$(uname -s)" in
  Linux | Darwin)
    if prompt_yes_no "Install pinned Neovim v${version} from the official GitHub release?"; then
      if install_pinned_neovim_unix && have_supported_nvim; then
        DEPENDENCY_SUMMARY+=("nvim: installed official v$(get_nvim_version)")
        return 0
      fi
      DEPENDENCY_SUMMARY+=("nvim: official install attempted")
      return 1
    fi
    ;;
  *)
    DEPENDENCY_SUMMARY+=("nvim: missing (unsupported platform for release install)")
    return 1
    ;;
  esac

  version_after="$(get_nvim_version 2>/dev/null || true)"
  if [ -n "$version_after" ]; then
    DEPENDENCY_SUMMARY+=("nvim: present but too old ($version_after < $NEOVIM_MIN_VERSION)")
  else
    DEPENDENCY_SUMMARY+=("nvim: missing")
  fi
  return 1
}

maybe_note_dependency() {
  local command_name
  command_name="$1"
  local description
  description="$2"

  if command -v "$command_name" >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("$command_name: present")
    return 0
  fi

  if is_interactive; then
    echo "Optional tool not found: $command_name ($description)." >&2
  fi
  DEPENDENCY_SUMMARY+=("$command_name: missing (manual install)")
}

maybe_install_rtk() {
  if check_dependency_status "rtk" "rtk"; then
    return 0
  fi

  if ! prompt_yes_no "Install rtk token-optimized AI CLI proxy from the official release (direct download)?"; then
    DEPENDENCY_SUMMARY+=("rtk: skipped")
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    if prompt_yes_no "rtk install needs curl and tar. Install them first?"; then
      local manager
      manager="$(detect_package_manager)"
      install_packages "$manager" curl tar
    else
      DEPENDENCY_SUMMARY+=("rtk: missing (requires curl and tar)")
      return 1
    fi
  fi

  local os arch target_url tmp_dir rtk_ver
  rtk_ver=$(get_managed_tool rtk ver)
  [ -z "$rtk_ver" ] && rtk_ver="0.37.0"

  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"

  case "$arch" in
  x86_64) arch="x86_64" ;;
  aarch64 | arm64) arch="aarch64" ;;
  *)
    DEPENDENCY_SUMMARY+=("rtk: unsupported architecture $arch")
    return 1
    ;;
  esac

  case "$os" in
  linux) target_url="https://github.com/rtk-ai/rtk/releases/download/v${rtk_ver}/rtk-${arch}-unknown-linux-musl.tar.gz" ;;
  darwin) target_url="https://github.com/rtk-ai/rtk/releases/download/v${rtk_ver}/rtk-${arch}-apple-darwin.tar.gz" ;;
  *)
    DEPENDENCY_SUMMARY+=("rtk: unsupported OS $os")
    return 1
    ;;
  esac

  tmp_dir="$(mktemp -d)"
  run_with_spinner "Downloading and extracting rtk v${rtk_ver}" sh -c "curl -fsSL '$target_url' | tar -xz -C '$tmp_dir'"

  if [ -f "$tmp_dir/rtk" ]; then
    run_cmd mkdir -p "$HOME_DIR/.local/bin"
    run_cmd cp "$tmp_dir/rtk" "$HOME_DIR/.local/bin/rtk"
    run_cmd chmod +x "$HOME_DIR/.local/bin/rtk"
    DEPENDENCY_SUMMARY+=("rtk: installed v${rtk_ver}")
  else
    # Fallback to cargo if direct download failed
    if command -v cargo >/dev/null 2>&1; then
      run_with_spinner "Installing rtk via cargo (fallback)" cargo install --git https://github.com/rtk-ai/rtk
      if command -v rtk >/dev/null 2>&1 || [ -x "$HOME_DIR/.cargo/bin/rtk" ]; then
        DEPENDENCY_SUMMARY+=("rtk: installed (via cargo fallback)")
        rm -rf "$tmp_dir"
        return 0
      fi
    fi
    DEPENDENCY_SUMMARY+=("rtk: install attempted")
  fi
  rm -rf "$tmp_dir"
}

maybe_install_oh_my_posh() {
  if check_dependency_status "oh-my-posh" "oh-my-posh"; then
    return 0
  fi

  if ! prompt_yes_no "Install oh-my-posh via the official install.sh (curl)?"; then
    DEPENDENCY_SUMMARY+=("oh-my-posh: skipped")
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    if prompt_yes_no "oh-my-posh install needs curl. Install curl first?"; then
      local manager
      manager="$(detect_package_manager)"
      install_packages "$manager" curl
    else
      DEPENDENCY_SUMMARY+=("oh-my-posh: missing (requires curl)")
      return 1
    fi
  fi

  run_with_spinner "Installing oh-my-posh" sh -c "curl -s https://ohmyposh.dev/install.sh | bash -s -- -d $HOME_DIR/.local/bin"
  if command -v oh-my-posh >/dev/null 2>&1 || [ -x "$HOME_DIR/.local/bin/oh-my-posh" ]; then
    DEPENDENCY_SUMMARY+=("oh-my-posh: installed")
  else
    DEPENDENCY_SUMMARY+=("oh-my-posh: install attempted")
  fi
}

eza_apt_repo_configured() {
  [ -f /etc/apt/keyrings/gierens.gpg ] || return 1
  [ -f /etc/apt/sources.list.d/gierens.list ] || return 1
  grep -Fq "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
    /etc/apt/sources.list.d/gierens.list 2>/dev/null
}

setup_eza_apt_repo() {
  if eza_apt_repo_configured; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    if prompt_yes_no "eza Debian/Ubuntu install needs curl. Install curl first?"; then
      install_packages apt curl
    else
      DEPENDENCY_SUMMARY+=("eza: missing (requires curl for Debian/Ubuntu repo setup)")
      return 1
    fi
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    if prompt_yes_no "eza Debian/Ubuntu install needs gpg. Install gpg first?"; then
      install_packages apt gnupg
    else
      DEPENDENCY_SUMMARY+=("eza: missing (requires gpg for Debian/Ubuntu repo setup)")
      return 1
    fi
  fi

  run_with_spinner "Creating gierens APT keyring directory for eza" sudo mkdir -p /etc/apt/keyrings || return 1
  run_with_spinner "Installing gierens APT signing key for eza" \
    sh -c 'curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg' || return 1
  run_with_spinner "Adding gierens APT source for eza" \
    sh -c 'echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null' || return 1
  APT_UPDATED=0
  return 0
}

maybe_install_eza() {
  local manager
  manager="$1"

  if check_dependency_status "eza" "eza"; then
    return 0
  fi

  case "$manager" in
  brew | pacman | zypper)
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
      echo "eza upstream notes Fedora 42+ may require manual install or cargo; skipping automatic dnf install." >/dev/tty
    fi
    ;;
  apt)
    if ! prompt_yes_no "Install eza modern ls aliases via the gierens Debian/Ubuntu APT repo?"; then
      DEPENDENCY_SUMMARY+=("eza: skipped")
      return 0
    fi

    if ! setup_eza_apt_repo; then
      DEPENDENCY_SUMMARY+=("eza: install attempted")
      return 0
    fi

    install_packages apt eza
    if command -v eza >/dev/null 2>&1; then
      DEPENDENCY_SUMMARY+=("eza: installed")
    else
      DEPENDENCY_SUMMARY+=("eza: install attempted")
    fi
    ;;
  *)
    DEPENDENCY_SUMMARY+=("eza: missing (manual install)")
    ;;
  esac
}

wezterm_apt_repo_configured() {
  [ -f /usr/share/keyrings/wezterm-fury.gpg ] && [ -f /etc/apt/sources.list.d/wezterm.list ]
}

setup_wezterm_apt_repo() {
  if wezterm_apt_repo_configured; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    if prompt_yes_no "WezTerm install needs curl. Install curl first?"; then
      install_packages apt curl
    else
      return 1
    fi
  fi

  run_with_spinner "Installing WezTerm APT signing key" \
    sh -c 'curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg' || return 1
  run_with_spinner "Adding WezTerm APT source" \
    sh -c 'echo "deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *" | sudo tee /etc/apt/sources.list.d/wezterm.list >/dev/null' || return 1
  APT_UPDATED=0
  return 0
}

maybe_install_wezterm() {
  local manager
  manager="$1"

  if check_dependency_status "wezterm" "wezterm"; then
    return 0
  fi

  case "$manager" in
  apt)
    if prompt_yes_no "Install WezTerm terminal via official APT repo?"; then
      setup_wezterm_apt_repo && install_packages apt wezterm
      if command -v wezterm >/dev/null 2>&1; then
        DEPENDENCY_SUMMARY+=("wezterm: installed")
      else
        DEPENDENCY_SUMMARY+=("wezterm: install attempted")
      fi
    else
      DEPENDENCY_SUMMARY+=("wezterm: skipped")
    fi
    ;;
  brew)
    if prompt_yes_no "Install WezTerm terminal via brew?"; then
      install_packages brew wezterm
      if command -v wezterm >/dev/null 2>&1; then
        DEPENDENCY_SUMMARY+=("wezterm: installed")
      else
        DEPENDENCY_SUMMARY+=("wezterm: install attempted")
      fi
    else
      DEPENDENCY_SUMMARY+=("wezterm: skipped")
    fi
    ;;
  *)
    maybe_note_dependency wezterm "WezTerm terminal (manual install recommended)"
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
  local manager
  manager="$1"
  local aur_helper
  aur_helper=""

  if check_dependency_status "q" "q"; then
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
  pacman)
    if command -v yay >/dev/null 2>&1; then
      aur_helper="yay"
    elif command -v paru >/dev/null 2>&1; then
      aur_helper="paru"
    else
      DEPENDENCY_SUMMARY+=("q: missing (Arch install requires yay or paru for AUR package q-dns-git)")
      return 0
    fi

    if ! prompt_yes_no "Install q via Arch AUR package q-dns-git using $aur_helper?"; then
      DEPENDENCY_SUMMARY+=("q: skipped")
      return 0
    fi

    run_with_spinner "Installing q from AUR package q-dns-git via $aur_helper" \
      "$aur_helper" -S --needed --noconfirm q-dns-git
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

maybe_install_p7zip() {
  local manager
  manager="$1"
  local package_name
  package_name="p7zip"

  if check_dependency_status "7z" "p7zip"; then
    return 0
  fi

  case "$manager" in
  apt) package_name="p7zip-full" ;;
  brew) package_name="p7zip" ;;
  esac

  maybe_install_dependency "$manager" 7z "$package_name" "archive preview and extraction for yazi"
}

maybe_install_poppler() {
  local manager
  manager="$1"
  local package_name
  package_name="poppler"

  if check_dependency_status "pdftotext" "poppler"; then
    return 0
  fi

  case "$manager" in
  apt) package_name="poppler-utils" ;;
  brew) package_name="poppler" ;;
  esac

  maybe_install_dependency "$manager" pdftotext "$package_name" "PDF preview support for yazi"
}

maybe_install_uv() {
  if check_dependency_status "uv" "uv"; then
    return 0
  fi

  if ! prompt_yes_no "Install uv for Python package manager (official installer)?"; then
    is_verbose && echo "skipping uv" >&2
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
  local archive_path
  archive_path="$1"
  local destination_dir
  destination_dir="$2"

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
    is_verbose && echo "skipping bw" >&2
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

  local bw_ver

  bw_ver=$(get_managed_tool bw ver)
  [ -z "$bw_ver" ] && bw_ver="1.22.1"
  release_url="https://github.com/bitwarden/cli/releases/download/v${bw_ver}/bw-linux-${bw_ver}.zip"
  archive_path="${TMPDIR:-/tmp}/bw-linux-${bw_ver}.zip"
  install_root="$STATE_HOME/tools/bitwarden-cli/v${bw_ver}"
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
    DEPENDENCY_SUMMARY+=("bw: installed official v${bw_ver}")
  else
    DEPENDENCY_SUMMARY+=("bw: install attempted")
  fi
}

maybe_install_dua_cli() {
  local manager
  manager="$1"
  local repo_url
  repo_url="https://github.com/byron/dua-cli.git"

  if command -v dua >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("dua: present")
    return 0
  fi

  if ! prompt_yes_no "Install dua-cli for disk usage analysis from byron/dua-cli via cargo?"; then
    is_verbose && echo "skipping dua-cli" >&2
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

source_nvm_if_available() {
  export NVM_DIR="${NVM_DIR:-$HOME_DIR/.nvm}"
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
    return 0
  fi
  return 1
}

ensure_nvm_checkout() {
  export NVM_DIR="${NVM_DIR:-$HOME_DIR/.nvm}"
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    return 0
  fi

  local nvm_repo nvm_ref
  nvm_repo=$(get_managed_tool nvm repo)
  nvm_ref=$(get_managed_tool nvm ref)

  if [ -z "$nvm_repo" ] || [ -z "$nvm_ref" ]; then
    return 1
  fi

  sync_repo "$nvm_repo" "$nvm_ref" "$NVM_DIR" >/dev/null 2>&1 || return 1
  [ -s "$NVM_DIR/nvm.sh" ]
}

maybe_install_node() {
  local node_ver
  node_ver=$(get_dep_field node ver 2>/dev/null || true)
  [ -z "$node_ver" ] && node_ver="24.15.0"

  source_nvm_if_available >/dev/null 2>&1 || true

  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("node: present")
    return 0
  fi

  if ! prompt_yes_no "Install Node.js $node_ver with npm via nvm?"; then
    is_verbose && echo "skipping Node.js" >&2
    DEPENDENCY_SUMMARY+=("node: skipped")
    return 1
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] nvm install $node_ver"
    echo "[dry-run] nvm alias default $node_ver"
    echo "[dry-run] nvm use default"
    DEPENDENCY_SUMMARY+=("node: install preview via nvm")
    return 0
  fi

  if ! ensure_nvm_checkout; then
    DEPENDENCY_SUMMARY+=("node: missing (nvm unavailable)")
    return 1
  fi

  if ! source_nvm_if_available >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("node: missing (nvm could not be loaded)")
    return 1
  fi

  run_with_spinner "Installing Node.js $node_ver via nvm" nvm install "$node_ver"
  run_with_spinner "Setting Node.js $node_ver as nvm default" nvm alias default "$node_ver"
  nvm use default >/dev/null 2>&1 || nvm use "$node_ver" >/dev/null 2>&1 || true

  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("node: installed")
    return 0
  fi

  DEPENDENCY_SUMMARY+=("node: install attempted")
  return 1
}

ensure_node_available_for_pnpm() {
  source_nvm_if_available >/dev/null 2>&1 || true

  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    return 0
  fi

  maybe_install_node || true
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  source_nvm_if_available >/dev/null 2>&1 || true
  command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1
}

maybe_install_pnpm() {
  local pnpm_home
  pnpm_home="${PNPM_HOME:-$HOME_DIR/.local/share/pnpm}"

  if resolve_pnpm_command >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("pnpm: present")
    return 0
  fi

  if ! prompt_yes_no "Install pnpm package manager?"; then
    is_verbose && echo "skipping pnpm" >&2
    DEPENDENCY_SUMMARY+=("pnpm: skipped")
    return 0
  fi

  if ! ensure_node_available_for_pnpm; then
    DEPENDENCY_SUMMARY+=("pnpm: missing (requires Node.js/npm; try oooconf deps node pnpm)")
    return 1
  fi

  export PNPM_HOME="$pnpm_home"
  export PATH="$PNPM_HOME:$PATH"
  run_cmd mkdir -p "$PNPM_HOME"

  local pnpm_ver

  pnpm_ver=$(get_dep_field pnpm ver 2>/dev/null || true)
  [ -z "$pnpm_ver" ] && pnpm_ver="10.18.3"

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] corepack enable --install-directory $PNPM_HOME pnpm"
    echo "[dry-run] corepack prepare pnpm@$pnpm_ver --activate"
    DEPENDENCY_SUMMARY+=("pnpm: install preview via corepack")
    return 0
  fi

  if command -v corepack >/dev/null 2>&1; then
    run_with_spinner "Enabling pnpm@$pnpm_ver via corepack" \
      corepack enable --install-directory "$PNPM_HOME" pnpm
    run_with_spinner "Preparing pnpm@$pnpm_ver via corepack" \
      corepack prepare "pnpm@$pnpm_ver" --activate
  elif command -v npm >/dev/null 2>&1; then
    run_with_spinner "Installing pnpm@$pnpm_ver via npm" \
      npm install --global "pnpm@$pnpm_ver" --prefix "$PNPM_HOME"
    if [ -x "$PNPM_HOME/bin/pnpm" ]; then
      run_cmd ln -sfn "$PNPM_HOME/bin/pnpm" "$PNPM_HOME/pnpm"
    fi
    if [ -x "$PNPM_HOME/bin/pnpx" ]; then
      run_cmd ln -sfn "$PNPM_HOME/bin/pnpx" "$PNPM_HOME/pnpx"
    fi
  else
    DEPENDENCY_SUMMARY+=("pnpm: missing (requires corepack or npm)")
    return 1
  fi

  if resolve_pnpm_command >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("pnpm: installed")
    return 0
  else
    DEPENDENCY_SUMMARY+=("pnpm: install attempted")
    return 1
  fi
}

maybe_install_cargo() {
  if check_dependency_status "cargo" "cargo"; then
    return 0
  fi

  if ! prompt_yes_no "Install Rust and cargo via rustup (official installer)?"; then
    is_verbose && echo "skipping cargo" >&2
    DEPENDENCY_SUMMARY+=("cargo: skipped")
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    run_with_spinner "Installing Rust via rustup" sh -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
  elif command -v wget >/dev/null 2>&1; then
    run_with_spinner "Installing Rust via rustup" sh -c 'wget -qO- https://sh.rustup.rs | sh -s -- -y'
  else
    DEPENDENCY_SUMMARY+=("cargo: missing (requires curl or wget)")
    return 0
  fi

  if command -v cargo >/dev/null 2>&1 || [ -x "$HOME_DIR/.cargo/bin/cargo" ]; then
    DEPENDENCY_SUMMARY+=("cargo: installed")
  else
    DEPENDENCY_SUMMARY+=("cargo: install attempted")
  fi
}
