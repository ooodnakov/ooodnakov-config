export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-$EDITOR}"
export PAGER="${PAGER:-less}"
export LESS="-FRX"

if [ -f "$HOME/.local/bin/env" ]; then
  . "$HOME/.local/bin/env"
fi

export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="${XDG_DATA_HOME:-$HOME/.local/share}/ooodnakov-config/bin:$PATH"

NPM_PACKAGES="$HOME/.npm"
export PATH="$NPM_PACKAGES/bin:$PATH"

export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

if [ -f "${XDG_DATA_HOME:-$HOME/.local/share}/ooodnakov-config/marker/marker.sh" ]; then
  . "${XDG_DATA_HOME:-$HOME/.local/share}/ooodnakov-config/marker/marker.sh"
fi
