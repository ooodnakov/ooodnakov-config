#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${HOME}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME_DIR/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME_DIR/.local/share}"
STATE_HOME="$DATA_HOME/ooodnakov-config"
FONT_TARGET_DIR="${XDG_DATA_HOME:-$HOME_DIR/.local/share}/fonts/ooodnakov"

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

link_file() {
  local source="$1"
  local target="$2"
  mkdir -p "$(dirname "$target")"
  ln -sfn "$source" "$target"
  echo "linked $target"
}

sync_repo() {
  local repo_url="$1"
  local ref="$2"
  local target="$3"

  if [ ! -d "$target/.git" ]; then
    git clone "$repo_url" "$target"
  fi

  git -C "$target" fetch origin "$ref"
  git -C "$target" checkout "$ref"
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

mkdir -p "$CONFIG_HOME" "$DATA_HOME" "$STATE_HOME"

sync_repo "$OH_MY_ZSH_REPO" "$OH_MY_ZSH_REF" "$STATE_HOME/oh-my-zsh"
sync_repo "$P10K_REPO" "$P10K_REF" "$STATE_HOME/powerlevel10k"
sync_repo "$ZSH_AUTOSUGGESTIONS_REPO" "$ZSH_AUTOSUGGESTIONS_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-autosuggestions"
sync_repo "$ZSH_HIGHLIGHTING_REPO" "$ZSH_HIGHLIGHTING_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
sync_repo "$ZSH_HISTORY_REPO" "$ZSH_HISTORY_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-history-substring-search"
sync_repo "$ZSH_AUTOCOMPLETE_REPO" "$ZSH_AUTOCOMPLETE_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-autocomplete"

link_file "$REPO_ROOT/home/.zshrc" "$HOME_DIR/.zshrc"
link_file "$REPO_ROOT/home/.config/zsh" "$CONFIG_HOME/zsh"
link_file "$REPO_ROOT/home/.config/wezterm" "$CONFIG_HOME/wezterm"
link_file "$REPO_ROOT/home/.config/ooodnakov" "$CONFIG_HOME/ooodnakov"

mkdir -p "$CONFIG_HOME/ohmyposh" "$CONFIG_HOME/powershell"
link_file "$REPO_ROOT/home/.config/ohmyposh/ooodnakov.omp.json" "$CONFIG_HOME/ohmyposh/ooodnakov.omp.json"
link_file "$REPO_ROOT/home/.config/powershell/Microsoft.PowerShell_profile.ps1" "$CONFIG_HOME/powershell/Microsoft.PowerShell_profile.ps1"

ensure_ssh_include
install_fonts

echo
echo "Bootstrap complete."
echo "If needed, create local overrides in $CONFIG_HOME/ooodnakov/local."
