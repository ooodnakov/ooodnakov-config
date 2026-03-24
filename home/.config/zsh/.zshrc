export TERM="xterm-256color"
export OOODNAKOV_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/ooodnakov"
export OOODNAKOV_SHARE_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/ooodnakov-config"
export ZSH="$OOODNAKOV_SHARE_HOME/oh-my-zsh"
export ZSH_CUSTOM="$ZSH/custom"
export POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true

if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

ZSH_THEME=""
plugins=(
  git
  git-extras
  k
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
  brew
)

for file in "$ZDOTDIR"/.zshrc.d/*.zsh(N); do
  source "$file"
done

source "$ZSH/oh-my-zsh.sh"

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
