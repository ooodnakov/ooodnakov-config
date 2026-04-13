# Keep the standard completion menu disabled so fzf-tab can capture the prefix.
zstyle ':completion:*' menu no
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':fzf-tab:*' switch-group '<' '>'
zstyle ':fzf-tab:*' fzf-bindings-default tab:down,btab:up,change:top,alt-s:toggle,bspace:backward-delete-char/eof,ctrl-h:backward-delete-char/eof
zstyle ':fzf-tab:complete:oooconf:*' fzf-flags --height=45% --layout=reverse --border=top
zstyle ':fzf-tab:complete:oooconf:*' show-group full
zstyle ':fzf-tab:complete:oooconf:*' query-string input
zstyle ':fzf-tab:complete:oooconf:*' fzf-preview '
case "${words[2]}" in
  deps)
    printf "dependency: %s\n\n%s\n" "$word" "$desc"
    ;;
  secrets)
    if [[ -n "${words[3]:-}" && "${words[3]}" != "$word" ]]; then
      printf "secrets %s\n\n%s\n" "$word" "$desc"
    else
      printf "subcommand: %s\n\n%s\n" "$word" "$desc"
    fi
    ;;
  ""|-*)
    printf "command: %s\n\n%s\n" "$word" "$desc"
    ;;
  *)
    printf "%s\n\n%s\n" "$word" "$desc"
    ;;
esac
'

if (( $+commands[eza] )); then
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
fi
