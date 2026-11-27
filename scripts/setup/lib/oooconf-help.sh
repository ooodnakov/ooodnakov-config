#!/usr/bin/env bash
# Sourced by scripts/setup/ooodnakov.sh; do not execute directly.

_help_python_available() {
  [ -f "$REPO_ROOT/scripts/cli/render_help.py" ] && {
    (command -v uv >/dev/null 2>&1 && [ -f "$REPO_ROOT/pyproject.toml" ] && [ -z "${UV_RUN_RECURSION_DEPTH:-}" ]) ||
      command -v python3 >/dev/null 2>&1
  }
}

print_help_for_scope() {
  local scope="${1:-main}"

  case "$scope" in
    shell|color|delta|wm|komorebi)
      command_usage "$scope"
      ;;
    wm.bar|"wm bar")
      command_usage "wm bar"
      ;;
    *)
      usage
      ;;
  esac
}

report_unknown_command() {
  local subject="$1"
  local suggestion="${2:-}"
  local scope="${3:-main}"
  local mode

  mode="$(get_typo_handling_mode)"
  case "$mode" in
    silent)
      ;;
    suggest)
      if [ -n "$suggestion" ]; then
        visible_error "Did you mean: $suggestion"
      else
        visible_error "$subject"
      fi
      ;;
    help|*)
      visible_error "$subject"
      if [ -n "$suggestion" ]; then
        visible_error "Did you mean: $suggestion"
      fi
      print_help_for_scope "$scope"
      ;;
  esac
}

resolve_command_alias() {
  case "$1" in
    check) printf 'doctor\n' ;;
    preview) printf 'dry-run\n' ;;
    upgrade) printf 'update\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

command_distance() {
  local left="$1"
  local right="$2"

  if [ "$left" = "$right" ]; then
    printf '0\n'
    return 0
  fi
  local diff=$(( ${#left} - ${#right} ))
  [ "$diff" -lt 0 ] && diff=$(( -diff ))
  printf '%s\n' $(( diff + 1 ))
}

_fallback_suggest_from_list() {
  local input="$1"
  shift
  local candidate word
  [ -n "$input" ] || return 0
  for candidate in "$@"; do
    for word in $candidate; do
      case "$word" in
        "$input") printf '%s\n' "$word"; return 0 ;;
      esac
    done
  done
  for candidate in "$@"; do
    for word in $candidate; do
      case "$word" in
        "$input"*|*"$input"*) printf '%s\n' "$word"; return 0 ;;
      esac
    done
  done
  return 0
}

suggest_command() {
  local input="$1"

  if [ -n "$input" ] && _help_python_available; then
    run_python "$REPO_ROOT/scripts/cli/render_help.py" \
      --mode suggest --repo-root "$REPO_ROOT" --platform unix --input "$input" 2>/dev/null && return 0
  fi

  _fallback_suggest_from_list "$input" "${KNOWN_COMMANDS[@]}"
}

suggest_from_list() {
  local input="$1"
  shift

  if [ -n "$input" ] && [ "$#" -gt 0 ] && _help_python_available; then
    run_python "$REPO_ROOT/scripts/cli/render_help.py" \
      --mode suggest --repo-root "$REPO_ROOT" --input "$input" --candidates "$@" 2>/dev/null && return 0
  fi

  _fallback_suggest_from_list "$input" "$@"
}

print_version() {
  if command -v git >/dev/null 2>&1 && [ -d "$REPO_ROOT/.git" ]; then
    git -C "$REPO_ROOT" describe --always --dirty --tags 2>/dev/null || git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

_usage_fallback() {
  cat <<EOF
Usage: oooconf [global options] <command> [command options]

Setup: bootstrap, install, deps, update
Inspect: doctor, status, snapshot, plan, apply, rollback, dry-run, version
Manage: delete, remove, lock, update-pins, completions, link
Tools: shell, color, delta, secrets, env, agents, fleet, wm
Aliases: check -> doctor, preview -> dry-run, upgrade -> update
Repo root: $REPO_ROOT
EOF
}

usage() {
  if _help_python_available; then
    run_python "$REPO_ROOT/scripts/cli/render_help.py" \
      --mode main --repo-root "$REPO_ROOT" --platform unix && return 0
  fi
  _usage_fallback
}

command_usage() {
  local command="${1:-}"
  command="$(resolve_command_alias "$command")"

  case "$command" in
    ""|-h|--help|help)
      usage
      return 0
      ;;
  esac

  if _help_python_available; then
    local rc=0
    run_python "$REPO_ROOT/scripts/cli/render_help.py" \
      --mode command --command "$command" --repo-root "$REPO_ROOT" --platform unix --quiet-unknown || rc=$?
    if [ "$rc" -eq 0 ]; then
      return 0
    fi
    if [ "$rc" -eq 2 ]; then
      local suggestion=""
      suggestion="$(suggest_command "$command")"
      report_unknown_command "Unknown command: $command" "$suggestion"
      return 1
    fi
  fi

  case "$command" in
    shell) handle_shell_command help ;;
    color) handle_color_command help ;;
    delta) handle_delta_command help ;;
    wm) handle_wm_command help ;;
    bootstrap|install|deps|update|doctor|status|snapshot|plan|apply|rollback|dry-run|delete|remove|lock|update-pins|completions|link|agents|fleet|secrets|env|minimal|version|komorebi|"wm bar")
      ui_section "oooconf $command"
      _usage_fallback
      ;;
    *)
      local suggestion=""
      suggestion="$(suggest_command "$command")"
      report_unknown_command "Unknown command: $command" "$suggestion"
      return 1
      ;;
  esac
}
