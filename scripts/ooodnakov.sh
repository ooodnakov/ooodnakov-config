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

print_version() {
  if command -v git >/dev/null 2>&1 && [ -d "$REPO_ROOT/.git" ]; then
    git -C "$REPO_ROOT" describe --always --dirty --tags 2>/dev/null || git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

usage() {
  cat <<EOF
Usage: oooconf [global options] <command> [command options]

Global options:
  -C, --repo-root PATH  run against a specific repo checkout
  -h, --help            show this help
  -n, --dry-run         add --dry-run to install or update
      --yes-optional    auto-accept optional dependency installs
  -V, --version         show CLI version information
      --print-repo-root print the resolved repo root and exit

Commands:
  bootstrap             clone/update repo then run install
  install               run setup install
  deps                  install optional dependencies only
  update                run setup update
  doctor                run setup doctor
  dry-run               run setup install --dry-run
  delete                remove managed links and restore latest backups
  remove                remove managed links only
  lock                  regenerate dependency lock artifacts
  update-pins           check/update pinned refs and refresh lock artifacts
  agents                detect/sync/doctor AGENTS.md common policy blocks
  secrets               sync or validate local secret env files
  help [command]        show general or command-specific help
  version               show CLI version information

Repo root:
  $REPO_ROOT
EOF
}

command_usage() {
  local command="$1"

  case "$command" in
    bootstrap)
      cat <<'EOF'
Usage: oooconf bootstrap

Clone or update the configured repo checkout, then run the install flow.
Environment overrides:
  OOODNAKOV_CONFIG_DIR
  OOODNAKOV_CONFIG_BRANCH
  OOODNAKOV_CONFIG_REPO_URL
  OOODNAKOV_CONFIG_HTTPS_REPO_URL
  OOODNAKOV_INTERACTIVE
EOF
      ;;
    install)
      cat <<'EOF'
Usage: oooconf install [--dry-run] [--yes-optional]

Apply managed config and optional dependency installation.
EOF
      ;;
    deps)
      cat <<'EOF'
Usage: oooconf deps [--dry-run] [dependency-key...]

Install optional dependencies only. Without dependency keys, an interactive
gum-based multi-select picker is used when available.
EOF
      ;;
    update)
      cat <<'EOF'
Usage: oooconf update [--dry-run] [--yes-optional]

Pull the repo with --ff-only, then re-run the install flow.
EOF
      ;;
    doctor)
      cat <<'EOF'
Usage: oooconf doctor

Validate managed symlinks and required commands.
EOF
      ;;
    dry-run)
      cat <<'EOF'
Usage: oooconf dry-run

Preview the install flow without mutating the filesystem.
EOF
      ;;
    delete)
      cat <<'EOF'
Usage: oooconf delete

Remove managed links and restore the latest backups when available.
EOF
      ;;
    remove)
      cat <<'EOF'
Usage: oooconf remove

Remove managed links without restoring backups.
EOF
      ;;
    lock)
      cat <<'EOF'
Usage: oooconf lock

Regenerate dependency lock artifacts from pinned refs in scripts/setup.sh.
EOF
      ;;
    update-pins)
      cat <<'EOF'
Usage: oooconf update-pins [--apply]

Compare pinned git refs to upstream HEAD and refresh lock artifacts.
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
Usage: oooconf secrets <sync|doctor> [options]

Render or validate local secret env files from the tracked template.
Examples:
  oooconf secrets login
  eval "$(oooconf secrets unlock --shell zsh)"
  oooconf secrets sync
  oooconf secrets sync --dry-run
  oooconf secrets doctor

Environment overrides:
  OOODNAKOV_SECRETS_BACKEND
  OOODNAKOV_BW_SERVER
EOF
      ;;
    version)
      cat <<'EOF'
Usage: oooconf version

Print the CLI version and resolved repo root.
EOF
      ;;
    ""|-h|--help|help)
      usage
      ;;
    *)
      echo "Unknown command: $command" >&2
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
      echo "$REPO_ROOT"
      exit 0
      ;;
    -V|--version)
      echo "oooconf $(print_version)"
      echo "$REPO_ROOT"
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
      command_usage "${2:-}"
      exit 0
      ;;
    version)
      echo "oooconf $(print_version)"
      echo "$REPO_ROOT"
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      command="$1"
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
    if ! command -v python3 >/dev/null 2>&1; then
      echo "python3 is required to generate dependency lock artifacts." >&2
      exit 1
    fi
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" python3 "$GEN_LOCK" "$@"
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
    if ! command -v python3 >/dev/null 2>&1; then
      echo "python3 is required for secrets sync." >&2
      exit 1
    fi
    exec "$(command -v env)" OOODNAKOV_REPO_ROOT="$REPO_ROOT" python3 "$RENDER_SECRETS" --repo-root "$REPO_ROOT" "$@"
    ;;
  *)
    echo "Unknown command: $command" >&2
    usage >&2
    exit 1
    ;;
esac
