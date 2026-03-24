# Keep the standard completion menu disabled so fzf-tab can capture the prefix.
zstyle ':completion:*' menu no
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':fzf-tab:*' switch-group '<' '>'

if (( $+commands[eza] )); then
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
fi
