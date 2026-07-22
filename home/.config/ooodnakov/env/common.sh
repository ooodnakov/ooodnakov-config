if [ -z "$EDITOR" ]; then
  if [ -x "$HOME/.local/share/ooodnakov-config/bin/nvim" ]; then
    export EDITOR="$HOME/.local/share/ooodnakov-config/bin/nvim"
  else
    export EDITOR="$(command -v nvim 2>/dev/null || echo '/usr/bin/nvim')"
  fi
fi
export VISUAL="${VISUAL:-$EDITOR}"
export PAGER="${PAGER:-less}"
export LESS="-FRX"
export YAZI_CONFIG_HOME="${YAZI_CONFIG_HOME:-$HOME/.config/yazi}"
export PILENS_DATA_DIR="${PILENS_DATA_DIR:-$HOME/.pi-lens/data}"
export SUDO_EDITOR="${SUDO_EDITOR:-$EDITOR}"
alias snvim="sudo -e"

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

if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
elif [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

NPM_PACKAGES="$HOME/.npm"
path_prepend "$NPM_PACKAGES/bin"

export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
path_prepend "$BUN_INSTALL/bin"

export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
path_prepend "$PNPM_HOME"
path_prepend "$PNPM_HOME/bin"

export GOPATH="${GOPATH:-$HOME/go}"
path_prepend "$GOPATH/bin"

if ! command -v o >/dev/null 2>&1 && command -v oooconf >/dev/null 2>&1; then
  o() {
    oooconf "$@"
  }
fi
# pnpm runtime set node lts -g
unset -f path_prepend
