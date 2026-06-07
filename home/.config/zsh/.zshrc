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

if [[ -f "$OOODNAKOV_CONFIG_HOME/env/common.sh" ]]; then
  source "$OOODNAKOV_CONFIG_HOME/env/common.sh"
fi

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

fpath=("$OOODNAKOV_CONFIG_HOME/zsh/completions" "$OOODNAKOV_CONFIG_HOME/zsh/completions/autogen" $fpath)

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
zsh_completion_watch_files=(
  "$OOODNAKOV_CONFIG_HOME/zsh/completions/_oooconf"
  "$OOODNAKOV_CONFIG_HOME/zsh/completions/autogen/.autogen-stamp"
)
if [[ -f "$ZSH_COMPDUMP" ]]; then
  for zsh_completion_watch_file in "${zsh_completion_watch_files[@]}"; do
    if [[ -f "$zsh_completion_watch_file" ]]; then
      if [[ "$zsh_completion_watch_file" -nt "$ZSH_COMPDUMP" || ( -f "$ZSH_COMPDUMP.zwc" && "$zsh_completion_watch_file" -nt "$ZSH_COMPDUMP.zwc" ) ]]; then
        rm -f "$ZSH_COMPDUMP" "$ZSH_COMPDUMP.zwc"
        break
      fi
    fi
  done
fi
unset zsh_completion_watch_file zsh_completion_watch_files

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
  zsh-fzf-history-search
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

if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  print -u2 "oooconf: oh-my-zsh is missing at $ZSH; run 'oooconf install' to restore managed shell plugins."
fi

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

# Custom SSH forward completion (defined in .zshrc.d/10-shell.zsh)
if (( $+functions[_ssh_forward_advanced] )); then
  compdef _ssh_forward_advanced ssh-forward
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

# Enable completion aliases for optional tools when installed.
if (( $+commands[uv] )) && (( $+functions[compdef] )); then
  # _uv is generated by `oooconf completions`. uvx is equivalent to
  # `uv tool run`, so wrap _uv with adjusted completion words.
  _uvx() {
    autoload -Uz _uv 2>/dev/null || return 1
    local -a uv_words
    uv_words=(uv tool run "${words[@]:1}")
    local CURRENT=$((CURRENT + 2))
    words=("${uv_words[@]}")
    _uv
  }
  compdef _uvx uvx
fi


if (( $+commands[pnpm] )); then
  # Already has static file in fpath.
  :
fi

alias k='k -h'

zmodload zsh/complist 2>/dev/null
if bindkey -M menuselect >/dev/null 2>&1; then
  bindkey -M menuselect '^M' .accept-line
  bindkey -M menuselect '\r' .accept-line
fi

case "${OOOCONF_ZSH_PROMPT:-p10k}" in
  ohmyposh)
    ooodnakov_omp_config="${OOOCONF_OMP_CONFIG:-$HOME/.config/ohmyposh/ooodnakov.omp.json}"
    if (( $+commands[oh-my-posh] )) && [[ -r "$ooodnakov_omp_config" ]]; then
      eval "$(oh-my-posh init zsh --config "$ooodnakov_omp_config")"
    elif (( $+commands[oh-my-posh] )); then
      print -u2 "oooconf: oh-my-posh config is missing at $ooodnakov_omp_config; falling back to Powerlevel10k."
      OOOCONF_ZSH_PROMPT=p10k
    else
      print -u2 "oooconf: oh-my-posh is missing; run 'oooconf install oh-my-posh' or 'oooconf shell prompt p10k'."
      OOOCONF_ZSH_PROMPT=p10k
    fi
    ;;
esac

if [[ "${OOOCONF_ZSH_PROMPT:-p10k}" != ohmyposh ]]; then
  for p10k_theme_file in \
    "$OOODNAKOV_SHARE_HOME/powerlevel10k/powerlevel10k.zsh-theme" \
    "$HOME/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme" \
    "/usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme"; do
    if [ -f "$p10k_theme_file" ]; then
      source "$p10k_theme_file"
      break
    fi
  done

  if (( ! $+functions[p10k] )); then
    print -u2 "oooconf: powerlevel10k is missing at $OOODNAKOV_SHARE_HOME/powerlevel10k; run 'oooconf install' to restore the managed prompt."
  fi
  unset p10k_theme_file

  if [ -f "$OOODNAKOV_CONFIG_HOME/p10k.zsh" ]; then
    source "$OOODNAKOV_CONFIG_HOME/p10k.zsh"
  fi
fi
unset ooodnakov_omp_config

ooodnakov_auto_uv_env_mode="${OOODNAKOV_AUTO_UV_ENV_MODE:-}"
if [[ -z "$ooodnakov_auto_uv_env_mode" ]]; then
  if [[ "${AUTO_UV_ENV_QUIET:-0}" == "1" ]]; then
    ooodnakov_auto_uv_env_mode=quiet
  else
    ooodnakov_auto_uv_env_mode=existing
  fi
fi
case "$ooodnakov_auto_uv_env_mode" in
  disabled|existing|enabled|quiet) ;;
  *) ooodnakov_auto_uv_env_mode=existing ;;
esac


case "$ooodnakov_auto_uv_env_mode" in
  disabled)
    if (( $+functions[add-zsh-hook] )) && (( $+functions[auto_uv_env] )); then
      add-zsh-hook -d chpwd auto_uv_env 2>/dev/null || true
    fi
    ;;
  existing)
    _ooodnakov_auto_uv_env_find_project_dir() {
      local dir="$PWD"
      while true; do
        if [[ -f "$dir/.auto-uv-env-ignore" ]]; then
          return 2
        fi
        if [[ -f "$dir/pyproject.toml" ]]; then
          print -r -- "$dir"
          return 0
        fi
        [[ "$dir" == "/" ]] && return 1
        dir="${dir%/*}"
        [[ -z "$dir" ]] && dir="/"
      done
    }

    _ooodnakov_auto_uv_env_is_within_dir() {
      local path="$1"
      local base="$2"

      [[ -n "$base" ]] || return 1
      [[ "$base" != "/" ]] && base="${base%/}"
      [[ "$path" != "/" ]] && path="${path%/}"

      if [[ "$base" == "/" ]]; then
        [[ "$path" == /* ]]
      else
        [[ "$path" == "$base" || "$path" == "$base/"* ]]
      fi
    }

    _ooodnakov_auto_uv_env_deactivate() {
      if [[ -n "${VIRTUAL_ENV:-}" ]] && [[ -n "${_AUTO_UV_ENV_ACTIVATION_DIR:-}" ]]; then
        if (( $+functions[deactivate] )); then
          deactivate
        else
          unset VIRTUAL_ENV
        fi
        unset _AUTO_UV_ENV_ACTIVATION_DIR
        unset AUTO_UV_ENV_PYTHON_VERSION
        [[ "${AUTO_UV_ENV_QUIET:-0}" != "1" ]] && print -P "%F{yellow}⬇️%f  Deactivated UV environment"
      fi
    }

    auto_uv_env() {
      if [[ -n "${VIRTUAL_ENV:-}" ]] && [[ -n "${_AUTO_UV_ENV_ACTIVATION_DIR:-}" ]] && _ooodnakov_auto_uv_env_is_within_dir "$PWD" "$_AUTO_UV_ENV_ACTIVATION_DIR"; then
        if [[ ! -d "$VIRTUAL_ENV" ]]; then
          [[ "${AUTO_UV_ENV_QUIET:-0}" != "1" ]] && print -P "%F{yellow}⚠️%f  Virtual environment was deleted, cleaning up..."
          unset VIRTUAL_ENV
          unset _AUTO_UV_ENV_ACTIVATION_DIR
          unset AUTO_UV_ENV_PYTHON_VERSION
        fi
      fi

      local project_dir="" project_status=0
      project_dir="$(_ooodnakov_auto_uv_env_find_project_dir)" || project_status=$?

      if [[ $project_status -eq 2 ]]; then
        _ooodnakov_auto_uv_env_deactivate
        return 0
      fi

      if [[ $project_status -ne 0 || -z "$project_dir" ]]; then
        if [[ -n "${_AUTO_UV_ENV_ACTIVATION_DIR:-}" ]] && ! _ooodnakov_auto_uv_env_is_within_dir "$PWD" "$_AUTO_UV_ENV_ACTIVATION_DIR"; then
          _ooodnakov_auto_uv_env_deactivate
        fi
        return 0
      fi

      if [[ -n "${VIRTUAL_ENV:-}" ]] && [[ "${_AUTO_UV_ENV_ACTIVATION_DIR:-}" == "$project_dir" ]] && [[ -d "$VIRTUAL_ENV" ]]; then
        return 0
      fi

      if [[ -n "${_AUTO_UV_ENV_ACTIVATION_DIR:-}" ]] && ! _ooodnakov_auto_uv_env_is_within_dir "$PWD" "$_AUTO_UV_ENV_ACTIVATION_DIR"; then
        _ooodnakov_auto_uv_env_deactivate
      fi

      [[ -n "${VIRTUAL_ENV:-}" ]] && return 0

      local venv_dir="${AUTO_UV_ENV_VENV_NAME:-.venv}"
      local activate_path="$project_dir/$venv_dir/bin/activate"
      [[ -f "$activate_path" ]] || return 0

      source "$activate_path"
      export _AUTO_UV_ENV_ACTIVATION_DIR="$project_dir"

      local python_version python_full_version
      if python_full_version="$(python --version 2>&1)"; then
        python_version="${python_full_version#Python }"
        export AUTO_UV_ENV_PYTHON_VERSION="$python_version"
        [[ "${AUTO_UV_ENV_QUIET:-0}" != "1" ]] && print -P "%F{green}🚀%f UV environment activated (Python $python_version)"
      else
        export AUTO_UV_ENV_PYTHON_VERSION="unknown"
        [[ "${AUTO_UV_ENV_QUIET:-0}" != "1" ]] && print -P "%F{green}🚀%f UV environment activated (Python not installed)"
      fi
    }

    autoload -U add-zsh-hook
    add-zsh-hook -d chpwd auto_uv_env 2>/dev/null || true
    add-zsh-hook chpwd auto_uv_env
    auto_uv_env
    ;;
  enabled|quiet)
    if [[ "$ooodnakov_auto_uv_env_mode" == quiet ]]; then
      export AUTO_UV_ENV_QUIET=1
    else
      export AUTO_UV_ENV_QUIET=0
    fi

    if [[ -f "$OOODNAKOV_SHARE_HOME/auto-uv-env/auto-uv-env.zsh" ]]; then
      # Guard against duplicate hook registration when the profile is re-sourced.
      # Multiple auto_uv_env chpwd hooks can cause repeated "Creating UV environment"
      # / activation status lines for a single directory change.
      if [[ -z "${OOODNAKOV_AUTO_UV_ENV_LOADED:-}" ]]; then
        export OOODNAKOV_AUTO_UV_ENV_LOADED=1
        # auto-uv-env runs an immediate startup check when sourced. Quiet only that
        # first run so opening a shell in a Python project doesn't spam status text.
        source "$OOODNAKOV_SHARE_HOME/auto-uv-env/auto-uv-env.zsh" >/dev/null 2>&1
      fi

      if (( $+functions[add-zsh-hook] )) && (( $+functions[auto_uv_env] )); then
        add-zsh-hook -d chpwd auto_uv_env 2>/dev/null || true
        add-zsh-hook chpwd auto_uv_env
      fi
    fi
    ;;
esac
unset ooodnakov_auto_uv_env_mode

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
bindkey '^R' fzf_history_search

[[ -s "$HOME/.local/share/marker/marker.sh" ]] && source "$HOME/.local/share/marker/marker.sh"

# To customize the Powerlevel10k prompt, edit ~/.config/ooodnakov/p10k.zsh.

unalias x 2>/dev/null
[ -f "$HOME/.x-cmd.root/X" ] && . "$HOME/.x-cmd.root/X" # boot up x-cmd.
unalias h 2>/dev/null

[ -f "$HOME/.x-cmd.root/X" ] && . "$HOME/.x-cmd.root/X" # boot up x-cmd.

# Re-add pnpm after x-cmd so it takes precedence over brew
# Only modify PATH if pnpm is not already at position 1
if [ -n "$PNPM_HOME" ] && [ "$path[1]" != "$PNPM_HOME" ]; then
  # Remove any existing pnpm entries
  path=("${(@)path:#$PNPM_HOME}" "${(@)path:#$PNPM_HOME/bin}")
  # Prepend pnpm at front
  path=("$PNPM_HOME" "$PNPM_HOME/bin" "$path[@]")
fi

# Remove duplicate PATH entries (x-cmd adds duplicates)
typeset -U path

function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}
