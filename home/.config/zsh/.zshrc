export TERM="xterm-256color"
export OOODNAKOV_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/ooodnakov"
export OOODNAKOV_SHARE_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/ooodnakov-config"
export OOODNAKOV_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}/ooodnakov-config"
export OOODNAKOV_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}/ooodnakov-config"
export ZSH="$OOODNAKOV_SHARE_HOME/oh-my-zsh"
export ZSH_CUSTOM="$ZSH/custom"
export ZSH_CACHE_DIR="$OOODNAKOV_CACHE_HOME/oh-my-zsh"
export POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
export HISTFILE="$OOODNAKOV_STATE_HOME/zsh/history"
export ZSH_COMPDUMP="$OOODNAKOV_CACHE_HOME/zsh/.zcompdump-${HOST%%.*}-${ZSH_VERSION}"
export ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=30
export ZSH_AUTOSUGGEST_USE_ASYNC=1

fpath=("$OOODNAKOV_CONFIG_HOME/zsh/completions" $fpath)

mkdir -p "${HISTFILE:h}" "${ZSH_COMPDUMP:h}" "$ZSH_CACHE_DIR"

zstyle ':omz:update' mode disabled

# Remove stale compdump files that use an older oh-my-zsh header format.
# Newer compinit expects the first line to start with "#files:" and fails
# with a math parsing error when it encounters old metadata-first dumps.
if [[ -f "$ZSH_COMPDUMP" ]]; then
  IFS= read -r zsh_compdump_header < "$ZSH_COMPDUMP"
  if [[ "$zsh_compdump_header" != '#files:'* ]]; then
    rm -f "$ZSH_COMPDUMP" "$ZSH_COMPDUMP.zwc"
  fi
  unset zsh_compdump_header
fi

if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

ZSH_THEME=""
plugins=(
  git
  git-extras
  sudo
  extract
  z
  history
  screen
  colorize
  debian
  docker
  python
  web-search
  history-substring-search
  fzf-tab
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-autocomplete
)

for brew_path in "${commands[brew]}" /opt/homebrew/bin/brew /usr/local/bin/brew "$HOME/.linuxbrew/bin/brew" /home/linuxbrew/.linuxbrew/bin/brew; do
  if [[ -x "$brew_path" ]]; then
    brew_prefix="${brew_path:A:h:h}"
    if [[ -d "$brew_prefix" && -O "$brew_prefix" ]]; then
      plugins+=(brew)
    fi
    break
  fi
done
unset brew_path brew_prefix

for file in "$ZDOTDIR"/.zshrc.d/*.zsh(N); do
  source "$file"
done

source "$ZSH/oh-my-zsh.sh"

if [ -f "$ZSH_CUSTOM/plugins/k/k.sh" ]; then
  source "$ZSH_CUSTOM/plugins/k/k.sh"
fi

# direnv supress stdout during startup in path with .envrc
if (( $+commands[direnv] )); then
  autoload -Uz add-zsh-hook
  typeset -gi OOODNAKOV_DIRENV_QUIET_STARTUP=1

  function _ooodnakov_direnv_hook() {
    trap -- '' SIGINT
    if (( OOODNAKOV_DIRENV_QUIET_STARTUP )); then
      eval "$(direnv export zsh 2>/dev/null)"
      OOODNAKOV_DIRENV_QUIET_STARTUP=0
    else
      eval "$(direnv export zsh)"
    fi
    trap - SIGINT
  }

  add-zsh-hook precmd _ooodnakov_direnv_hook
  add-zsh-hook chpwd _ooodnakov_direnv_hook
fi

# Enable uv/uvx completions when uv is installed.
if (( $+commands[uv] )); then
  eval "$(uv generate-shell-completion zsh)"
fi

alias k='k -h'

zmodload zsh/complist 2>/dev/null
bindkey -M menuselect '^M' .accept-line
bindkey -M menuselect '\r' .accept-line

if [ -f "$OOODNAKOV_SHARE_HOME/powerlevel10k/powerlevel10k.zsh-theme" ]; then
  source "$OOODNAKOV_SHARE_HOME/powerlevel10k/powerlevel10k.zsh-theme"
fi

if [ -f "$OOODNAKOV_CONFIG_HOME/p10k.zsh" ]; then
  source "$OOODNAKOV_CONFIG_HOME/p10k.zsh"
fi

if [ -f "$OOODNAKOV_SHARE_HOME/auto-uv-env/auto-uv-env.zsh" ]; then
  source "$OOODNAKOV_SHARE_HOME/auto-uv-env/auto-uv-env.zsh"
fi

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

[[ -s "$HOME/.local/share/marker/marker.sh" ]] && source "$HOME/.local/share/marker/marker.sh"

# To customize prompt, run `p10k configure` or edit ~/.config/ooodnakov/p10k.zsh.
[[ ! -f ~/.config/ooodnakov/p10k.zsh ]] || source ~/.config/ooodnakov/p10k.zsh
