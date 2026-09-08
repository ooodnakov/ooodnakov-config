#!/usr/bin/env bash
# Sourced by scripts/setup/setup.sh; do not execute directly.

doctor_check_link() {
  local source
  source="$1"
  local target
  target="$2"
  if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    ui_line ok "$target -> $source"
  else
    ui_line missing "$target (expected symlink to $source)"
    FAILURES+=("doctor link $target")
  fi
}

doctor_check_command() {
  local name
  name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    ui_line ok "command: $name"
  else
    ui_line missing "command: $name"
    FAILURES+=("doctor command $name")
  fi
}

doctor_check_nvim() {
  local version
  if ! command -v nvim >/dev/null 2>&1; then
    ui_line missing "command: nvim"
    FAILURES+=("doctor command nvim")
    return 1
  fi

  version="$(get_nvim_version 2>/dev/null || true)"
  if [ -n "$version" ] && version_gte "$version" "$NEOVIM_MIN_VERSION"; then
    ui_line ok "command: nvim ($version)"
  else
    ui_line missing "command: nvim >= $NEOVIM_MIN_VERSION (found ${version:-unknown})"
    FAILURES+=("doctor command nvim version")
    return 1
  fi
}

doctor_check_managed_repo() {
  local name
  name="$1"
  local target
  target="$2"
  local required_file
  required_file="$3"
  local expected_ref
  expected_ref="$(get_managed_tool "$name" ref)"
  local actual_ref

  if [ ! -d "$target/.git" ]; then
    ui_line missing "managed repo: $name ($target)"
    ui_line hint "          repair: oooconf install"
    FAILURES+=("doctor managed repo $name")
    return 1
  fi

  if [ ! -f "$target/$required_file" ]; then
    ui_line missing "managed repo file: $name/$required_file"
    ui_line hint "          repair: oooconf install"
    FAILURES+=("doctor managed repo file $name")
    return 1
  fi

  actual_ref="$(git -C "$target" rev-parse HEAD 2>/dev/null || true)"
  if [ -n "$expected_ref" ] && [ "$actual_ref" != "$expected_ref" ]; then
    ui_line missing "managed repo ref: $name (expected $expected_ref, found ${actual_ref:-unknown})"
    ui_line hint "          repair: oooconf install"
    FAILURES+=("doctor managed repo ref $name")
    return 1
  fi

  ui_line ok "managed repo: $name (${actual_ref:-unknown})"
}

run_doctor() {
  ui_section "Doctor checks"
  if ! python3 "$REPO_ROOT/scripts/cli/transaction_apply.py" --repo-root "$REPO_ROOT" status --check-incomplete; then
    ui_line missing "incomplete managed-link transaction"
    ui_line hint "          repair: oooconf rollback --last"
    FAILURES+=("doctor incomplete transaction")
  fi
  local managed_links
  if managed_links="$(python3 "$REPO_ROOT/scripts/cli/operation_plan.py" --repo-root "$REPO_ROOT" --scope links --emit-managed-links)"; then
    while IFS='|' read -r _key source target; do
      [ -n "$target" ] || continue
      doctor_check_link "$source" "$target"
    done <<<"$managed_links"
  else
    ui_line missing "unable to resolve managed profile links"
    FAILURES+=("doctor profile links")
  fi
  doctor_check_command git
  doctor_check_command zsh
  doctor_check_command wezterm
  doctor_check_command yazi
  doctor_check_nvim
  doctor_check_command oooconf
  doctor_check_command o
  doctor_check_managed_repo "oh-my-zsh" "$STATE_HOME/oh-my-zsh" "oh-my-zsh.sh"
  doctor_check_managed_repo "powerlevel10k" "$STATE_HOME/powerlevel10k" "powerlevel10k.zsh-theme"
  doctor_check_managed_repo "k" "$STATE_HOME/oh-my-zsh/custom/plugins/k" "k.sh"
  doctor_check_managed_repo "zsh-autosuggestions" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-autosuggestions" "zsh-autosuggestions.zsh"
  doctor_check_managed_repo "zsh-syntax-highlighting" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-syntax-highlighting" "zsh-syntax-highlighting.zsh"
  doctor_check_managed_repo "zsh-history-substring-search" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-history-substring-search" "zsh-history-substring-search.zsh"
  doctor_check_managed_repo "zsh-autocomplete" "$STATE_HOME/oh-my-zsh/custom/plugins/zsh-autocomplete" "zsh-autocomplete.plugin.zsh"
  doctor_check_managed_repo "fzf-tab" "$STATE_HOME/oh-my-zsh/custom/plugins/fzf-tab" "fzf-tab.plugin.zsh"
  doctor_check_managed_repo "forgit" "$STATE_HOME/oh-my-zsh/custom/plugins/forgit" "forgit.plugin.zsh"
  doctor_check_managed_repo "you-should-use" "$STATE_HOME/oh-my-zsh/custom/plugins/you-should-use" "you-should-use.plugin.zsh"
  if [ -d "$FONT_TARGET_DIR" ]; then
    ui_line ok "fonts dir: $FONT_TARGET_DIR"
  else
    ui_line missing "fonts dir: $FONT_TARGET_DIR"
    FAILURES+=("doctor fonts")
  fi

  if [ "${#FAILURES[@]}" -gt 0 ]; then
    ui_line warn "Doctor found ${#FAILURES[@]} issue(s)."
    ui_line hint "Run 'oooconf install' to retry missing managed checkouts and repair links."
    return 1
  fi
  ui_line ok "Doctor checks passed."
}
