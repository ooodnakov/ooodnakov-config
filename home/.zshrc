# Managed by ooodnakov-config.
# Keep secrets and machine-specific overrides in ~/.config/ooodnakov/local/env.zsh.
# zmodload zsh/zprof
export OOODNAKOV_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/ooodnakov"
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"

if [ -f "$ZDOTDIR/.zshrc" ]; then
  source "$ZDOTDIR/.zshrc"
fi
# zprof
