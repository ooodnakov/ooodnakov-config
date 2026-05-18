#!/usr/bin/env bash
# Sourced by scripts/setup/ooodnakov.sh; do not execute directly.

print_help_for_scope() {
  local scope="${1:-main}"

  case "$scope" in
    shell)
      handle_shell_command help
      ;;
    color)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf color [status|list|<theme>|dark|light]

Set or inspect the oooconf CLI color theme and dark/light mode.
Themes:
  default, catppuccin, gruvbox, nord, tokyonight, noctalia
Modes:
  dark, light
Examples:
  oooconf color status
  oooconf color list
  oooconf color catppuccin
  oooconf color noctalia
  oooconf color light
EOF
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
  ui_banner
  ui_spacer
  printf '%s\n' "$(ui_colorize "section" "Usage: oooconf [global options] <command> [command options]")"
  printf '%s\n' "$(ui_colorize "muted" "A reproducible cross-platform dotfiles manager with setup, health checks, secrets, and shell tooling.")"

  ui_spacer
  ui_separator
  ui_section_fancy "version" "Global options"
  cat <<EOF
  -C, --repo-root PATH  run against a specific repo checkout
  -h, --help            show this help
  -n, --dry-run         add --dry-run to install or update
      --yes-optional    auto-accept optional dependency installs
      --skip-deps       skip dependency installation
  -V, --version         show CLI version information
      --print-repo-root print the resolved repo root and exit
EOF

  ui_spacer
  ui_separator
  ui_section_fancy "install" "Setup"
  ui_command_row "bootstrap" "clone/update repo then run install"
  ui_command_row "install" "apply managed config and optional dependency installs"
  ui_command_row "deps" "install optional dependencies only"
  ui_command_row "update" "pull repo with --ff-only, then re-run install"

  ui_spacer
  ui_section_fancy "doctor" "Inspect & Validate"
  ui_command_row "doctor" "validate managed symlinks, shell runtimes, and required commands"
  ui_command_row "dry-run" "preview install flow without mutating filesystem"
  ui_command_row "version" "print CLI version and repo root"

  ui_spacer
  ui_section_fancy "lock" "Manage State"
  ui_command_row "delete" "remove managed links and restore latest backups"
  ui_command_row "remove" "remove managed links only (no backup restore)"
  ui_command_row "lock" "regenerate dependency lock artifacts from pinned refs"
  ui_command_row "update-pins" "compare/update pinned refs and refresh lock artifacts"
  ui_command_row "completions" "regenerate tracked shell completions (autogen + oooconf)"
  ui_command_row "link" "inspect or manage links from the symlink manifest"

  ui_spacer
  ui_section_fancy "shell" "Shell / Secrets / Agents"
  ui_command_row "shell" "manage local shell preferences such as forgit aliases"
  ui_command_row "color" "set a unified oooconf CLI color theme"
  ui_command_row "secrets" "sync or validate local secret env files"
  ui_command_row "agents" "detect/sync/doctor/update AGENTS.md and agent CLI workflows"

  ui_spacer
  ui_separator
  cat <<EOF | ui_render_help_block
Aliases:
  check -> doctor
  preview -> dry-run
  upgrade -> update
Getting help:
  oooconf --help                     show this message
  oooconf help <command>             show command-specific help
  oooconf help secrets               show secrets subcommand help
UI controls:
  OOOCONF_COLOR=always|never|auto    override color output
  OOOCONF_ASCII=1                    force ASCII icons and borders
  OOOCONF_THEME=<theme>              set the CLI color theme for this run
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
      cat <<'EOF' | ui_render_help_block
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
      cat <<'EOF' | ui_render_help_block
Usage: oooconf install [--dry-run] [--yes-optional] [--skip-deps]

Apply managed config and optional dependency installation.
Creates symlinks from tracked config in home/ to their target locations,
backing up any replaced files. Optionally installs dependencies when
allowed.
Examples:
  oooconf install                      # interactive dependency prompts
  oooconf install --yes-optional       # auto-accept all optional installs
  oooconf install --skip-deps          # apply config without dependency installs
  oooconf install --dry-run            # preview without making changes
EOF
      ;;
    deps)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf deps [--dry-run] [--all] [dependency-key...]

Install optional dependencies only. Without dependency keys, an interactive
gum-based multi-select picker is used when available.
Dependency keys match those defined in deps.lock.json. Common keys include:
bat, delta, eza, fd, fzf, gum, glow, rg, yazi, ffmpeg, jq, p7zip, poppler, zoxide, and others.
Examples:
  oooconf deps                         # interactive picker (when gum available)
  oooconf deps <key...>                # specific tools (see optional-deps.toml for keys)
  oooconf deps --dry-run               # preview installation
  oooconf deps --all                   # install all dependency keys
EOF
      ;;
    update)
      cat <<'EOF' | ui_render_help_block
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
      cat <<'EOF' | ui_render_help_block
Usage: oooconf doctor

Validate managed symlinks, shell runtimes, and required commands.
Checks that managed config links point to valid targets, key tools are
available on PATH, and pinned zsh runtime checkouts are complete.
Examples:
  oooconf doctor                       # run all checks
EOF
      ;;
    dry-run)
      cat <<'EOF' | ui_render_help_block
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
      cat <<'EOF' | ui_render_help_block
Usage: oooconf delete [--dry-run]

Remove managed links and restore the latest backups when available.
Use this to undo the managed config and return to your previous state.
Backup files are stored in ~/.local/state/ooodnakov-config/backups/.
Examples:
  oooconf delete                       # restore from backups
  oooconf delete --dry-run            # preview without making changes
EOF
      ;;
    remove)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf remove [--dry-run]

Remove managed links without restoring backups.
Use this when you want to cleanly remove the managed config without
attempting to restore previous configurations.
Examples:
  oooconf remove                       # clean removal
  oooconf remove --dry-run            # preview without making changes
EOF
      ;;
    lock)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf lock [--dry-run]

Regenerate dependency lock artifacts from managed tool refs.
Reads pinned versions from scripts/optional-deps.toml and writes
the resolved lock file to deps.lock.json.
Examples:
  oooconf lock                         # regenerate lock artifact
  oooconf lock --dry-run              # preview without making changes
EOF
      ;;
    update-pins)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf update-pins [--apply] [--offline] [--dry-run]

Compare pinned git refs in scripts/optional-deps.toml to upstream HEAD.
Without --apply, reports differences and refreshes lock artifacts. With --apply,
updates pinned refs in the catalog and regenerates lock artifacts.
Examples:
  oooconf update-pins                  # check for pin drift
  oooconf update-pins --apply          # update pins and regenerate lock
  oooconf update-pins --offline --dry-run # validate local catalog parsing
EOF
      ;;
    completions)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf completions [--dry-run]

Regenerate tracked shell completion files:
  - autogen zsh completions under home/.config/ooodnakov/zsh/completions/autogen
  - oooconf command completions for zsh and PowerShell
This does not install dependencies; it only rebuilds completion files.
Examples:
  oooconf completions                  # rebuild tracked completion files
  oooconf completions --dry-run        # preview generation actions
EOF
      ;;
    link)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf link [--dry-run]

Create or update symlinks from tracked config in home/ to their target
locations, backing up any replaced files. Reads from links.toml manifest
with auto-discovery for home/.config, home/.local, and home/.glzr.
Examples:
  oooconf link                       # create/update all manifest links
  oooconf link --dry-run            # preview without making changes
EOF
      ;;
    agents)
      cat <<'EOF' | ui_render_help_block

Usage: oooconf agents <detect|sync|doctor|install|provider|update|mcp|rtk|skills> [options]

Manage shared AGENTS.md instructions and validate configured agent tooling.
Subcommands:
  detect [--json]       detect configured agent CLIs on PATH
  sync [--check] [--materialize-secrets]
                        append/update shared AGENTS.md managed block
  doctor [--strict-config-paths]
                        verify AGENTS.md managed block and default agent config paths
  install [<agent> ...] [--all|--missing] [--check]
                        install missing, selected, or all configured agent CLIs
  update [--check]      update installed agent CLIs (pnpm-based tools use pnpm)
  provider sync minimax [--check] [--region global|china] [--materialize-secrets]
                        configure MiniMax-M2.7 backends for Claude Code, OpenCode, and Codex CLI
  mcp sync|status       synchronize or inspect managed MCP servers
  rtk init [--check]    initialize RTK hooks for detected agents
  mcp add [--name N] [--json JSON] [--multi] [--preview] [--sync-now]
                        add one MCP JSON server entry to shared config
  skills sync [--check] sync configured skill specs across agents
  skills view [--check] [--json]
                        list global shared skills catalog via pnpm dlx
  skills add <source> [--agent gemini] [--sync-now]
                        add one shared skill source (e.g. vercel-labs/agent-skills)
Examples:
  oooconf agents detect                 # list available agent CLIs
  oooconf agents sync --check           # verify AGENTS.md managed sections
  oooconf agents install --check        # preview missing agent CLI installs
  oooconf agents install codex gemini   # install selected agent CLIs
  oooconf agents mcp status             # show managed MCP server status
  oooconf agents provider sync minimax   # configure MiniMax-M2.7 provider backends
  oooconf agents skills view --json     # show shared skills catalog as JSON
EOF
      ;;
    secrets)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf secrets <sync|doctor|list|status|login|unlock|logout|add|remove> [options]

Render or validate local secret env files from the tracked template.
Examples:
  oooconf secrets                      # show current sync/session status
  oooconf secrets login                # choose login method interactively
  oooconf secrets login --method apikey
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
    minimal)
      cat <<'EOF' | ui_render_help_block
Usage: oooconf minimal [--dry-run]

Install minimal required dependencies for managed config.
Examples:
  oooconf minimal                       # install minimal deps
  oooconf minimal --dry-run            # preview without making changes
EOF
      ;;
    shell)
      handle_shell_command help
      ;;
    color)
      handle_color_command help
      ;;
    version)
      cat <<'EOF' | ui_render_help_block
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
