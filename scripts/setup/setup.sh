#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON_LIB="$REPO_ROOT/scripts/lib/python.sh"
OPTIONAL_DEPS_SCRIPT="$REPO_ROOT/scripts/cli/read_optional_deps.py"
AUTOGEN_COMPLETIONS_MANIFEST="$REPO_ROOT/scripts/generate/autogen-completions.txt"
OOOCONF_COMPLETIONS_GENERATOR="$REPO_ROOT/scripts/cli/generate_oooconf_completions.py"
HOME_DIR="${HOME}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME_DIR/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME_DIR/.local/share}"
STATE_HOME="$DATA_HOME/ooodnakov-config"
FONT_TARGET_DIR="${XDG_DATA_HOME:-$HOME_DIR/.local/share}/fonts/ooodnakov"
COMMAND="${1:-install}"
DRY_RUN=0
MINIMAL=0
BACKUP_ROOT="${OOODNAKOV_BACKUP_ROOT:-$HOME_DIR/.local/state/ooodnakov-config/backups}"
LOG_ROOT="${OOODNAKOV_LOG_ROOT:-$HOME_DIR/.local/state/ooodnakov-config/logs}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
INTERACTIVE="${OOODNAKOV_INTERACTIVE:-auto}"
INSTALL_OPTIONAL="${OOODNAKOV_INSTALL_OPTIONAL:-prompt}"
VERBOSE="${OOODNAKOV_VERBOSE:-0}"
SKIP_DEPS="${OOODNAKOV_SKIP_DEPS:-0}"
DEPENDENCY_SUMMARY=()
TOOL_SUMMARY=()
FAILURES=()
PACKAGE_MANAGER=""
APT_UPDATED=0
LOG_FILE=""
LOG_LATEST=""
KNOWN_SETUP_COMMANDS=(install update doctor deps completions link)
PROGRESS_TOTAL=0
PROGRESS_CURRENT=0
PROGRESS_TITLE=""
NEOVIM_MIN_VERSION="${OOODNAKOV_NEOVIM_MIN_VERSION:-0.10.0}"
NEOVIM_VERSION="${OOODNAKOV_NEOVIM_VERSION:-}"
LINK_MANAGER="$REPO_ROOT/scripts/link_manager.py"

# shellcheck source=/dev/null
source "$PYTHON_LIB"

# shellcheck source=/dev/null
OOODNAKOV_OOSCRIPT=1 source "$REPO_ROOT/scripts/setup/ooodnakov.sh"

# All pins, versions, and managed tools now live in optional-deps.toml ONLY.
OPTIONAL_DEPS_PLATFORM_CATALOG_CACHE=""
OPTIONAL_DEPS_CHECK_COMMAND_CACHE=""
OPTIONAL_DEPS_HANDLER_CACHE=""
OPTIONAL_DEPS_INSTALL_INFO_CACHE=""
# shellcheck source=scripts/setup/lib/setup-ui.sh
source "$REPO_ROOT/scripts/setup/lib/setup-ui.sh"
# shellcheck source=scripts/setup/lib/setup-optional-deps.sh
source "$REPO_ROOT/scripts/setup/lib/setup-optional-deps.sh"
# shellcheck source=scripts/setup/lib/setup-installers.sh
source "$REPO_ROOT/scripts/setup/lib/setup-installers.sh"
# shellcheck source=scripts/setup/lib/setup-links.sh
source "$REPO_ROOT/scripts/setup/lib/setup-links.sh"
# shellcheck source=scripts/setup/lib/setup-completions.sh
source "$REPO_ROOT/scripts/setup/lib/setup-completions.sh"
# shellcheck source=scripts/setup/lib/setup-summary.sh
source "$REPO_ROOT/scripts/setup/lib/setup-summary.sh"
# shellcheck source=scripts/setup/lib/setup-doctor.sh
source "$REPO_ROOT/scripts/setup/lib/setup-doctor.sh"

shift || true
cli_selected_optional_keys=()
selected_optional_key_csv="${OOODNAKOV_SELECTED_OPTIONAL_KEYS:-}"
while [ "$#" -gt 0 ]; do
  case "$1" in
  --dry-run) DRY_RUN=1 ;;
  --yes-optional) INSTALL_OPTIONAL=always ;;
  --minimal) MINIMAL=1 ;;
  --all) ALL_DEPS=1 ;;
  -h | --help)
    usage
    exit 0
    ;;
  --*)
    echo "unknown option: $1" >&2
    usage >&2
    exit 1
    ;;
  *)
    if ! optional_dependency_exists_any "$1"; then
      echo "unknown dependency key: $1" >&2
      suggestion="$(suggest_dependency_key "$1")"
      if [ -n "$suggestion" ]; then
        echo "Did you mean: $suggestion" >&2
      fi
      exit 1
    fi
    cli_selected_optional_keys+=("$1")
    ;;
  esac
  shift
done

if [ "${#cli_selected_optional_keys[@]}" -gt 0 ]; then
  selected_optional_key_csv="$(
    IFS=,
    printf '%s' "${cli_selected_optional_keys[*]}"
  )"
fi

case "$COMMAND" in
install) ;;
update) ;;
doctor)
  [ "$DRY_RUN" -eq 1 ] && ui_line hint "[dry-run] would run doctor checks" && exit 0
  run_doctor
  exit $?
  ;;
deps)
  if [ "$MINIMAL" = 1 ]; then
    selected_optional_key_csv=$(run_python "$OPTIONAL_DEPS_SCRIPT" "minimal" | tr ' ' ',')
  elif [ "${ALL_DEPS:-0}" = 1 ]; then
    selected_optional_key_csv=$(run_python "$OPTIONAL_DEPS_SCRIPT" "keys" | paste -sd, -)
  fi
  if [ -z "$selected_optional_key_csv" ] && is_interactive; then
    if selected_optional_key_csv="$(choose_optional_dependencies_with_gum)"; then
      :
    else
      _deps_gum_rc=$?
      case $_deps_gum_rc in
      2)
        echo "All optional dependencies are already present."
        exit 0
        ;;
      3)
        # User cancelled the gum picker (Esc) — nothing to install.
        exit 0
        ;;
      1)
        # gum not available, fall back to text prompt
        if selected_optional_key_csv="$(choose_optional_dependencies_without_gum)"; then
          :
        else
          _deps_fallback_rc=$?
          case $_deps_fallback_rc in
          2)
            echo "All optional dependencies are already present."
            exit 0
            ;;
          3)
            # User cancelled the text prompt — nothing to install.
            exit 0
            ;;
          *)
            echo "No optional dependencies selected." >&2
            exit 1
            ;;
          esac
        fi
        ;;
      *)
        echo "No optional dependencies selected." >&2
        exit 1
        ;;
      esac
    fi
  elif [ -z "$selected_optional_key_csv" ] && ! is_interactive; then
    echo "oooconf deps needs explicit dependency keys in non-interactive mode." >&2
    exit 1
  fi
  INSTALL_OPTIONAL=always
  ;;
minimal)
  if [ "$DRY_RUN" -eq 1 ]; then
    ui_line hint "[dry-run] would run minimal-setup.sh"
    exit 0
  fi
  "$REPO_ROOT/scripts/setup/minimal-setup.sh"
  ;;
completions) ;;
link)
  if ! command -v python3 >/dev/null 2>&1; then
    echo "oooconf link requires python3" >&2
    exit 1
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    ui_line hint "[dry-run] would link:"
    while IFS='|' read -r key source target; do
      ui_line hint "  $target -> $source"
    done < <(python3 "$LINK_MANAGER" --repo-root "$REPO_ROOT" --format text) || true
    exit 0
  fi
  while IFS='|' read -r key source target; do
    link_file "$source" "$target" || {
      echo "Failed to link $target" >&2
      exit 1
    }
  done < <(python3 "$LINK_MANAGER" --repo-root "$REPO_ROOT" --format text) || exit 1
  exit 0
  ;;
delete)
  if [ "$DRY_RUN" -eq 1 ]; then
    ui_line hint "[dry-run] would run delete.sh restore --dry-run"
    exit 0
  fi
  "$REPO_ROOT/scripts/setup/delete.sh" restore
  ;;
remove)
  if [ "$DRY_RUN" -eq 1 ]; then
    ui_line hint "[dry-run] would run delete.sh remove --dry-run"
    exit 0
  fi
  "$REPO_ROOT/scripts/setup/delete.sh" remove
  ;;
lock)
  if [ "$DRY_RUN" -eq 1 ]; then
    ui_line hint "[dry-run] would regenerate deps.lock.json and docs/dependency-lock.md"
    exit 0
  fi
  run_python "$REPO_ROOT/scripts/generate/generate_dependency_lock.py"
  ;;
update-pins)
  if [ "$DRY_RUN" -eq 1 ]; then
    ui_line hint "[dry-run] would check pin drift and refresh lock artifacts"
    exit 0
  fi
  "$REPO_ROOT/scripts/update/update-pins.sh"
  ;;
*)
  usage >&2
  exit 1
  ;;
esac

initialize_logging
if [ "$COMMAND" = "completions" ]; then
  progress_init 3 "oooconf completions"
  progress_step "Preparing completion output path"
  prepare_completion_output_path
  progress_step "Generating tracked autogen completions"
  generate_autogen_completions || true
  progress_step "Generating oooconf command completions"
  generate_oooconf_completions || true
  echo
  ui_line ok "Completion generation complete."
  if [ -n "$LOG_FILE" ]; then
    ui_line info "Log file: $LOG_FILE"
  fi
  exit 0
fi

if [ "$COMMAND" = "deps" ]; then
  progress_init 3 "oooconf deps"
  progress_step "Preparing dependency install paths"
  run_cmd mkdir -p "$DATA_HOME" "$STATE_HOME" "$HOME_DIR/.local/bin"
  progress_step "Installing selected optional dependencies"
  install_optional_dependencies
  progress_step "Rendering dependency summary"
  print_summary
  echo
  ui_line ok "Optional dependency install complete."
  if [ -n "$LOG_FILE" ]; then
    ui_line info "Log file: $LOG_FILE"
  fi
  exit 0
fi

if [ "$COMMAND" = "update" ]; then
  progress_init 8 "oooconf update"
else
  progress_init 7 "oooconf install"
fi

run_cmd mkdir -p "$CONFIG_HOME" "$DATA_HOME" "$STATE_HOME"
if [ "$COMMAND" = "update" ]; then
  progress_step "Pulling latest repository changes"
  update_repo
fi
progress_step "Prepared local state directories"

progress_step "Checking/installing optional dependencies"
install_optional_dependencies

progress_step "Syncing shell framework repositories"
install_managed_tools
ensure_oh_my_zsh_permissions || true

progress_step "Installing managed utility checkouts"
install_auto_uv_env

progress_step "Linking managed config files"
if command -v python3 >/dev/null 2>&1; then
  while IFS='|' read -r _key source_rel target_path; do
    link_file "$source_rel" "$target_path" || true
  done < <(python3 "$LINK_MANAGER" --repo-root "$REPO_ROOT" --format text 2>/dev/null || true)
else
  # Fallback: use hardcoded pairs if python is unavailable
  managed_link_pairs=(
    "home/.zshrc|$HOME_DIR/.zshrc"
    "home/.config/zsh|$CONFIG_HOME/zsh"
    "home/.config/wezterm|$CONFIG_HOME/wezterm"
    "home/.config/yazi|$CONFIG_HOME/yazi"
    "home/.config/niri|$CONFIG_HOME/niri"
    "home/.config/noctalia|$CONFIG_HOME/noctalia"
    "home/.config/ooodnakov|$CONFIG_HOME/ooodnakov"
  )
  for link_pair in "${managed_link_pairs[@]}"; do
    IFS='|' read -r source_rel target_path <<<"$link_pair"
    link_file "$REPO_ROOT/$source_rel" "$target_path" || true
  done
fi

if link_file "$REPO_ROOT/home/.config/nvim" "$CONFIG_HOME/nvim"; then
  # Sync LazyVim plugins non-interactively
  nvim_cmd=""
  nvim_cmd="$(resolve_nvim_command 2>/dev/null || true)"
  if [ -n "$nvim_cmd" ]; then
    if run_with_spinner "Syncing LazyVim plugins" "$nvim_cmd" --headless "+Lazy! sync" +qa; then
      TOOL_SUMMARY+=("nvim: plugins synced")
    else
      TOOL_SUMMARY+=("nvim: plugin sync failed")
    fi
  fi
fi

progress_step "Generating completion files and platform integrations"
generate_tracked_completions || true
ensure_ssh_include || true
install_fonts

progress_step "Finalizing setup and summary"
if is_interactive && [ -f "$HOME_DIR/.zshrc" ]; then
  # This only updates the current setup process; it cannot mutate the parent shell session.
  # shellcheck disable=SC1090,SC1091
  . "$HOME_DIR/.zshrc" || true
fi

print_summary

echo
ui_line ok "Bootstrap complete."
ui_line hint "If needed, create local overrides in $CONFIG_HOME/ooodnakov/local."
if [ -n "$LOG_FILE" ]; then
  ui_line info "Log file: $LOG_FILE"
fi
