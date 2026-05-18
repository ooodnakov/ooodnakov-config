#!/usr/bin/env bash
# Sourced by scripts/setup/ooodnakov.sh; do not execute directly.

require_repo_script() {
  local script_path="$1"
  if [ ! -x "$script_path" ]; then
    echo "Required script is missing or not executable: $script_path" >&2
    exit 1
  fi
}

should_normalize_global_flags() {
  case "$1" in
    bootstrap|install|deps|update|doctor|completions|dry-run|delete|remove|lock|update-pins|agents|minimal)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

exec_setup_command() {
  local setup_command="$1"
  local supports_dry_run="$2"
  shift 2
  local setup_args=()
  [ "$all_deps_requested" -eq 1 ] && [ "$setup_command" = "deps" ] && setup_args+=("--all")
  setup_args+=("$@")

  require_repo_script "$SETUP"
  if [ "$dry_run_requested" -eq 1 ]; then
    if [ "$supports_dry_run" -ne 1 ]; then
      echo "--dry-run is not supported for $setup_command" >&2
      exit 1
    fi
    if [ "$yes_optional_requested" -eq 1 ]; then
      exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" OOODNAKOV_INSTALL_OPTIONAL=always OOODNAKOV_SKIP_DEPS="$skip_deps_requested" "$SETUP" "$setup_command" --dry-run "${setup_args[@]}"
    fi
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" OOODNAKOV_SKIP_DEPS="$skip_deps_requested" "$SETUP" "$setup_command" --dry-run "${setup_args[@]}"
  fi

  if [ "$yes_optional_requested" -eq 1 ]; then
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" OOODNAKOV_INSTALL_OPTIONAL=always OOODNAKOV_SKIP_DEPS="$skip_deps_requested" "$SETUP" "$setup_command" "${setup_args[@]}"
  fi
  exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" OOODNAKOV_SKIP_DEPS="$skip_deps_requested" "$SETUP" "$setup_command" "${setup_args[@]}"
}

require_no_dry_run() {
  local command_name="$1"
  if [ "$dry_run_requested" -eq 1 ]; then
    echo "--dry-run is not supported for $command_name" >&2
    exit 1
  fi
}

exec_delete_command() {
  local command_name="$1"
  local delete_mode="$2"
  shift 2
  require_repo_script "$DELETE"
  local dry_run_arg=""
  [ "$dry_run_requested" -eq 1 ] && dry_run_arg="--dry-run"
  exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" "$DELETE" "$delete_mode" $dry_run_arg "$@"
}
