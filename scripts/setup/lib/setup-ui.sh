#!/usr/bin/env bash
# Sourced by scripts/setup/setup.sh; do not execute directly.

run_python() {
  oooconf_run_python "$REPO_ROOT" "$@"
}

get_managed_tool() {
  local name
  name="$1"
  local field
  field="${2:-ref}"

  run_python "$OPTIONAL_DEPS_SCRIPT" managed-tool-field "$name" "$field" 2>/dev/null || true
}

get_dep_field() {
  local key="$1"
  local field="$2"
  run_python scripts/cli/read_optional_deps.py field "$key" "$field"
}

is_interactive() {
  case "$INTERACTIVE" in
  always) return 0 ;;
  never) return 1 ;;
  auto) [ -t 1 ] && [ -r /dev/tty ] ;;
  *) return 1 ;;
  esac
}

is_verbose() {
  case "$VERBOSE" in
  1 | [Tt][Rr][Uu][Ee] | [Yy][Ee][Ss] | [Oo][Nn] | [Vv][Ee][Rr][Bb][Oo][Ss][Ee]) return 0 ;;
  *) return 1 ;;
  esac
}

progress_init() {
  PROGRESS_TOTAL="$1"
  PROGRESS_CURRENT=0
  PROGRESS_TITLE="$2"
  if is_interactive; then
    printf "\n%s\n" "$PROGRESS_TITLE"
  else
    echo "$PROGRESS_TITLE"
  fi
}

progress_step() {
  local description
  description="$1"
  PROGRESS_CURRENT=$((PROGRESS_CURRENT + 1))

  if ! is_interactive; then
    printf '[%s/%s] %s\n' "$PROGRESS_CURRENT" "$PROGRESS_TOTAL" "$description"
    return 0
  fi

  printf 'Step: %s\n' "$description"

  local width=24 filled=0 empty=0 percent=0 bar
  if [ "$PROGRESS_TOTAL" -gt 0 ]; then
    percent=$((PROGRESS_CURRENT * 100 / PROGRESS_TOTAL))
    filled=$((PROGRESS_CURRENT * width / PROGRESS_TOTAL))
  fi
  empty=$((width - filled))
  bar="$(printf '%*s' "$filled" '' | tr ' ' '█')$(printf '%*s' "$empty" '' | tr ' ' '░')"
  printf '\r[%s] %3d%% (%d/%d) %s' "$bar" "$percent" "$PROGRESS_CURRENT" "$PROGRESS_TOTAL" "$description" >/dev/tty
}

usage() {
  ui_banner
  ui_spacer
  ui_section_fancy "version" "Global options"
  cat <<'EOF'
  -C, --repo-root PATH  run against a specific repo checkout
  -h, --help            show this help
  -n, --dry-run         add --dry-run to install or update
      --yes-optional    auto-accept optional dependency installs
      --skip-deps       skip dependency installation
  -V, --version         show CLI version information
      --print-repo-root print the resolved repo root and exit
EOF

  ui_spacer
  ui_separator
  ui_section_fancy "install" "Setup"
  ui_command_row "bootstrap" "clone/update repo then run install"
  ui_command_row "install" "apply managed config and optional dependency installs"
  ui_command_row "deps" "install optional dependencies only"
  ui_command_row "update" "pull repo with --ff-only, then re-run install"

  ui_spacer
  ui_section_fancy "doctor" "Inspect & Validate"
  ui_command_row "doctor" "validate managed symlinks and required commands"
  ui_command_row "dry-run" "preview install flow without mutating filesystem"
  ui_command_row "version" "print CLI version and repo root"

  ui_spacer
  ui_section_fancy "lock" "Manage State"
  ui_command_row "delete" "remove managed links and restore latest backups"
  ui_command_row "remove" "remove managed links only (no backup restore)"
  ui_command_row "lock" "regenerate dependency lock artifacts from pinned refs"
  ui_command_row "update-pins" "compare/update pinned refs and refresh lock artifacts"
  ui_command_row "completions" "regenerate tracked shell completions (autogen + oooconf)"
  ui_command_row "link" "inspect or manage links from the symlink manifest"

  ui_spacer
  ui_section_fancy "shell" "Shell / Secrets / Agents"
  ui_command_row "shell" "manage local shell preferences such as forgit aliases"
  ui_command_row "color" "set a unified oooconf CLI color theme"
  ui_command_row "secrets" "sync or validate local secret env files"
  ui_command_row "agents" "detect/sync/doctor/update AGENTS.md and agent CLI workflows"

  ui_spacer
  ui_separator
  cat <<'EOF'
Aliases:
  check -> doctor
  preview -> dry-run
  upgrade -> update
Getting help:
  ./scripts/setup/setup.sh --help              show this message
  ./scripts/setup/setup.sh <command> --help     show command-specific help
UI controls:
  OOOCONF_COLOR=always|never|auto    override color output
  OOOCONF_ASCII=1                    force ASCII icons and borders
  OOOCONF_THEME=<theme>              set the CLI color theme for this run
EOF
}

initialize_logging() {
  local active_log_root
  active_log_root="$LOG_ROOT"

  if ! mkdir -p "$active_log_root" 2>/dev/null; then
    active_log_root="${TMPDIR:-/tmp}/ooodnakov-config-logs"
    mkdir -p "$active_log_root" || {
      LOG_FILE=""
      LOG_LATEST=""
      ui_line warn "failed to create log directory under $LOG_ROOT or $active_log_root"
      return 0
    }
  fi

  LOG_FILE="$active_log_root/setup-${COMMAND}-${TIMESTAMP}.log"
  LOG_LATEST="$active_log_root/setup-latest.log"

  if [ -n "${LOG_FILE:-}" ] && command -v tee >/dev/null 2>&1; then
    exec > >(tee -a "$LOG_FILE") 2>&1
  else
    exec >>"${LOG_FILE:-/dev/null}" 2>&1
  fi

  ln -sfn "$LOG_FILE" "$LOG_LATEST" 2>/dev/null || cp -f "$LOG_FILE" "$LOG_LATEST"
  is_verbose && ui_line info "Logging to $LOG_FILE"
  return 0
}

bullet() {
  ui_line info "$*"
}

run_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    ui_line hint "[dry-run] $*"
    return 0
  fi
  "$@"
}

prompt_yes_no() {
  local prompt
  prompt="$1"
  local reply

  case "$INSTALL_OPTIONAL" in
  always) return 0 ;;
  never) return 1 ;;
  prompt) ;;
  *) ;;
  esac

  if ! is_interactive; then
    return 1
  fi
  if command -v gum >/dev/null 2>&1; then
    gum confirm --default=false "$prompt" </dev/tty >/dev/tty 2>/dev/tty
    return $?
  fi


  printf "%s [y/N] " "$prompt" >/dev/tty
  read -r reply </dev/tty
  case "$reply" in
  y | Y | yes | YES) return 0 ;;
  *) return 1 ;;
  esac
}

run_with_spinner() {
  local label
  label="$1"
  shift
  if [ "$DRY_RUN" -eq 1 ]; then
    ui_line hint "[dry-run] $label: $*"
    return 0
  fi

  if ! is_verbose; then
    local logfile status
    if is_interactive; then
      printf "[-] %s..." "$label" >/dev/tty
    fi
    logfile="$(mktemp)"
    (
      "$@"
    ) >"$logfile" 2>&1
    status=$?
    if [ $status -ne 0 ]; then
      if is_interactive; then
        printf "\r" >/dev/tty
        ui_line fail "[failed] $label"
      else
        ui_line fail "[failed] $label"
      fi
      cat "$logfile" >&2
      if [ "${OOODNAKOV_RECORD_SPINNER_FAILURES:-1}" != "0" ]; then
        FAILURES+=("$label")
      fi
    else
      if is_interactive; then
        printf "\r" >/dev/tty
        ui_line ok "[ok] $label"
      else
        ui_line ok "[ok] $label"
      fi
    fi
    rm -f "$logfile"
    return $status
  fi

  # Print the intent immediately so the user knows what we are starting,
  # especially helpful if is_interactive is false or sudo prompts.
  printf "[-] %s..." "$label"

  local logfile pid spinner_index=0
  local -a frames=('-' "\\" '|' '/')

  logfile="$(mktemp)"
  (
    "$@"
  ) >"$logfile" 2>&1 &
  pid=$!

  if is_interactive; then
    while kill -0 "$pid" 2>/dev/null; do
      printf "\r[%s] %s" "${frames[$spinner_index]}" "$label" >/dev/tty
      spinner_index=$(((spinner_index + 1) % ${#frames[@]}))
      sleep 0.12
    done
    printf "\r" >/dev/tty
  fi

  wait "$pid"
  local status
  status=$?

  if [ $status -eq 0 ]; then
    if is_interactive; then
      printf "\r" >/dev/tty
      ui_line ok "[ok] $label"
    else
      # Overwrite the "[-] label..." line with [ok]
      ui_line ok "[ok] $label"
    fi
  else
    if is_interactive; then
      printf "\r" >/dev/tty
      ui_line fail "[failed] $label"
    else
      ui_line fail "[failed] $label"
    fi
    cat "$logfile" >&2
    if [ "${OOODNAKOV_RECORD_SPINNER_FAILURES:-1}" != "0" ]; then
      FAILURES+=("$label")
    fi
  fi

  rm -f "$logfile"
  return $status
}

retry_attempt_count() {
  local attempts
  attempts="${OOODNAKOV_GIT_SYNC_ATTEMPTS:-3}"

  case "$attempts" in
  "" | *[!0-9]*) attempts=3 ;;
  esac

  if [ "$attempts" -lt 1 ]; then
    attempts=1
  fi

  printf '%s\n' "$attempts"
}

run_with_retry() {
  local label
  label="$1"
  shift

  local attempts
  attempts="$(retry_attempt_count)"
  local attempt
  local status
  local retry_delay

  attempt=1
  status=1

  while [ "$attempt" -le "$attempts" ]; do
    if [ "$attempts" -gt 1 ]; then
      OOODNAKOV_RECORD_SPINNER_FAILURES=0 run_with_spinner "$label (attempt $attempt/$attempts)" "$@" && return 0
    else
      OOODNAKOV_RECORD_SPINNER_FAILURES=0 run_with_spinner "$label" "$@" && return 0
    fi

    status=$?
    if [ "$attempt" -lt "$attempts" ]; then
      retry_delay="$attempt"
      ui_line hint "[retry] $label after ${retry_delay}s"
      sleep "$retry_delay"
    fi
    attempt=$((attempt + 1))
  done

  if [ "${OOODNAKOV_RECORD_RETRY_FAILURES:-1}" != "0" ]; then
    FAILURES+=("$label")
  fi
  return "$status"
}

record_failure() {
  local label
  label="$1"
  FAILURES+=("$label")
  ui_line fail "[failed] $label"
}
