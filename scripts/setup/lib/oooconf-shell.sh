#!/usr/bin/env bash
# Sourced by scripts/setup/ooodnakov.sh; do not execute directly.

run_python() {
  oooconf_run_python "$REPO_ROOT" "$@"
}

shell_config_home() {
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/ooodnakov"
}

shell_local_env_zsh_path() {
  printf '%s\n' "$(shell_config_home)/local/env.zsh"
}

shell_local_env_ps1_path() {
  printf '%s\n' "$(shell_config_home)/local/env.ps1"
}

ensure_local_override_file() {
  local target="$1"
  local start_marker="$2"
  local end_marker="$3"

  mkdir -p "$(dirname "$target")"

  if [ ! -f "$target" ]; then
    cat >"$target" <<EOF
$start_marker
# Add machine-specific env vars here. This section is preserved across syncs.
$end_marker
EOF
    return 0
  fi

  if ! grep -Fq "$start_marker" "$target"; then
    cat >>"$target" <<EOF

$start_marker
# Add machine-specific env vars here. This section is preserved across syncs.
$end_marker
EOF
  fi
}

upsert_override_line() {
  local target="$1"
  local variable_name="$2"
  local replacement_line="$3"
  local tmp_file

  ensure_local_override_file "$target" "$LOCAL_OVERRIDES_START" "$LOCAL_OVERRIDES_END"

  tmp_file="$(mktemp)"
  awk \
    -v start="$LOCAL_OVERRIDES_START" \
    -v end="$LOCAL_OVERRIDES_END" \
    -v variable_name="$variable_name" \
    -v replacement_line="$replacement_line" '
      BEGIN {
        in_block = 0
        inserted = 0
      }
      index($0, start) == 1 {
        in_block = 1
        print
        next
      }
      index($0, end) == 1 {
        if (in_block && !inserted) {
          print replacement_line
          inserted = 1
        }
        in_block = 0
        print
        next
      }
      in_block && $0 ~ ("(^export " variable_name "=)|(^\\$env:" variable_name " = )") {
        if (!inserted) {
          print replacement_line
          inserted = 1
        }
        next
      }
      { print }
      END {
        if (!inserted) {
          if (NR > 0) {
            print ""
          }
          print start
          print replacement_line
          print end
        }
      }
    ' "$target" >"$tmp_file"
  cat "$tmp_file" >"$target"
  rm -f "$tmp_file"
}

get_zsh_prompt_mode() {
  local env_zsh mode

  if [ -n "${OOOCONF_ZSH_PROMPT:-}" ]; then
    printf '%s\n' "$OOOCONF_ZSH_PROMPT"
    return 0
  fi

  env_zsh="$(shell_local_env_zsh_path)"
  if [ -f "$env_zsh" ]; then
    mode="$(sed -n "s/^export ${OOOCONF_ZSH_PROMPT_VAR}=\"\([^\"]*\)\"$/\1/p" "$env_zsh" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi
  fi

  printf 'p10k\n'
}

get_prompt_style_mode() {
  local env_zsh env_ps1 mode

  if [ -n "${OOOCONF_PROMPT_STYLE:-}" ]; then
    printf '%s\n' "$OOOCONF_PROMPT_STYLE"
    return 0
  fi

  env_zsh="$(shell_local_env_zsh_path)"
  if [ -f "$env_zsh" ]; then
    mode="$(sed -n "s/^export ${OOOCONF_PROMPT_STYLE_VAR}=\"\([^\"]*\)\"$/\1/p" "$env_zsh" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi
  fi

  env_ps1="$(shell_local_env_ps1_path)"
  if [ -f "$env_ps1" ]; then
    mode="$(sed -n "s/^\$env:${OOOCONF_PROMPT_STYLE_VAR} = '\([^']*\)'$/\1/p" "$env_ps1" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi
  fi

  printf 'verbose\n'
}

get_forgit_alias_mode() {
  local env_zsh mode
  env_zsh="$(shell_local_env_zsh_path)"

  if [ -f "$env_zsh" ]; then
    mode="$(sed -n "s/^export ${FORGIT_ALIAS_VAR}=\"\\([^\"]*\\)\"$/\\1/p" "$env_zsh" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi
  fi

  printf 'plain\n'
}

get_typo_handling_mode() {
  local env_zsh mode

  if [ -n "${OOODNAKOV_TYPO_HANDLING_MODE:-}" ]; then
    printf '%s\n' "$OOODNAKOV_TYPO_HANDLING_MODE"
    return 0
  fi

  env_zsh="$(shell_local_env_zsh_path)"

  if [ -f "$env_zsh" ]; then
    mode="$(sed -n "s/^export ${TYPO_HANDLING_VAR}=\"\\([^\"]*\\)\"$/\\1/p" "$env_zsh" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi
  fi

  printf 'suggest\n'
}

get_psfzf_tab_mode() {
  local env_ps1 mode
  env_ps1="$(shell_local_env_ps1_path)"

  if [ -f "$env_ps1" ]; then
    mode="$(sed -n "s/^\$env:${PSFZF_TAB_VAR} = '\\([^']*\\)'$/\\1/p" "$env_ps1" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi
  fi

  printf 'enabled\n'
}

get_psfzf_git_mode() {
  local env_ps1 mode
  env_ps1="$(shell_local_env_ps1_path)"

  if [ -f "$env_ps1" ]; then
    mode="$(sed -n "s/^\$env:${PSFZF_GIT_VAR} = '\\([^']*\\)'$/\\1/p" "$env_ps1" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi
  fi

  printf 'enabled\n'
}

get_auto_uv_env_mode() {
  local env_zsh env_ps1 mode

  case "${OOODNAKOV_AUTO_UV_ENV_MODE:-}" in
    disabled|existing|enabled|quiet)
      printf '%s\n' "$OOODNAKOV_AUTO_UV_ENV_MODE"
      return 0
      ;;
  esac

  env_zsh="$(shell_local_env_zsh_path)"
  if [ -f "$env_zsh" ]; then
    mode="$(sed -n "s/^export ${OOODNAKOV_AUTO_UV_ENV_MODE_VAR}=\"\([^\"]*\)\"$/\1/p" "$env_zsh" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi

    if grep -q "^export ${AUTO_UV_ENV_VAR}=\"1\"$" "$env_zsh"; then
      printf 'quiet\n'
      return 0
    fi
  fi

  env_ps1="$(shell_local_env_ps1_path)"
  if [ -f "$env_ps1" ]; then
    mode="$(sed -n "s/^\$env:${OOODNAKOV_AUTO_UV_ENV_MODE_VAR} = '\([^']*\)'$/\1/p" "$env_ps1" | head -n 1)"
    if [ -n "$mode" ]; then
      printf '%s\n' "$mode"
      return 0
    fi

    if grep -q "^\$env:${AUTO_UV_ENV_VAR} = 1$" "$env_ps1"; then
      printf 'quiet\n'
      return 0
    fi
  fi
  printf 'existing\n'
}

set_zsh_prompt_mode() {
  local mode="$1"
  local env_zsh

  case "$mode" in
    p10k|ohmyposh) ;;
    *)
      visible_error "Invalid zsh prompt mode: $mode"
      visible_error "Expected one of: p10k, ohmyposh"
      return 1
      ;;
  esac

  env_zsh="$(shell_local_env_zsh_path)"
  upsert_override_line "$env_zsh" "$OOOCONF_ZSH_PROMPT_VAR" "export $OOOCONF_ZSH_PROMPT_VAR=\"$mode\""

  ui_line ok "zsh prompt set to $mode"
  ui_line info "zsh: $env_zsh"
  ui_line hint "Open a new zsh session or run: exec zsh"
}

set_prompt_style_mode() {
  local mode="$1"
  local env_zsh env_ps1

  case "$mode" in
    verbose|concise) ;;
    *)
      visible_error "Invalid prompt style: $mode"
      visible_error "Expected one of: verbose, concise"
      return 1
      ;;
  esac

  env_zsh="$(shell_local_env_zsh_path)"
  env_ps1="$(shell_local_env_ps1_path)"

  upsert_override_line "$env_zsh" "$OOOCONF_PROMPT_STYLE_VAR" "export $OOOCONF_PROMPT_STYLE_VAR=\"$mode\""
  upsert_override_line "$env_ps1" "$OOOCONF_PROMPT_STYLE_VAR" "\$env:$OOOCONF_PROMPT_STYLE_VAR = '$mode'"

  ui_line ok "prompt style set to $mode"
  ui_line info "zsh: $env_zsh"
  ui_line info "pwsh: $env_ps1"
  ui_line hint "Open a new shell session to apply the change."
}

set_auto_uv_env_mode() {
  local mode="$1"
  local env_zsh env_ps1 quiet_val

  case "$mode" in
    disabled|existing|enabled|quiet) ;;
    *)
      visible_error "Invalid auto-uv-env mode: $mode"
      visible_error "Expected one of: disabled, existing, enabled, quiet"
      return 1
      ;;
  esac

  env_zsh="$(shell_local_env_zsh_path)"
  env_ps1="$(shell_local_env_ps1_path)"
  [ "$mode" = "quiet" ] && quiet_val=1 || quiet_val=0

  upsert_override_line "$env_zsh" "$OOODNAKOV_AUTO_UV_ENV_MODE_VAR" "export $OOODNAKOV_AUTO_UV_ENV_MODE_VAR=\"$mode\""
  upsert_override_line "$env_ps1" "$OOODNAKOV_AUTO_UV_ENV_MODE_VAR" "\$env:$OOODNAKOV_AUTO_UV_ENV_MODE_VAR = '$mode'"
  upsert_override_line "$env_zsh" "$AUTO_UV_ENV_VAR" "export $AUTO_UV_ENV_VAR=\"$quiet_val\""
  upsert_override_line "$env_ps1" "$AUTO_UV_ENV_VAR" "\$env:$AUTO_UV_ENV_VAR = $quiet_val"

  ui_line ok "auto-uv-env mode set to $mode"
  ui_line info "zsh: $env_zsh"
  ui_line info "pwsh: $env_ps1"
  ui_line hint "Open a new shell session to apply the change."
}

set_forgit_alias_mode() {
  local mode="$1"
  local env_zsh env_ps1

  case "$mode" in
    plain|forgit) ;;
    *)
      visible_error "Invalid forgit alias mode: $mode"
      visible_error "Expected one of: plain, forgit"
      return 1
      ;;
  esac

  env_zsh="$(shell_local_env_zsh_path)"
  env_ps1="$(shell_local_env_ps1_path)"

  upsert_override_line "$env_zsh" "$FORGIT_ALIAS_VAR" "export $FORGIT_ALIAS_VAR=\"$mode\""
  upsert_override_line "$env_ps1" "$FORGIT_ALIAS_VAR" "\$env:$FORGIT_ALIAS_VAR = '$mode'"

  ui_line ok "forgit alias mode set to $mode"
  ui_line info "zsh: $env_zsh"
  ui_line info "pwsh: $env_ps1"
  ui_line hint "Open a new shell or run: exec zsh"
}

set_typo_handling_mode() {
  local mode="$1"
  local env_zsh env_ps1

  case "$mode" in
    silent|suggest|help) ;;
    *)
      visible_error "Invalid typo handling mode: $mode"
      visible_error "Expected one of: silent, suggest, help"
      return 1
      ;;
  esac

  env_zsh="$(shell_local_env_zsh_path)"
  env_ps1="$(shell_local_env_ps1_path)"

  upsert_override_line "$env_zsh" "$TYPO_HANDLING_VAR" "export $TYPO_HANDLING_VAR=\"$mode\""
  upsert_override_line "$env_ps1" "$TYPO_HANDLING_VAR" "\$env:$TYPO_HANDLING_VAR = '$mode'"

  ui_line ok "typo handling mode set to $mode"
  ui_line info "zsh: $env_zsh"
  ui_line info "pwsh: $env_ps1"
  ui_line hint "Open a new shell or run: exec zsh"
}

set_psfzf_tab_mode() {
  local mode="$1"
  local env_ps1

  case "$mode" in
    enabled|disabled) ;;
    *)
      visible_error "Invalid psfzf-tab mode: $mode"
      visible_error "Expected one of: enabled, disabled"
      return 1
      ;;
  esac

  env_ps1="$(shell_local_env_ps1_path)"
  upsert_override_line "$env_ps1" "$PSFZF_TAB_VAR" "\$env:$PSFZF_TAB_VAR = '$mode'"

  ui_line ok "psfzf-tab mode set to $mode"
  ui_line info "pwsh: $env_ps1"
  ui_line hint "Open a new shell session to apply the change."
}

set_psfzf_git_mode() {
  local mode="$1"
  local env_ps1

  case "$mode" in
    enabled|disabled) ;;
    *)
      visible_error "Invalid psfzf-git mode: $mode"
      visible_error "Expected one of: enabled, disabled"
      return 1
      ;;
  esac

  env_ps1="$(shell_local_env_ps1_path)"
  upsert_override_line "$env_ps1" "$PSFZF_GIT_VAR" "\$env:$PSFZF_GIT_VAR = '$mode'"

  ui_line ok "psfzf-git mode set to $mode"
  ui_line info "pwsh: $env_ps1"
  ui_line hint "Open a new shell session to apply the change."
}

print_shell_status() {
  ui_line info "forgit-aliases: $(get_forgit_alias_mode)"
  ui_line info "typo-handling: $(get_typo_handling_mode)"
  ui_line info "psfzf-tab: $(get_psfzf_tab_mode)"
  ui_line info "psfzf-git: $(get_psfzf_git_mode)"
  ui_line info "prompt: $(get_zsh_prompt_mode)"
  ui_line info "prompt-style: $(get_prompt_style_mode)"
  ui_line info "auto-uv-env: $(get_auto_uv_env_mode)"
}

handle_shell_command() {
  local subcommand="${1:-}"
  local suggestion=""

  case "$subcommand" in
    ""|-h|--help|help)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf shell status
       oooconf shell prompt [p10k|ohmyposh|status]
       oooconf shell prompt-style [verbose|concise|status]
       oooconf shell forgit-aliases [plain|forgit|status]
       oooconf shell typo-handling [silent|suggest|help|status]
       oooconf shell psfzf-tab [enabled|disabled|status]
       oooconf shell psfzf-git [enabled|disabled|status]
       oooconf shell auto-uv-env [disabled|existing|enabled|quiet|status]

Manage local shell preferences that live in the preserved LOCAL OVERRIDES block.
Forgit alias modes:
  plain   keep plain git aliases like gd/gco and define glo as git log
  forgit  enable upstream forgit aliases like glo/gd/gco
  status  show the currently configured mode
Typo handling modes:
  silent   exit 1 without printing anything for wrong commands
  suggest  print only the closest suggestion when available
  help     print the unknown command, suggestion, and full help
PSFzf options:
  psfzf-tab  enable or disable fzf-based tab completion in PowerShell
  psfzf-git  enable or disable fzf-based git keybindings in PowerShell
  status     show the currently configured mode
Prompt options:
  prompt        switch only the zsh prompt engine between Powerlevel10k and Oh My Posh
  prompt-style  switch all managed prompts between verbose and concise layouts
  status        show the currently configured mode
Auto UV environment options:
  disabled  disable automatic Python virtualenv activation
  existing  activate existing .venv directories without creating missing ones (default)
  enabled   activate Python venvs and create missing .venv directories with uv
  quiet     enabled mode, but suppress activation/deactivation messages
  status    show the currently configured mode
Examples:
  oooconf shell status
  oooconf shell prompt status
  oooconf shell prompt ohmyposh
  oooconf shell prompt p10k
  oooconf shell prompt-style concise
  oooconf shell forgit-aliases status
  oooconf shell forgit-aliases plain
  oooconf shell forgit-aliases forgit
  oooconf shell typo-handling status
  oooconf shell typo-handling suggest
  oooconf shell typo-handling silent
  oooconf shell psfzf-tab enabled
  oooconf shell psfzf-tab disabled
  oooconf shell psfzf-git status
  oooconf shell auto-uv-env existing
  oooconf shell auto-uv-env disabled
EOF
      ;;
    status)
      print_shell_status
      ;;

    prompt)
      case "${2:-status}" in
        status)
          get_zsh_prompt_mode
          ;;
        p10k|ohmyposh)
          set_zsh_prompt_mode "$2"
          ;;
        *)
          suggestion="$(suggest_from_list "${2:-}" "${KNOWN_SHELL_PROMPT_MODES[@]}")"
          report_unknown_command "Unknown shell option: ${2:-}" "$suggestion" shell
          return 1
          ;;
      esac
      ;;
    prompt-style)
      case "${2:-status}" in
        status)
          get_prompt_style_mode
          ;;
        verbose|concise)
          set_prompt_style_mode "$2"
          ;;
        *)
          suggestion="$(suggest_from_list "${2:-}" "${KNOWN_SHELL_PROMPT_STYLE_MODES[@]}")"
          report_unknown_command "Unknown shell option: ${2:-}" "$suggestion" shell
          return 1
          ;;
      esac
      ;;
    forgit-aliases)
      case "${2:-status}" in
        status)
          printf '%s\n' "$(get_forgit_alias_mode)"
          ;;
        plain|forgit)
          set_forgit_alias_mode "$2"
          ;;
        *)
          suggestion="$(suggest_from_list "${2:-}" "${KNOWN_SHELL_FORGIT_MODES[@]}")"
          report_unknown_command "Unknown shell option: ${2:-}" "$suggestion" shell
          return 1
          ;;
      esac
      ;;
    typo-handling)
      case "${2:-status}" in
        status)
          printf '%s\n' "$(get_typo_handling_mode)"
          ;;
        silent|suggest|help)
          set_typo_handling_mode "$2"
          ;;
        *)
          suggestion="$(suggest_from_list "${2:-}" "${KNOWN_SHELL_TYPO_MODES[@]}")"
          report_unknown_command "Unknown shell option: ${2:-}" "$suggestion" shell
          return 1
          ;;
      esac
      ;;
    psfzf-tab)
      case "${2:-status}" in
        status)
          get_psfzf_tab_mode
          ;;
        enabled|disabled)
          set_psfzf_tab_mode "$2"
          ;;
        *)
          suggestion="$(suggest_from_list "${2:-}" "${KNOWN_SHELL_PSFZF_MODES[@]}")"
          report_unknown_command "Unknown shell option: ${2:-}" "$suggestion" shell
          return 1
          ;;
      esac
      ;;
    psfzf-git)
      case "${2:-status}" in
        status)
          get_psfzf_git_mode
          ;;
        enabled|disabled)
          set_psfzf_git_mode "$2"
          ;;
        *)
          suggestion="$(suggest_from_list "${2:-}" "${KNOWN_SHELL_PSFZF_MODES[@]}")"
          report_unknown_command "Unknown shell option: ${2:-}" "$suggestion" shell
          return 1
          ;;
      esac
      ;;
    auto-uv-env)
      case "${2:-status}" in
        status)
          get_auto_uv_env_mode
          ;;
        disabled|existing|enabled|quiet)
          set_auto_uv_env_mode "$2"
          ;;
        *)
          suggestion="$(suggest_from_list "${2:-}" "${KNOWN_SHELL_AUTO_UV_MODES[@]}")"
          report_unknown_command "Unknown shell option: ${2:-}" "$suggestion" shell
          return 1
          ;;
      esac
      ;;
    *)
      suggestion="$(suggest_from_list "$subcommand" "${KNOWN_SHELL_SUBCOMMANDS[@]}")"
      report_unknown_command "Unknown shell subcommand: $subcommand" "$suggestion" shell
      return 1
      ;;
  esac
}
