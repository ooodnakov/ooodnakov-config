#!/usr/bin/env python3
"""Render oooconf help text and typo suggestions from the canonical CLI spec."""

from __future__ import annotations

import argparse
import contextlib
import io
import os
import re
import sys
from collections.abc import Iterable
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import cli_ui  # noqa: E402
from oooconf_cli_spec import CliSpec, Command, load_cli_spec  # noqa: E402

DEFAULT_REPO_ROOT = SCRIPT_DIR.parents[1]
SPEC_REL_PATH = Path("scripts/cli/oooconf-cli-spec.toml")

MAIN_GROUPS: tuple[tuple[str, str, tuple[str, ...]], ...] = (
    ("install", "Setup", ("bootstrap", "install", "deps", "update")),
    (
        "doctor",
        "Inspect & Validate",
        ("doctor", "status", "snapshot", "plan", "apply", "rollback", "dry-run", "version"),
    ),
    ("lock", "Manage State", ("delete", "remove", "lock", "update-pins", "completions", "link")),
    ("shell", "Shell / Secrets / Agents", ("shell", "color", "delta", "secrets", "env", "agents", "fleet", "wm")),
)

HIDDEN_FROM_MAIN = {"help", "minimal", "komorebi"}

HELP_HEADINGS = {
    "Aliases:",
    "Auto UV environment options:",
    "Available modes:",
    "Bars:",
    "Common workflows:",
    "Environment overrides:",
    "Examples:",
    "Exit codes:",
    "Forgit alias modes:",
    "Getting help:",
    "Global options:",
    "Hosts:",
    "Mode values:",
    "Modes:",
    "Note:",
    "Options:",
    "Output:",
    "PSFzf options:",
    "Prompt options:",
    "Repo root:",
    "Safety:",
    "Subcommands:",
    "Themes:",
    "Transport:",
    "Typo handling modes:",
    "UI controls:",
    "Window managers:",
}

_HINT_LINE_RE = re.compile(r"^\s+(?:oooconf\b|OOODNAKOV_|OOOCONF_|\$env:OOOCONF_|\./scripts/|eval\s+\"\$\(oooconf\b)")


def resolve_platform(platform: str) -> str:
    """Resolve 'auto' to 'windows' or 'unix'."""
    if platform in {"unix", "windows"}:
        return platform
    return "windows" if sys.platform == "win32" else "unix"


def load_spec(repo_root: Path) -> CliSpec:
    """Load the canonical CLI spec from repo_root."""
    return load_cli_spec(repo_root / SPEC_REL_PATH)


def render_help_block(text: str) -> str:
    """Apply cli_ui colors to a multi-line help block."""
    lines: list[str] = []
    for line in text.splitlines():
        if line.startswith("Usage:"):
            lines.append(cli_ui.colorize(line, "section"))
        elif line in HELP_HEADINGS or (line.startswith("Checks ") and line.endswith(":")):
            lines.append(cli_ui.colorize(line, "info"))
        elif _HINT_LINE_RE.match(line):
            lines.append(cli_ui.colorize(line, "hint"))
        else:
            lines.append(line)
    return "\n".join(lines)


def resolve_command_alias(command: str, spec: CliSpec) -> str:
    """Resolve a command alias via the spec (e.g., check -> doctor)."""
    aliases = spec.aliases()
    return aliases.get(command, command)


def edit_distance(left: str, right: str) -> int:
    """Compute Levenshtein edit distance between two strings."""
    if left == right:
        return 0
    if not left:
        return len(right)
    if not right:
        return len(left)

    previous = list(range(len(right) + 1))
    for i, left_char in enumerate(left, start=1):
        current = [i]
        for j, right_char in enumerate(right, start=1):
            cost = 0 if left_char == right_char else 1
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost))
        previous = current
    return previous[-1]


def known_commands(spec: CliSpec, platform: str = "auto") -> list[str]:
    """Return known top-level command names from the spec."""
    if platform == "windows":
        return [name for name, cmd in spec.commands.items() if "windows" in cmd.platforms]
    return spec.command_names()


def suggest_from_candidates(value: str, candidates: Iterable[str]) -> str | None:
    """Return the closest candidate within the edit-distance threshold, or None."""
    if not value:
        return None

    best_match: str | None = None
    best_distance = sys.maxsize
    for candidate in candidates:
        text = candidate.strip()
        if not text:
            continue
        distance = edit_distance(value, text)
        if distance < best_distance:
            best_distance = distance
            best_match = text

    threshold = 2 if len(value) <= 4 else 3
    return best_match if best_distance <= threshold else None


def suggest_command(value: str, spec: CliSpec, platform: str = "auto") -> str | None:
    """Return the closest matching known command for a mistyped input."""
    return suggest_from_candidates(value, known_commands(spec, platform=platform))


def _format_global_options(spec: CliSpec) -> str:
    """Format the global options block, reflecting spec options cleanly."""
    rows: list[tuple[str, str]] = [
        ("  -C, --repo-root PATH", spec.global_options.get("--repo-root", "set repo root path")),
        ("      --profile NAME", spec.global_options.get("--profile", "select portable capability profile")),
        ("  -h, --help", spec.global_options.get("--help", "show help")),
        ("  -n, --dry-run", spec.global_options.get("--dry-run", "preview actions without changing files")),
        (
            "      --yes-optional",
            spec.global_options.get("--yes-optional", "auto-confirm optional dependency installs"),
        ),
        ("      --skip-deps", spec.global_options.get("--skip-deps", "skip dependency installation")),
        ("      --no-deps", spec.global_options.get("--no-deps", "alias for --skip-deps")),
        ("      --all", spec.global_options.get("--all", "select all dependency keys at once")),
        ("      --latest", spec.global_options.get("--latest", "install latest manager-backed dependency versions")),
        ("  -V, --version", spec.global_options.get("--version", "show version")),
        ("      --print-repo-root", spec.global_options.get("--print-repo-root", "print resolved repo root")),
    ]
    handled = {
        "-C",
        "--repo-root",
        "--profile",
        "-h",
        "--help",
        "-n",
        "--dry-run",
        "--yes-optional",
        "--skip-deps",
        "--no-deps",
        "--all",
        "--latest",
        "-V",
        "--version",
        "--print-repo-root",
    }
    for opt, desc in spec.global_options.items():
        if opt not in handled:
            rows.append((f"      {opt}", desc))

    width = max(len(label) for label, _ in rows) + 2
    return "\n".join(f"{label:<{width}}{desc}" for label, desc in rows)


def render_main(spec: CliSpec, repo_root: Path, platform: str = "auto") -> str:
    """Render main `oooconf --help` usage output."""
    resolved_platform = resolve_platform(platform)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        cli_ui.banner()
        cli_ui.spacer()
        print(cli_ui.colorize("Usage: oooconf [global options] <command> [command options]", "section", bold=True))
        print(
            cli_ui.colorize(
                "A reproducible cross-platform dotfiles manager with setup, health checks, secrets, and shell tooling.",
                "muted",
            )
        )

        cli_ui.spacer()
        cli_ui.separator()
        cli_ui.section_fancy("version", "Global options")
        print(_format_global_options(spec))

        listed: set[str] = set()
        for icon_name, title, names in MAIN_GROUPS:
            cli_ui.spacer()
            if icon_name == "install":
                cli_ui.separator()
            cli_ui.section_fancy(icon_name, title)
            for name in names:
                cmd = spec.commands.get(name)
                if cmd is None:
                    continue
                listed.add(name)
                cli_ui.command_row(name, cmd.description)

        aliases = spec.aliases()
        extra_commands = [
            (name, cmd)
            for name, cmd in spec.commands.items()
            if name not in listed and name not in aliases and name not in HIDDEN_FROM_MAIN
        ]
        if extra_commands:
            cli_ui.spacer()
            cli_ui.section_fancy("default", "Other")
            for name, cmd in extra_commands:
                cli_ui.command_row(name, cmd.description)

        cli_ui.spacer()
        cli_ui.separator()

        footer_parts: list[str] = ["Aliases:"]
        for alias_name, target in aliases.items():
            footer_parts.append(f"  {alias_name} -> {target}")

        if resolved_platform == "windows":
            footer_parts.extend(
                [
                    "Note:",
                    "  bootstrap is Unix-only in this wrapper.",
                    "  On Windows, run `scripts/setup/setup.ps1 install` for initial setup.",
                ]
            )

        footer_parts.extend(
            [
                "Getting help:",
                "  oooconf --help                     show this message",
                "  oooconf help <command>             show command-specific help",
                "  oooconf help secrets               show secrets subcommand help",
            ]
        )

        if resolved_platform == "windows":
            footer_parts.extend(
                [
                    "UI controls:",
                    "  $env:OOOCONF_COLOR='always'        override color output",
                    "  $env:OOOCONF_ASCII='1'             force ASCII icons and borders",
                    "  $env:OOOCONF_THEME='<theme>'       set the CLI color theme for this run",
                ]
            )
        else:
            footer_parts.extend(
                [
                    "UI controls:",
                    "  OOOCONF_COLOR=always|never|auto    override color output",
                    "  OOOCONF_ASCII=1                    force ASCII icons and borders",
                    "  OOOCONF_THEME=<theme>              set the CLI color theme for this run",
                ]
            )

        footer_parts.extend(
            [
                "  Nerd Font icons render automatically on UTF-8 terminals; ASCII tags are",
                "  used when output is redirected or the glyphs are unavailable.",
                "Common workflows:",
            ]
        )
        if resolved_platform == "windows":
            footer_parts.extend(
                [
                    "  # Initial setup on Windows:",
                    "  ./scripts/setup/setup.ps1 install",
                ]
            )
        else:
            footer_parts.extend(
                [
                    "  # Initial setup on a new machine:",
                    "  oooconf bootstrap",
                ]
            )

        footer_parts.extend(
            [
                "  # Preview what install would do:",
                "  oooconf dry-run",
                "  # Apply config and install dependencies:",
                "  oooconf install",
                "  oooconf deps",
                "  # Check if everything is set up correctly:",
                "  oooconf doctor",
                "  # Update to latest config:",
                "  oooconf update",
                "Repo root:",
                f"  {repo_root}",
            ]
        )
        print(render_help_block("\n".join(footer_parts)))

    return buf.getvalue()


def _command_help_blocks(platform: str) -> dict[str, str]:
    """Return curated per-command help blocks preserving all usage lines, options, and examples."""
    apply_platform = "windows" if platform == "windows" else "linux"
    secrets_unlock_example = (
        "  oooconf secrets unlock --shell pwsh | Invoke-Expression"
        if platform == "windows"
        else '  eval "$(oooconf secrets unlock --shell zsh)"'
    )

    return {
        "bootstrap": """\
Usage: oooconf bootstrap

Clone or update the configured repo checkout, then run the install flow.
This is the recommended first command on a new machine. It handles repo
cloning (if missing), pulls latest changes, and runs the full install.
Environment overrides:
  OOODNAKOV_CONFIG_DIR            custom config directory
  OOODNAKOV_CONFIG_BRANCH         git branch to checkout (default: main)
  OOODNAKOV_CONFIG_REPO_URL       SSH repo URL for git clone
  OOODNAKOV_CONFIG_HTTPS_REPO_URL HTTPS repo URL for git clone
  OOODNAKOV_INTERACTIVE           set to "never" to skip all prompts
Examples:
  oooconf bootstrap
  OOODNAKOV_INTERACTIVE=never oooconf bootstrap""",
        "install": """\
Usage: oooconf install [--dry-run] [--yes-optional] [--skip-deps] [--profile NAME] [--minimal] [--min-dep]

Apply managed config and optional dependency installation.
Creates symlinks from tracked config in home/ to their target locations,
backing up any replaced files. Optionally installs dependencies when
allowed.
Examples:
  oooconf install                      # interactive dependency prompts
  oooconf install --yes-optional       # auto-accept all optional installs
  oooconf install --skip-deps          # apply config without dependency installs
  oooconf install --profile terminal   # apply only terminal-profile managed links
  oooconf install --minimal            # minimal profile links (sparse checkout safe)
  oooconf install --minimal --min-dep  # minimal links plus minimal dependencies
  oooconf install --dry-run            # preview without making changes""",
        "deps": """\
Usage: oooconf deps [--dry-run] [--yes-optional] [--all] [--latest] [--min-dep] [dependency-key...]

Install optional dependencies only. Without dependency keys, an interactive
gum-based multi-select picker is used when available.
GitHub release installs are tracked by marcosnils/bin. Use --latest to run
Topgrade with bounded retries; it invokes `bin update` and reports individual
manager failures as warnings. Set OOODNAKOV_DEPS_LATEST_STRICT=1 to fail instead.
GitHub auth uses GITHUB_AUTH_TOKEN, falling back to GITHUB_TOKEN.
All dependency metadata (versions, URLs, and install methods) lives in scripts/optional-deps.toml
and deps.lock.json.
Examples:
  oooconf deps                         # interactive picker (when gum available)
  oooconf deps <key...>                # specific tools (see scripts/optional-deps.toml for keys)
  oooconf deps --dry-run               # preview installation
  oooconf deps --all                   # install all dependency keys
  oooconf deps --min-dep               # install only the [minimal] dependency set
  oooconf deps --latest <key...>       # update manager-backed tools to latest""",
        "update": """\
Usage: oooconf update [--dry-run] [--yes-optional] [--no-deps] [--profile NAME] [--min-dep]

Pull the repo with --ff-only, then re-run the install flow.
Use this to update your config to the latest tracked state. It performs
a fast-forward pull only, failing if local changes would prevent it.
Examples:
  oooconf update                       # pull and reinstall
  oooconf update --yes-optional        # also install missing dependencies
  oooconf update --no-deps             # skip optional dependency installation
  oooconf update --dry-run             # preview pull and install""",
        "doctor": """\
Usage: oooconf doctor [--format text|json] [--platform linux|macos|windows] [--profile NAME]

Emit stable, versioned checks with severity and remediation. Exits non-zero when
one or more checks have error status.
Examples:
  oooconf doctor                       # run all checks
  oooconf doctor --format json         # machine-readable contract""",
        "status": """\
Usage: oooconf status [--format text|json] [--platform linux|macos|windows] [--profile NAME]

Summarize the selected profile, managed links, dependency availability,
incomplete transactions, and generated artifact drift without mutation.
Examples:
  oooconf status
  oooconf status --format json""",
        "snapshot": """\
Usage: oooconf snapshot <export|inspect|apply> [options]

Export only allowlisted portable preferences and capabilities to TOML, validate
and preview an import, or apply it through the planner and transaction executor.
Examples:
  oooconf snapshot export --profile terminal --output terminal.toml
  oooconf snapshot inspect terminal.toml --format json
  oooconf snapshot apply terminal.toml""",
        "dry-run": """\
Usage: oooconf dry-run [--format text|json] [--scope install|links] [--platform linux|macos|windows] [--profile NAME] [dependency-key...]

Compatibility alias for `oooconf plan`. Builds a validated operation plan without
changing the filesystem.
Examples:
  oooconf dry-run                      # preview install
  oooconf dry-run --format json        # emit versioned JSON""",
        "plan": """\
Usage: oooconf plan [--format text|json] [--scope install|links] [--platform linux|macos|windows] [--profile NAME] [dependency-key...]

Build a deterministic, validated operation plan without changing the filesystem.
JSON output is versioned for automation. Dependency keys are validated against the
shared optional dependency catalog.

Examples:
  oooconf plan
  oooconf plan --format json
  oooconf plan --scope links
  oooconf plan --profile workstation
  oooconf plan bat zoxide --format json""",
        "apply": f"""\
Usage: oooconf apply [--platform linux|macos|windows] [--profile NAME]

Validate and transactionally apply managed links. The command uses an exclusive
cross-process lock and writes an atomic journal under the oooconf state directory.
An identical second apply is a no-op.

Examples:
  oooconf apply
  oooconf apply --platform {apply_platform}""",
        "rollback": """\
Usage: oooconf rollback --last

Reverse the latest eligible managed-link transaction. Rollback removes only links
created by that transaction, restores its backups, and refuses to delete or replace
user-modified targets.

Examples:
  oooconf rollback --last""",
        "delete": """\
Usage: oooconf delete [--dry-run]

Remove managed links and restore the latest backups when available.
Use this to undo the managed config and return to your previous state.
Backup files are stored in ~/.local/state/ooodnakov-config/backups/.
Examples:
  oooconf delete                       # restore from backups
  oooconf delete --dry-run             # preview without making changes""",
        "remove": """\
Usage: oooconf remove [--dry-run]

Remove managed links without restoring backups.
Use this when you want to cleanly remove the managed config without
attempting to restore previous configurations.
Examples:
  oooconf remove                       # clean removal
  oooconf remove --dry-run             # preview without making changes""",
        "lock": """\
Usage: oooconf lock [--dry-run]

Regenerate dependency lock artifacts from managed tool refs.
Reads pinned versions from scripts/optional-deps.toml and writes
the resolved lock file to deps.lock.json.
Examples:
  oooconf lock                         # regenerate lock artifact
  oooconf lock --dry-run               # preview without making changes""",
        "update-pins": """\
Usage: oooconf update-pins [--apply] [--offline] [--dry-run]

Compare pinned git refs in scripts/optional-deps.toml to upstream HEAD.
Without --apply, reports differences and refreshes lock artifacts. With --apply,
updates pinned refs in the catalog and regenerates lock artifacts.
Examples:
  oooconf update-pins                  # check for pin drift
  oooconf update-pins --apply          # update pins and regenerate lock
  oooconf update-pins --offline --dry-run # validate local catalog parsing""",
        "completions": """\
Usage: oooconf completions [--dry-run]

Regenerate completion files:
  - autogen zsh completions under home/.config/ooodnakov/zsh/completions/autogen
  - oooconf command completions for zsh and PowerShell
  - PowerShell tool-completion cache under ~/.cache/ooodnakov-config/completions
This does not install dependencies; it only rebuilds completion files.
Examples:
  oooconf completions                  # rebuild tracked completion files
  oooconf completions --dry-run        # preview generation actions""",
        "link": """\
Usage: oooconf link [--dry-run]

Create or update symlinks from tracked config in home/ to their target
locations, backing up any replaced files. Reads from links.toml manifest
with auto-discovery for home/.config, home/.local, and home/.glzr.
Examples:
  oooconf link                         # create/update all manifest links
  oooconf link --dry-run               # preview without making changes""",
        "agents": """\
Usage: oooconf agents <detect|sync|doctor|install|provider|update|mcp|rtk|skills> [options]

Manage shared AGENTS.md instructions and validate configured agent tooling.
Subcommands:
  detect [--json]        detect configured agent CLIs on PATH
  sync [--check] [--agents A...] [--select] [--materialize-secrets]
                         sync managed policy/MCP blocks into global agent configs
  doctor [--strict-config-paths]
                         verify managed blocks and default agent config paths
  install [<agent> ...] [--all|--missing] [--check]
                         install missing, selected, or all configured agent CLIs
  update [--check]       update installed agent CLIs (pnpm-based tools use pnpm)
  provider sync minimax [--check] [--region global|china] [--agents A...] [--select]
                         configure MiniMax-M2.7 backends for Claude Code, OpenCode, and Codex CLI
  mcp sync [--check] [--servers S...] [--select]
  mcp status             clone/pull managed MCP servers; show status
  mcp add [--name N] [--json JSON] [--multi] [--preview] [--sync-now]
                         add MCP JSON entries to shared config
  rtk init [--check]     initialize RTK hooks for detected agents
  skills sync [--check] [--agents A...] [--select]
                         sync configured skill specs across agents
  skills view [--check] [--json]
                         list global shared skills catalog via pnpm dlx
  skills add <source> [--sync-now]
                         add one shared skill source
Examples:
  oooconf agents detect
  oooconf agents sync --check
  oooconf agents sync --agents claude
  oooconf agents install --check
  oooconf agents install codex qwen
  oooconf agents mcp status
  oooconf agents provider sync minimax --agents codex
  oooconf agents skills view --json""",
        "fleet": """\
Usage: oooconf fleet sync [HOST...] [--all] [--repo-path PATH] [--branch NAME]
                         [--jobs N] [--resolve] [--no-push] [--format text|json]
                         [--dry-run]

Pull this repo's latest changes on SSH fleet hosts.
Per host: stash local work, rebase onto the remote branch, restore the stash,
push commits that exist only on that host, then run oooconf update --no-deps.
An omp agent is only spawned when --resolve is passed.
Hosts:
  HOST...                SSH config aliases from ~/.ssh/config and included files
  --all                  select every host alias; wildcard patterns are skipped
Checks (per host, before anything else runs):
  ssh reachable, user is not root, the repo path exists, the machine is not
  this one; aliases sharing a HostName and Port are deduped and skipped.
Options:
  --repo-path PATH       remote repo path (default: oooconf --print-repo-root)
  --branch NAME          remote branch (default: checked-out branch's upstream)
  --jobs N               parallel hosts (default: 4)
  --resolve              after the run, let omp fix unfinished hosts: one host
                         gets a remote agent, several get one local agent that
                         ssh's out; the agent receives each host's status
  --no-push              never push commits that exist only on the host
  --format text|json     output format (default: text)
  --dry-run              inspect repo/branch/dirty/ahead/behind only
Output:
  live per-step activity (connecting, preflight, repo, fetch, stash, pull,
  push, link refresh) as an in-place spinner with oooconf colors and Nerd
  Font icons; when stdout is piped (or OOOCONF_UI=stdout) each step prints on
  its own line. PowerShell pipes native output, so an attached console still
  gets live colored output. Then one status line per host, then the summary.
  --format json prints only the JSON document.
Transport:
  one persistent ssh session per host (sh -l), so every step shares a single
  connection; a transient connection error is retried once per call. Each
  command prepends ~/.local/bin, ~/.bun/bin, ~/.cargo/bin, ~/.local/share/pnpm
  and ~/bin to PATH, because a non-interactive login sh often lacks the user
  bins that hold oooconf, omp, and bun.
Safety:
  Without --resolve, a conflict keeps the stash in place and stops before update.
  With --resolve the streamed per-host status is followed by the agent, which
  fixes conflicts; the sync then restores the stash, pushes host-only commits,
  and re-runs the links.
  --dry-run performs no fetch, stash, pull, push, or link refresh.
  A spawned omp agent is announced, its output is streamed and rendered as
  Markdown (headings, lists, tables, fenced code, emphasis), and the command
  waits for it to finish before continuing.
Exit codes:
  0 ok, dry-run, and skipped hosts       2 at least one conflict       1 failure
Examples:
  oooconf fleet sync --all --format json
  oooconf fleet sync orange site
  oooconf fleet sync --all --resolve
  oooconf fleet sync site --dry-run""",
        "secrets": f"""\
Usage: oooconf secrets <sync|doctor|list|status|login|unlock|logout|add|remove> [options]

Render or validate local secret env files from the tracked template.
Examples:
  oooconf secrets                      # show current sync/session status
  oooconf secrets login                # choose login method, then unlock prompt
  oooconf secrets login --method apikey
  oooconf secrets unlock               # prompt for password and save session
  oooconf secrets unlock 'your-password'
{secrets_unlock_example}
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
  OOODNAKOV_BW_SERVER""",
        "env": """\
Usage: oooconf env [KEY VALUE] [--secrets]

Add or update KEY in the preserved LOCAL OVERRIDES blocks of env.zsh and env.ps1.
With no arguments, prompt for the name and hidden value, then optionally upload it
to Bitwarden (the default is no).
Examples:
  oooconf env SUPER_TOKEN dsadadasasdasddas
  oooconf env SUPER_TOKEN dsadadasasdasddas --secrets
  oooconf env                            # interactive flow
  oooconf env help""",
        "minimal": """\
Usage: oooconf minimal [--min-dep] [--dry-run]

Link the minimal shell profile (sparse-checkout friendly). Dependencies are
installed only with --min-dep, which installs the [minimal] key set.
Examples:
  oooconf minimal                      # minimal config, no dependency installs
  oooconf minimal --min-dep            # minimal config plus minimal dependencies
  oooconf minimal --dry-run            # preview without making changes""",
        "shell": """\
Usage: oooconf shell status
       oooconf shell prompt [p10k|ohmyposh|status]
       oooconf shell prompt-style [verbose|concise|status]
       oooconf shell forgit-aliases [plain|forgit|status]
       oooconf shell typo-handling [silent|suggest|help|status]
       oooconf shell psfzf-tab [enabled|disabled|status]
       oooconf shell psfzf-git [enabled|disabled|status]
       oooconf shell poshgit [enabled|disabled|status]
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
  poshgit    enable or disable posh-git auto-import in PowerShell
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
  oooconf shell poshgit enabled
  oooconf shell poshgit disabled
  oooconf shell auto-uv-env existing
  oooconf shell auto-uv-env disabled""",
        "color": """\
Usage: oooconf color [status|list|<theme>|dark|light]

Set or inspect the oooconf CLI color theme and dark/light mode.
Themes:
  default, catppuccin, gruvbox, nord, tokyonight, noctalia
Modes:
  dark, light
This also syncs theme-friendly overrides for yazi, wezterm and ghostty local overrides, komorebi/komorebi.bar, sketchybar colors, zebar css vars, and themed oh-my-posh config.
Status output also reports detected nvim and oh-my-posh theme config state.
Examples:
  oooconf color status                 # print current theme and synced config state
  oooconf color list                   # list available themes
  oooconf color catppuccin             # switch to Catppuccin colors
  oooconf color noctalia               # switch to Noctalia colors
  oooconf color light                  # switch to light mode""",
        "delta": """\
Usage: oooconf delta <inject|status|remove>

Configure git-delta as the git pager and diff viewer.
Subcommands:
  inject          write delta git config to ~/.gitconfig (idempotent, warns if present)
  status          check whether delta is configured in ~/.gitconfig
  remove          remove ooodnakov's delta config block from ~/.gitconfig
Examples:
  oooconf delta inject
  oooconf delta status
  oooconf delta remove""",
        "version": """\
Usage: oooconf version

Print the CLI version (git describe or commit SHA) and resolved repo root.
Examples:
  oooconf version                      # show version and repo path""",
        "wm": """\
Usage: oooconf wm status
       oooconf wm set [komorebi|glazewm|aerospace|omniwm]
       oooconf wm start
       oooconf wm stop
       oooconf wm reload
       oooconf wm bar set <zebar|yabs|sketchybar> [name]
       oooconf wm bar zebar-config status
       oooconf wm bar zebar-config list
       oooconf wm bar zebar-config set <name>
       oooconf wm komorebi status
       oooconf wm komorebi reload
       oooconf wm komorebi start [--bar]
       oooconf wm komorebi stop [--bar]

Switch between or manage window managers and status bars.
Window managers:
  komorebi, glazewm, aerospace, omniwm
Bars:
  zebar, yabs, sketchybar
Subcommands:
  status         shows the currently running window manager
  set            stops the current WM and starts the specified one
  start          starts the default WM
  stop           stops any running WM stack
  reload         reloads the configuration of the active WM
  bar            manage bar and zebar (set, zebar-config, start, stop, reload)
  komorebi       manage komorebi (status, reload, start, stop) with optional --bar
Examples:
  oooconf wm status
  oooconf wm set komorebi
  oooconf wm set glazewm
  oooconf wm set aerospace
  oooconf wm reload
  oooconf wm bar set zebar overline-zebar-komorebi
  oooconf wm bar zebar-config list
  oooconf wm bar zebar-config set overline-zebar-komorebi
  oooconf wm komorebi start --bar
  oooconf wm komorebi stop --bar""",
        "wm bar": """\
Usage: oooconf wm bar set <type>
       oooconf wm bar zebar-config status
       oooconf wm bar zebar-config list
       oooconf wm bar zebar-config set <name>
       oooconf wm bar stop
       oooconf wm bar start
       oooconf wm bar reload
       oooconf wm bar help

Manage status bars (zebar, yabs, sketchybar) and zebar configs.
Subcommands:
  set           set or show default bar type
  zebar-config  manage zebar configs (status, list, set)
  stop          stop zebar and komorebi-bar (keep komorebi running)
  start         start configured bar
  reload        restart configured bar (stop then start)
  help          show this help
Examples:
  oooconf wm bar set                   # show current bar type
  oooconf wm bar set zebar             # set to zebar
  oooconf wm bar zebar-config list
  oooconf wm bar zebar-config set overline-zebar-komorebi
  oooconf wm bar stop
  oooconf wm bar start
  oooconf wm bar reload""",
        "komorebi": """\
Usage: oooconf komorebi [status|start|stop|reload]

Manage the Komorebi window manager directly.
Subcommands:
  status         show whether komorebi is running
  start          start komorebi
  stop           stop komorebi
  reload         restart komorebi when running
Examples:
  oooconf komorebi status
  oooconf komorebi start
  oooconf komorebi stop
  oooconf komorebi reload""",
    }


def _render_spec_fallback(command: str, cmd: Command) -> str:
    """Synthesize help text from a Command node if no curated block exists."""
    parts = [f"Usage: oooconf {command}"]
    if cmd.subcommands:
        parts[0] += f" <{'|'.join(cmd.subcommands)}>"
    if cmd.options:
        parts[0] += " [options]"
    parts.extend(["", cmd.description])
    if cmd.subcommands:
        parts.append("Subcommands:")
        for sub_name, sub_cmd in cmd.subcommands.items():
            parts.append(f"  {sub_name:<18} {sub_cmd.description}")
    if cmd.options:
        parts.append("Options:")
        for opt, desc in cmd.options.items():
            parts.append(f"  {opt:<18} {desc}")
    return "\n".join(parts)


def render_command(spec: CliSpec, command: str, repo_root: Path, platform: str = "auto") -> str | None:
    """Render command-specific help text, or None if the command is unknown."""
    normalized = command.strip()
    if normalized == "wm.bar":
        normalized = "wm bar"

    resolved = resolve_command_alias(normalized, spec)
    if resolved in {"", "help", "-h", "--help"}:
        return render_main(spec, repo_root, platform=platform)

    resolved_platform = resolve_platform(platform)
    blocks = _command_help_blocks(resolved_platform)
    body = blocks.get(resolved)
    if body is None:
        cmd_node = spec.commands.get(resolved)
        if cmd_node is None:
            return None
        body = _render_spec_fallback(resolved, cmd_node)

    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        cli_ui.section(f"oooconf {resolved}")
        print(render_help_block(body))
    return buf.getvalue()


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Render oooconf help and command suggestions.")
    parser.add_argument("--mode", choices=("main", "command", "suggest"), default="main")
    parser.add_argument("--repo-root", type=Path, default=DEFAULT_REPO_ROOT)
    parser.add_argument("--command", dest="command_flag", default=None)
    parser.add_argument("--input", dest="suggest_input", default=None)
    parser.add_argument("--candidates", nargs="*", default=None)
    parser.add_argument("--platform", choices=("auto", "unix", "windows"), default="auto")
    parser.add_argument("--interactive", action="store_true", help="Force interactive UI detection via CONOUT$")
    parser.add_argument("--quiet-unknown", action="store_true", help="Suppress stderr on unknown commands")
    parser.add_argument("positional", nargs="?", default=None)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    if args.interactive and os.environ.get("OOOCONF_UI", "").lower() not in {"stdout", "off", "never"}:
        cli_ui.set_ui_override(True)

    repo_root = args.repo_root.resolve()
    spec = load_spec(repo_root)

    if args.mode == "main":
        sys.stdout.write(render_main(spec, repo_root, platform=args.platform))
        return 0

    if args.mode == "command":
        target = args.command_flag if args.command_flag is not None else (args.positional or "")
        rendered = render_command(spec, target, repo_root, platform=args.platform)
        if rendered is None:
            if not args.quiet_unknown:
                cli_ui.error("fail", f"Unknown command: {target}")
                suggestion = suggest_command(target, spec, platform=args.platform)
                if suggestion:
                    cli_ui.error("hint", f"Did you mean: {suggestion}")
            return 2
        sys.stdout.write(rendered)
        return 0

    # args.mode == "suggest"
    query = args.suggest_input if args.suggest_input is not None else (args.positional or "")
    if args.candidates is not None:
        pool = [token for item in args.candidates for token in item.split() if token]
        match = suggest_from_candidates(query, pool)
    else:
        match = suggest_command(query, spec, platform=args.platform)
    if match:
        print(match)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
