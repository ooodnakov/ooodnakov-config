#!/usr/bin/env bash
# Sourced by scripts/setup/setup.sh; do not execute directly.

completion_autogen_target_dir() {
  printf '%s\n' "$REPO_ROOT/home/.config/ooodnakov/zsh/completions/autogen"
}

prepare_completion_output_path() {
  local target_dir
  target_dir="$(completion_autogen_target_dir)"
  if [ "$DRY_RUN" -eq 1 ]; then
    ui_line hint "[dry-run] ensure directory $target_dir"
    return 0
  fi

  mkdir -p "$target_dir"
}

generate_autogen_completions() {
  if [ ! -f "$AUTOGEN_COMPLETIONS_GENERATOR" ]; then
    TOOL_SUMMARY+=("autogen completions: generator missing ($AUTOGEN_COMPLETIONS_GENERATOR)")
    return 1
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    run_python "$AUTOGEN_COMPLETIONS_GENERATOR" --dry-run
    return $?
  fi

  run_with_spinner "Generating autogen tool completions" \
    run_python "$AUTOGEN_COMPLETIONS_GENERATOR"
}

generate_oooconf_completions() {
  if [ "$DRY_RUN" -eq 1 ]; then
    ui_line hint "[dry-run] Generating oooconf command completions"
    return 0
  fi

  if [ ! -f "$OOOCONF_COMPLETIONS_GENERATOR" ]; then
    TOOL_SUMMARY+=("oooconf completions: generator missing ($OOOCONF_COMPLETIONS_GENERATOR)")
    return 1
  fi

  run_with_spinner "Generating oooconf command completions" \
    run_python "$OOOCONF_COMPLETIONS_GENERATOR"
}

generate_powershell_completions() {
  local generator="$REPO_ROOT/scripts/generate/generate_powershell_completions.ps1"

  # The cache is consumed only by the managed PowerShell profile on Windows;
  # generating it anywhere else (Linux/macOS pwsh, WSL) is dead work.
  if [ "$(detect_platform)" != "windows" ]; then
    TOOL_SUMMARY+=("PowerShell completions: skipped (Windows only)")
    return 0
  fi

  if ! command -v pwsh >/dev/null 2>&1; then
    TOOL_SUMMARY+=("PowerShell completions: pwsh not found")
    return 0
  fi

  if [ ! -f "$generator" ]; then
    TOOL_SUMMARY+=("PowerShell completions: generator missing ($generator)")
    return 1
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    ui_line hint "[dry-run] Generating PowerShell completion cache"
    return 0
  fi

  run_with_spinner "Generating PowerShell completion cache" \
    pwsh -NoLogo -NoProfile -File "$generator"
}

generate_tracked_completions() {
  prepare_completion_output_path
  generate_autogen_completions
  generate_oooconf_completions
  generate_powershell_completions
}
