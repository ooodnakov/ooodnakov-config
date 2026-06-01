# ==========================================
# Standard Zsh Completion & Style Settings
# ==========================================

# Keep the standard completion menu disabled so fzf-tab can capture the prefix.
zstyle ':completion:*' menu no
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':autocomplete:*' add-semicolon no

# ==========================================
# Fzf-tab Global Settings
# ==========================================

zstyle ':fzf-tab:*' switch-group '<' '>'
zstyle ':fzf-tab:*' fzf-bindings-default tab:down,btab:up,change:top,alt-s:toggle,bspace:backward-delete-char/eof,ctrl-h:backward-delete-char/eof

# ==========================================
# Custom Directory Previews (cd)
# ==========================================

# Use eza if available, fall back to standard ls with colors, or a basic ls
if (( $+commands[eza] )); then
  zstyle ':fzf-tab:complete:(cd|z):*' fzf-preview 'eza -1 --color=always --icons=always $realpath'
elif [[ "$OSTYPE" == "darwin"* ]]; then
  zstyle ':fzf-tab:complete:(cd|z):*' fzf-preview 'ls -1G $realpath'
else
  zstyle ':fzf-tab:complete:(cd|z):*' fzf-preview 'ls -1 --color=always $realpath'
fi
# ==========================================
# Custom Previews: oooconf
# ==========================================

# Group configuration
zstyle ':fzf-tab:complete:(o|oooconf):*' fzf-flags --height=45% --layout=reverse --border=top
zstyle ':fzf-tab:complete:(o|oooconf):*' show-group full
zstyle ':fzf-tab:complete:(o|oooconf):*' query-string input

# Optimized Preview Script
# Note: Single quotes wrap the entire zstyle definition, double quotes used safely inside.
zstyle ':fzf-tab:complete:(o|oooconf):*' fzf-preview '
  subcmd="${words[2]}"
  
  case "$subcmd" in
    deps)
      printf "dependency: %s\n\n%s\n" "$word" "$desc"
      ;;
    secrets)
      # Streamlined lookahead check for the 3rd argument
      if [[ -n "${words[3]}" && "${words[3]}" != "$word" ]]; then
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
# ==========================================
# Custom Previews for Binaries/Commands
# ==========================================

# Previews the command using 'tldr' if installed, otherwise falls back to 'man'
if (( $+commands[tldr] )); then
  zstyle ':fzf-tab:complete:-command-:*' fzf-preview 'tldr --color=always "$word" 2>/dev/null || man "$word" 2>/dev/null'
else
  zstyle ':fzf-tab:complete:-command-:*' fzf-preview 'man "$word" 2>/dev/null'
fi
# ==========================================
# Generic fallback preview for ALL files and folders on your system
# ==========================================
# Generic fallback preview for ALL system contexts (Folders, Images, Archives, Text)
zstyle ':fzf-tab:complete:*' fzf-preview '
  # 📁 DIRECTORY PREVIEWS
  if [[ -d "$realpath" ]]; then
    eza -1 --color=always --icons=always "$realpath" 2>/dev/null || ls -1G "$realpath"

  # 📄 FILE PREVIEWS
  elif [[ -f "$realpath" ]]; then
    mime=$(file --mime-type -b "$realpath")

    case "$mime" in
      # 🖼️ IMAGE PREVIEWS (WezTerm Native)
      image/*)
        if (( $+commands[wezterm] )); then
          chafa "$realpath"
        else
          printf "Image: %s\n(wezterm binary not found in PATH)" "$(basename "$realpath")"
        fi
        ;;

      # 📦 ARCHIVE PREVIEWS (7-Zip Only)
      application/zip|application/x-tar|application/x-bzip2|application/x-gzip|application/x-7z-compressed|application/x-rar)
        if (( $+commands[7z] )); then
          7z l "$realpath" 2>/dev/null
        else
          printf "Archive: %s\n(Install 7z to preview contents)" "$(basename "$realpath")"
        fi
        ;;

      # 📝 TEXT/CODE PREVIEWS
      *)
        if (( $+commands[bat] )); then
          bat --style=numbers --color=always --line-range :500 "$realpath" 2>/dev/null
        else
          cat "$realpath" 2>/dev/null
        fi
        ;;
    esac
  else
    printf "System Context: %s\n" "$word"
  fi
'