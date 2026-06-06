# Dot-sourced by scripts/setup/ooodnakov.ps1; do not execute directly.

function Get-KnownCommands {
    $fallback = @("install", "deps", "update", "doctor", "dry-run", "delete", "remove", "lock", "update-pins", "completions", "agents", "secrets", "shell", "color", "delta", "version", "check", "preview", "upgrade")
    if (-not (Test-Path $CommandsFile)) {
        return $fallback
    }

    $commands = @(
        Get-Content -Path $CommandsFile -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith("#") }
    )
    $commands = @($commands | Where-Object { $_ -ne "bootstrap" })
    if ($commands.Count -eq 0) {
        return $fallback
    }
    return $commands
}

function Write-UnknownCommandMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Suggestion,
        [string]$Scope = "main"
    )

    $mode = Get-TypoHandlingMode
    switch ($mode) {
        "silent" {
            return
        }
        "suggest" {
            if ($Suggestion) {
                Write-UiLine -Role hint -Message "Did you mean: $Suggestion"
            } else {
                Write-UiLine -Role fail -Message $Message
            }
            return
        }
        default {
            Write-UiLine -Role fail -Message $Message
            if ($Suggestion) {
                Write-UiLine -Role hint -Message "Did you mean: $Suggestion"
            }
            if ($Scope -eq "shell") {
                Show-CommandUsage "shell"
            } else {
                Show-Usage
            }
            return
        }
    }
}

function Resolve-CommandAlias {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    switch ($CommandName) {
        "check" { return "doctor" }
        "preview" { return "dry-run" }
        "upgrade" { return "update" }
        default { return $CommandName }
    }
}

function Get-EditDistance {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Left,
        [Parameter(Mandatory = $true)]
        [string]$Right
    )

    $Left = [string]$Left
    $Right = [string]$Right

    $rightLength = $Right.Length
    $previous = New-Object int[] ($rightLength + 1)
    for ($j = 0; $j -le $rightLength; $j++) {
        $previous[$j] = $j
    }

    for ($i = 1; $i -le $Left.Length; $i++) {
        $current = New-Object int[] ($rightLength + 1)
        $current[0] = $i
        $leftChar = $Left.Substring($i - 1, 1)

        for ($j = 1; $j -le $rightLength; $j++) {
            $rightChar = $Right.Substring($j - 1, 1)
            $cost = if ($leftChar -ceq $rightChar) { 0 } else { 1 }
            $deletion = $previous[$j] + 1
            $insertion = $current[($j - 1)] + 1
            $substitution = $previous[($j - 1)] + $cost
            $current[$j] = [Math]::Min([Math]::Min($deletion, $insertion), $substitution)
        }

        $previous = $current
    }

    return $previous[$rightLength]
}

function Get-CommandSuggestion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputCommand
    )

    $bestCommand = $null
    $bestDistance = [int]::MaxValue

    foreach ($candidate in @($KnownCommands | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        $candidateText = [string]$candidate
        $distance = Get-EditDistance -Left $InputCommand -Right $candidateText
        if ($distance -lt $bestDistance) {
            $bestDistance = $distance
            $bestCommand = $candidateText
        }
    }

    $threshold = if ($InputCommand.Length -le 4) { 2 } else { 3 }
    if ($bestDistance -le $threshold) {
        return $bestCommand
    }

    return $null
}

function Get-SuggestionFromList {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputValue,
        [Parameter(Mandatory = $true)]
        [string[]]$Candidates
    )

    $bestMatch = $null
    $bestDistance = [int]::MaxValue

    foreach ($candidate in @($Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        $candidateText = [string]$candidate
        $distance = Get-EditDistance -Left $InputValue -Right $candidateText
        if ($distance -lt $bestDistance) {
            $bestDistance = $distance
            $bestMatch = $candidateText
        }
    }

    $threshold = if ($InputValue.Length -le 4) { 2 } else { 3 }
    if ($bestDistance -le $threshold) {
        return $bestMatch
    }

    return $null
}

function Get-Version {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        try {
            $version = git -C $RepoRoot describe --always --dirty --tags 2>$null
            if ($LASTEXITCODE -eq 0 -and $version) {
                return $version.Trim()
            }
        } catch {
        }

        try {
            $version = git -C $RepoRoot rev-parse --short HEAD 2>$null
            if ($LASTEXITCODE -eq 0 -and $version) {
                return $version.Trim()
            }
        } catch {
        }
    }

    return "unknown"
}

function Show-Usage {
    Write-UiBanner
    Write-UiSpacer
    Write-Output (Format-UiText -Text "Usage: oooconf [global options] <command> [command options]" -Role "section" -Bold)
    Write-Output (Format-UiText -Text "A reproducible cross-platform dotfiles manager with setup, health checks, secrets, and shell tooling." -Role "muted")

    Write-UiSpacer
    Write-UiSeparator
    Write-UiSectionFancy -IconName "version" -Title "Global options"
    Write-Output @"
  -C, --repo-root PATH  run against a specific repo checkout
  -h, --help            show this help
  -n, --dry-run         add --dry-run to install or update
      --yes-optional    auto-accept optional dependency installs
      --skip-deps       skip dependency installation
  -V, --version         show CLI version information
      --print-repo-root print the resolved repo root and exit
"@

    Write-UiSpacer
    Write-UiSeparator
    Write-UiSectionFancy -IconName "install" -Title "Setup"
    Write-UiCommandRow -CommandName "bootstrap" -Description "clone/update repo then run install"
    Write-UiCommandRow -CommandName "install" -Description "apply managed config and optional dependency installs"
    Write-UiCommandRow -CommandName "deps" -Description "install optional dependencies only"
    Write-UiCommandRow -CommandName "update" -Description "pull repo with --ff-only, then re-run install"

    Write-UiSpacer
    Write-UiSectionFancy -IconName "doctor" -Title "Inspect & Validate"
    Write-UiCommandRow -CommandName "doctor" -Description "validate managed symlinks and required commands"
    Write-UiCommandRow -CommandName "dry-run" -Description "preview install flow without mutating filesystem"
    Write-UiCommandRow -CommandName "version" -Description "print CLI version and repo root"

    Write-UiSpacer
    Write-UiSectionFancy -IconName "lock" -Title "Manage State"
    Write-UiCommandRow -CommandName "delete" -Description "remove managed links and restore latest backups"
    Write-UiCommandRow -CommandName "remove" -Description "remove managed links only (no backup restore)"
    Write-UiCommandRow -CommandName "lock" -Description "regenerate dependency lock artifacts from pinned refs"
    Write-UiCommandRow -CommandName "update-pins" -Description "compare/update pinned refs and refresh lock artifacts"
    Write-UiCommandRow -CommandName "completions" -Description "regenerate tracked shell completions (autogen + oooconf)"
    Write-UiCommandRow -CommandName "link" -Description "inspect or manage links from the symlink manifest"

    Write-UiSpacer
    Write-UiSectionFancy -IconName "shell" -Title "Shell / Secrets / Agents"
    Write-UiCommandRow -CommandName "shell" -Description "manage local shell preferences such as forgit aliases"
    Write-UiCommandRow -CommandName "color" -Description "set a unified oooconf CLI color theme"
    Write-UiCommandRow -CommandName "delta" -Description "inject or manage git-delta gitconfig"
    Write-UiCommandRow -CommandName "secrets" -Description "sync or validate local secret env files"
    Write-UiCommandRow -CommandName "agents" -Description "detect/sync/doctor/update AGENTS.md and agent CLI workflows"
    Write-UiCommandRow -CommandName "wm" -Description "switch between or manage window managers (komorebi/glazewm)"

    Write-UiSpacer
    Write-UiSeparator
    Write-UiHelpBlock @"
Aliases:
  check -> doctor
  preview -> dry-run
  upgrade -> update
Note:
  bootstrap is Unix-only in this wrapper.
  On Windows, run ``scripts/setup/setup.ps1 install`` for initial setup.
Getting help:
  oooconf --help                     show this message
  oooconf help <command>             show command-specific help
  oooconf help secrets               show secrets subcommand help
UI controls:
  `$env:OOOCONF_COLOR='always'       override color output
  `$env:OOOCONF_ASCII='1'            force ASCII icons and borders
  `$env:OOOCONF_THEME='<theme>'      set the CLI color theme for this run
Common workflows:
  # Initial setup on Windows:
  ./scripts/setup/setup.ps1 install
  # Preview what install would do:
  oooconf dry-run
  # Apply config and install dependencies:
  oooconf install
  oooconf deps
"@
}

function Show-CommandUsage {
    param($command)
    switch ($command) {
        "install" {
            Write-UiHelpBlock @"
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
"@
        }
        "deps" {
            Write-UiHelpBlock @"
Usage: oooconf deps [--dry-run] [--all] [dependency-key...]

Install optional dependencies only. Without dependency keys, an interactive
picker is shown (using gum if available).

All dependency metadata (including versions, URLs, and install methods) lives exclusively in scripts/optional-deps.toml.
Examples:
  oooconf deps                         # interactive picker (when gum available)
  oooconf deps key1 key2               # install specific dependency keys
  oooconf deps --dry-run               # preview only
  oooconf deps --all                   # install all dependency keys
"@
        }
        "update" {
            Write-UiHelpBlock @"
Usage: oooconf update [--dry-run] [--yes-optional]

Pull the repo with --ff-only, then re-run the install flow.
Use this to update your config to the latest tracked state. It performs
a fast-forward pull only, failing if local changes would prevent it.
Examples:
  oooconf update                       # pull and reinstall
  oooconf update --yes-optional        # also install missing dependencies
  oooconf update --dry-run             # preview pull and install
"@
        }
        "doctor" {
            Write-UiHelpBlock @"
Usage: oooconf doctor

Validate managed symlinks and required commands.
Checks that all managed config links point to valid targets and that
key tools (git, zsh, wezterm, yazi, nvim, etc.) are available on PATH.
Examples:
  oooconf doctor                       # run all checks
"@
        }
        "dry-run" {
            Write-UiHelpBlock @"
Usage: oooconf dry-run

Preview the install flow without mutating the filesystem.
Shows what links would be created, what files would be backed up, and
what dependencies would be installed, without making any changes.
Examples:
  oooconf dry-run                      # preview install
  oooconf --yes-optional dry-run       # preview with dependency installs
"@
        }
        "link" {
            Write-UiHelpBlock @"
Usage: oooconf link [--dry-run]

Create or update symlinks from tracked config in home/ to their target
locations, backing up any replaced files. Reads from links.toml manifest
with auto-discovery for home/.config, home/.local, and home/.glzr.
Examples:
  oooconf link                       # create/update all manifest links
  oooconf link --dry-run            # preview without making changes
"@
        }
        "delete" {
            Write-UiHelpBlock @"
Usage: oooconf delete

Remove managed links and restore the latest backups when available.
Use this to undo the managed config and return to your previous state.
Backup files are stored in ~/.local/state/ooodnakov-config/backups/.
Examples:
  oooconf delete                       # restore from backups
"@
        }
        "remove" {
            Write-UiHelpBlock @"
Usage: oooconf remove

Remove managed links without restoring backups.
Use this when you want to cleanly remove the managed config without
putting previous files back in place.
Examples:
  oooconf remove                       # clean removal
"@
        }
        "lock" {
            Write-UiHelpBlock @"
Usage: oooconf lock

Regenerate dependency lock artifacts from managed tool refs.
Reads pinned versions from scripts/optional-deps.toml and writes
the resolved lock file to deps.lock.json.
Examples:
  oooconf lock                         # regenerate lock artifact
"@
        }
        "update-pins" {
            Write-UiHelpBlock @"
Usage: oooconf update-pins [--apply] [--offline] [--dry-run]

Compare pinned git refs in scripts/optional-deps.toml to upstream HEAD.
Without --apply, reports differences and refreshes lock artifacts. With --apply,
updates pinned refs in the catalog and regenerates lock artifacts.
Examples:
  oooconf update-pins                  # check for pin drift
  oooconf update-pins --apply          # update pins and regenerate lock
  oooconf update-pins --offline --dry-run # validate local catalog parsing
"@
        }
        "completions" {
            Write-UiHelpBlock @"
Usage: oooconf completions [--dry-run]

Regenerate tracked shell completion files:
  - autogen zsh completions under home/.config/ooodnakov/zsh/completions/autogen
  - oooconf command completions for zsh and PowerShell
This does not install dependencies; it only rebuilds completion files.
Examples:
  oooconf completions                  # rebuild tracked completion files
  oooconf completions --dry-run        # preview generation actions
"@
        }
        "agents" {
            Write-UiHelpBlock @"

Usage: oooconf agents <detect|sync|doctor|install|provider|update|mcp|rtk|skills> [options]

Manage shared AGENTS.md instructions and validate configured agent tooling.
Subcommands:
  detect [--json]                detect configured agent CLIs on PATH
  sync [--check] [--materialize-secrets]
                                  append/update shared AGENTS.md managed block
  doctor [--strict-config-paths] verify AGENTS.md managed block and default agent config paths
  install [<agent> ...] [--all|--missing] [--check]
                                  install missing, selected, or all configured agent CLIs
  update [--check]               update installed agent CLIs (pnpm-based tools use pnpm)
  provider sync minimax [--check] [--region global|china] [--materialize-secrets]
                                  configure MiniMax-M2.7 backends for Claude Code, OpenCode, and Codex CLI
  mcp sync|status                synchronize or inspect managed MCP servers
  rtk init [--check]             initialize RTK hooks for detected agents
  mcp add [--name N] [--json J] [--multi] [--preview] [--sync-now]
                                  add one MCP JSON server entry to shared config
  skills sync [--check]          sync configured skill specs across agents
  skills view [--check] [--json] list global shared skills catalog via pnpm dlx
  skills add <source> [--agent gemini] [--sync-now]
                                  add one shared skill source
Examples:
  oooconf agents detect                 # list available agent CLIs
  oooconf agents sync --check           # verify AGENTS.md managed sections
  oooconf agents install --check        # preview missing agent CLI installs
  oooconf agents install codex gemini   # install selected agent CLIs
  oooconf agents mcp status             # show managed MCP server status
  oooconf agents provider sync minimax   # configure MiniMax-M2.7 provider backends
  oooconf agents skills view --json     # show shared skills catalog as JSON
"@
        }
        "secrets" {
            Write-UiHelpBlock @"
Usage: oooconf secrets <sync|doctor|list|status|login|unlock|logout|add|remove> [options]

Render or validate local secret env files from the tracked template.
Examples:
  oooconf secrets                      # show current sync/session status
  oooconf secrets login                # choose login method interactively
  oooconf secrets login --method apikey
  oooconf secrets unlock               # prompt for password and save session
  oooconf secrets unlock 'your-password'
  oooconf secrets unlock --shell pwsh | Invoke-Expression
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
"@
        }
        "version" {
            Write-UiHelpBlock @"
Usage: oooconf version

Print the CLI version (git describe or commit SHA) and resolved repo root.
Examples:
  oooconf version                      # show version and repo path
"@
        }
        "shell" {
            Write-UiHelpBlock @"
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
"@
        }
        "color" {
            Write-UiHelpBlock @"
Usage: oooconf color [status|list|<theme>|dark|light]

Set or inspect the oooconf CLI color theme and dark/light mode.
Themes:
  default, catppuccin, gruvbox, nord, tokyonight, noctalia
Modes:
  dark, light
This also syncs theme-friendly overrides for yazi, wezterm local override, komorebi/komorebi.bar, sketchybar colors, zebar css vars, and themed oh-my-posh config.
Status output also reports detected nvim and oh-my-posh theme config state.
Examples:
  oooconf color status                 # print current theme and synced config state
  oooconf color list                   # list available themes
  oooconf color catppuccin             # switch to Catppuccin colors
  oooconf color noctalia               # switch to Noctalia colors
"@
        }
        "delta" {
            Invoke-DeltaCommand -DeltaArgs @("help")
        }
        "wm" {
            Write-UiHelpBlock @"
Usage: oooconf wm status
       oooconf wm set [komorebi|glazewm]
       oooconf wm start
       oooconf wm stop
       oooconf wm reload
       oooconf wm bar set zebar <name>
       oooconf wm bar zebar-config status
       oooconf wm bar zebar-config list
       oooconf wm bar zebar-config set <name>
       oooconf wm komorebi reload
       oooconf wm komorebi start [--bar]
       oooconf wm komorebi stop [--bar]

Switch between or manage window managers.
Subcommands:
  status         shows the currently running window manager
  set            stops the current WM and starts the specified one
  start          starts the default WM (komorebi)
  stop           stops any running WM stack
  reload         reloads the configuration of the active WM
  bar            manage bar and zebar (set, zebar-config)
  komorebi       manage komorebi (reload, start, stop) with optional --bar
Examples:
  oooconf wm status
  oooconf wm set glazewm
  oooconf wm reload
  oooconf wm bar set zebar overline-zebar-komorebi
  oooconf wm bar zebar-config list
  oooconf wm bar zebar-config set overline-zebar-komorebi
  oooconf wm komorebi start --bar
  oooconf wm komorebi stop --bar
"@
        }
        "wm bar" {
            Write-UiHelpBlock @"
Usage: oooconf wm bar set <type>
       oooconf wm bar zebar-config status
       oooconf wm bar zebar-config list
       oooconf wm bar zebar-config set <name>
       oooconf wm bar stop
       oooconf wm bar start
       oooconf wm bar reload
       oooconf wm bar help

Subcommands:
  set           set or show default bar type
  zebar-config  manage zebar configs (status, list, set)
  stop          stop zebar and komorebi-bar (keep komorebi running)
  start         start zebar with configured settings
  reload        restart zebar (stop then start)
  help          show this help
Examples:
  oooconf wm bar set              # show current bar type
  oooconf wm bar set zebar        # set to zebar
  oooconf wm bar zebar-config list
  oooconf wm bar zebar-config set overline-zebar-komorebi
  oooconf wm bar stop
  oooconf wm bar start
  oooconf wm bar reload
"@
        }
        "" { Show-Usage }
        "help" { Show-Usage }
        "-h" { Show-Usage }
        "--help" { Show-Usage }
        default {
            $suggestion = Get-CommandSuggestion -InputCommand $CommandName
            Write-UnknownCommandMessage -Message "Unknown command: $CommandName" -Suggestion $suggestion
            throw "Unknown command: $CommandName"
        }
    }
}

function Require-PythonRuntime {
    $pyprojectPath = Join-Path $RepoRoot "pyproject.toml"
    if ((Get-Command uv -ErrorAction SilentlyContinue) -and (Test-Path $pyprojectPath)) {
        return
    }

    if (Get-Command python3 -ErrorAction SilentlyContinue) {
        return
    }

    throw "python3 or uv is required."
}
