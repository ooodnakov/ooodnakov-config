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

if [[ -f "$OOODNAKOV_CONFIG_HOME/local/env.zsh" ]]; then
  source "$OOODNAKOV_CONFIG_HOME/local/env.zsh"
  export OOODNAKOV_LOCAL_ENV_LOADED=1
fi

export OOODNAKOV_FORGIT_ALIAS_MODE="${OOODNAKOV_FORGIT_ALIAS_MODE:-plain}"

case "$OOODNAKOV_FORGIT_ALIAS_MODE" in
  plain) export FORGIT_NO_ALIASES=1 ;;
  forgit) unset FORGIT_NO_ALIASES ;;
  *) export FORGIT_NO_ALIASES=1 ;;
esac

fpath=("$OOODNAKOV_CONFIG_HOME/zsh/completions" $fpath)

# Create runtime directories with explicit permissions so compaudit accepts
# the Oh My Zsh completion cache regardless of the caller's umask.
install -d -m 700 "${HISTFILE:h}"
install -d -m 755 "$OOODNAKOV_CACHE_HOME" "${ZSH_COMPDUMP:h}" "$ZSH_CACHE_DIR" "$ZSH_CACHE_DIR/completions"

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

# Rebuild completion caches when tracked custom completion files change.
zsh_oooconf_completion="$OOODNAKOV_CONFIG_HOME/zsh/completions/_oooconf"
if [[ -f "$ZSH_COMPDUMP" && -f "$zsh_oooconf_completion" ]]; then
  if [[ "$zsh_oooconf_completion" -nt "$ZSH_COMPDUMP" || "$zsh_oooconf_completion" -nt "$ZSH_COMPDUMP.zwc" ]]; then
    rm -f "$ZSH_COMPDUMP" "$ZSH_COMPDUMP.zwc"
  fi
fi
unset zsh_oooconf_completion

if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

ZSH_THEME=""
plugins=(
  git
  git-extras
  forgit
  sudo
  extract
  history
  screen
  colorize
  colored-man-pages
  debian
  docker
  python
  web-search
  history-substring-search
  you-should-use
  zsh-syntax-highlighting
  zsh-autocomplete
  fzf-tab
  zsh-autosuggestions
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

if (( $+functions[forgit::log] )); then
  forgit() {
    local subcommand="${1:-log}"
    if (( $# > 0 )); then
      shift
    fi

    case "$subcommand" in
      log) forgit::log "$@" ;;
      diff) forgit::diff "$@" ;;
      add) forgit::add "$@" ;;
      show) forgit::show "$@" ;;
      ignore) forgit::ignore "$@" ;;
      blame) forgit::blame "$@" ;;
      checkout_branch) forgit::checkout::branch "$@" ;;
      checkout_commit) forgit::checkout::commit "$@" ;;
      checkout_tag) forgit::checkout::tag "$@" ;;
      stash_show) forgit::stash::show "$@" ;;
      stash_push) forgit::stash::push "$@" ;;
      clean) forgit::clean "$@" ;;
      rebase) forgit::rebase "$@" ;;
      worktree) forgit::worktree "$@" ;;
      *)
        printf '%s\n' \
          "usage: forgit [log|diff|add|show|ignore|blame|checkout_branch|checkout_commit|checkout_tag|stash_show|stash_push|clean|rebase|worktree] [args...]" >&2
        return 2
        ;;
    esac
  }

  forgit_log() { forgit::log "$@"; }
  forgit_diff() { forgit::diff "$@"; }
  forgit_add() { forgit::add "$@"; }
  forgit_show() { forgit::show "$@"; }
  forgit_ignore() { forgit::ignore "$@"; }
  forgit_blame() { forgit::blame "$@"; }
  forgit_checkout_branch() { forgit::checkout::branch "$@"; }
  forgit_checkout_commit() { forgit::checkout::commit "$@"; }
  forgit_checkout_tag() { forgit::checkout::tag "$@"; }
  forgit_stash_show() { forgit::stash::show "$@"; }
  forgit_stash_push() { forgit::stash::push "$@"; }
  forgit_clean() { forgit::clean "$@"; }
  forgit_rebase() { forgit::rebase "$@"; }
  forgit_worktree() { forgit::worktree "$@"; }
fi

# Bind alias completions explicitly so fzf-tab sees the intended git/forgit
# completer instead of relying on alias expansion heuristics.
if (( $+functions[compdef] )); then
  compdef _git-log forgit_log
  compdef _git-forgit-diff forgit_diff
  compdef _git-add forgit_add
  compdef _git-show forgit_show
  compdef _git-branches forgit_checkout_branch
  compdef __git_recent_commits forgit_checkout_commit
  compdef __git_tags forgit_checkout_tag
  compdef _git-stash-show forgit_stash_show
  compdef _git-add forgit_stash_push
  compdef _git-clean forgit_clean
  compdef _git-rebase forgit_rebase
  compdef _git-worktree forgit_worktree

  case "${OOODNAKOV_FORGIT_ALIAS_MODE:-plain}" in
    forgit)
      compdef _git-add ga
      compdef _git-staged grh
      compdef _git-log glo
      compdef _git-reflog grl
      compdef _git-forgit-diff gd
      compdef _git-show gso
      compdef _git-branches gcb
      compdef _git-switch gsw
      compdef __git_recent_commits gco
      compdef __git_tags gct
      compdef _git-clean gclean
      compdef _git-stash-show gss
      compdef _git-add gsp
      compdef _git-rebase grb
      compdef _git-worktree gwt
      compdef _git-worktrees gwd
      ;;
    *)
      compdef _git-status gs
      compdef _git-diff gd
      compdef _git-commit gc
      compdef _git-push gp
      compdef _git-pull gl
      compdef _git-checkout gco
      compdef _git-log glo
      ;;
  esac
fi

if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh --cmd z)"
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

# Enable completions for optional tools when installed.
if (( $+commands[uv] )); then
  eval "$(uv generate-shell-completion zsh)"
fi

if (( $+commands[rustup] )); then
  source <(rustup completions zsh)
  source <(rustup completions zsh cargo)
fi

if (( $+commands[pnpm] )); then
  # Already has static file in fpath, but if we wanted dynamic:
  # eval "$(pnpm completion zsh)"
  :
fi

if (( $+commands[gum] )); then
  source <(gum completion zsh)
fi

if (( $+commands[bw] )); then
  source <(bw completion --shell zsh)
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
