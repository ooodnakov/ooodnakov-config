#!/usr/bin/env bash
# Sourced by scripts/setup/setup.sh; do not execute directly.

completion_autogen_target_dir() {
  printf '%s\n' "$REPO_ROOT/home/.config/ooodnakov/zsh/completions/autogen"
}

prepare_completion_output_path() {
  local target_dir
  target_dir="$(completion_autogen_target_dir)"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] ensure directory $target_dir"
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

generate_tracked_completions() {
  prepare_completion_output_path
  generate_autogen_completions
  generate_oooconf_completions
}
