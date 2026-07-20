#!/usr/bin/env bash
# Sourced by scripts/setup/setup.sh; do not execute directly.

detect_platform() {
  case "$(uname -s)" in
  Linux*) echo "linux" ;;
  Darwin*) echo "macos" ;;
  CYGWIN* | MINGW* | MSYS* | Windows*) echo "windows" ;;
  *) echo "unknown" ;;
  esac
}

load_optional_deps_platform_catalog_cache() {
  if [ -z "$OPTIONAL_DEPS_PLATFORM_CATALOG_CACHE" ]; then
    OPTIONAL_DEPS_PLATFORM_CATALOG_CACHE="$(run_python "$OPTIONAL_DEPS_SCRIPT" catalog-platform "$(detect_platform)")"
  fi
}

load_optional_deps_check_command_cache() {
  if [ -z "$OPTIONAL_DEPS_CHECK_COMMAND_CACHE" ]; then
    OPTIONAL_DEPS_CHECK_COMMAND_CACHE="$(run_python "$OPTIONAL_DEPS_SCRIPT" check-commands)"
  fi
}

load_optional_deps_handler_cache() {
  if [ -z "$OPTIONAL_DEPS_HANDLER_CACHE" ]; then
    OPTIONAL_DEPS_HANDLER_CACHE="$(run_python "$OPTIONAL_DEPS_SCRIPT" handlers)"
  fi
}

load_optional_deps_install_info_cache() {
  if [ -z "$OPTIONAL_DEPS_INSTALL_INFO_CACHE" ]; then
    OPTIONAL_DEPS_INSTALL_INFO_CACHE="$(run_python "$OPTIONAL_DEPS_SCRIPT" install-info-lines "$(detect_platform)")"
  fi
}

lookup_pipe_cache_value() {
  local cache key
  cache="$1"
  key="$2"
  printf '%s\n' "$cache" |
    awk -F'|' -v expected="$key" '$1 == expected { print substr($0, index($0, FS) + 1); exit }'
}

optional_dependency_check_command() {
  local key value
  key="$1"
  load_optional_deps_check_command_cache
  value="$(lookup_pipe_cache_value "$OPTIONAL_DEPS_CHECK_COMMAND_CACHE" "$key")"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf 'command -v %s\n' "$key"
  fi
}

optional_dependency_handler() {
  local key
  key="$1"
  load_optional_deps_handler_cache
  lookup_pipe_cache_value "$OPTIONAL_DEPS_HANDLER_CACHE" "$key"
}

optional_dependency_install_info_line() {
  local key us
  key="$1"
  us="$(printf '\037')"
  load_optional_deps_install_info_cache
  printf '%s\n' "$OPTIONAL_DEPS_INSTALL_INFO_CACHE" |
    awk -F"$us" -v expected="$key" '$1 == expected { print; exit }'
}

optional_dependency_applicable() {
  local key
  key="$1"
  local platform
  platform="$(detect_platform)"
  local info
  info="$(run_python "$OPTIONAL_DEPS_SCRIPT" install-info "$key" "$platform" 2>/dev/null)" || return 1
  local manager
  manager="$(echo "$info" | cut -d'|' -f1)"
  [ -n "$manager" ] && [ "$manager" != "none" ]
}

optional_dependency_catalog() {
  load_optional_deps_platform_catalog_cache
  printf '%s\n' "$OPTIONAL_DEPS_PLATFORM_CATALOG_CACHE"
}

optional_dependency_catalog_all() {
  run_python "$OPTIONAL_DEPS_SCRIPT" catalog
}

optional_dependency_exists() {
  local expected_key
  expected_key="$1"
  local key label description

  while IFS='|' read -r key label description; do
    [ "$key" = "$expected_key" ] && return 0
  done < <(optional_dependency_catalog)

  return 1
}

optional_dependency_exists_any() {
  # Check if key exists in full catalog (including platform-inapplicable deps).
  local expected_key
  expected_key="$1"
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
  local left
  left="$1"
  local right
  right="$2"

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
  local input
  input="$1"
  shift

  local best_candidate

  best_candidate=""
  local best_distance
  best_distance=999
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
  local input
  input="$1"
  local keys
  keys=()
  local key

  while IFS= read -r key; do
    [ -n "$key" ] && keys+=("$key")
  done < <(optional_dependency_keys_all)

  suggest_from_candidates "$input" "${keys[@]}"
}

optional_dependency_label() {
  local expected_key
  expected_key="$1"
  local key label description

  while IFS='|' read -r key label description; do
    if [ "$key" = "$expected_key" ]; then
      printf '%s - %s\n' "$label" "$description"
      return 0
    fi
  done < <(optional_dependency_catalog)

  return 1
}

optional_dependency_install_info() {
  local key
  key="$1"
  local platform
  platform="$(detect_platform)"
  run_python "$OPTIONAL_DEPS_SCRIPT" install-info "$key" "$platform" 2>/dev/null
}

optional_dependency_field() {
  local key
  key="$1"
  local field
  field="$2"

  case "$field" in
  handler) optional_dependency_handler "$key" ;;
  *) run_python "$OPTIONAL_DEPS_SCRIPT" field "$key" "$field" 2>/dev/null || true ;;
  esac
}

resolve_package_manager_for_dependency() {
  local detected_manager
  detected_manager="$1"
  local declared_manager
  declared_manager="$2"

  case "$declared_manager" in
  apt)
    case "$detected_manager" in
    apt | dnf | pacman | zypper) printf '%s\n' "$detected_manager" ;;
    *) printf '%s\n' "$declared_manager" ;;
    esac
    ;;
  *)
    printf '%s\n' "$declared_manager"
    ;;
  esac
}

optional_dependency_selected() {
  local key
  key="$1"

  if [ -z "$selected_optional_key_csv" ]; then
    return 0
  fi

  case ",$selected_optional_key_csv," in
  *,"$key",*) return 0 ;;
  *) return 1 ;;
  esac
}

optional_dependency_present() {
  # Now uses central check_dependency_status (which reads check= from optional-deps.toml)
  # No more hard-coded list or overrides — sole source of truth is the TOML.
  check_dependency_status "$1" "$1" >/dev/null 2>&1
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

  ui_line hint "gum is required for the multi-select dependency picker"
  if ! prompt_yes_no "Install gum now and continue with the picker?"; then
    return 1
  fi

  local previous_mode

  previous_mode="$INSTALL_OPTIONAL"
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
    ui_line info "All optional dependencies are already present."
    return 2
  fi

  ui_line info "Available optional dependencies:"
  local i
  for ((i = 0; i < ${#all_keys[@]}; i++)); do
    printf "  %-10s %s\n" "${all_keys[$i]}" "${all_labels[$i]}" >&2
  done
  echo >&2
  printf "Enter space/comma-separated keys to install (or empty to skip): " >&2
  if ! read -r selection </dev/tty; then
    # User cancelled (Ctrl+C) — treat as "user declined"
    return 3
  fi

  selection="$(echo "$selection" | tr ',' ' ')"
  local -a wanted_keys=()
  read -ra wanted_keys <<<"$selection"

  if [ "${#wanted_keys[@]}" -eq 0 ]; then
    # User entered nothing — treat as "user declined"
    return 3
  fi

  # Validate keys
  local wanted
  for wanted in "${wanted_keys[@]}"; do
    if ! optional_dependency_exists "$wanted"; then
      ui_line fail "Unknown dependency key: $wanted"
      return 1
    fi
  done

  selected_keys_csv="$(
    IFS=,
    printf '%s' "${wanted_keys[*]}"
  )"
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
    ui_line info "All optional dependencies are already present."
    return 2
  fi

  # Build gum args as positional arguments (not piped stdin) so gum can use /dev/tty for interaction.
  local -a gum_args=()
  gum_args+=(--no-limit --height 20 --header "Select optional dependencies. Use arrows to move, x to toggle, enter to continue.")

  # Make the picker searchable: pre-filter the full list with gum filter (live fuzzy
  # search), then hand the matches to gum choose for toggle/checkbox-style multi-select.
  local filtered_selection
  filtered_selection="$(printf '%s\n' "${options[@]}" | gum filter --no-limit --placeholder "Type to filter dependencies (tab toggles match, enter confirms)..." </dev/tty 2>/dev/tty)" || {
    stty sane </dev/tty 2>/dev/null || true
    return 3
  }
  stty sane </dev/tty 2>/dev/null || true

  if [ -z "$filtered_selection" ]; then
    return 3
  fi

  local -a filtered_options=()
  while IFS= read -r opt; do
    [ -n "$opt" ] && filtered_options+=("$opt")
  done <<<"$filtered_selection"

  local opt
  for opt in "${filtered_options[@]}"; do
    gum_args+=("$opt")
  done

  selection="$(gum choose "${gum_args[@]}" </dev/tty 2>/dev/null)" || {
    # Reset terminal state after gum exits (prevents hang on subsequent invocations)
    stty sane </dev/tty 2>/dev/null || true
    # gum returned non-zero: 1 = user cancelled (Esc), 130 = interrupted
    # Treat as "user declined" with no selections.
    return 3
  }
  # Reset terminal state after gum exits
  stty sane </dev/tty 2>/dev/null || true

  if [ -n "$selection" ]; then
    while IFS=$'\t' read -r selected_key _; do
      [ -n "$selected_key" ] && selected_keys+=("$selected_key")
    done <<<"$selection"
  fi

  if [ "${#selected_keys[@]}" -eq 0 ]; then
    # User submitted the picker but selected nothing — treat as "user declined"
    return 3
  fi

  local IFS

  IFS=,
  printf '%s\n' "${selected_keys[*]}"
}

install_optional_dependency_if_selected() {
  local key
  key="$1"
  shift

  optional_dependency_selected "$key" || return 0
  "$@"
}

install_optional_dependency_from_catalog() {
  local key
  key="$1"
  local detected_manager
  detected_manager="$2"
  local description info declared_manager package_name command_name winget_id choco_id install_manager handler

  info="$(optional_dependency_install_info_line "$key")"
  if [ -n "$info" ]; then
    local us
    us="$(printf '\037')"
    IFS="$us" read -r _ description declared_manager package_name command_name winget_id choco_id _ platform_url asset_name handler <<<"$info"
  else
    description="$(optional_dependency_label "$key")"
    info="$(optional_dependency_install_info "$key" || true)"
    handler="$(optional_dependency_field "$key" "handler")"
    IFS='|' read -r declared_manager package_name command_name winget_id choco_id _ platform_url asset_name <<<"$info"
  fi
  install_manager="$(resolve_package_manager_for_dependency "$detected_manager" "$declared_manager")"

  if [ -n "$handler" ]; then
    local handler_func
    handler_func="maybe_install_${handler//-/_}"
    if declare -f "$handler_func" >/dev/null 2>&1; then
      "$handler_func" "$install_manager"
      return 0
    fi
  fi

  if [ -z "$command_name" ]; then
    command_name="$key"
  fi

  case "$install_manager" in
  custom | curl)
    maybe_note_dependency "$command_name" "$description (manual installer: $install_manager)"
    ;;
  winget)
    maybe_note_dependency "$command_name" "$description (Windows winget package: ${winget_id:-$package_name})"
    ;;
  choco)
    maybe_note_dependency "$command_name" "$description (Windows choco package: ${choco_id:-$package_name})"
    ;;
  pnpm)
    if optional_dependency_selected "$key"; then
      local pnpm_cmd
      if ! ensure_pnpm_available; then
        DEPENDENCY_SUMMARY+=("$command_name: missing (pnpm unavailable; install pnpm first)")
        return 0
      fi
      pnpm_cmd="$(resolve_pnpm_command 2>/dev/null || true)"
      if [ -z "$pnpm_cmd" ]; then
        DEPENDENCY_SUMMARY+=("$command_name: missing (pnpm unavailable; install pnpm first)")
        return 0
      fi
      run_with_spinner "Installing $description via pnpm" "$pnpm_cmd" add -g "$package_name"
      if command -v "$command_name" >/dev/null 2>&1; then
        DEPENDENCY_SUMMARY+=("$command_name: installed via pnpm")
      else
        DEPENDENCY_SUMMARY+=("$command_name: install attempted via pnpm")
      fi
    fi
    ;;
  pip)
    local python_cmd
    python_cmd="python3"
    if ! command -v "$python_cmd" >/dev/null 2>&1; then
      DEPENDENCY_SUMMARY+=("$command_name: missing (python3 unavailable for pip)")
      return 0
    fi
    if check_pip_dependency_status "$command_name" "$python_cmd"; then
      return 0
    fi
    if ! python_has_pip "$python_cmd"; then
      DEPENDENCY_SUMMARY+=("$command_name: missing (pip unavailable for $python_cmd)")
      return 0
    fi
    if optional_dependency_selected "$key"; then
      run_with_spinner "Installing $description via pip" "$python_cmd" -m pip install --user --upgrade "$package_name"
      if check_pip_dependency_status "$command_name" "$python_cmd"; then
        DEPENDENCY_SUMMARY+=("$command_name: installed via pip")
      else
        DEPENDENCY_SUMMARY+=("$command_name: install attempted via pip")
      fi
    fi
    ;;
  github-release)
    maybe_install_github_release "$key" "$description" "$package_name" "$command_name" "$platform_url" "$asset_name"
    ;;
  "")
    maybe_note_dependency "$command_name" "$description (no package manager declared)"
    ;;
  *)
    maybe_install_dependency "$install_manager" "$command_name" "$package_name" "$description"
    ;;
  esac
}

install_optional_dependencies() {
  if [ "$SKIP_DEPS" -eq 1 ]; then
    is_verbose && echo "Skipping optional dependency installation (--skip-deps)"
    return 0
  fi
  local manager
  local key label description
  manager="$(detect_package_manager)"
  PACKAGE_MANAGER="$manager"

  if [ "$manager" != "none" ] && [ "$manager" != "brew" ] && is_interactive; then
    is_verbose && printf "Refreshing sudo credentials before dependency installation...\n" >/dev/tty
    sudo -v || return 1
  fi

  is_verbose && echo "Dependency check:"
  load_optional_deps_platform_catalog_cache
  load_optional_deps_check_command_cache
  load_optional_deps_handler_cache
  load_optional_deps_install_info_cache

  while IFS='|' read -r key label description; do
    [ -n "$key" ] || continue
    install_optional_dependency_if_selected "$key" install_optional_dependency_from_catalog "$key" "$manager" || true
  done < <(optional_dependency_catalog)
}
