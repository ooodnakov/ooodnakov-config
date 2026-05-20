#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091
set -euo pipefail

DEFAULT_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_ROOT="${OOODNAKOV_REPO_ROOT:-$DEFAULT_REPO_ROOT}"
PYTHON_LIB="$REPO_ROOT/scripts/lib/python.sh"
# shellcheck source=/dev/null
source "$PYTHON_LIB"
SETUP="$REPO_ROOT/scripts/setup/setup.sh"
DELETE="$REPO_ROOT/scripts/setup/delete.sh"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"
GEN_LOCK="$REPO_ROOT/scripts/generate/generate_dependency_lock.py"
UPDATE_PINS="$REPO_ROOT/scripts/update/update-pins.sh"
RENDER_SECRETS="$REPO_ROOT/scripts/generate/render_secrets.py"
AGENTS_TOOL="$REPO_ROOT/scripts/cli/agents_tool.py"
SYNC_COLOR_THEME="$REPO_ROOT/scripts/lib/sync_color_theme.py"
COMMANDS_FILE="$REPO_ROOT/scripts/cli/oooconf-commands.txt"
KNOWN_COMMANDS=()
KNOWN_SHELL_SUBCOMMANDS=(status prompt prompt-style forgit-aliases typo-handling psfzf-tab psfzf-git auto-uv-env)
KNOWN_SHELL_FORGIT_MODES=(plain forgit status)
KNOWN_SHELL_TYPO_MODES=(silent suggest help status)
KNOWN_SHELL_PSFZF_MODES=(enabled disabled status)
KNOWN_SHELL_AUTO_UV_MODES=(enabled quiet status)
KNOWN_SHELL_PROMPT_MODES=(p10k ohmyposh status)
KNOWN_SHELL_PROMPT_STYLE_MODES=(verbose concise status)
KNOWN_COLOR_THEMES=(default catppuccin gruvbox nord tokyonight noctalia)
KNOWN_COLOR_MODES=(dark light)
KNOWN_WM_MODES=(komorebi glazewm aerospace omniwm)
KNOWN_BAR_TYPES=(zebar yabs sketchybar)
KNOWN_KOMOREBI_COMMANDS=(status start stop reload)
LOCAL_OVERRIDES_START="# --- LOCAL OVERRIDES START ---"
LOCAL_OVERRIDES_END="# --- LOCAL OVERRIDES END ---"
FORGIT_ALIAS_VAR="OOODNAKOV_FORGIT_ALIAS_MODE"
TYPO_HANDLING_VAR="OOODNAKOV_TYPO_HANDLING_MODE"
PSFZF_TAB_VAR="OOODNAKOV_PSFZF_TAB"
PSFZF_GIT_VAR="OOODNAKOV_PSFZF_GIT"
AUTO_UV_ENV_VAR="AUTO_UV_ENV_QUIET"
OOOCONF_THEME_VAR="OOOCONF_THEME"
OOOCONF_COLOR_MODE_VAR="OOOCONF_COLOR_MODE"
OOOCONF_OMP_CONFIG_VAR="OOOCONF_OMP_CONFIG"
OOOCONF_ZSH_PROMPT_VAR="OOOCONF_ZSH_PROMPT"
OOOCONF_PROMPT_STYLE_VAR="OOOCONF_PROMPT_STYLE"

# shellcheck source=scripts/setup/lib/oooconf-delta.sh
source "$REPO_ROOT/scripts/setup/lib/oooconf-delta.sh"
# shellcheck source=scripts/setup/lib/oooconf-ui.sh
source "$REPO_ROOT/scripts/setup/lib/oooconf-ui.sh"
# shellcheck source=scripts/setup/lib/oooconf-shell.sh
source "$REPO_ROOT/scripts/setup/lib/oooconf-shell.sh"
# shellcheck source=scripts/setup/lib/oooconf-color.sh
source "$REPO_ROOT/scripts/setup/lib/oooconf-color.sh"
# shellcheck source=scripts/setup/lib/oooconf-wm.sh
source "$REPO_ROOT/scripts/setup/lib/oooconf-wm.sh"
# shellcheck source=scripts/setup/lib/oooconf-bar.sh
source "$REPO_ROOT/scripts/setup/lib/oooconf-bar.sh"
# shellcheck source=scripts/setup/lib/oooconf-help.sh
source "$REPO_ROOT/scripts/setup/lib/oooconf-help.sh"
# shellcheck source=scripts/setup/lib/oooconf-dispatch.sh
source "$REPO_ROOT/scripts/setup/lib/oooconf-dispatch.sh"

if [ "${OOODNAKOV_OOSCRIPT:-0}" = "1" ]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi

dry_run_requested=0
yes_optional_requested=0
skip_deps_requested=0
all_deps_requested=0
command=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -C|--repo-root)
      [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 1; }
      REPO_ROOT="$2"
      SETUP="$REPO_ROOT/scripts/setup/setup.sh"
      DELETE="$REPO_ROOT/scripts/setup/delete.sh"
      BOOTSTRAP="$REPO_ROOT/bootstrap.sh"
      GEN_LOCK="$REPO_ROOT/scripts/generate/generate_dependency_lock.py"
      UPDATE_PINS="$REPO_ROOT/scripts/update/update-pins.sh"
      RENDER_SECRETS="$REPO_ROOT/scripts/generate/render_secrets.py"
      AGENTS_TOOL="$REPO_ROOT/scripts/cli/agents_tool.py"
      SYNC_COLOR_THEME="$REPO_ROOT/scripts/lib/sync_color_theme.py"
      shift 2
      ;;
    --print-repo-root)
      ui_line info "$REPO_ROOT"
      exit 0
      ;;
    -V|--version)
      ui_line info "oooconf $(print_version)"
      ui_line info "$REPO_ROOT"
      exit 0
      ;;
    -h|--help)
      if [ -n "${2:-}" ] && [[ "${2:-}" != -* ]]; then
        command_usage "$2"
      else
        usage
      fi
      exit 0
      ;;
    -n|--dry-run)
      dry_run_requested=1
      shift
      ;;
    --yes-optional)
      yes_optional_requested=1
      shift
      ;;
    --all)
      all_deps_requested=1
      shift
      ;;
    --skip-deps)
      skip_deps_requested=1
      shift
      ;;
    help)
      command_usage "$(resolve_command_alias "${2:-}")"
      exit 0
      ;;
    version)
      ui_line info "oooconf $(print_version)"
      ui_line info "$REPO_ROOT"
      exit 0
      ;;
    -*)
      visible_error "Unknown option: $1"
      usage >&2
      exit 1
      ;;
    *)
      command="$(resolve_command_alias "$1")"
      shift
      break
      ;;
  esac
done

if [ -z "$command" ]; then
  if [ "$dry_run_requested" -eq 1 ]; then
    command="install"
  else
    usage
    exit 0
  fi
fi


if should_normalize_global_flags "$command"; then
  normalized_args=()
  for arg in "$@"; do
    case "$arg" in
      -n|--dry-run)
        dry_run_requested=1
        ;;
      --yes-optional)
        yes_optional_requested=1
        ;;
      --skip-deps)
        skip_deps_requested=1
        ;;
      --all)        all_deps_requested=1        ;;
      *)
        normalized_args+=("$arg")
        ;;
    esac
  done
  if [ ${#normalized_args[@]} -gt 0 ]; then
    set -- "${normalized_args[@]}"
  else
    set --
  fi
fi




case "$command" in
  bootstrap)
    require_no_dry_run bootstrap
    require_repo_script "$BOOTSTRAP"
    exec "$BOOTSTRAP" "$@"
    ;;
  install)
    exec_setup_command install 1 "$@"
    ;;
  deps)
    exec_setup_command deps 1 "$@"
  ;;
  minimal)
    dry_run_arg=""
    [ "$dry_run_requested" -eq 1 ] && dry_run_arg="--dry-run"
    exec "$REPO_ROOT/scripts/setup/minimal-setup.sh" $dry_run_arg
  ;;

  update)
    exec_setup_command update 1 "$@"
    ;;
  doctor)
    exec_setup_command doctor 0 "$@"
    ;;
  completions)
    exec_setup_command completions 1 "$@"
    ;;
  link)
    require_repo_script "$SETUP"
    OOODNAKOV_REPO_ROOT="$REPO_ROOT" exec "$SETUP" link "$@"
    ;;
  dry-run)
    if [ "$dry_run_requested" -eq 1 ]; then
      echo "Use either dry-run or --dry-run, not both" >&2
      exit 1
    fi
    require_repo_script "$SETUP"
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" "$SETUP" install --dry-run "$@"
    ;;
  delete)
    exec_delete_command delete restore "$@"
    ;;
  remove)
    exec_delete_command remove remove "$@"
    ;;
  lock)
    dry_run_arg=""
    [ "$dry_run_requested" -eq 1 ] && dry_run_arg="--dry-run"
    OOODNAKOV_REPO_ROOT="$REPO_ROOT" run_python "$GEN_LOCK" $dry_run_arg "$@"
    exit $?
    ;;
  update-pins)
    require_repo_script "$UPDATE_PINS"
    dry_run_arg=""
    [ "$dry_run_requested" -eq 1 ] && dry_run_arg="--dry-run"
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" "$UPDATE_PINS" $dry_run_arg "$@"
    ;;
  agents)
    require_no_dry_run agents
    if ! command -v python3 >/dev/null 2>&1; then
      echo "python3 is required for agents command." >&2
      exit 1
    fi
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" python3 "$AGENTS_TOOL" --repo-root "$REPO_ROOT" "$@"
    ;;
  secrets)
    OOODNAKOV_REPO_ROOT="$REPO_ROOT" run_python "$RENDER_SECRETS" --repo-root "$REPO_ROOT" "$@"
    exit $?
    ;;
  shell)
    handle_shell_command "$@"
    ;;
  color)
    handle_color_command "$@"
    ;;
  delta)
    handle_delta_command "$@"
    ;;
  wm)
    handle_wm_command "$@"
    ;;
  komorebi)
    handle_komorebi_command "$@"
    ;;
  *)
    suggestion="$(suggest_command "$command")"
    report_unknown_command "Unknown command: $command" "$suggestion"
    exit 1
    ;;
esac
