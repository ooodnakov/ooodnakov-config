#!/usr/bin/env bash
# Sourced by scripts/setup/ooodnakov.sh; do not execute directly.

# Git delta configuration block — injected into ~/.gitconfig
DELTA_GITCONFIG_BLOCK='
[core]
    pager = delta

[interactive]
    diffFilter = delta --color-only

[delta]
    navigate = true
    dark = true

[merge]
    conflictStyle = zdiff3
'

# Section names that must not be duplicated in ~/.gitconfig
DELTA_SECTIONS="core interactive delta merge"

# Marker lines used to detect and protect our block
DELTA_SECTION_START="# --- ooodnakov delta start ---"
DELTA_SECTION_END="# --- ooodnakov delta end ---"

handle_delta_command() {
  local action="${1:-}"

  if [ -z "$action" ] || [ "$action" = "help" ]; then
    print_delta_help
    return 0
  fi

  case "$action" in
    inject)
      shift
      delta_inject "$@"
      ;;
    status)
      delta_status
      ;;
    remove)
      delta_remove
      ;;
    *)
      suggestion="$(suggest_from_list "$action" "inject status remove")"
      report_unknown_command "Unknown delta action: $action" "$suggestion" delta
      return 1
      ;;
  esac
}

print_delta_help() {
  cat <<'EOF' | ui_render_help_block
Usage: oooconf delta <inject|status|remove>

Configure git-delta as the git pager and diff viewer.

Subcommands:
  inject          write delta git config to ~/.gitconfig (idempotent, warns if present)
  status          check whether delta is configured in ~/.gitconfig
  remove          remove ooodnakov's delta config block from ~/.gitconfig

Examples:
  oooconf delta inject
  oooconf delta status
  oooconf delta remove
EOF
}

# Check whether delta is already installed on this machine.
check_delta_installed() {
  command -v delta >/dev/null 2>&1
}

# Check whether git is available.
check_git_installed() {
  command -v git >/dev/null 2>&1
}

# Check whether our block is already present in ~/.gitconfig.
delta_block_present() {
  local gitconfig="$1"
  [ -f "$gitconfig" ] && grep -Fq "$DELTA_SECTION_START" "$gitconfig"
}

# Check whether a section (e.g. "delta") is already defined in gitconfig
# outside our managed block. Returns 0 if found, 1 otherwise.
delta_section_exists_outside_block() {
  local gitconfig="$1"
  local section="$2"
  local in_block=0

  while IFS= read -r line; do
    # Enter/exit managed block
    if [ "$line" = "$DELTA_SECTION_START" ]; then
      in_block=1
    elif [ "$line" = "$DELTA_SECTION_END" ]; then
      in_block=0
    elif [ "$in_block" -eq 0 ]; then
      # Trim whitespace for comparison
      local trimmed
      trimmed="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      if [ "$trimmed" = "[$section]" ]; then
        return 0
      fi
    fi
  done < "$gitconfig"

  return 1
}

# Remove our managed block from ~/.gitconfig.
delta_remove_from_gitconfig() {
  local gitconfig="$1"
  local tmp_file
  tmp_file="$(mktemp)"
  local in_block=0

  while IFS= read -r line; do
    if [ "$line" = "$DELTA_SECTION_START" ]; then
      in_block=1
      continue
    elif [ "$line" = "$DELTA_SECTION_END" ]; then
      in_block=0
      continue
    fi
    [ "$in_block" -eq 0 ] && printf '%s\n' "$line"
  done < "$gitconfig" > "$tmp_file"

  mv "$tmp_file" "$gitconfig"
}

delta_inject() {
  local dry_run="${OOODNAKOV_DELTA_DRY_RUN:-0}"

  if ! check_git_installed; then
    ui_line error "git is not installed — cannot update ~/.gitconfig"
    return 1
  fi

  local gitconfig
  gitconfig="${GIT_CONFIG_GLOBAL:-"$HOME/.gitconfig"}"

  if ! delta_block_present "$gitconfig"; then
    if [ "$dry_run" -eq 1 ]; then
      ui_line info "[dry-run] would write delta config to $gitconfig"
      return 0
    fi

    # Warn if any of our sections already exist outside our block
    local warned=0
    for section in $DELTA_SECTIONS; do
      if delta_section_exists_outside_block "$gitconfig" "$section"; then
        ui_line warn "warning: [$section] already defined in $gitconfig — will not be modified"
        warned=1
      fi
    done

    if [ "$warned" -eq 1 ]; then
      ui_line warn "warning: existing [$section] sections were not modified"
      ui_line info "run 'oooconf delta remove' first if you want a clean slate"
    fi

    # Append our block
    {
      printf '\n%s\n' "$DELTA_SECTION_START"
      printf '%s\n' "$DELTA_GITCONFIG_BLOCK"
      printf '%s\n' "$DELTA_SECTION_END"
    } >> "$gitconfig"

    ui_line success "delta config injected into $gitconfig"

    if check_delta_installed; then
      ui_line success "delta is installed — config is active"
    else
      ui_line warn "delta is not installed — run 'oooconf deps delta' to install it"
    fi
  else
    ui_line info "delta config already present in $gitconfig (use 'oooconf delta remove' first to replace)"
    return 0
  fi
}

delta_status() {
  local gitconfig="${GIT_CONFIG_GLOBAL:-"$HOME/.gitconfig"}"

  if delta_block_present "$gitconfig"; then
    ui_line success "delta config: managed block found in $gitconfig"
  else
    ui_line info "delta config: no managed block in $gitconfig"
  fi

  if check_delta_installed; then
    local ver
    ver="$(delta --version 2>/dev/null | awk '{print $NF}')"
    ui_line success "delta: installed ($ver)"
  else
    ui_line warn "delta: not installed (run 'oooconf deps delta' to install)"
  fi

  # Show effective pager setting
  if command -v git >/dev/null 2>&1; then
    local pager
    pager="$(git config --global core.pager 2>/dev/null || true)"
    if [ -n "$pager" ]; then
      if echo "$pager" | grep -q "delta"; then
        ui_line success "core.pager: $pager"
      else
        ui_line info "core.pager: $pager (not delta)"
      fi
    else
      ui_line info "core.pager: not set"
    fi
  fi
}

delta_remove() {
  local dry_run="${OOODNAKOV_DELTA_DRY_RUN:-0}"

  if ! check_git_installed; then
    ui_line error "git is not installed"
    return 1
  fi

  local gitconfig="${GIT_CONFIG_GLOBAL:-"$HOME/.gitconfig"}"

  if ! delta_block_present "$gitconfig"; then
    ui_line info "no managed delta config found in $gitconfig"
    return 0
  fi

  if [ "$dry_run" -eq 1 ]; then
    ui_line info "[dry-run] would remove delta config block from $gitconfig"
    return 0
  fi

  delta_remove_from_gitconfig "$gitconfig"
  ui_line success "delta config removed from $gitconfig"
}
