#!/usr/bin/env bash
set -euo pipefail

DEFAULT_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="${OOODNAKOV_REPO_ROOT:-$DEFAULT_REPO_ROOT}"
SETUP="$REPO_ROOT/scripts/setup.sh"
DELETE="$REPO_ROOT/scripts/delete.sh"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"
GEN_LOCK="$REPO_ROOT/scripts/generate-dependency-lock.py"
UPDATE_PINS="$REPO_ROOT/scripts/update-pins.sh"
RENDER_SECRETS="$REPO_ROOT/scripts/render-secrets.py"
AGENTS_TOOL="$REPO_ROOT/scripts/agents-tool.py"
KNOWN_COMMANDS=(bootstrap install deps update doctor dry-run delete remove lock update-pins agents secrets shell version check preview upgrade)
KNOWN_SHELL_SUBCOMMANDS=(forgit-aliases typo-handling)
KNOWN_SHELL_FORGIT_MODES=(plain forgit status)
KNOWN_SHELL_TYPO_MODES=(silent suggest help status)
LOCAL_OVERRIDES_START="# --- LOCAL OVERRIDES START ---"
LOCAL_OVERRIDES_END="# --- LOCAL OVERRIDES END ---"
FORGIT_ALIAS_VAR="OOODNAKOV_FORGIT_ALIAS_MODE"
TYPO_HANDLING_VAR="OOODNAKOV_TYPO_HANDLING_MODE"

ui_is_interactive() {
  [ -t 1 ]
}

ui_use_nerd_font() {
  [ "${OOOCONF_ASCII:-0}" != "1" ] && ui_is_interactive
}

ui_use_color() {
  case "${OOOCONF_COLOR:-auto}" in
    0|false|never) return 1 ;;
    1|true|always) return 0 ;;
  esac
  [ -z "${NO_COLOR:-}" ] && ui_is_interactive
}

ui_icon() {
  local name="$1"
  if ui_use_nerd_font; then
    case "$name" in
      section) printf '%b' '\U000f018d' ;;
      ok) printf '%b' '\U000f012c' ;;
      warn) printf '%b' '\U000f002a' ;;
      fail) printf '%b' '\U000f0156' ;;
      info) printf '%b' '\U000f02fc' ;;
      hint) printf '%b' '\U000f0311' ;;
      *) printf '•' ;;
    esac
  else
    case "$name" in
      section) printf '==' ;;
      ok) printf '[ok]' ;;
      warn) printf '[warn]' ;;
      fail) printf '[fail]' ;;
      info) printf '[info]' ;;
      hint) printf '->' ;;
      *) printf '-' ;;
    esac
  fi
}

ui_colorize() {
  local role="$1"
  local text="$2"
  local code=""
  if ! ui_use_color; then
    printf '%s' "$text"
    return 0
  fi
  case "$role" in
    section) code='1;38;5;111' ;;
    ok) code='1;38;5;78' ;;
    warn) code='1;38;5;221' ;;
    fail) code='1;38;5;203' ;;
    info) code='1;38;5;117' ;;
    hint) code='38;5;245' ;;
    muted) code='38;5;245' ;;
    *) code='' ;;
  esac
  if [ -n "$code" ]; then
    printf '\033[%sm%s\033[0m' "$code" "$text"
  else
    printf '%s' "$text"
  fi
}

ui_line() {
  local role="$1"
  shift
  printf '%s %s\n' "$(ui_colorize "$role" "$(ui_icon "$role")")" "$*"
}

ui_section() {
  local title="$1"
  local rule_char='-'
  ui_use_nerd_font && rule_char='─'
  ui_line section "$title"
  ui_colorize muted "$(printf '%*s' "$((${#title}+3))" '' | tr ' ' "$rule_char")"
  printf '\n'
}

# Run a Python script, preferring `uv run` (which uses the pinned .python-version
# and .venv) when uv is available, falling back to plain python3.
run_python() {
  if command -v uv >/dev/null 2>&1 && [ -f "$REPO_ROOT/pyproject.toml" ]; then
    uv run "$@"
  else
    python3 "$@"
  fi
}

visible_error() {
  if [ -t 1 ]; then
    ui_line fail "$*"
  else
    printf '%s\n' "$*" >&2
  fi
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
  mv "$tmp_file" "$target"
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

  printf 'help\n'
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

print_help_for_scope() {
  local scope="${1:-main}"

  case "$scope" in
    shell)
      handle_shell_command help
      ;;
    *)
      usage
      ;;
  esac
}

report_unknown_command() {
  local subject="$1"
  local suggestion="${2:-}"
  local scope="${3:-main}"
  local mode

  mode="$(get_typo_handling_mode)"
  case "$mode" in
    silent)
      ;;
    suggest)
      if [ -n "$suggestion" ]; then
        visible_error "Did you mean: $suggestion"
      else
        visible_error "$subject"
      fi
      ;;
    help|*)
      visible_error "$subject"
      if [ -n "$suggestion" ]; then
        visible_error "Did you mean: $suggestion"
      fi
      print_help_for_scope "$scope"
      ;;
  esac
}

handle_shell_command() {
  local subcommand="${1:-}"
  local suggestion=""

  case "$subcommand" in
    ""|-h|--help|help)
      ui_section "oooconf shell"
      cat <<'EOF'
Usage:
  oooconf shell forgit-aliases [plain|forgit|status]
  oooconf shell typo-handling [silent|suggest|help|status]

Manage local shell preferences that live in the preserved LOCAL OVERRIDES block.

Forgit alias modes:
  plain   keep plain git aliases like gd/gco and define glo as git log
  forgit  enable upstream forgit aliases like glo/gd/gco
  status  show the currently configured mode

Typo handling modes:
  silent   exit 1 without printing anything for wrong commands
  suggest  print only the closest suggestion when available
  help     print the unknown command, suggestion, and full help

Examples:
  oooconf shell forgit-aliases status
  oooconf shell forgit-aliases plain
  oooconf shell forgit-aliases forgit
  oooconf shell typo-handling status
  oooconf shell typo-handling suggest
  oooconf shell typo-handling silent
EOF
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
    *)
      suggestion="$(suggest_from_list "$subcommand" "${KNOWN_SHELL_SUBCOMMANDS[@]}")"
      report_unknown_command "Unknown shell subcommand: $subcommand" "$suggestion" shell
      return 1
      ;;
  esac
}

resolve_command_alias() {
  case "$1" in
    check) printf 'doctor\n' ;;
    preview) printf 'dry-run\n' ;;
    upgrade) printf 'update\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

command_distance() {
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

suggest_command() {
  local input="$1"
  local best_command=""
  local best_distance=999
  local candidate distance threshold

  for candidate in "${KNOWN_COMMANDS[@]}"; do
    distance="$(command_distance "$input" "$candidate")"
    if [ "$distance" -lt "$best_distance" ]; then
      best_distance="$distance"
      best_command="$candidate"
    fi
  done

  threshold=3
  if [ "${#input}" -le 4 ] && [ "$threshold" -gt 2 ]; then
    threshold=2
  fi

  if [ "$best_distance" -le "$threshold" ]; then
    printf '%s\n' "$best_command"
  fi

  return 0
}

suggest_from_list() {
  local input="$1"
  shift
  local candidates=("$@")
  local best_match=""
  local best_distance=999
  local candidate distance threshold

  for candidate in "${candidates[@]}"; do
    distance="$(command_distance "$input" "$candidate")"
    if [ "$distance" -lt "$best_distance" ]; then
      best_distance="$distance"
      best_match="$candidate"
    fi
  done

  threshold=3
  if [ "${#input}" -le 4 ] && [ "$threshold" -gt 2 ]; then
    threshold=2
  fi

  if [ "$best_distance" -le "$threshold" ]; then
    printf '%s\n' "$best_match"
  fi

  return 0
}

print_version() {
  if command -v git >/dev/null 2>&1 && [ -d "$REPO_ROOT/.git" ]; then
    git -C "$REPO_ROOT" describe --always --dirty --tags 2>/dev/null || git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

usage() {
  ui_section "oooconf"
  cat <<EOF
Usage: oooconf [global options] <command> [command options]

oooconf — reproducible cross-platform dotfiles manager

Global options:
  -C, --repo-root PATH  run against a specific repo checkout
  -h, --help            show this help
  -n, --dry-run         add --dry-run to install or update
      --yes-optional    auto-accept optional dependency installs
  -V, --version         show CLI version information
      --print-repo-root print the resolved repo root and exit

Commands:
  Setup:
    bootstrap             clone/update repo then run install
    install               apply managed config and optional dependency installs
    deps                  install optional dependencies only
    update                pull repo with --ff-only, then re-run install

  Inspect & Validate:
    doctor                validate managed symlinks and required commands
    dry-run               preview install flow without mutating filesystem
    version               print CLI version and repo root

  Manage State:
    delete                remove managed links and restore latest backups
    remove                remove managed links only (no backup restore)
    lock                  regenerate dependency lock artifacts from pinned refs
    update-pins           compare/update pinned refs and refresh lock artifacts

  Shell:
    shell                 manage local shell preferences such as forgit aliases

  Secrets:
    secrets               sync or validate local secret env files

  Agents:
    agents                detect/sync/doctor AGENTS.md shared policy sections

Aliases:
  check -> doctor
  preview -> dry-run
  upgrade -> update

Getting help:
  oooconf --help                     show this message
  oooconf help <command>             show command-specific help
  oooconf help secrets               show secrets subcommand help

Common workflows:
  # Initial setup on a new machine:
  oooconf bootstrap

  # Preview what install would do:
  oooconf dry-run

  # Apply config and install dependencies:
  oooconf install
  oooconf deps

  # Check if everything is set up correctly:
  oooconf doctor

  # Update to latest config:
  oooconf update

Repo root:
  $REPO_ROOT
EOF
}

command_usage() {
  local command="$1"
  command="$(resolve_command_alias "$command")"
  ui_section "oooconf $command"

  case "$command" in
    bootstrap)
      cat <<'EOF'
Usage: oooconf bootstrap

Clone or update the configured repo checkout, then run the install flow.

This is the recommended first command on a new machine. It handles repo
cloning (if missing), pulls latest changes, and runs the full install.

Environment overrides:
  OOODNAKOV_CONFIG_DIR          custom config directory
  OOODNAKOV_CONFIG_BRANCH       git branch to checkout (default: main)
  OOODNAKOV_CONFIG_REPO_URL     SSH repo URL for git clone
  OOODNAKOV_CONFIG_HTTPS_REPO_URL HTTPS repo URL for git clone
  OOODNAKOV_INTERACTIVE         set to "never" to skip all prompts

Examples:
  oooconf bootstrap
  OOODNAKOV_INTERACTIVE=never oooconf bootstrap
EOF
      ;;
    install)
      cat <<'EOF'
Usage: oooconf install [--dry-run] [--yes-optional]

Apply managed config and optional dependency installation.

Creates symlinks from tracked config in home/ to their target locations,
backing up any replaced files. Optionally installs dependencies when
allowed.

Examples:
  oooconf install                      # interactive dependency prompts
  oooconf install --yes-optional       # auto-accept all optional installs
  oooconf install --dry-run            # preview without making changes
EOF
      ;;
    deps)
      cat <<'EOF'
Usage: oooconf deps [--dry-run] [dependency-key...]

Install optional dependencies only. Without dependency keys, an interactive
gum-based multi-select picker is used when available.

Dependency keys match those defined in deps.lock.json. Common keys include:
bat, delta, eza, fd, fzf, gum, glow, rg, yazi, ffmpeg, jq, p7zip, poppler, zoxide, and others.

Examples:
  oooconf deps                         # interactive picker (when gum available)
  oooconf deps bat delta fd ripgrep    # install specific tools
  oooconf deps --dry-run               # preview installation
EOF
      ;;
    update)
      cat <<'EOF'
Usage: oooconf update [--dry-run] [--yes-optional]

Pull the repo with --ff-only, then re-run the install flow.

Use this to update your config to the latest tracked state. It performs
a fast-forward pull only, failing if local changes would prevent it.

Examples:
  oooconf update                       # pull and reinstall
  oooconf update --yes-optional        # also install missing dependencies
  oooconf update --dry-run             # preview pull and install
EOF
      ;;
    doctor)
      cat <<'EOF'
Usage: oooconf doctor

Validate managed symlinks and required commands.

Checks that all managed config links point to valid targets and that
key tools (git, zsh, wezterm, nvim, etc.) are available on PATH.

Examples:
  oooconf doctor                       # run all checks
EOF
      ;;
    dry-run)
      cat <<'EOF'
Usage: oooconf dry-run

Preview the install flow without mutating the filesystem.

Shows what links would be created, what files would be backed up, and
what dependencies would be installed, without making any changes.

Examples:
  oooconf dry-run                      # preview install
  oooconf --yes-optional dry-run       # preview with dependency installs
EOF
      ;;
    delete)
      cat <<'EOF'
Usage: oooconf delete

Remove managed links and restore the latest backups when available.

Use this to undo the managed config and return to your previous state.
Backup files are stored in ~/.local/state/ooodnakov-config/backups/.

Examples:
  oooconf delete                       # restore from backups
EOF
      ;;
    remove)
      cat <<'EOF'
Usage: oooconf remove

Remove managed links without restoring backups.

Use this when you want to cleanly remove the managed config without
attempting to restore previous configurations.

Examples:
  oooconf remove                       # clean removal
EOF
      ;;
    lock)
      cat <<'EOF'
Usage: oooconf lock

Regenerate dependency lock artifacts from pinned refs in setup scripts.

Reads pinned versions from scripts/setup.sh (or setup.ps1) and writes
the resolved lock file to deps.lock.json.

Examples:
  oooconf lock                         # regenerate lock artifact
EOF
      ;;
    update-pins)
      cat <<'EOF'
Usage: oooconf update-pins [--apply]

Compare pinned git refs to upstream HEAD and refresh lock artifacts.

Without --apply, only reports differences. With --apply, updates the
pinned refs in setup scripts and regenerates lock artifacts.

Examples:
  oooconf update-pins                  # check for pin drift
  oooconf update-pins --apply          # update pins and regenerate lock
EOF
      ;;
    agents)
      cat <<'EOF'
Usage: oooconf agents <detect|sync|doctor> [options]

Manage shared AGENTS.md instructions and validate configured agent tooling.

Subcommands:
  detect [--json]       detect configured agent CLIs on PATH
  sync [--check]        append/update shared AGENTS.md managed block
  doctor [--strict-config-paths]
                        verify AGENTS.md managed block and default agent config paths
EOF
      ;;
    secrets)
      cat <<'EOF'
Usage: oooconf secrets <sync|doctor|list|status|login|unlock|logout|add|remove> [options]

Render or validate local secret env files from the tracked template.
Examples:
  oooconf secrets                      # show current sync/session status
  oooconf secrets login
  oooconf secrets unlock               # prompt for password and save session
  oooconf secrets unlock 'your-password'
  eval "$(oooconf secrets unlock --shell zsh)"
  oooconf secrets sync
  oooconf secrets sync --dry-run
  oooconf secrets ls                   # alias for list
  oooconf secrets list
  oooconf secrets list --resolved
  oooconf secrets status
  oooconf secrets doctor
  oooconf secrets logout
  oooconf secrets add GITHUB_TOKEN bw://item/abc123/password
  oooconf secrets add SOME_URL https://example.com
  oooconf secrets rm GITHUB_TOKEN      # alias for remove
  oooconf secrets remove GITHUB_TOKEN

Environment overrides:
  OOODNAKOV_SECRETS_BACKEND
  OOODNAKOV_BW_SERVER
EOF
      ;;
    shell)
      handle_shell_command help
      ;;
    version)
      cat <<'EOF'
Usage: oooconf version

Print the CLI version (git describe or commit SHA) and resolved repo root.

Examples:
  oooconf version                      # show version and repo path
EOF
      ;;
    ""|-h|--help|help)
      usage
      ;;
    *)
      suggestion="$(suggest_command "$command")"
      report_unknown_command "Unknown command: $command" "$suggestion"
      return 1
      ;;
  esac
}

require_repo_script() {
  local script_path="$1"
  if [ ! -x "$script_path" ]; then
    echo "Required script is missing or not executable: $script_path" >&2
    exit 1
  fi
}

dry_run_requested=0
yes_optional_requested=0
command=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -C|--repo-root)
      [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 1; }
      REPO_ROOT="$2"
      SETUP="$REPO_ROOT/scripts/setup.sh"
      DELETE="$REPO_ROOT/scripts/delete.sh"
      BOOTSTRAP="$REPO_ROOT/bootstrap.sh"
      GEN_LOCK="$REPO_ROOT/scripts/generate-dependency-lock.py"
      UPDATE_PINS="$REPO_ROOT/scripts/update-pins.sh"
      RENDER_SECRETS="$REPO_ROOT/scripts/render-secrets.py"
      AGENTS_TOOL="$REPO_ROOT/scripts/agents-tool.py"
      shift 2
      ;;
    --print-repo-root)
      ui_line info "$REPO_ROOT"
      exit 0
      ;;
    -V|--version)
      ui_line info "oooconf $(print_version)"
      ui_line info "$REPO_ROOT"
      exit 0
      ;;
    -h|--help)
      if [ -n "${2:-}" ] && [[ "${2:-}" != -* ]]; then
        command_usage "$2"
      else
        usage
      fi
      exit 0
      ;;
    -n|--dry-run)
      dry_run_requested=1
      shift
      ;;
    --yes-optional)
      yes_optional_requested=1
      shift
      ;;
    help)
      command_usage "$(resolve_command_alias "${2:-}")"
      exit 0
      ;;
    version)
      ui_line info "oooconf $(print_version)"
      ui_line info "$REPO_ROOT"
      exit 0
      ;;
    -*)
      visible_error "Unknown option: $1"
      usage >&2
      exit 1
      ;;
    *)
      command="$(resolve_command_alias "$1")"
      shift
      break
      ;;
  esac
done

if [ -z "$command" ]; then
  if [ "$dry_run_requested" -eq 1 ]; then
    command="install"
  else
    usage
    exit 0
  fi
fi

case "$command" in
  bootstrap)
    if [ "$dry_run_requested" -eq 1 ]; then
      echo "--dry-run is not supported for bootstrap" >&2
      exit 1
    fi
    require_repo_script "$BOOTSTRAP"
    exec "$BOOTSTRAP" "$@"
    ;;
  install)
    require_repo_script "$SETUP"
    if [ "$dry_run_requested" -eq 1 ]; then
      if [ "$yes_optional_requested" -eq 1 ]; then
        exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" OOODNAKOV_INSTALL_OPTIONAL=always "$SETUP" install --dry-run "$@"
      fi
      exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" "$SETUP" install --dry-run "$@"
    fi
    if [ "$yes_optional_requested" -eq 1 ]; then
      exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" OOODNAKOV_INSTALL_OPTIONAL=always "$SETUP" install "$@"
    fi
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" "$SETUP" install "$@"
    ;;
  deps)
    require_repo_script "$SETUP"
    if [ "$dry_run_requested" -eq 1 ]; then
      if [ "$yes_optional_requested" -eq 1 ]; then
        exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" OOODNAKOV_INSTALL_OPTIONAL=always "$SETUP" deps --dry-run "$@"
      fi
      exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" "$SETUP" deps --dry-run "$@"
    fi
    if [ "$yes_optional_requested" -eq 1 ]; then
      exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" OOODNAKOV_INSTALL_OPTIONAL=always "$SETUP" deps "$@"
    fi
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" "$SETUP" deps "$@"
    ;;
  update)
    require_repo_script "$SETUP"
    if [ "$dry_run_requested" -eq 1 ]; then
      if [ "$yes_optional_requested" -eq 1 ]; then
        exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" OOODNAKOV_INSTALL_OPTIONAL=always "$SETUP" update --dry-run "$@"
      fi
      exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" "$SETUP" update --dry-run "$@"
    fi
    if [ "$yes_optional_requested" -eq 1 ]; then
      exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" OOODNAKOV_INSTALL_OPTIONAL=always "$SETUP" update "$@"
    fi
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" "$SETUP" update "$@"
    ;;
  doctor)
    if [ "$dry_run_requested" -eq 1 ]; then
      echo "--dry-run is not supported for doctor" >&2
      exit 1
    fi
    require_repo_script "$SETUP"
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" "$SETUP" doctor "$@"
    ;;
  dry-run)
    if [ "$dry_run_requested" -eq 1 ]; then
      echo "Use either dry-run or --dry-run, not both" >&2
      exit 1
    fi
    require_repo_script "$SETUP"
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" "$SETUP" install --dry-run "$@"
    ;;
  delete)
    if [ "$dry_run_requested" -eq 1 ]; then
      echo "--dry-run is not supported for delete" >&2
      exit 1
    fi
    require_repo_script "$DELETE"
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" "$DELETE" restore "$@"
    ;;
  remove)
    if [ "$dry_run_requested" -eq 1 ]; then
      echo "--dry-run is not supported for remove" >&2
      exit 1
    fi
    require_repo_script "$DELETE"
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" "$DELETE" remove "$@"
    ;;
  lock)
    if [ "$dry_run_requested" -eq 1 ]; then
      echo "--dry-run is not supported for lock" >&2
      exit 1
    fi
    OOODNAKOV_REPO_ROOT="$REPO_ROOT" run_python "$GEN_LOCK" "$@"
    exit $?
    ;;
  update-pins)
    if [ "$dry_run_requested" -eq 1 ]; then
      echo "--dry-run is not supported for update-pins" >&2
      exit 1
    fi
    require_repo_script "$UPDATE_PINS"
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" "$UPDATE_PINS" "$@"
    ;;
  agents)
    if [ "$dry_run_requested" -eq 1 ]; then
      echo "--dry-run is not supported for agents" >&2
      exit 1
    fi
    if ! command -v python3 >/dev/null 2>&1; then
      echo "python3 is required for agents command." >&2
      exit 1
    fi
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" python3 "$AGENTS_TOOL" --repo-root "$REPO_ROOT" "$@"
    ;;
  secrets)
    OOODNAKOV_REPO_ROOT="$REPO_ROOT" run_python "$RENDER_SECRETS" --repo-root "$REPO_ROOT" "$@"
    exit $?
    ;;
  shell)
    handle_shell_command "$@"
    ;;
  *)
    suggestion="$(suggest_command "$command")"
    report_unknown_command "Unknown command: $command" "$suggestion"
    exit 1
    ;;
esac
