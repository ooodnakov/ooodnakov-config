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
  local target_dir
  target_dir="$(completion_autogen_target_dir)"
  local spec binary description output_file completion_cmd
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] Generating autogen completions in $target_dir"
    return 0
  fi

  prepare_completion_output_path

  if [ ! -f "$AUTOGEN_COMPLETIONS_MANIFEST" ]; then
    TOOL_SUMMARY+=("autogen completions: manifest missing ($AUTOGEN_COMPLETIONS_MANIFEST)")
    return 1
  fi

  while IFS= read -r spec; do
    case "$spec" in
    "" | \#*) continue ;;
    esac
    IFS='|' read -r binary description output_file completion_cmd <<<"$spec"
    if command -v "$binary" >/dev/null 2>&1; then
      run_with_spinner "$description" sh -c "cd '$REPO_ROOT' && $completion_cmd > '$target_dir/$output_file'"
    fi
  done <"$AUTOGEN_COMPLETIONS_MANIFEST"
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
