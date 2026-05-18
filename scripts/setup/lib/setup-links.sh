#!/usr/bin/env bash
# Sourced by scripts/setup/setup.sh; do not execute directly.

link_file() {
  local source
  source="$1"
  local target
  target="$2"
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
  local source
  source="$1"
  local target
  target="$2"
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

backup_incomplete_checkout() {
  local target
  target="$1"

  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    return 0
  fi

  if [ -d "$target/.git" ]; then
    return 0
  fi

  local target_dir target_name backup_dir backup_path backup_index first_child
  target_dir="$(dirname "$target")"
  target_name="$(basename "$target")"

  if [ -d "$target" ]; then
    first_child="$(find "$target" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)"
    if [ -z "$first_child" ]; then
      run_cmd rmdir "$target" || return 1
      return 0
    fi
  fi

  backup_dir="$BACKUP_ROOT$target_dir"
  backup_path="$backup_dir/${target_name}.${TIMESTAMP}"
  backup_index=1
  while [ -e "$backup_path" ] || [ -L "$backup_path" ]; do
    backup_path="$backup_dir/${target_name}.${TIMESTAMP}.$backup_index"
    backup_index=$((backup_index + 1))
  done

  run_cmd mkdir -p "$backup_dir" || return 1
  run_cmd mv "$target" "$backup_path" || return 1
  echo "backed up incomplete checkout $target -> $backup_path"
}

clone_repo_with_fallbacks() {
  local repo_url
  repo_url="$1"
  local target
  target="$2"
  local name
  name="$(basename "$target")"
  local label
  label="Cloning $name"

  backup_incomplete_checkout "$target" || return 1
  OOODNAKOV_RECORD_RETRY_FAILURES=0 run_with_retry "$label" git clone "$repo_url" "$target" && return 0
  [ -d "$target/.git" ] && return 0

  backup_incomplete_checkout "$target" || return 1
  OOODNAKOV_RECORD_RETRY_FAILURES=0 run_with_retry "$label with HTTP/1.1" \
    git -c http.version=HTTP/1.1 clone "$repo_url" "$target" && return 0
  [ -d "$target/.git" ] && return 0

  backup_incomplete_checkout "$target" || return 1
  OOODNAKOV_RECORD_RETRY_FAILURES=0 run_with_retry "$label with blobless fallback" \
    git -c http.version=HTTP/1.1 clone --filter=blob:none "$repo_url" "$target" && return 0

  FAILURES+=("$label")
  return 1
}

fetch_repo_ref_with_fallbacks() {
  local target
  target="$1"
  local ref
  ref="$2"
  local name
  name="$(basename "$target")"
  local label
  label="Updating $name"

  OOODNAKOV_RECORD_RETRY_FAILURES=0 run_with_retry "$label" git -C "$target" fetch origin "$ref" && return 0
  OOODNAKOV_RECORD_RETRY_FAILURES=0 run_with_retry "$label with HTTP/1.1" \
    git -c http.version=HTTP/1.1 -C "$target" fetch origin "$ref" && return 0

  FAILURES+=("$label")
  return 1
}

sync_repo() {
  local repo_url
  repo_url="$1"
  local ref
  ref="$2"
  local target
  target="$3"

  if [ -z "$repo_url" ] || [ -z "$ref" ] || [ -z "$target" ]; then
    record_failure "Resolving managed tool metadata for $(basename "${target:-unknown}")"
    return 1
  fi

  if [ ! -d "$target/.git" ]; then
    clone_repo_with_fallbacks "$repo_url" "$target" || return 1
  fi

  fetch_repo_ref_with_fallbacks "$target" "$ref" || return 1
  run_with_retry "Pinning $(basename "$target")" git -c advice.detachedHead=false -C "$target" checkout "$ref" || return 1
}

normalize_tree_permissions() {
  local target
  target="$1"

  [ -e "$target" ] || return 0

  find "$target" -type d -exec chmod u=rwx,go=rx {} + || return 1
  find "$target" -type f -exec chmod u=rw,go=r {} + || return 1
}

restore_git_executable_bits() {
  local repo_root
  repo_root="$1"
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
  local omz_root
  omz_root="$STATE_HOME/oh-my-zsh"
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
  local ssh_dir
  ssh_dir="$HOME_DIR/.ssh"
  local ssh_config
  ssh_config="$ssh_dir/config"
  local include_line
  include_line="Include ~/.config/ooodnakov/ssh/config"

  run_cmd mkdir -p "$ssh_dir"
  run_cmd touch "$ssh_config"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] ensure SSH include in %s\n' "$ssh_config"
    return 0
  fi

  if ! grep -Fqx "$include_line" "$ssh_config"; then
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '[dry-run] prepend SSH include in %s\n' "$ssh_config"
    elif printf "%s\n\n" "$include_line" | cat - "$ssh_config" >"$ssh_config.tmp" && mv "$ssh_config.tmp" "$ssh_config"; then
      :
    else
      record_failure "Updating SSH include config"
      return 1
    fi
  fi
}

install_fonts() {
  local source_dir
  source_dir="$REPO_ROOT/fonts/meslo"

  if [ -d "$source_dir" ]; then
    run_cmd mkdir -p "$FONT_TARGET_DIR"
    run_cmd cp "$source_dir"/*.ttf "$FONT_TARGET_DIR"/ || record_failure "Copying bundled fonts"
    if command -v fc-cache >/dev/null 2>&1; then
      run_with_spinner "Refreshing font cache" fc-cache -f "$FONT_TARGET_DIR" >/dev/null 2>&1 || true
    fi
  fi
}

install_managed_tools() {
  # All pins now pulled from optional-deps.toml via get_managed_tool (sole source of truth)
  local ohmyzsh_repo
  ohmyzsh_repo=$(get_managed_tool oh-my-zsh repo)
  local ohmyzsh_ref
  ohmyzsh_ref=$(get_managed_tool oh-my-zsh ref)
  local p10k_repo
  p10k_repo=$(get_managed_tool powerlevel10k repo)
  local p10k_ref
  p10k_ref=$(get_managed_tool powerlevel10k ref)
  local nvm_repo
  nvm_repo=$(get_managed_tool nvm repo)
  local nvm_ref
  nvm_ref=$(get_managed_tool nvm ref)
  local k_repo
  k_repo=$(get_managed_tool k repo)
  local k_ref
  k_ref=$(get_managed_tool k ref)
  local marker_repo
  marker_repo=$(get_managed_tool marker repo)
  local marker_ref
  marker_ref=$(get_managed_tool marker ref)
  local todo_repo
  todo_repo=$(get_managed_tool todo-txt repo)
  local todo_ref
  todo_ref=$(get_managed_tool todo-txt ref)
  local autosuggestions_repo
  autosuggestions_repo=$(get_managed_tool zsh-autosuggestions repo)
  local autosuggestions_ref
  autosuggestions_ref=$(get_managed_tool zsh-autosuggestions ref)
  local highlighting_repo
  highlighting_repo=$(get_managed_tool zsh-syntax-highlighting repo)
  local highlighting_ref
  highlighting_ref=$(get_managed_tool zsh-syntax-highlighting ref)
  local history_repo
  history_repo=$(get_managed_tool zsh-history-substring-search repo)
  local history_ref
  history_ref=$(get_managed_tool zsh-history-substring-search ref)
  local autocomplete_repo
  autocomplete_repo=$(get_managed_tool zsh-autocomplete repo)
  local autocomplete_ref
  autocomplete_ref=$(get_managed_tool zsh-autocomplete ref)
  local fzftab_repo
  fzftab_repo=$(get_managed_tool fzf-tab repo)
  local fzftab_ref
  fzftab_ref=$(get_managed_tool fzf-tab ref)
  local forgit_repo
  forgit_repo=$(get_managed_tool forgit repo)
  local forgit_ref
  forgit_ref=$(get_managed_tool forgit ref)
  local youshoulduse_repo
  youshoulduse_repo=$(get_managed_tool you-should-use repo)
  local youshoulduse_ref
  youshoulduse_ref=$(get_managed_tool you-should-use ref)
  local autouv_repo
  autouv_repo=$(get_managed_tool auto-uv-env repo)
  local autouv_ref
  autouv_ref=$(get_managed_tool auto-uv-env ref)

  local bin_dir

  bin_dir="$STATE_HOME/bin"

  sync_repo "$ohmyzsh_repo" "$ohmyzsh_ref" "$STATE_HOME/oh-my-zsh" && TOOL_SUMMARY+=("oh-my-zsh: synced") || TOOL_SUMMARY+=("oh-my-zsh: failed")
  sync_repo "$p10k_repo" "$p10k_ref" "$STATE_HOME/powerlevel10k" && TOOL_SUMMARY+=("powerlevel10k: synced") || TOOL_SUMMARY+=("powerlevel10k: failed")
  sync_repo "$nvm_repo" "$nvm_ref" "$HOME_DIR/.nvm" && TOOL_SUMMARY+=("nvm: synced") || TOOL_SUMMARY+=("nvm: failed")
  sync_repo "$k_repo" "$k_ref" "$STATE_HOME/oh-my-zsh/custom/plugins/k" && TOOL_SUMMARY+=("k: synced") || TOOL_SUMMARY+=("k: failed")
  sync_repo "$marker_repo" "$marker_ref" "$STATE_HOME/marker" && TOOL_SUMMARY+=("marker: synced") || TOOL_SUMMARY+=("marker: failed")
  sync_repo "$todo_repo" "$todo_ref" "$STATE_HOME/todo" && TOOL_SUMMARY+=("todo.txt-cli: synced") || TOOL_SUMMARY+=("todo.txt-cli: failed")
  sync_repo "$autosuggestions_repo" "$autosuggestions_ref" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-autosuggestions" && TOOL_SUMMARY+=("zsh-autosuggestions: synced") || TOOL_SUMMARY+=("zsh-autosuggestions: failed")
  sync_repo "$highlighting_repo" "$highlighting_ref" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-syntax-highlighting" && TOOL_SUMMARY+=("zsh-syntax-highlighting: synced") || TOOL_SUMMARY+=("zsh-syntax-highlighting: failed")
  sync_repo "$history_repo" "$history_ref" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-history-substring-search" && TOOL_SUMMARY+=("zsh-history-substring-search: synced") || TOOL_SUMMARY+=("zsh-history-substring-search: failed")
  sync_repo "$autocomplete_repo" "$autocomplete_ref" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-autocomplete" && TOOL_SUMMARY+=("zsh-autocomplete: synced") || TOOL_SUMMARY+=("zsh-autocomplete: failed")
  sync_repo "$fzftab_repo" "$fzftab_ref" "$STATE_HOME/oh-my-zsh/custom/plugins/fzf-tab" && TOOL_SUMMARY+=("fzf-tab: synced") || TOOL_SUMMARY+=("fzf-tab: failed")
  sync_repo "$forgit_repo" "$forgit_ref" "$STATE_HOME/oh-my-zsh/custom/plugins/forgit" && TOOL_SUMMARY+=("forgit: synced") || TOOL_SUMMARY+=("forgit: failed")
  sync_repo "$youshoulduse_repo" "$youshoulduse_ref" "$STATE_HOME/oh-my-zsh/custom/plugins/you-should-use" && TOOL_SUMMARY+=("you-should-use: synced") || TOOL_SUMMARY+=("you-should-use: failed")

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
  local source_dir
  source_dir="$STATE_HOME/src/auto-uv-env"
  local legacy_dir
  legacy_dir="$STATE_HOME/auto-uv-env"
  local share_dir
  share_dir="$STATE_HOME/auto-uv-env"
  local bin_dir
  bin_dir="$STATE_HOME/bin"

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

  local autouv_repo

  autouv_repo=$(get_managed_tool auto-uv-env repo)
  local autouv_ref
  autouv_ref=$(get_managed_tool auto-uv-env ref)
  sync_repo "$autouv_repo" "$autouv_ref" "$source_dir" || {
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

update_repo() {
  run_with_spinner "Pulling latest repository changes" git -C "$REPO_ROOT" pull --ff-only
}
