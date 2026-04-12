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

  Secrets:
    secrets               sync or validate local secret env files

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
bat, delta, eza, fd, fzf, gum, glow, ripgrep, zoxide, and others.

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
    secrets)
      cat <<'EOF'
Usage: oooconf secrets <sync|doctor|list|status|login|unlock|logout> [options]

Render or validate local secret env files from the tracked template.
Examples:
  oooconf secrets login
  eval "$(oooconf secrets unlock --shell zsh)"
  oooconf secrets sync
  oooconf secrets sync --dry-run
  oooconf secrets list
  oooconf secrets list --resolved
  oooconf secrets status
  oooconf secrets doctor
  oooconf secrets logout

Environment overrides:
  OOODNAKOV_SECRETS_BACKEND
  OOODNAKOV_BW_SERVER
EOF
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
