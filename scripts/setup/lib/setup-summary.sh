#!/usr/bin/env bash
# Sourced by scripts/setup/setup.sh; do not execute directly.

print_summary() {
  local item

  echo
  if [ ${#DEPENDENCY_SUMMARY[@]} -gt 0 ]; then
    ui_section "Dependency summary"
    for item in "${DEPENDENCY_SUMMARY[@]}"; do
      if ! is_verbose && [[ "$item" == *": present" || "$item" == *": skipped" ]]; then
        continue
      fi
      bullet "$item"
    done
  fi

  if [ ${#TOOL_SUMMARY[@]} -gt 0 ]; then
    ui_section "Managed tools"
    for item in "${TOOL_SUMMARY[@]}"; do
      if ! is_verbose && [[ "$item" == *": linked" || "$item" == *": synced" || "$item" == "ensured directory: "* || "$item" == *": linked into "* || "$item" == *": permissions normalized" || "$item" == *": install.py succeeded" ]]; then
        continue
      fi
      bullet "$item"
    done
  fi
  if [ "${#FAILURES[@]}" -gt 0 ]; then
    ui_section "Failures"
    for item in "${FAILURES[@]}"; do
      bullet "$item"
    done
  fi
}
