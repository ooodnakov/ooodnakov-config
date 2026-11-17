# ==========================================
# Standard Zsh Completion & Style Settings
# ==========================================

# Keep the standard completion menu disabled so fzf-tab can capture the prefix.
zstyle ':completion:*' menu no
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':autocomplete:*' add-semicolon no