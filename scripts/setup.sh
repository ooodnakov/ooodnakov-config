#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${HOME}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME_DIR/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME_DIR/.local/share}"
STATE_HOME="$DATA_HOME/ooodnakov-config"
FONT_TARGET_DIR="${XDG_DATA_HOME:-$HOME_DIR/.local/share}/fonts/ooodnakov"
COMMAND="${1:-install}"
BACKUP_ROOT="${OOODNAKOV_BACKUP_ROOT:-$HOME_DIR/.local/state/ooodnakov-config/backups}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
INTERACTIVE="${OOODNAKOV_INTERACTIVE:-auto}"
DEPENDENCY_SUMMARY=()
TOOL_SUMMARY=()

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
K_REPO="https://github.com/supercrabtree/k.git"
K_REF="e2bfbaf3b8ca92d6ffc4280211805ce4b8a8c19e"
MARKER_REPO="https://github.com/jotyGill/marker.git"
MARKER_REF="c123085891228e51cfa58d555708bad67ed98f02"
TODO_REPO="https://github.com/todotxt/todo.txt-cli.git"
TODO_REF="b20f9b45e210129ef020d3ba212d86b9ba9cf70d"

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

link_file() {
  local source="$1"
  local target="$2"
  mkdir -p "$(dirname "$target")"
  backup_target "$source" "$target"
  ln -sfn "$source" "$target"
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
  mkdir -p "$backup_dir"

  if [ -d "$target" ] && [ ! -L "$target" ]; then
    mv "$target" "$backup_dir/${target_name}.${TIMESTAMP}"
  else
    mv "$target" "$backup_dir/${target_name}.${TIMESTAMP}"
  fi
  echo "backed up $target -> $backup_dir/${target_name}.${TIMESTAMP}"
}

sync_repo() {
  local repo_url="$1"
  local ref="$2"
  local target="$3"

  if [ ! -d "$target/.git" ]; then
    git clone "$repo_url" "$target"
  fi

  git -C "$target" fetch origin "$ref"
  git -c advice.detachedHead=false -C "$target" checkout "$ref"
}

ensure_ssh_include() {
  local ssh_dir="$HOME_DIR/.ssh"
  local ssh_config="$ssh_dir/config"
  local include_line="Include ~/.config/ooodnakov/ssh/config"

  mkdir -p "$ssh_dir"
  touch "$ssh_config"

  if ! grep -Fqx "$include_line" "$ssh_config"; then
    printf "%s\n\n" "$include_line" | cat - "$ssh_config" > "$ssh_config.tmp"
    mv "$ssh_config.tmp" "$ssh_config"
  fi
}

install_fonts() {
  local source_dir="$REPO_ROOT/fonts/meslo"

  if [ -d "$source_dir" ]; then
    mkdir -p "$FONT_TARGET_DIR"
    cp "$source_dir"/*.ttf "$FONT_TARGET_DIR"/
    if command -v fc-cache >/dev/null 2>&1; then
      fc-cache -f "$FONT_TARGET_DIR" >/dev/null 2>&1 || true
    fi
  fi
}

install_managed_tools() {
  local bin_dir="$STATE_HOME/bin"

  sync_repo "$K_REPO" "$K_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/k"
  TOOL_SUMMARY+=("k: synced")
  sync_repo "$MARKER_REPO" "$MARKER_REF" "$STATE_HOME/marker"
  TOOL_SUMMARY+=("marker: synced")
  sync_repo "$TODO_REPO" "$TODO_REF" "$STATE_HOME/todo"
  TOOL_SUMMARY+=("todo.txt-cli: synced")

  mkdir -p "$bin_dir"
  ln -sfn "$STATE_HOME/todo/todo.sh" "$bin_dir/todo.sh"
  TOOL_SUMMARY+=("todo.sh: linked into $bin_dir")

  if command -v python3 >/dev/null 2>&1 && [ -f "$STATE_HOME/marker/install.py" ]; then
    python3 "$STATE_HOME/marker/install.py" >/dev/null 2>&1 || true
    TOOL_SUMMARY+=("marker: install.py attempted")
  else
    TOOL_SUMMARY+=("marker: install.py skipped")
  fi
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
}

update_repo() {
  git -C "$REPO_ROOT" pull --ff-only
}

install_optional_dependencies() {
  local manager
  manager="$(detect_package_manager)"

  echo "Dependency check:"
  maybe_install_dependency "$manager" wget wget "downloading auxiliary assets and parity with ezsh tooling"
  maybe_install_dependency "$manager" zsh zsh "default shell support"
  maybe_install_dependency "$manager" fzf fzf "fzf shell integration"
  maybe_install_dependency "$manager" eza eza "modern ls aliases"
  maybe_install_dependency "$manager" dua dua-cli "disk usage analysis"
  maybe_install_dependency "$manager" autoconf autoconf "building optional ezsh native components"
  maybe_install_dependency "$manager" fc-cache fontconfig "refreshing installed font caches"
  maybe_note_dependency k "manual install if you want the standalone k command"
  maybe_install_dependency "$manager" python3 python3 "extra ezsh-style tools such as marker and helper scripts"
}

case "$COMMAND" in
  install)
    ;;
  update)
    update_repo
    ;;
  *)
    echo "Usage: $0 [install|update]" >&2
    exit 1
    ;;
esac

mkdir -p "$CONFIG_HOME" "$DATA_HOME" "$STATE_HOME"

install_optional_dependencies

sync_repo "$OH_MY_ZSH_REPO" "$OH_MY_ZSH_REF" "$STATE_HOME/oh-my-zsh"
sync_repo "$P10K_REPO" "$P10K_REF" "$STATE_HOME/powerlevel10k"
sync_repo "$ZSH_AUTOSUGGESTIONS_REPO" "$ZSH_AUTOSUGGESTIONS_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-autosuggestions"
sync_repo "$ZSH_HIGHLIGHTING_REPO" "$ZSH_HIGHLIGHTING_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
sync_repo "$ZSH_HISTORY_REPO" "$ZSH_HISTORY_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-history-substring-search"
sync_repo "$ZSH_AUTOCOMPLETE_REPO" "$ZSH_AUTOCOMPLETE_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-autocomplete"
install_managed_tools

link_file "$REPO_ROOT/home/.zshrc" "$HOME_DIR/.zshrc"
link_file "$REPO_ROOT/home/.config/zsh" "$CONFIG_HOME/zsh"
link_file "$REPO_ROOT/home/.config/wezterm" "$CONFIG_HOME/wezterm"
link_file "$REPO_ROOT/home/.config/ooodnakov" "$CONFIG_HOME/ooodnakov"

mkdir -p "$CONFIG_HOME/ohmyposh" "$CONFIG_HOME/powershell"
link_file "$REPO_ROOT/home/.config/ohmyposh/ooodnakov.omp.json" "$CONFIG_HOME/ohmyposh/ooodnakov.omp.json"
link_file "$REPO_ROOT/home/.config/powershell/Microsoft.PowerShell_profile.ps1" "$CONFIG_HOME/powershell/Microsoft.PowerShell_profile.ps1"

ensure_ssh_include
install_fonts

if is_interactive && [ -f "$HOME_DIR/.zshrc" ]; then
  # This only updates the current setup process; it cannot mutate the parent shell session.
  # shellcheck disable=SC1090
  . "$HOME_DIR/.zshrc" || true
fi

print_summary

echo
echo "Bootstrap complete."
echo "If needed, create local overrides in $CONFIG_HOME/ooodnakov/local."
