export EDITOR="${EDITOR:-$HOME/.local/share/ooodnakov-config/bin/nvim}"
export VISUAL="${VISUAL:-$EDITOR}"
export PAGER="${PAGER:-less}"
export LESS="-FRX"
export YAZI_CONFIG_HOME="${YAZI_CONFIG_HOME:-$HOME/.config/yazi}"

export SUDO_EDITOR="${SUDO_EDITOR:-$EDITOR}"
snvim() {
  sudo env "PATH=$HOME/.local/share/ooodnakov-config/bin:$HOME/.local/bin:$PATH" "$EDITOR" "$@"
}

path_prepend() {
  case ":$PATH:" in
    *":$1:"*) ;;
    *) export PATH="$1:$PATH" ;;
  esac
}

if [ -f "$HOME/.local/bin/env" ]; then
  . "$HOME/.local/bin/env"
fi

path_prepend "$HOME/.local/bin"
path_prepend "$HOME/.cargo/bin"
path_prepend "${XDG_DATA_HOME:-$HOME/.local/share}/ooodnakov-config/bin"

NPM_PACKAGES="$HOME/.npm"
path_prepend "$NPM_PACKAGES/bin"

export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
path_prepend "$PNPM_HOME"

if ! command -v o >/dev/null 2>&1 && command -v oooconf >/dev/null 2>&1; then
  o() {
    oooconf "$@"
  }
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

if [ -f "${XDG_DATA_HOME:-$HOME/.local/share}/ooodnakov-config/marker/marker.sh" ]; then
  . "${XDG_DATA_HOME:-$HOME/.local/share}/ooodnakov-config/marker/marker.sh"
fi

unset -f path_prepend
