#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_LIB="$REPO_ROOT/scripts/lib/python.sh"
OPTIONAL_DEPS_SCRIPT="$REPO_ROOT/scripts/read_optional_deps.py"
AUTOGEN_COMPLETIONS_MANIFEST="$REPO_ROOT/scripts/autogen-completions.txt"
OOOCONF_COMPLETIONS_GENERATOR="$REPO_ROOT/scripts/generate_oooconf_completions.py"
HOME_DIR="${HOME}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME_DIR/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME_DIR/.local/share}"
STATE_HOME="$DATA_HOME/ooodnakov-config"
FONT_TARGET_DIR="${XDG_DATA_HOME:-$HOME_DIR/.local/share}/fonts/ooodnakov"
COMMAND="${1:-install}"
DRY_RUN=0
BACKUP_ROOT="${OOODNAKOV_BACKUP_ROOT:-$HOME_DIR/.local/state/ooodnakov-config/backups}"
LOG_ROOT="${OOODNAKOV_LOG_ROOT:-$HOME_DIR/.local/state/ooodnakov-config/logs}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
INTERACTIVE="${OOODNAKOV_INTERACTIVE:-auto}"
INSTALL_OPTIONAL="${OOODNAKOV_INSTALL_OPTIONAL:-prompt}"
VERBOSE="${OOODNAKOV_VERBOSE:-0}"
DEPENDENCY_SUMMARY=()
TOOL_SUMMARY=()
FAILURES=()
PACKAGE_MANAGER=""
APT_UPDATED=0
LOG_FILE=""
LOG_LATEST=""
KNOWN_SETUP_COMMANDS=(install update doctor deps completions)
PROGRESS_TOTAL=0
PROGRESS_CURRENT=0
PROGRESS_TITLE=""

source "$PYTHON_LIB"

run_python() {
  oooconf_run_python "$REPO_ROOT" "$@"
}

# All pins, versions, and managed tools now live in optional-deps.toml ONLY.
# These variables are deprecated and will be removed. Use get_managed_tool() instead.
get_managed_tool() {
  local name="$1"
  local field="${2:-ref}"
  run_python scripts/read_optional_deps.py managed-tools | \
    python3 -c '
import sys, json
data = json.load(sys.stdin)
name = sys.argv[1]
field = sys.argv[2]
print(data.get(name, {}).get(field, ""))
' "$name" "$field"
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
    1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn]|[Vv][Ee][Rr][Bb][Oo][Ss][Ee]) return 0 ;;
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
  local description="$1"
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
  printf '\r[%s] %3d%% (%d/%d) %s' "$bar" "$percent" "$PROGRESS_CURRENT" "$PROGRESS_TOTAL" "$description" > /dev/tty
}

usage() {
  cat <<'EOF'
Usage: ./scripts/setup.sh [install|update|doctor|deps|completions] [--dry-run] [dependency-key...]

Commands:
  install   apply managed config and dependencies
  update    git pull this repo, then run install flow
  doctor    validate managed links and required tools
  deps      install optional dependencies only
  completions  regenerate tracked shell completion files (autogen + oooconf)

Options:
  --dry-run print actions without mutating filesystem
  --yes-optional auto-accept optional dependency installs
EOF
}

initialize_logging() {
  local active_log_root="$LOG_ROOT"

  if ! mkdir -p "$active_log_root" 2>/dev/null; then
    active_log_root="${TMPDIR:-/tmp}/ooodnakov-config-logs"
    mkdir -p "$active_log_root" || {
      LOG_FILE=""
      LOG_LATEST=""
      echo "warning: failed to create log directory under $LOG_ROOT or $active_log_root" >&2
      return 0
    }
  fi

  LOG_FILE="$active_log_root/setup-${COMMAND}-${TIMESTAMP}.log"
  LOG_LATEST="$active_log_root/setup-latest.log"

  if command -v tee >/dev/null 2>&1; then
    exec > >(tee -a "$LOG_FILE") 2>&1
  else
    exec >>"$LOG_FILE" 2>&1
  fi

  ln -sfn "$LOG_FILE" "$LOG_LATEST" 2>/dev/null || cp -f "$LOG_FILE" "$LOG_LATEST"
  is_verbose && echo "Logging to $LOG_FILE"
}

run_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

prompt_yes_no() {
  local prompt="$1"
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

  printf "%s [y/N] " "$prompt" > /dev/tty
  read -r reply < /dev/tty
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

detect_platform() {
  case "$(uname -s)" in
    Linux*) echo "linux" ;;
    Darwin*) echo "macos" ;;
    CYGWIN*|MINGW*|MSYS*|Windows*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}

optional_dependency_applicable() {
  local key="$1"
  local platform
  platform="$(detect_platform)"
  local info
  info="$(run_python "$OPTIONAL_DEPS_SCRIPT" install-info "$key" "$platform" 2>/dev/null)" || return 1
  local manager
  manager="$(echo "$info" | cut -d'|' -f1)"
  [ -n "$manager" ] && [ "$manager" != "none" ]
}

optional_dependency_catalog() {
  local key label description
  while IFS='|' read -r key label description; do
    optional_dependency_applicable "$key" || continue
    printf '%s|%s|%s\n' "$key" "$label" "$description"
  done < <(run_python "$OPTIONAL_DEPS_SCRIPT" catalog)
}

optional_dependency_catalog_all() {
  run_python "$OPTIONAL_DEPS_SCRIPT" catalog
}

optional_dependency_exists() {
  local expected_key="$1"
  local key label description

  while IFS='|' read -r key label description; do
    [ "$key" = "$expected_key" ] && return 0
  done < <(optional_dependency_catalog)

  return 1
}

optional_dependency_exists_any() {
  # Check if key exists in full catalog (including platform-inapplicable deps).
  local expected_key="$1"
  local key label description

  while IFS='|' read -r key label description; do
    [ "$key" = "$expected_key" ] && return 0
  done < <(optional_dependency_catalog_all)

  return 1
}

optional_dependency_keys() {
  local key label description

  while IFS='|' read -r key label description; do
    printf '%s\n' "$key"
  done < <(optional_dependency_catalog)
}

optional_dependency_keys_all() {
  local key label description

  while IFS='|' read -r key label description; do
    printf '%s\n' "$key"
  done < <(optional_dependency_catalog_all)
}

edit_distance() {
  local left="$1"
  local right="$2"

  awk -v left="$left" -v right="$right" '
    BEGIN {
      left_len = length(left)
      right_len = length(right)

      for (i = 0; i <= left_len; i++) {
        dist[i, 0] = i
      }
      for (j = 0; j <= right_len; j++) {
        dist[0, j] = j
      }

      for (i = 1; i <= left_len; i++) {
        left_char = substr(left, i, 1)
        for (j = 1; j <= right_len; j++) {
          right_char = substr(right, j, 1)
          cost = (left_char == right_char) ? 0 : 1
          deletion = dist[i - 1, j] + 1
          insertion = dist[i, j - 1] + 1
          substitution = dist[i - 1, j - 1] + cost

          best = deletion
          if (insertion < best) {
            best = insertion
          }
          if (substitution < best) {
            best = substitution
          }
          dist[i, j] = best
        }
      }

      print dist[left_len, right_len]
    }
  '
}

suggest_from_candidates() {
  local input="$1"
  shift

  local best_candidate=""
  local best_distance=999
  local candidate distance threshold

  for candidate in "$@"; do
    distance="$(edit_distance "$input" "$candidate")"
    if [ "$distance" -lt "$best_distance" ]; then
      best_distance="$distance"
      best_candidate="$candidate"
    fi
  done

  threshold=3
  if [ "${#input}" -le 4 ] && [ "$threshold" -gt 2 ]; then
    threshold=2
  fi

  if [ "$best_distance" -le "$threshold" ]; then
    printf '%s\n' "$best_candidate"
  fi
}

suggest_setup_command() {
  suggest_from_candidates "$1" "${KNOWN_SETUP_COMMANDS[@]}"
}

suggest_dependency_key() {
  local input="$1"
  local keys=()
  local key

  while IFS= read -r key; do
    [ -n "$key" ] && keys+=("$key")
  done < <(optional_dependency_keys_all)

  suggest_from_candidates "$input" "${keys[@]}"
}

optional_dependency_label() {
  local expected_key="$1"
  local key label description

  while IFS='|' read -r key label description; do
    if [ "$key" = "$expected_key" ]; then
      printf '%s - %s\n' "$label" "$description"
      return 0
    fi
  done < <(optional_dependency_catalog)

  return 1
}

selected_optional_key_csv="${OOODNAKOV_SELECTED_OPTIONAL_KEYS:-}"

optional_dependency_install_info() {
  local key="$1"
  local platform
  platform="$(detect_platform)"
  run_python "$OPTIONAL_DEPS_SCRIPT" install-info "$key" "$platform" 2>/dev/null
}

resolve_package_manager_for_dependency() {
  local detected_manager="$1"
  local declared_manager="$2"

  case "$declared_manager" in
    apt)
      case "$detected_manager" in
        apt|dnf|pacman|zypper) printf '%s\n' "$detected_manager" ;;
        *) printf '%s\n' "$declared_manager" ;;
      esac
      ;;
    *)
      printf '%s\n' "$declared_manager"
      ;;
  esac
}

optional_dependency_selected() {
  local key="$1"

  if [ -z "$selected_optional_key_csv" ]; then
    return 0
  fi

  case ",$selected_optional_key_csv," in
    *,"$key",*) return 0 ;;
    *) return 1 ;;
  esac
}

optional_dependency_present() {
  local key="$1"

  case "$key" in
    wget|git|rg|zsh|direnv|fzf|bat|delta|glow|gum|zoxide|q|eza|yazi|ffmpeg|jq|oh-my-posh|wezterm|node|npm|pnpm|fc-cache|cargo|k|python3|rtk)
      command -v "$key" >/dev/null 2>&1
      ;;
    fd)
      command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1
      ;;
    uv)
      command -v uv >/dev/null 2>&1 || [ -x "$HOME_DIR/.local/bin/uv" ]
      ;;
    bw)
      command -v bw >/dev/null 2>&1 || [ -x "$STATE_HOME/bin/bw" ]
      ;;
    dua)
      command -v dua >/dev/null 2>&1
      ;;
    p7zip)
      command -v 7z >/dev/null 2>&1
      ;;
    poppler)
      command -v pdftotext >/dev/null 2>&1
      ;;
    nvim)
      have_supported_nvim
      ;;
    *)
      return 1
      ;;
  esac
}

gum_apt_repo_configured() {
  [ -f /etc/apt/keyrings/charm.gpg ] || return 1
  [ -f /etc/apt/sources.list.d/charm.list ] || return 1
  grep -Fq "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
    /etc/apt/sources.list.d/charm.list 2>/dev/null
}

setup_gum_apt_repo() {
  if gum_apt_repo_configured; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    if prompt_yes_no "gum Debian/Ubuntu install needs curl. Install curl first?"; then
      install_packages apt curl
    else
      DEPENDENCY_SUMMARY+=("gum: missing (requires curl for Debian/Ubuntu repo setup)")
      return 1
    fi
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    if prompt_yes_no "gum Debian/Ubuntu install needs gpg. Install gpg first?"; then
      install_packages apt gpg
    else
      DEPENDENCY_SUMMARY+=("gum: missing (requires gpg for Debian/Ubuntu repo setup)")
      return 1
    fi
  fi

  run_with_spinner "Creating Charm APT keyring directory for gum" sudo mkdir -p /etc/apt/keyrings || return 1
  run_with_spinner "Installing Charm APT signing key for gum" \
    sh -c 'curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg' || return 1
  run_with_spinner "Adding Charm APT source for gum" \
    sh -c 'echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list >/dev/null' || return 1
  APT_UPDATED=0
  return 0
}

gum_rpm_repo_configured() {
  [ -f /etc/yum.repos.d/charm.repo ]
}

setup_gum_rpm_repo() {
  if gum_rpm_repo_configured; then
    return 0
  fi

  run_with_spinner "Installing Charm RPM repo for gum" \
    sh -c "cat <<'EOF' | sudo tee /etc/yum.repos.d/charm.repo >/dev/null
[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key
EOF" || return 1
  run_with_spinner "Importing Charm RPM signing key for gum" sudo rpm --import https://repo.charm.sh/yum/gpg.key || return 1
  return 0
}

install_gum_package() {
  local manager="$1"

  case "$manager" in
    brew|pacman)
      install_packages "$manager" gum
      ;;
    apt)
      setup_gum_apt_repo || return 1
      install_packages apt gum
      ;;
    dnf|zypper)
      setup_gum_rpm_repo || return 1
      install_packages "$manager" gum
      ;;
    *)
      return 1
      ;;
  esac
}

maybe_install_gum() {
  local manager="$1"

  if check_dependency_status "gum" "gum"; then
    return 0
  fi

  if [ "$manager" = "none" ]; then
    DEPENDENCY_SUMMARY+=("gum: missing (no supported package manager)")
    return 1
  fi

  if ! prompt_yes_no "Install gum for interactive terminal selectors and prompts?"; then
    DEPENDENCY_SUMMARY+=("gum: skipped")
    return 0
  fi

  if install_gum_package "$manager" && command -v gum >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("gum: installed")
    return 0
  fi

  DEPENDENCY_SUMMARY+=("gum: install attempted")
  return 1
}

ensure_gum_for_optional_selector() {
  local manager

  if command -v gum >/dev/null 2>&1; then
    return 0
  fi

  manager="$(detect_package_manager)"
  if [ "$manager" = "none" ] || ! is_interactive; then
    return 1
  fi

  printf "gum is required for the multi-select dependency picker.\n" > /dev/tty
  if ! prompt_yes_no "Install gum now and continue with the picker?"; then
    return 1
  fi

  local previous_mode="$INSTALL_OPTIONAL"
  INSTALL_OPTIONAL=always
  maybe_install_gum "$manager" >/dev/null 2>&1 || true
  INSTALL_OPTIONAL="$previous_mode"
  command -v gum >/dev/null 2>&1
}

choose_optional_dependencies_without_gum() {
  local key label description selection selected_keys_csv
  local -a all_keys=() all_labels=()

  while IFS='|' read -r key label description; do
    if optional_dependency_present "$key"; then
      continue
    fi
    all_keys+=("$key")
    all_labels+=("$label")
  done < <(optional_dependency_catalog)

  if [ "${#all_keys[@]}" -eq 0 ]; then
    echo "All optional dependencies are already present." >&2
    return 2
  fi

  echo "Available optional dependencies:" >&2
  local i
  for (( i = 0; i < ${#all_keys[@]}; i++ )); do
    printf "  %-10s %s\n" "${all_keys[$i]}" "${all_labels[$i]}" >&2
  done
  echo >&2
  printf "Enter space/comma-separated keys to install (or empty to skip): " >&2
  if ! read -r selection < /dev/tty; then
    # User cancelled (Ctrl+C) — treat as "user declined"
    return 3
  fi

  selection="$(echo "$selection" | tr ',' ' ')"
  local -a wanted_keys=()
  read -ra wanted_keys <<< "$selection"

  if [ "${#wanted_keys[@]}" -eq 0 ]; then
    # User entered nothing — treat as "user declined"
    return 3
  fi

  # Validate keys
  local wanted
  for wanted in "${wanted_keys[@]}"; do
    if ! optional_dependency_exists "$wanted"; then
      echo "Unknown dependency key: $wanted" >&2
      return 1
    fi
  done

  selected_keys_csv="$(IFS=,; printf '%s' "${wanted_keys[*]}")"
  printf '%s\n' "$selected_keys_csv"
}

choose_optional_dependencies_with_gum() {
  local key label description selection selected_key
  local -a options=()
  local -a selected_keys=()

  ensure_gum_for_optional_selector || return 1

  while IFS='|' read -r key label description; do
    if optional_dependency_present "$key"; then
      continue
    fi
    options+=("$key"$'\t'"$label"$'\t'"$description")
  done < <(optional_dependency_catalog)

  if [ "${#options[@]}" -eq 0 ]; then
    echo "All optional dependencies are already present." >&2
    return 2
  fi

  # Build gum args as positional arguments (not piped stdin) so gum can use /dev/tty for interaction.
  local -a gum_args=()
  gum_args+=(--no-limit --height 20 --header "Select optional dependencies to install. Use arrows to move, x to toggle, enter to continue.")
  local opt
  for opt in "${options[@]}"; do
    gum_args+=("$opt")
  done

  selection="$(gum choose "${gum_args[@]}" < /dev/tty 2>/dev/tty)" || {
    # Reset terminal state after gum exits (prevents hang on subsequent invocations)
    stty sane < /dev/tty 2>/dev/null || true
    # gum returned non-zero: 1 = user cancelled (Esc), 130 = interrupted
    # Treat as "user declined" with no selections.
    return 3
  }
  # Reset terminal state after gum exits
  stty sane < /dev/tty 2>/dev/null || true

  if [ -n "$selection" ]; then
    while IFS=$'\t' read -r selected_key _; do
      [ -n "$selected_key" ] && selected_keys+=("$selected_key")
    done <<< "$selection"
  fi

  if [ "${#selected_keys[@]}" -eq 0 ]; then
    # User submitted the picker but selected nothing — treat as "user declined"
    return 3
  fi

  local IFS=,
  printf '%s\n' "${selected_keys[*]}"
}

maybe_install_fastfetch() {
  local manager="$1"

  if check_dependency_status "fastfetch" "fastfetch"; then
    return 0
  fi

  case "$manager" in
    apt)
      if apt_package_available "fastfetch"; then
        maybe_install_dependency apt fastfetch fastfetch "system information tool"
      elif command -v brew >/dev/null 2>&1; then
        if prompt_yes_no "fastfetch not found in APT. Install via Homebrew instead?"; then
          maybe_install_dependency brew fastfetch fastfetch "system information tool"
        else
          DEPENDENCY_SUMMARY+=("fastfetch: skipped (APT package unavailable and brew install declined)")
        fi
      else
        DEPENDENCY_SUMMARY+=("fastfetch: missing (APT package unavailable and brew not found)")
      fi
      ;;
    *)
      maybe_install_dependency "$manager" fastfetch fastfetch "system information tool"
      ;;
  esac
}

install_optional_dependency_if_selected() {
  local key="$1"
  shift

  optional_dependency_selected "$key" || return 0
  "$@"
}

install_optional_dependency_from_catalog() {
  local key="$1"
  local detected_manager="$2"
  local description info declared_manager package_name command_name winget_id choco_id install_manager

  description="$(optional_dependency_label "$key")"
  info="$(optional_dependency_install_info "$key" || true)"
  IFS='|' read -r declared_manager package_name command_name winget_id choco_id _ <<< "$info"
  install_manager="$(resolve_package_manager_for_dependency "$detected_manager" "$declared_manager")"

  case "$key" in
    gum) maybe_install_gum "$install_manager" ;;
    q) maybe_install_q "$install_manager" ;;
    eza) maybe_install_eza "$install_manager" ;;
    p7zip) maybe_install_p7zip "$install_manager" ;;
    poppler) maybe_install_poppler "$install_manager" ;;
    oh-my-posh) maybe_install_oh_my_posh ;;
    wezterm) maybe_install_wezterm "$install_manager" ;;
    uv) maybe_install_uv ;;
    bw) maybe_install_bw ;;
    pnpm) maybe_install_pnpm ;;
    cargo) maybe_install_cargo ;;
    dua) maybe_install_dua_cli "$install_manager" ;;
    nvim) maybe_install_neovim "$install_manager" ;;
    k) maybe_note_dependency k "manual install if you want the standalone k command" ;;
    rtk) maybe_install_rtk ;;
    fastfetch) maybe_install_fastfetch "$install_manager" ;;
    "")
      return 0
      ;;
    *)
      if [ -z "$command_name" ]; then
        command_name="$key"
      fi
      case "$install_manager" in
        custom|curl)
          maybe_note_dependency "$command_name" "$description (manual installer: $install_manager)"
          ;;
        winget)
          maybe_note_dependency "$command_name" "$description (Windows winget package: ${winget_id:-$package_name})"
          ;;
        choco)
          maybe_note_dependency "$command_name" "$description (Windows choco package: ${choco_id:-$package_name})"
          ;;
        "")
          maybe_note_dependency "$command_name" "$description (no package manager declared)"
          ;;
        *)
          maybe_install_dependency "$install_manager" "$command_name" "$package_name" "$description"
          ;;
      esac
      ;;
  esac
}

run_with_spinner() {
  local label="$1"
  shift
  if [ "$DRY_RUN" -eq 1 ]; then
    printf "[dry-run] %s: %s\n" "$label" "$*"
    return 0
  fi

  if ! is_verbose; then
    local logfile status
    if is_interactive; then
      printf "[-] %s..." "$label" > /dev/tty
    fi
    logfile="$(mktemp)"
    (
      "$@"
    ) >"$logfile" 2>&1
    status=$?
    if [ $status -ne 0 ]; then
      if is_interactive; then
        printf "\r[failed] %s\n" "$label" > /dev/tty
      else
        printf "[failed] %s\n" "$label" >&2
      fi
      cat "$logfile" >&2
      FAILURES+=("$label")
    else
      if is_interactive; then
        printf "\r[ok] %s\n" "$label" > /dev/tty
      else
        printf "[ok] %s\n" "$label"
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
      printf "\r[%s] %s" "${frames[$spinner_index]}" "$label" > /dev/tty
      spinner_index=$(((spinner_index + 1) % ${#frames[@]}))
      sleep 0.12
    done
    printf "\r" > /dev/tty
  fi

  wait "$pid"
  local status=$?

  if [ $status -eq 0 ]; then
    if is_interactive; then
      printf "[ok] %s\n" "$label" > /dev/tty
    else
      # Overwrite the "[-] label..." line with [ok]
      printf "\r[ok] %s\n" "$label"
    fi
  else
    if is_interactive; then
      printf "[failed] %s\n" "$label" > /dev/tty
    else
      printf "\r[failed] %s\n" "$label"
    fi
    cat "$logfile" >&2
    FAILURES+=("$label")
  fi

  rm -f "$logfile"
  return $status
}

record_failure() {
  local label="$1"
  FAILURES+=("$label")
  printf "\r[failed] %s\n" "$label" >&2
}

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo apt
  elif command -v dnf >/dev/null 2>&1; then
    echo dnf
  elif command -v pacman >/dev/null 2>&1; then
    echo pacman
  elif command -v zypper >/dev/null 2>&1; then
    echo zypper
  elif command -v brew >/dev/null 2>&1; then
    echo brew
  else
    echo none
  fi
}

install_packages() {
  local manager="$1"
  shift
  case "$manager" in
    apt)
      if [ "$APT_UPDATED" -eq 0 ]; then
        run_with_spinner "Updating apt package index" sudo apt-get -qq update
        APT_UPDATED=1
      fi
      run_with_spinner "Installing packages: $*" sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"
      ;;
    dnf)
      run_with_spinner "Installing packages: $*" sudo dnf install -y "$@"
      ;;
    pacman)
      run_with_spinner "Installing packages: $*" sudo pacman -Sy --needed --noconfirm "$@"
      ;;
    zypper)
      run_with_spinner "Installing packages: $*" sudo zypper install -y "$@"
      ;;
    brew)
      run_with_spinner "Installing packages: $*" env HOMEBREW_NO_AUTO_UPDATE=1 brew install "$@"
      ;;
    *)
      return 1
      ;;
  esac
}

apt_package_available() {
  local package_name="$1"

  if ! command -v apt-cache >/dev/null 2>&1; then
    return 1
  fi

  apt-cache show "$package_name" >/dev/null 2>&1
}

check_dependency_status() {
  local command_name="$1"
  local log_name="${2:-$1}"

  if [ "$DRY_RUN" -ne 1 ] && is_interactive && is_verbose; then
    printf "[-] Checking %s...\r" "$log_name" > /dev/tty
  fi

  if command -v "$command_name" >/dev/null 2>&1; then
    if [ "$DRY_RUN" -ne 1 ] && is_interactive && is_verbose; then
      printf "\r[ok] %s is present.             \n" "$log_name" > /dev/tty
    elif [ "$DRY_RUN" -ne 1 ] && is_verbose; then
      printf "[ok] %s is present.\n" "$log_name"
    fi
    DEPENDENCY_SUMMARY+=("$log_name: present")
    return 0
  fi

  if [ "$DRY_RUN" -ne 1 ] && is_interactive && is_verbose; then
    printf "\r" > /dev/tty
  fi
  return 1
}

maybe_install_dependency() {
  local manager="$1"
  local command_name="$2"
  local package_name="$3"
  local description="$4"

  if check_dependency_status "$command_name"; then
    return 0
  fi

  if [ "$manager" = "none" ]; then
    echo "missing optional dependency: $command_name ($description)" >&2
    DEPENDENCY_SUMMARY+=("$command_name: missing (no supported package manager)")
    return 1
  fi

  if [ "$manager" = "cargo" ]; then
    if ! command -v cargo >/dev/null 2>&1; then
      maybe_install_cargo
    fi
    if ! command -v cargo >/dev/null 2>&1; then
      if [ -x "$HOME_DIR/.cargo/bin/cargo" ]; then
        export PATH="$HOME_DIR/.cargo/bin:$PATH"
      else
        DEPENDENCY_SUMMARY+=("$command_name: missing (cargo unavailable)")
        return 0
      fi
    fi
    if prompt_yes_no "Install $command_name for $description via cargo?"; then
      run_with_spinner "Installing $command_name from Git via cargo" cargo install --locked --git "$package_name"
      if command -v "$command_name" >/dev/null 2>&1 || [ -x "$HOME_DIR/.cargo/bin/$command_name" ]; then
        DEPENDENCY_SUMMARY+=("$command_name: installed")
      else
        DEPENDENCY_SUMMARY+=("$command_name: install attempted")
      fi
    else
      is_verbose && echo "skipping $command_name" >&2
      DEPENDENCY_SUMMARY+=("$command_name: skipped")
    fi
    return 0
  fi

  if [ "$manager" = "apt" ] && ! apt_package_available "$package_name"; then
    if is_interactive; then
      echo "APT package not available: $package_name ($description); skipping automatic install." > /dev/tty
    fi
    DEPENDENCY_SUMMARY+=("$command_name: missing (apt package unavailable)")
    return 0
  fi

  if prompt_yes_no "Install $package_name for $description?"; then
    install_packages "$manager" "$package_name"
    if command -v "$command_name" >/dev/null 2>&1; then
      DEPENDENCY_SUMMARY+=("$command_name: installed")
    else
      DEPENDENCY_SUMMARY+=("$command_name: install attempted")
    fi
  else
    is_verbose && echo "skipping $package_name" >&2
    DEPENDENCY_SUMMARY+=("$command_name: skipped")
  fi
}

normalize_semver() {
  local version="${1#v}"
  version="${version%%-*}"
  printf '%s\n' "$version"
}

version_gte() {
  local left right
  local -a left_parts right_parts
  local i left_value right_value

  left="$(normalize_semver "$1")"
  right="$(normalize_semver "$2")"
  IFS=. read -r -a left_parts <<< "$left"
  IFS=. read -r -a right_parts <<< "$right"

  for i in 0 1 2 3; do
    left_value="${left_parts[$i]:-0}"
    right_value="${right_parts[$i]:-0}"
    if (( left_value > right_value )); then
      return 0
    fi
    if (( left_value < right_value )); then
      return 1
    fi
  done

  return 0
}

get_nvim_version() {
  local nvim_cmd
  nvim_cmd="$(resolve_nvim_command)" || return 1
  "$nvim_cmd" --version 2>/dev/null | awk 'NR == 1 { sub(/^NVIM v/, "", $0); print $0; exit }'
}

resolve_nvim_command() {
  if [ -x "$STATE_HOME/bin/nvim" ]; then
    printf '%s\n' "$STATE_HOME/bin/nvim"
    return 0
  fi

  if command -v nvim >/dev/null 2>&1; then
    command -v nvim
    return 0
  fi

  return 1
}

have_supported_nvim() {
  local version
  version="$(get_nvim_version 2>/dev/null)" || return 1
  [ -n "$version" ] && version_gte "$version" "$NEOVIM_MIN_VERSION"
}

download_to_file() {
  local url="$1"
  local output="$2"

  if command -v curl >/dev/null 2>&1; then
    run_with_spinner "Downloading $(basename "$output")" curl -fL --retry 3 -o "$output" "$url"
  elif command -v wget >/dev/null 2>&1; then
    run_with_spinner "Downloading $(basename "$output")" wget -qO "$output" "$url"
  else
    echo "Neither curl nor wget is available for downloading $url" >&2
    return 1
  fi
}

install_pinned_neovim_linux() {
  local asset_name extracted_dir release_url
  local tools_root install_root bin_dir archive_path

  case "$(uname -m)" in
    x86_64|amd64)
      asset_name="nvim-linux-x86_64.tar.gz"
      extracted_dir="nvim-linux-x86_64"
      ;;
    aarch64|arm64)
      asset_name="nvim-linux-arm64.tar.gz"
      extracted_dir="nvim-linux-arm64"
      ;;
    *)
      echo "Unsupported Linux architecture for pinned Neovim install: $(uname -m)" >&2
      return 1
      ;;
  esac

  release_url="https://github.com/neovim/neovim/releases/download/v${NEOVIM_LINUX_VERSION}/${asset_name}"
  tools_root="$STATE_HOME/tools/neovim"
  install_root="$tools_root/v${NEOVIM_LINUX_VERSION}"
  bin_dir="$STATE_HOME/bin"
  archive_path="${TMPDIR:-/tmp}/${asset_name}"

  run_cmd mkdir -p "$install_root" "$bin_dir" || return 1

  if [ ! -x "$install_root/$extracted_dir/bin/nvim" ]; then
    download_to_file "$release_url" "$archive_path" || return 1
    run_with_spinner "Extracting pinned Neovim v${NEOVIM_LINUX_VERSION}" tar -xzf "$archive_path" -C "$install_root" || return 1
  fi

  run_cmd ln -sfn "$install_root/$extracted_dir/bin/nvim" "$bin_dir/nvim" || return 1
}

maybe_install_neovim() {
  local manager="$1"
  local version_before version_after attempted_package_install=0

  if have_supported_nvim; then
    DEPENDENCY_SUMMARY+=("nvim: present ($(get_nvim_version))")
    return 0
  fi

  version_before="$(get_nvim_version 2>/dev/null || true)"
  if [ -n "$version_before" ] && is_interactive; then
    echo "Detected Neovim $version_before, but LazyVim requires >= $NEOVIM_MIN_VERSION." > /dev/tty
  fi

  if [ "$manager" != "none" ]; then
    if [ "$manager" = "apt" ] && ! apt_package_available "neovim"; then
      if is_interactive; then
        echo "APT package not available: neovim (Neovim runtime for LazyVim); skipping automatic package install." > /dev/tty
      fi
    elif prompt_yes_no "Install neovim package for LazyVim?"; then
      attempted_package_install=1
      install_packages "$manager" neovim
      if have_supported_nvim; then
        DEPENDENCY_SUMMARY+=("nvim: installed ($(get_nvim_version))")
        return 0
      fi
    else
      is_verbose && echo "skipping neovim package" >&2
    fi
  fi

  if [ "$(uname -s)" = "Linux" ]; then
    if [ "$attempted_package_install" -eq 1 ] || prompt_yes_no "Install pinned Neovim v${NEOVIM_LINUX_VERSION} from the official release?"; then
      if install_pinned_neovim_linux && have_supported_nvim; then
        DEPENDENCY_SUMMARY+=("nvim: installed official v$(get_nvim_version)")
        return 0
      fi
      DEPENDENCY_SUMMARY+=("nvim: official install attempted")
      return 1
    fi
  fi

  version_after="$(get_nvim_version 2>/dev/null || true)"
  if [ -n "$version_after" ]; then
    DEPENDENCY_SUMMARY+=("nvim: present but too old ($version_after < $NEOVIM_MIN_VERSION)")
  else
    DEPENDENCY_SUMMARY+=("nvim: missing")
  fi
  return 1
}

maybe_note_dependency() {
  local command_name="$1"
  local description="$2"

  if command -v "$command_name" >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("$command_name: present")
    return 0
  fi

  if is_interactive; then
    echo "Optional tool not found: $command_name ($description)." >&2
  fi
  DEPENDENCY_SUMMARY+=("$command_name: missing (manual install)")
}

maybe_install_rtk() {
  if check_dependency_status "rtk" "rtk"; then
    return 0
  fi

  if ! prompt_yes_no "Install rtk token-optimized AI CLI proxy from the official release (direct download)?"; then
    DEPENDENCY_SUMMARY+=("rtk: skipped")
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    if prompt_yes_no "rtk install needs curl and tar. Install them first?"; then
      local manager
      manager="$(detect_package_manager)"
      install_packages "$manager" curl tar
    else
      DEPENDENCY_SUMMARY+=("rtk: missing (requires curl and tar)")
      return 1
    fi
  fi

  local os arch target_url tmp_dir
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"

  case "$arch" in
    x86_64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) DEPENDENCY_SUMMARY+=("rtk: unsupported architecture $arch"); return 1 ;;
  esac

  case "$os" in
    linux) target_url="https://github.com/rtk-ai/rtk/releases/download/v${RTK_VERSION}/rtk-${arch}-unknown-linux-musl.tar.gz" ;;
    darwin) target_url="https://github.com/rtk-ai/rtk/releases/download/v${RTK_VERSION}/rtk-${arch}-apple-darwin.tar.gz" ;;
    *) DEPENDENCY_SUMMARY+=("rtk: unsupported OS $os"); return 1 ;;
  esac

  tmp_dir="$(mktemp -d)"
  run_with_spinner "Downloading and extracting rtk v${RTK_VERSION}" sh -c "curl -fsSL '$target_url' | tar -xz -C '$tmp_dir'"
  
  if [ -f "$tmp_dir/rtk" ]; then
    run_cmd mkdir -p "$HOME_DIR/.local/bin"
    run_cmd cp "$tmp_dir/rtk" "$HOME_DIR/.local/bin/rtk"
    run_cmd chmod +x "$HOME_DIR/.local/bin/rtk"
    DEPENDENCY_SUMMARY+=("rtk: installed v${RTK_VERSION}")
  else
    # Fallback to cargo if direct download failed
    if command -v cargo >/dev/null 2>&1; then
       run_with_spinner "Installing rtk via cargo (fallback)" cargo install --git https://github.com/rtk-ai/rtk
       if command -v rtk >/dev/null 2>&1 || [ -x "$HOME_DIR/.cargo/bin/rtk" ]; then
         DEPENDENCY_SUMMARY+=("rtk: installed (via cargo fallback)")
         rm -rf "$tmp_dir"
         return 0
       fi
    fi
    DEPENDENCY_SUMMARY+=("rtk: install attempted")
  fi
  rm -rf "$tmp_dir"
}

maybe_install_oh_my_posh() {
  if check_dependency_status "oh-my-posh" "oh-my-posh"; then
    return 0
  fi

  if ! prompt_yes_no "Install oh-my-posh via the official install.sh (curl)?"; then
    DEPENDENCY_SUMMARY+=("oh-my-posh: skipped")
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    if prompt_yes_no "oh-my-posh install needs curl. Install curl first?"; then
      local manager
      manager="$(detect_package_manager)"
      install_packages "$manager" curl
    else
      DEPENDENCY_SUMMARY+=("oh-my-posh: missing (requires curl)")
      return 1
    fi
  fi

  run_with_spinner "Installing oh-my-posh" sh -c "curl -s https://ohmyposh.dev/install.sh | bash -s -- -d $HOME_DIR/.local/bin"
  if command -v oh-my-posh >/dev/null 2>&1 || [ -x "$HOME_DIR/.local/bin/oh-my-posh" ]; then
    DEPENDENCY_SUMMARY+=("oh-my-posh: installed")
  else
    DEPENDENCY_SUMMARY+=("oh-my-posh: install attempted")
  fi
}

eza_apt_repo_configured() {
  [ -f /etc/apt/keyrings/gierens.gpg ] || return 1
  [ -f /etc/apt/sources.list.d/gierens.list ] || return 1
  grep -Fq "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
    /etc/apt/sources.list.d/gierens.list 2>/dev/null
}

setup_eza_apt_repo() {
  if eza_apt_repo_configured; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    if prompt_yes_no "eza Debian/Ubuntu install needs curl. Install curl first?"; then
      install_packages apt curl
    else
      DEPENDENCY_SUMMARY+=("eza: missing (requires curl for Debian/Ubuntu repo setup)")
      return 1
    fi
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    if prompt_yes_no "eza Debian/Ubuntu install needs gpg. Install gpg first?"; then
      install_packages apt gnupg
    else
      DEPENDENCY_SUMMARY+=("eza: missing (requires gpg for Debian/Ubuntu repo setup)")
      return 1
    fi
  fi

  run_with_spinner "Creating gierens APT keyring directory for eza" sudo mkdir -p /etc/apt/keyrings || return 1
  run_with_spinner "Installing gierens APT signing key for eza" \
    sh -c 'curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg' || return 1
  run_with_spinner "Adding gierens APT source for eza" \
    sh -c 'echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null' || return 1
  APT_UPDATED=0
  return 0
}

maybe_install_eza() {
  local manager="$1"

  if check_dependency_status "eza" "eza"; then
    return 0
  fi

  case "$manager" in
    brew|pacman|zypper)
      if prompt_yes_no "Install eza for modern ls aliases?"; then
        install_packages "$manager" eza
        if command -v eza >/dev/null 2>&1; then
          DEPENDENCY_SUMMARY+=("eza: installed")
        else
          DEPENDENCY_SUMMARY+=("eza: install attempted")
        fi
      else
        DEPENDENCY_SUMMARY+=("eza: skipped")
      fi
      ;;
    dnf)
      DEPENDENCY_SUMMARY+=("eza: manual install recommended on Fedora 42+")
      if is_interactive; then
        echo "eza upstream notes Fedora 42+ may require manual install or cargo; skipping automatic dnf install." > /dev/tty
      fi
      ;;
    apt)
      if ! prompt_yes_no "Install eza modern ls aliases via the gierens Debian/Ubuntu APT repo?"; then
        DEPENDENCY_SUMMARY+=("eza: skipped")
        return 0
      fi

      if ! setup_eza_apt_repo; then
        DEPENDENCY_SUMMARY+=("eza: install attempted")
        return 0
      fi

      install_packages apt eza
      if command -v eza >/dev/null 2>&1; then
        DEPENDENCY_SUMMARY+=("eza: installed")
      else
        DEPENDENCY_SUMMARY+=("eza: install attempted")
      fi
      ;;
    *)
      DEPENDENCY_SUMMARY+=("eza: missing (manual install)")
      ;;
  esac
}

wezterm_apt_repo_configured() {
  [ -f /usr/share/keyrings/wezterm-fury.gpg ] && [ -f /etc/apt/sources.list.d/wezterm.list ]
}

setup_wezterm_apt_repo() {
  if wezterm_apt_repo_configured; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    if prompt_yes_no "WezTerm install needs curl. Install curl first?"; then
      install_packages apt curl
    else
      return 1
    fi
  fi

  run_with_spinner "Installing WezTerm APT signing key" \
    sh -c 'curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg' || return 1
  run_with_spinner "Adding WezTerm APT source" \
    sh -c 'echo "deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *" | sudo tee /etc/apt/sources.list.d/wezterm.list >/dev/null' || return 1
  APT_UPDATED=0
  return 0
}

maybe_install_wezterm() {
  local manager="$1"

  if check_dependency_status "wezterm" "wezterm"; then
    return 0
  fi

  case "$manager" in
    apt)
      if prompt_yes_no "Install WezTerm terminal via official APT repo?"; then
        setup_wezterm_apt_repo && install_packages apt wezterm
        if command -v wezterm >/dev/null 2>&1; then
          DEPENDENCY_SUMMARY+=("wezterm: installed")
        else
          DEPENDENCY_SUMMARY+=("wezterm: install attempted")
        fi
      else
        DEPENDENCY_SUMMARY+=("wezterm: skipped")
      fi
      ;;
    brew)
      if prompt_yes_no "Install WezTerm terminal via brew?"; then
        install_packages brew wezterm
        if command -v wezterm >/dev/null 2>&1; then
          DEPENDENCY_SUMMARY+=("wezterm: installed")
        else
          DEPENDENCY_SUMMARY+=("wezterm: install attempted")
        fi
      else
        DEPENDENCY_SUMMARY+=("wezterm: skipped")
      fi
      ;;
    *)
      maybe_note_dependency wezterm "WezTerm terminal (manual install recommended)"
      ;;
  esac
}

q_apt_repo_configured() {
  [ -f /etc/apt/keyrings/natesales.gpg ] || return 1
  [ -f /etc/apt/sources.list.d/natesales.list ] || return 1
  grep -Fq "deb [signed-by=/etc/apt/keyrings/natesales.gpg] https://repo.natesales.net/apt * *" \
    /etc/apt/sources.list.d/natesales.list 2>/dev/null
}

setup_q_apt_repo() {
  if q_apt_repo_configured; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    if prompt_yes_no "q Debian/Ubuntu install needs curl. Install curl first?"; then
      install_packages apt curl
    else
      DEPENDENCY_SUMMARY+=("q: missing (requires curl for Debian/Ubuntu repo setup)")
      return 1
    fi
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    if prompt_yes_no "q Debian/Ubuntu install needs gpg. Install gpg first?"; then
      install_packages apt gpg
    else
      DEPENDENCY_SUMMARY+=("q: missing (requires gpg for Debian/Ubuntu repo setup)")
      return 1
    fi
  fi

  run_with_spinner "Creating natesales APT keyring directory for q" sudo mkdir -p /etc/apt/keyrings || return 1
  run_with_spinner "Installing natesales APT signing key for q" \
    sh -c 'curl -fsSL https://repo.natesales.net/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/natesales.gpg' || return 1
  run_with_spinner "Adding natesales APT source for q" \
    sh -c 'echo "deb [signed-by=/etc/apt/keyrings/natesales.gpg] https://repo.natesales.net/apt * *" | sudo tee /etc/apt/sources.list.d/natesales.list >/dev/null' || return 1
  APT_UPDATED=0
  return 0
}

maybe_install_q() {
  local manager="$1"
  local aur_helper=""

  if check_dependency_status "q" "q"; then
    return 0
  fi

  case "$manager" in
    apt)
      if ! prompt_yes_no "Install q text-as-data CLI via the natesales Debian/Ubuntu APT repo?"; then
        DEPENDENCY_SUMMARY+=("q: skipped")
        return 0
      fi

      if ! setup_q_apt_repo; then
        DEPENDENCY_SUMMARY+=("q: install attempted")
        return 0
      fi

      install_packages apt q
      if command -v q >/dev/null 2>&1; then
        DEPENDENCY_SUMMARY+=("q: installed")
      else
        DEPENDENCY_SUMMARY+=("q: install attempted")
      fi
      ;;
    pacman)
      if command -v yay >/dev/null 2>&1; then
        aur_helper="yay"
      elif command -v paru >/dev/null 2>&1; then
        aur_helper="paru"
      else
        DEPENDENCY_SUMMARY+=("q: missing (Arch install requires yay or paru for AUR package q-dns-git)")
        return 0
      fi

      if ! prompt_yes_no "Install q via Arch AUR package q-dns-git using $aur_helper?"; then
        DEPENDENCY_SUMMARY+=("q: skipped")
        return 0
      fi

      run_with_spinner "Installing q from AUR package q-dns-git via $aur_helper" \
        "$aur_helper" -S --needed --noconfirm q-dns-git
      if command -v q >/dev/null 2>&1; then
        DEPENDENCY_SUMMARY+=("q: installed")
      else
        DEPENDENCY_SUMMARY+=("q: install attempted")
      fi
      ;;
    none)
      DEPENDENCY_SUMMARY+=("q: missing (no supported package manager)")
      ;;
    *)
      maybe_install_dependency "$manager" q q "q text-as-data CLI"
      ;;
  esac
}

maybe_install_p7zip() {
  local manager="$1"
  local package_name="p7zip"

  if check_dependency_status "7z" "p7zip"; then
    return 0
  fi

  case "$manager" in
    apt) package_name="p7zip-full" ;;
    brew) package_name="p7zip" ;;
  esac

  maybe_install_dependency "$manager" 7z "$package_name" "archive preview and extraction for yazi"
}

maybe_install_poppler() {
  local manager="$1"
  local package_name="poppler"

  if check_dependency_status "pdftotext" "poppler"; then
    return 0
  fi

  case "$manager" in
    apt) package_name="poppler-utils" ;;
    brew) package_name="poppler" ;;
  esac

  maybe_install_dependency "$manager" pdftotext "$package_name" "PDF preview support for yazi"
}

maybe_install_uv() {
  if check_dependency_status "uv" "uv"; then
    return 0
  fi

  if ! prompt_yes_no "Install uv for Python package manager (official installer)?"; then
    is_verbose && echo "skipping uv" >&2
    DEPENDENCY_SUMMARY+=("uv: skipped")
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    run_with_spinner "Installing uv via official installer" sh -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
  elif command -v wget >/dev/null 2>&1; then
    run_with_spinner "Installing uv via official installer" sh -c 'wget -qO- https://astral.sh/uv/install.sh | sh'
  else
    if [ "$PACKAGE_MANAGER" != "none" ] && prompt_yes_no "uv installer needs curl or wget. Install curl and retry?"; then
      install_packages "$PACKAGE_MANAGER" curl
      run_with_spinner "Installing uv via official installer" sh -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
    else
      DEPENDENCY_SUMMARY+=("uv: missing (requires curl or wget)")
      return 0
    fi
  fi

  if command -v uv >/dev/null 2>&1 || [ -x "$HOME_DIR/.local/bin/uv" ]; then
    DEPENDENCY_SUMMARY+=("uv: installed")
  else
    DEPENDENCY_SUMMARY+=("uv: install attempted")
  fi
}

extract_zip_archive() {
  local archive_path="$1"
  local destination_dir="$2"

  if command -v unzip >/dev/null 2>&1; then
    run_with_spinner "Extracting $(basename "$archive_path")" unzip -oq "$archive_path" -d "$destination_dir"
  elif command -v bsdtar >/dev/null 2>&1; then
    run_with_spinner "Extracting $(basename "$archive_path")" bsdtar -xf "$archive_path" -C "$destination_dir"
  else
    echo "Neither unzip nor bsdtar is available for extracting $archive_path" >&2
    return 1
  fi
}

maybe_install_bw() {
  local archive_path release_url install_root bin_dir extracted_binary target_binary

  if command -v bw >/dev/null 2>&1 || [ -x "$STATE_HOME/bin/bw" ]; then
    DEPENDENCY_SUMMARY+=("bw: present")
    return 0
  fi

  if ! prompt_yes_no "Install Bitwarden CLI from the official native executable archive?"; then
    is_verbose && echo "skipping bw" >&2
    DEPENDENCY_SUMMARY+=("bw: skipped")
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    if [ "$PACKAGE_MANAGER" != "none" ] && prompt_yes_no "Bitwarden CLI installer needs curl or wget. Install curl and retry?"; then
      install_packages "$PACKAGE_MANAGER" curl
    else
      DEPENDENCY_SUMMARY+=("bw: missing (requires curl or wget)")
      return 0
    fi
  fi

  if ! command -v unzip >/dev/null 2>&1 && ! command -v bsdtar >/dev/null 2>&1; then
    if [ "$PACKAGE_MANAGER" != "none" ] && prompt_yes_no "Bitwarden CLI archive extraction needs unzip or bsdtar. Install unzip and retry?"; then
      install_packages "$PACKAGE_MANAGER" unzip
    else
      DEPENDENCY_SUMMARY+=("bw: missing (requires unzip or bsdtar)")
      return 0
    fi
  fi

  release_url="https://github.com/bitwarden/cli/releases/download/v${BW_VERSION}/bw-linux-${BW_VERSION}.zip"
  archive_path="${TMPDIR:-/tmp}/bw-linux-${BW_VERSION}.zip"
  install_root="$STATE_HOME/tools/bitwarden-cli/v${BW_VERSION}"
  bin_dir="$STATE_HOME/bin"
  extracted_binary="$install_root/bw"
  target_binary="$bin_dir/bw"

  run_cmd mkdir -p "$install_root" "$bin_dir" || {
    DEPENDENCY_SUMMARY+=("bw: install attempted")
    return 1
  }

  if [ ! -x "$extracted_binary" ]; then
    download_to_file "$release_url" "$archive_path" || {
      DEPENDENCY_SUMMARY+=("bw: install attempted")
      return 1
    }
    extract_zip_archive "$archive_path" "$install_root" || {
      DEPENDENCY_SUMMARY+=("bw: install attempted")
      return 1
    }
    run_cmd chmod u=rwx,go=rx "$extracted_binary" || true
  fi

  run_cmd ln -sfn "$extracted_binary" "$target_binary" || {
    DEPENDENCY_SUMMARY+=("bw: install attempted")
    return 1
  }

  if command -v bw >/dev/null 2>&1 || [ -x "$target_binary" ]; then
    DEPENDENCY_SUMMARY+=("bw: installed official v$BW_VERSION")
  else
    DEPENDENCY_SUMMARY+=("bw: install attempted")
  fi
}

maybe_install_dua_cli() {
  local manager="$1"
  local repo_url="https://github.com/byron/dua-cli.git"

  if command -v dua >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("dua: present")
    return 0
  fi

  if ! prompt_yes_no "Install dua-cli for disk usage analysis from byron/dua-cli via cargo?"; then
    is_verbose && echo "skipping dua-cli" >&2
    DEPENDENCY_SUMMARY+=("dua: skipped")
    return 0
  fi

  if ! command -v cargo >/dev/null 2>&1; then
    maybe_install_dependency "$manager" cargo cargo "Rust package manager required for dua-cli"
  fi

  if ! command -v cargo >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("dua: missing (cargo unavailable)")
    return 0
  fi

  run_with_spinner "Installing dua-cli from GitHub via cargo" cargo install --locked --git "$repo_url" dua-cli
  if command -v dua >/dev/null 2>&1 || [ -x "$HOME_DIR/.cargo/bin/dua" ]; then
    DEPENDENCY_SUMMARY+=("dua: installed")
  else
    DEPENDENCY_SUMMARY+=("dua: install attempted")
  fi
}

maybe_install_pnpm() {
  local pnpm_home="${PNPM_HOME:-$HOME_DIR/.local/share/pnpm}"

  if command -v pnpm >/dev/null 2>&1; then
    DEPENDENCY_SUMMARY+=("pnpm: present")
    return 0
  fi

  if ! prompt_yes_no "Install pnpm package manager?"; then
    is_verbose && echo "skipping pnpm" >&2
    DEPENDENCY_SUMMARY+=("pnpm: skipped")
    return 0
  fi

  export PNPM_HOME="$pnpm_home"
  export PATH="$PNPM_HOME:$PATH"
  run_cmd mkdir -p "$PNPM_HOME"

  if command -v corepack >/dev/null 2>&1; then
    run_with_spinner "Enabling pnpm@$PNPM_VERSION via corepack" \
      corepack enable --install-directory "$PNPM_HOME" pnpm
    run_with_spinner "Preparing pnpm@$PNPM_VERSION via corepack" \
      corepack prepare "pnpm@$PNPM_VERSION" --activate
  elif command -v npm >/dev/null 2>&1; then
    run_with_spinner "Installing pnpm@$PNPM_VERSION via npm" \
      npm install --global "pnpm@$PNPM_VERSION" --prefix "$PNPM_HOME"
    if [ -x "$PNPM_HOME/bin/pnpm" ]; then
      run_cmd ln -sfn "$PNPM_HOME/bin/pnpm" "$PNPM_HOME/pnpm"
    fi
    if [ -x "$PNPM_HOME/bin/pnpx" ]; then
      run_cmd ln -sfn "$PNPM_HOME/bin/pnpx" "$PNPM_HOME/pnpx"
    fi
  else
    DEPENDENCY_SUMMARY+=("pnpm: missing (requires corepack or npm)")
    return 0
  fi

  if command -v pnpm >/dev/null 2>&1 || [ -x "$PNPM_HOME/pnpm" ] || [ -x "$PNPM_HOME/bin/pnpm" ]; then
    DEPENDENCY_SUMMARY+=("pnpm: installed")
  else
    DEPENDENCY_SUMMARY+=("pnpm: install attempted")
  fi
}

link_file() {
  local source="$1"
  local target="$2"
  run_cmd mkdir -p "$(dirname "$target")"
  backup_target "$source" "$target" || {
    record_failure "Backing up $target"
    return 1
  }
  run_cmd ln -sfn "$source" "$target" || {
    record_failure "Linking $target"
    return 1
  }
  echo "linked $target"
}

backup_target() {
  local source="$1"
  local target="$2"
  local target_dir target_name backup_dir

  if [ -L "$target" ]; then
    local current
    current="$(readlink "$target")"
    if [ "$current" = "$source" ]; then
      return
    fi
  fi

  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    return
  fi

  target_dir="$(dirname "$target")"
  target_name="$(basename "$target")"
  backup_dir="$BACKUP_ROOT$target_dir"
  run_cmd mkdir -p "$backup_dir"

  if [ -d "$target" ] && [ ! -L "$target" ]; then
    run_cmd mv "$target" "$backup_dir/${target_name}.${TIMESTAMP}"
  else
    run_cmd mv "$target" "$backup_dir/${target_name}.${TIMESTAMP}"
  fi
  echo "backed up $target -> $backup_dir/${target_name}.${TIMESTAMP}"
}

sync_repo() {
  local repo_url="$1"
  local ref="$2"
  local target="$3"

  if [ ! -d "$target/.git" ]; then
    run_with_spinner "Cloning $(basename "$target")" git clone "$repo_url" "$target" || return 1
  fi

  run_with_spinner "Updating $(basename "$target")" git -C "$target" fetch origin "$ref" || return 1
  run_with_spinner "Pinning $(basename "$target")" git -c advice.detachedHead=false -C "$target" checkout "$ref" || return 1
}

normalize_tree_permissions() {
  local target="$1"

  [ -e "$target" ] || return 0

  find "$target" -type d -exec chmod u=rwx,go=rx {} + || return 1
  find "$target" -type f -exec chmod u=rw,go=r {} + || return 1
}

restore_git_executable_bits() {
  local repo_root="$1"
  local relative_path

  [ -d "$repo_root/.git" ] || return 0

  while IFS= read -r relative_path; do
    [ -n "$relative_path" ] || continue
    run_cmd chmod u=rwx,go=rx "$repo_root/$relative_path" || return 1
  done < <(
    git -C "$repo_root" ls-files --stage |
      awk '$1 == "100755" { print $4 }'
  )
}

ensure_oh_my_zsh_permissions() {
  local omz_root="$STATE_HOME/oh-my-zsh"
  local git_dir
  local repo_root

  if ! normalize_tree_permissions "$omz_root"; then
    TOOL_SUMMARY+=("oh-my-zsh permissions: failed")
    record_failure "Normalizing oh-my-zsh permissions"
    return 1
  fi

  while IFS= read -r git_dir; do
    repo_root="${git_dir%/.git}"
    restore_git_executable_bits "$repo_root" || {
      TOOL_SUMMARY+=("oh-my-zsh permissions: failed")
      record_failure "Restoring executable bits in $repo_root"
      return 1
    }
  done < <(find "$omz_root" -type d -name .git -prune)

  TOOL_SUMMARY+=("oh-my-zsh permissions: normalized")
}

ensure_ssh_include() {
  local ssh_dir="$HOME_DIR/.ssh"
  local ssh_config="$ssh_dir/config"
  local include_line="Include ~/.config/ooodnakov/ssh/config"

  run_cmd mkdir -p "$ssh_dir"
  run_cmd touch "$ssh_config"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] ensure SSH include in %s\n' "$ssh_config"
    return 0
  fi

  if ! grep -Fqx "$include_line" "$ssh_config"; then
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '[dry-run] prepend SSH include in %s\n' "$ssh_config"
    elif printf "%s\n\n" "$include_line" | cat - "$ssh_config" > "$ssh_config.tmp" && mv "$ssh_config.tmp" "$ssh_config"; then
      :
    else
      record_failure "Updating SSH include config"
      return 1
    fi
  fi
}

install_fonts() {
  local source_dir="$REPO_ROOT/fonts/meslo"

  if [ -d "$source_dir" ]; then
    run_cmd mkdir -p "$FONT_TARGET_DIR"
    run_cmd cp "$source_dir"/*.ttf "$FONT_TARGET_DIR"/ || record_failure "Copying bundled fonts"
    if command -v fc-cache >/dev/null 2>&1; then
      run_with_spinner "Refreshing font cache" fc-cache -f "$FONT_TARGET_DIR" >/dev/null 2>&1 || true
    fi
  fi
}

generate_autogen_completions() {
  local target_dir="$REPO_ROOT/home/.config/ooodnakov/zsh/completions/autogen"
  local spec binary description output_file completion_cmd
  [ "$DRY_RUN" -eq 1 ] && { echo "[dry-run] Generating autogen completions in $target_dir"; return 0; }

  mkdir -p "$target_dir"

  if [ ! -f "$AUTOGEN_COMPLETIONS_MANIFEST" ]; then
    TOOL_SUMMARY+=("autogen completions: manifest missing ($AUTOGEN_COMPLETIONS_MANIFEST)")
    return 1
  fi

  while IFS= read -r spec; do
    case "$spec" in
      ""|\#*) continue ;;
    esac
    IFS='|' read -r binary description output_file completion_cmd <<< "$spec"
    if command -v "$binary" >/dev/null 2>&1; then
      run_with_spinner "$description" sh -c "$completion_cmd > '$target_dir/$output_file'"
    fi
  done < "$AUTOGEN_COMPLETIONS_MANIFEST"
}

generate_oooconf_completions() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] Generating oooconf command completions"
    return 0
  fi

  if [ ! -f "$OOOCONF_COMPLETIONS_GENERATOR" ]; then
    TOOL_SUMMARY+=("oooconf completions: generator missing ($OOOCONF_COMPLETIONS_GENERATOR)")
    return 1
  fi

  run_with_spinner "Generating oooconf command completions" \
    run_python "$OOOCONF_COMPLETIONS_GENERATOR"
}

install_managed_tools() {
  local bin_dir="$STATE_HOME/bin"

  sync_repo "$NVM_REPO" "$NVM_REF" "$HOME_DIR/.nvm" && TOOL_SUMMARY+=("nvm: synced") || TOOL_SUMMARY+=("nvm: failed")
  sync_repo "$K_REPO" "$K_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/k" && TOOL_SUMMARY+=("k: synced") || TOOL_SUMMARY+=("k: failed")
  sync_repo "$MARKER_REPO" "$MARKER_REF" "$STATE_HOME/marker" && TOOL_SUMMARY+=("marker: synced") || TOOL_SUMMARY+=("marker: failed")
  sync_repo "$TODO_REPO" "$TODO_REF" "$STATE_HOME/todo" && TOOL_SUMMARY+=("todo.txt-cli: synced") || TOOL_SUMMARY+=("todo.txt-cli: failed")

  run_cmd mkdir -p "$bin_dir"
  run_cmd ln -sfn "$STATE_HOME/todo/todo.sh" "$bin_dir/todo.sh" && TOOL_SUMMARY+=("todo.sh: linked into $bin_dir") || TOOL_SUMMARY+=("todo.sh: link failed")

  if command -v python3 >/dev/null 2>&1 && [ -f "$STATE_HOME/marker/install.py" ]; then
    if python3 "$STATE_HOME/marker/install.py" >/dev/null 2>&1; then
      TOOL_SUMMARY+=("marker: install.py succeeded")
    else
      TOOL_SUMMARY+=("marker: install.py failed")
      if [ "$PACKAGE_MANAGER" = "apt" ] && prompt_yes_no "marker install failed. Install python-is-python3 and retry?"; then
        install_packages "$PACKAGE_MANAGER" python-is-python3
        if python3 "$STATE_HOME/marker/install.py" >/dev/null 2>&1; then
          TOOL_SUMMARY+=("marker: retry succeeded after python-is-python3")
        else
          TOOL_SUMMARY+=("marker: retry failed after python-is-python3")
        fi
      fi
    fi
  else
    TOOL_SUMMARY+=("marker: install.py skipped")
  fi
}

install_auto_uv_env() {
  local source_dir="$STATE_HOME/src/auto-uv-env"
  local legacy_dir="$STATE_HOME/auto-uv-env"
  local share_dir="$STATE_HOME/auto-uv-env"
  local bin_dir="$STATE_HOME/bin"

  if [ -d "$legacy_dir/.git" ] && [ ! -e "$source_dir" ]; then
    run_cmd mkdir -p "$(dirname "$source_dir")"
    if run_cmd mv "$legacy_dir" "$source_dir"; then
      TOOL_SUMMARY+=("auto-uv-env: migrated legacy checkout to $source_dir")
    else
      TOOL_SUMMARY+=("auto-uv-env: failed to migrate legacy checkout")
      record_failure "Migrating auto-uv-env checkout"
      return 1
    fi
  fi

  sync_repo "$AUTO_UV_ENV_REPO" "$AUTO_UV_ENV_REF" "$source_dir" || {
    TOOL_SUMMARY+=("auto-uv-env: failed")
    return 1
  }

  if [ "$DRY_RUN" -eq 1 ]; then
    TOOL_SUMMARY+=("auto-uv-env: dry-run preview")
    return 0
  fi

  if [ ! -f "$source_dir/auto-uv-env" ] || [ ! -d "$source_dir/share/auto-uv-env" ]; then
    TOOL_SUMMARY+=("auto-uv-env: install payload missing from source checkout")
    record_failure "Installing auto-uv-env payload"
    return 1
  fi

  run_cmd mkdir -p "$bin_dir"
  run_cmd mkdir -p "$share_dir"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] install auto-uv-env share files into %s\n' "$share_dir"
  elif ! find "$source_dir/share/auto-uv-env" -maxdepth 1 -type f -exec install -m 0644 {} "$share_dir/" \;; then
    TOOL_SUMMARY+=("auto-uv-env: failed to install share files")
    record_failure "Installing auto-uv-env share files"
    return 1
  fi

  run_cmd ln -sfn "$source_dir/auto-uv-env" "$bin_dir/auto-uv-env" || {
    TOOL_SUMMARY+=("auto-uv-env: failed to link executable")
    record_failure "Linking auto-uv-env executable"
    return 1
  }

  run_cmd chmod u=rwx,go=rx "$source_dir/auto-uv-env" || true
  TOOL_SUMMARY+=("auto-uv-env: installed to $share_dir and linked into $bin_dir")
}

print_summary() {
  local item

  echo
  echo "Dependency summary:"
  for item in "${DEPENDENCY_SUMMARY[@]}"; do
    if ! is_verbose && [[ "$item" == *": present" || "$item" == *": skipped" ]]; then
      continue
    fi
    echo "  - $item"
  done

  echo "Managed tools:"
  for item in "${TOOL_SUMMARY[@]}"; do
    if ! is_verbose && [[ "$item" == *": linked" || "$item" == *": synced" || "$item" == "ensured directory: "* || "$item" == *": linked into "* || "$item" == *": permissions normalized" || "$item" == *": install.py succeeded" ]]; then
       continue
    fi
    echo "  - $item"
  done
  if [ "${#FAILURES[@]}" -gt 0 ]; then
    echo "Failures:"
    for item in "${FAILURES[@]}"; do
      echo "  - $item"
    done
  fi
}

update_repo() {
  run_with_spinner "Pulling latest repository changes" git -C "$REPO_ROOT" pull --ff-only
}

doctor_check_link() {
  local source="$1"
  local target="$2"
  if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    echo "[ok] $target -> $source"
  else
    echo "[missing] $target (expected symlink to $source)"
    FAILURES+=("doctor link $target")
  fi
}

doctor_check_command() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    echo "[ok] command: $name"
  else
    echo "[missing] command: $name"
    FAILURES+=("doctor command $name")
  fi
}

doctor_check_nvim() {
  local version
  if ! command -v nvim >/dev/null 2>&1; then
    echo "[missing] command: nvim"
    FAILURES+=("doctor command nvim")
    return 1
  fi

  version="$(get_nvim_version 2>/dev/null || true)"
  if [ -n "$version" ] && version_gte "$version" "$NEOVIM_MIN_VERSION"; then
    echo "[ok] command: nvim ($version)"
  else
    echo "[missing] command: nvim >= $NEOVIM_MIN_VERSION (found ${version:-unknown})"
    FAILURES+=("doctor command nvim version")
    return 1
  fi
}

run_doctor() {
  echo "Running doctor checks..."
  doctor_check_link "$REPO_ROOT/home/.zshrc" "$HOME_DIR/.zshrc"
  doctor_check_link "$REPO_ROOT/home/.config/zsh" "$CONFIG_HOME/zsh"
  doctor_check_link "$REPO_ROOT/home/.config/wezterm" "$CONFIG_HOME/wezterm"
  doctor_check_link "$REPO_ROOT/home/.config/nvim" "$CONFIG_HOME/nvim"
  doctor_check_link "$REPO_ROOT/home/.config/ooodnakov" "$CONFIG_HOME/ooodnakov"
  doctor_check_link "$REPO_ROOT/home/.config/ohmyposh/ooodnakov.omp.json" "$CONFIG_HOME/ohmyposh/ooodnakov.omp.json"
  doctor_check_link "$REPO_ROOT/home/.config/powershell/Microsoft.PowerShell_profile.ps1" "$CONFIG_HOME/powershell/Microsoft.PowerShell_profile.ps1"
  doctor_check_command git
  doctor_check_command zsh
  doctor_check_command wezterm
  doctor_check_nvim
  doctor_check_command oooconf
  doctor_check_command o
  if [ -d "$FONT_TARGET_DIR" ]; then
    echo "[ok] fonts dir: $FONT_TARGET_DIR"
  else
    echo "[missing] fonts dir: $FONT_TARGET_DIR"
    FAILURES+=("doctor fonts")
  fi

  if [ "${#FAILURES[@]}" -gt 0 ]; then
    echo "Doctor found ${#FAILURES[@]} issue(s)."
    return 1
  fi
  echo "Doctor checks passed."
}

maybe_install_cargo() {
  if check_dependency_status "cargo" "cargo"; then
    return 0
  fi

  if ! prompt_yes_no "Install Rust and cargo via rustup (official installer)?"; then
    is_verbose && echo "skipping cargo" >&2
    DEPENDENCY_SUMMARY+=("cargo: skipped")
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    run_with_spinner "Installing Rust via rustup" sh -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
  elif command -v wget >/dev/null 2>&1; then
    run_with_spinner "Installing Rust via rustup" sh -c 'wget -qO- https://sh.rustup.rs | sh -s -- -y'
  else
    DEPENDENCY_SUMMARY+=("cargo: missing (requires curl or wget)")
    return 0
  fi

  if command -v cargo >/dev/null 2>&1 || [ -x "$HOME_DIR/.cargo/bin/cargo" ]; then
    DEPENDENCY_SUMMARY+=("cargo: installed")
  else
    DEPENDENCY_SUMMARY+=("cargo: install attempted")
  fi
}

install_optional_dependencies() {
  local manager
  local key label description
  manager="$(detect_package_manager)"
  PACKAGE_MANAGER="$manager"

  if [ "$manager" != "none" ] && [ "$manager" != "brew" ] && is_interactive; then
    is_verbose && printf "Refreshing sudo credentials before dependency installation...\n" > /dev/tty
    sudo -v || return 1
  fi

  is_verbose && echo "Dependency check:"

  while IFS='|' read -r key label description; do
    [ -n "$key" ] || continue
    install_optional_dependency_if_selected "$key" install_optional_dependency_from_catalog "$key" "$manager"
  done < <(optional_dependency_catalog)
}

shift || true
cli_selected_optional_keys=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes-optional) INSTALL_OPTIONAL=always ;;
    -h|--help) usage; exit 0 ;;
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
        usage >&2
        exit 1
      fi
      if ! optional_dependency_applicable "$1" 2>/dev/null; then
        _deps_platform="$(detect_platform)"
        echo "Note: $1 is not applicable on $_deps_platform; skipping." >&2
      fi
      cli_selected_optional_keys+=("$1")
      ;;
  esac
  shift
done

if [ "${#cli_selected_optional_keys[@]}" -gt 0 ]; then
  selected_optional_key_csv="$(IFS=,; printf '%s' "${cli_selected_optional_keys[*]}")"
fi

case "$COMMAND" in
  install) ;;
  update) ;;
  doctor) run_doctor; exit $? ;;
  deps)
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
                *) echo "No optional dependencies selected." >&2; exit 1 ;;
              esac
            fi
            ;;
          *) echo "No optional dependencies selected." >&2; exit 1 ;;
        esac
      fi
    elif [ -z "$selected_optional_key_csv" ] && ! is_interactive; then
      echo "oooconf deps needs explicit dependency keys in non-interactive mode." >&2
      exit 1
    fi
    INSTALL_OPTIONAL=always
    ;;
  completions) ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    suggestion="$(suggest_setup_command "$COMMAND")"
    if [ -n "$suggestion" ]; then
      echo "Did you mean: $suggestion" >&2
    fi
    usage >&2
    exit 1
    ;;
esac

initialize_logging
if [ "$COMMAND" = "completions" ]; then
  progress_init 3 "oooconf completions"
  progress_step "Preparing completion output path"
  run_cmd mkdir -p "$REPO_ROOT/home/.config/ooodnakov/zsh/completions/autogen"
  progress_step "Generating tracked autogen completions"
  generate_autogen_completions || true
  progress_step "Generating oooconf command completions"
  generate_oooconf_completions || true
  echo
  echo "Completion generation complete."
  if [ -n "$LOG_FILE" ]; then
    echo "Log file: $LOG_FILE"
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
  echo "Optional dependency install complete."
  if [ -n "$LOG_FILE" ]; then
    echo "Log file: $LOG_FILE"
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
sync_repo "$OH_MY_ZSH_REPO" "$OH_MY_ZSH_REF" "$STATE_HOME/oh-my-zsh" || TOOL_SUMMARY+=("oh-my-zsh: failed")
sync_repo "$P10K_REPO" "$P10K_REF" "$STATE_HOME/powerlevel10k" || TOOL_SUMMARY+=("powerlevel10k: failed")
sync_repo "$ZSH_AUTOSUGGESTIONS_REPO" "$ZSH_AUTOSUGGESTIONS_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-autosuggestions" || TOOL_SUMMARY+=("zsh-autosuggestions: failed")
sync_repo "$ZSH_HIGHLIGHTING_REPO" "$ZSH_HIGHLIGHTING_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-syntax-highlighting" || TOOL_SUMMARY+=("zsh-syntax-highlighting: failed")
sync_repo "$ZSH_HISTORY_REPO" "$ZSH_HISTORY_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-history-substring-search" || TOOL_SUMMARY+=("zsh-history-substring-search: failed")
sync_repo "$ZSH_AUTOCOMPLETE_REPO" "$ZSH_AUTOCOMPLETE_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-autocomplete" || TOOL_SUMMARY+=("zsh-autocomplete: failed")
sync_repo "$FZF_TAB_REPO" "$FZF_TAB_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/fzf-tab" || TOOL_SUMMARY+=("fzf-tab: failed")
sync_repo "$FORGIT_REPO" "$FORGIT_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/forgit" || TOOL_SUMMARY+=("forgit: failed")
sync_repo "$YOU_SHOULD_USE_REPO" "$YOU_SHOULD_USE_REF" "$STATE_HOME/oh-my-zsh/custom/plugins/you-should-use" || TOOL_SUMMARY+=("you-should-use: failed")
install_auto_uv_env
ensure_oh_my_zsh_permissions || true

progress_step "Installing managed tool checkouts"
install_managed_tools

progress_step "Linking managed config files"
managed_link_pairs=(
  "home/.zshrc|$HOME_DIR/.zshrc"
  "home/.config/zsh|$CONFIG_HOME/zsh"
  "home/.config/wezterm|$CONFIG_HOME/wezterm"
  "home/.config/ooodnakov|$CONFIG_HOME/ooodnakov"
)

for link_pair in "${managed_link_pairs[@]}"; do
  IFS='|' read -r source_rel target_path <<< "$link_pair"
  link_file "$REPO_ROOT/$source_rel" "$target_path" || true
done

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

run_cmd mkdir -p "$HOME_DIR/.local/bin"
link_file "$REPO_ROOT/home/.config/ooodnakov/bin/oooconf" "$HOME_DIR/.local/bin/oooconf" || true
link_file "$REPO_ROOT/home/.config/ooodnakov/bin/o" "$HOME_DIR/.local/bin/o" || true

progress_step "Generating completions and platform integrations"
generate_autogen_completions || true
generate_oooconf_completions || true

run_cmd mkdir -p "$CONFIG_HOME/ohmyposh" "$CONFIG_HOME/powershell"
link_file "$REPO_ROOT/home/.config/ohmyposh/ooodnakov.omp.json" "$CONFIG_HOME/ohmyposh/ooodnakov.omp.json" || true
link_file "$REPO_ROOT/home/.config/powershell/Microsoft.PowerShell_profile.ps1" "$CONFIG_HOME/powershell/Microsoft.PowerShell_profile.ps1" || true

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
echo "Bootstrap complete."
echo "If needed, create local overrides in $CONFIG_HOME/ooodnakov/local."
if [ -n "$LOG_FILE" ]; then
  echo "Log file: $LOG_FILE"
fi
