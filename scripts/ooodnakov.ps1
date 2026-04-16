param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments = @()
)

$ErrorActionPreference = "Stop"

$RepoRoot = if ($env:OOODNAKOV_REPO_ROOT) {
    $env:OOODNAKOV_REPO_ROOT
} else {
    (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}
$SetupScript = Join-Path $PSScriptRoot "setup.ps1"
$GenerateLockScript = Join-Path $PSScriptRoot "generate-dependency-lock.py"
$UpdatePinsScript = Join-Path $PSScriptRoot "update-pins.py"
$RenderSecretsScript = Join-Path $PSScriptRoot "render-secrets.py"
$AgentsToolScript = Join-Path $PSScriptRoot "agents-tool.py"
$KnownCommands = @("install", "deps", "update", "doctor", "dry-run", "lock", "update-pins", "agents", "secrets", "shell", "version", "bootstrap", "delete", "remove", "check", "preview", "upgrade")
$KnownShellSubcommands = @("forgit-aliases", "typo-handling")
$KnownShellForgitModes = @("plain", "forgit", "status")
$KnownShellTypoModes = @("silent", "suggest", "help", "status")
$LocalOverridesStart = "# --- LOCAL OVERRIDES START ---"
$LocalOverridesEnd = "# --- LOCAL OVERRIDES END ---"
$ForgitAliasVar = "OOODNAKOV_FORGIT_ALIAS_MODE"
$TypoHandlingVar = "OOODNAKOV_TYPO_HANDLING_MODE"

# Run a Python script, preferring `uv run` when available.
function Run-Python {
    param([string]$ScriptPath, [string[]]$ScriptArgs)
    $pyprojectPath = Join-Path $RepoRoot "pyproject.toml"
    if ((Get-Command uv -ErrorAction SilentlyContinue) -and (Test-Path $pyprojectPath)) {
        & uv run $ScriptPath @ScriptArgs
    } else {
        & python3 $ScriptPath @ScriptArgs
    }
}

function Get-ShellConfigHome {
    $baseConfigHome = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME ".config" }
    return Join-Path $baseConfigHome "ooodnakov"
}

function Get-LocalEnvZshPath {
    return Join-Path (Get-ShellConfigHome) "local/env.zsh"
}

function Get-LocalEnvPs1Path {
    return Join-Path (Get-ShellConfigHome) "local/env.ps1"
}

function Ensure-LocalOverrideFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        @(
            $LocalOverridesStart
            "# Add machine-specific env vars here. This section is preserved across syncs."
            $LocalOverridesEnd
        ) | Set-Content -LiteralPath $Path
        return
    }

    $content = Get-Content -LiteralPath $Path
    if ($content -notcontains $LocalOverridesStart) {
        Add-Content -LiteralPath $Path -Value ""
        Add-Content -LiteralPath $Path -Value $LocalOverridesStart
        Add-Content -LiteralPath $Path -Value "# Add machine-specific env vars here. This section is preserved across syncs."
        Add-Content -LiteralPath $Path -Value $LocalOverridesEnd
    }
}

function Set-LocalOverrideLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$VariableName,
        [Parameter(Mandatory = $true)]
        [string]$ReplacementLine
    )

    Ensure-LocalOverrideFile -Path $Path
    $lines = Get-Content -LiteralPath $Path
    $result = New-Object System.Collections.Generic.List[string]
    $inBlock = $false
    $inserted = $false

    foreach ($line in $lines) {
        if ($line -eq $LocalOverridesStart) {
            $inBlock = $true
            $result.Add($line)
            continue
        }

        if ($line -eq $LocalOverridesEnd) {
            if ($inBlock -and -not $inserted) {
                $result.Add($ReplacementLine)
                $inserted = $true
            }
            $inBlock = $false
            $result.Add($line)
            continue
        }

        if ($inBlock -and ($line -match ("^export " + [regex]::Escape($VariableName) + "=") -or $line -match ('^\$env:' + [regex]::Escape($VariableName) + ' = '))) {
            if (-not $inserted) {
                $result.Add($ReplacementLine)
                $inserted = $true
            }
            continue
        }

        $result.Add($line)
    }

    if (-not $inserted) {
        if ($result.Count -gt 0 -and $result[$result.Count - 1] -ne "") {
            $result.Add("")
        }
        $result.Add($LocalOverridesStart)
        $result.Add($ReplacementLine)
        $result.Add($LocalOverridesEnd)
    }

    Set-Content -LiteralPath $Path -Value $result
}

function Get-ForgitAliasMode {
    $envPath = Get-LocalEnvZshPath
    if (Test-Path -LiteralPath $envPath) {
        foreach ($line in Get-Content -LiteralPath $envPath) {
            if ($line -match "^export $([regex]::Escape($ForgitAliasVar))=""([^""]+)""$") {
                return $Matches[1]
            }
        }
    }

    return "plain"
}

function Get-TypoHandlingMode {
    if ($env:OOODNAKOV_TYPO_HANDLING_MODE) {
        return $env:OOODNAKOV_TYPO_HANDLING_MODE
    }

    $envPath = Get-LocalEnvZshPath
    if (Test-Path -LiteralPath $envPath) {
        foreach ($line in Get-Content -LiteralPath $envPath) {
            if ($line -match "^export $([regex]::Escape($TypoHandlingVar))=""([^""]+)""$") {
                return $Matches[1]
            }
        }
    }

    return "help"
}

function Set-ForgitAliasMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    if ($Mode -notin @("plain", "forgit")) {
        throw "Invalid forgit alias mode: $Mode`nExpected one of: plain, forgit"
    }

    $envZsh = Get-LocalEnvZshPath
    $envPs1 = Get-LocalEnvPs1Path

    Set-LocalOverrideLine -Path $envZsh -VariableName $ForgitAliasVar -ReplacementLine "export $ForgitAliasVar=""$Mode"""
    Set-LocalOverrideLine -Path $envPs1 -VariableName $ForgitAliasVar -ReplacementLine "`$env:$ForgitAliasVar = '$Mode'"

    Write-Output "forgit alias mode set to $Mode"
    Write-Output "zsh: $envZsh"
    Write-Output "pwsh: $envPs1"
    Write-Output "Open a new shell session to apply the change."
}

function Set-TypoHandlingMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    if ($Mode -notin @("silent", "suggest", "help")) {
        throw "Invalid typo handling mode: $Mode`nExpected one of: silent, suggest, help"
    }

    $envZsh = Get-LocalEnvZshPath
    $envPs1 = Get-LocalEnvPs1Path

    Set-LocalOverrideLine -Path $envZsh -VariableName $TypoHandlingVar -ReplacementLine "export $TypoHandlingVar=""$Mode"""
    Set-LocalOverrideLine -Path $envPs1 -VariableName $TypoHandlingVar -ReplacementLine "`$env:$TypoHandlingVar = '$Mode'"

    Write-Output "typo handling mode set to $Mode"
    Write-Output "zsh: $envZsh"
    Write-Output "pwsh: $envPs1"
    Write-Output "Open a new shell session to apply the change."
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
                Write-Output "Did you mean: $Suggestion"
            } else {
                Write-Output $Message
            }
            return
        }
        default {
            Write-Output $Message
            if ($Suggestion) {
                Write-Output "Did you mean: $Suggestion"
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

function Invoke-ShellCommand {
    param(
        [string[]]$ShellArgs
    )

    $subcommand = if ($ShellArgs.Count -gt 0) { $ShellArgs[0] } else { "" }

    switch ($subcommand) {
        "" { Show-CommandUsage "shell"; return }
        "help" { Show-CommandUsage "shell"; return }
        "-h" { Show-CommandUsage "shell"; return }
        "--help" { Show-CommandUsage "shell"; return }
        "forgit-aliases" {
            $mode = if ($ShellArgs.Count -gt 1) { $ShellArgs[1] } else { "status" }
            switch ($mode) {
                "status" { Write-Output (Get-ForgitAliasMode) }
                "plain" { Set-ForgitAliasMode -Mode $mode }
                "forgit" { Set-ForgitAliasMode -Mode $mode }
                default {
                    $suggestion = Get-SuggestionFromList -InputValue $mode -Candidates $KnownShellForgitModes
                    Write-UnknownCommandMessage -Message "Unknown shell option: $mode" -Suggestion $suggestion -Scope shell
                    throw "Unknown shell option: $mode`nExpected one of: plain, forgit, status"
                }
            }
            return
        }
        "typo-handling" {
            $mode = if ($ShellArgs.Count -gt 1) { $ShellArgs[1] } else { "status" }
            switch ($mode) {
                "status" { Write-Output (Get-TypoHandlingMode) }
                "silent" { Set-TypoHandlingMode -Mode $mode }
                "suggest" { Set-TypoHandlingMode -Mode $mode }
                "help" { Set-TypoHandlingMode -Mode $mode }
                default {
                    $suggestion = Get-SuggestionFromList -InputValue $mode -Candidates $KnownShellTypoModes
                    Write-UnknownCommandMessage -Message "Unknown shell option: $mode" -Suggestion $suggestion -Scope shell
                    throw "Unknown shell option: $mode`nExpected one of: silent, suggest, help, status"
                }
            }
            return
        }
        default {
            $suggestion = Get-SuggestionFromList -InputValue $subcommand -Candidates $KnownShellSubcommands
            Write-UnknownCommandMessage -Message "Unknown shell subcommand: $subcommand" -Suggestion $suggestion -Scope shell
            throw "Unknown shell subcommand: $subcommand"
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
            $insertion = $current[$j - 1] + 1
            $substitution = $previous[$j - 1] + $cost
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

$AgentsToolScript = Join-Path $PSScriptRoot "agents-tool.py"

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
    @"
Usage: oooconf [global options] <command> [command options]

oooconf - reproducible cross-platform dotfiles manager

Global options:
  -C, --repo-root PATH  run against a specific repo checkout
  -h, --help            show this help
  -n, --dry-run         add --dry-run to install or update
      --yes-optional    auto-accept optional dependency installs
  -V, --version         show CLI version information
      --print-repo-root print the resolved repo root and exit

Commands:
  Setup:
    install               apply managed config and optional dependency installs
    deps                  install optional dependencies only
    update                pull repo with --ff-only, then re-run install

  Inspect & Validate:
    doctor                validate managed symlinks and required commands
    dry-run               preview install flow without mutating filesystem
    version               print CLI version and repo root

  Manage State:
    lock                  regenerate dependency lock artifacts from pinned refs
    update-pins           compare/update pinned refs and refresh lock artifacts
    agents                detect/sync/doctor AGENTS.md common policy blocks

  Shell:
    shell                 manage local shell preferences such as forgit aliases

  Secrets:
    secrets               sync or validate local secret env files

Aliases:
  check -> doctor
  preview -> dry-run
  upgrade -> update

Note:
  bootstrap, delete, and remove commands are available in the Unix
  version only. On Windows, use setup.ps1 directly for bootstrap,
  and manual cleanup for delete/remove scenarios.

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
  `$RepoRoot
"@
}

function Show-CommandUsage {
    param(
        [string]$CommandName
    )

    $CommandName = Resolve-CommandAlias -CommandName $CommandName
    switch ($CommandName) {
        "install" {
            @"
Usage: oooconf install [--dry-run] [--yes-optional]

Apply managed config and optional dependency installation.

Creates symlinks from tracked config in home/ to their target locations,
backing up any replaced files. Optionally installs dependencies when
allowed.

Examples:
  oooconf install                      # interactive dependency prompts
  oooconf install --yes-optional       # auto-accept all optional installs
  oooconf install --dry-run            # preview without making changes
"@
        }
        "deps" {
            @"
Usage: oooconf deps [--dry-run] [dependency-key...]

Install optional dependencies only. Without dependency keys, an interactive
gum-based multi-select picker is used when available.

Dependency keys match those defined in deps.lock.json. Common keys include:
bat, delta, eza, fd, fzf, gum, glow, rg, yazi, ffmpeg, jq, p7zip, poppler, zoxide, and others.

Examples:
  oooconf deps                         # interactive picker (when gum available)
  oooconf deps bat delta fd ripgrep    # install specific tools
  oooconf deps --dry-run               # preview installation
"@
        }
        "update" {
            @"
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
            @"
Usage: oooconf doctor

Validate managed symlinks and required commands.

Checks that all managed config links point to valid targets and that
key tools (git, zsh, wezterm, nvim, etc.) are available on PATH.

Examples:
  oooconf doctor                       # run all checks
"@
        }
        "dry-run" {
            @"
Usage: oooconf dry-run

Preview the install flow without mutating the filesystem.

Shows what links would be created, what files would be backed up, and
what dependencies would be installed, without making any changes.

Examples:
  oooconf dry-run                      # preview install
  oooconf --yes-optional dry-run       # preview with dependency installs
"@
        }
        "lock" {
            @"
Usage: oooconf lock

Regenerate dependency lock artifacts from pinned refs in setup scripts.

Reads pinned versions from scripts/setup.ps1 (or setup.sh) and writes
the resolved lock file to deps.lock.json.

Examples:
  oooconf lock                         # regenerate lock artifact
"@
        }
        "update-pins" {
            @"
Usage: oooconf update-pins [--apply]

Compare pinned git refs to upstream HEAD and refresh lock artifacts.

Without --apply, only reports differences. With --apply, updates the
pinned refs in setup scripts and regenerates lock artifacts.

Examples:
  oooconf update-pins                  # check for pin drift
  oooconf update-pins --apply          # update pins and regenerate lock
"@
        }
        "agents" {
            @"
Usage: oooconf agents <detect|sync|doctor> [options]

Manage shared AGENTS.md instructions and validate configured agent tooling.

Subcommands:
  detect [--json]       detect configured agent CLIs on PATH
  sync [--check]        append/update shared AGENTS.md managed block
  doctor [--strict-config-paths]
                        verify AGENTS.md managed block and default agent config paths
"@
        }
        "secrets" {
            @"
Usage: oooconf secrets <sync|doctor|list|status|login|unlock|logout|add|remove> [options]

Render or validate local secret env files from the tracked template.
Examples:
  oooconf secrets                      # show current sync/session status
  oooconf secrets login
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
            @"
Usage: oooconf version

Print the CLI version (git describe or commit SHA) and resolved repo root.

Examples:
  oooconf version                      # show version and repo path
"@
        }
        "shell" {
            @"
Usage: oooconf shell forgit-aliases [plain|forgit|status]
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

function Require-Python3 {
    if (-not (Get-Command python3 -ErrorAction SilentlyContinue)) {
        throw "python3 is required."
    }
}

$dryRunRequested = $false
$yesOptionalRequested = $false
$command = $null
$remaining = [System.Collections.Generic.List[string]]::new()

for ($i = 0; $i -lt $Arguments.Count; $i++) {
    $arg = $Arguments[$i]
    switch ($arg) {
        "-C" {
            if ($i + 1 -ge $Arguments.Count) {
                throw "Missing value for $arg"
            }
            $RepoRoot = $Arguments[$i + 1]
            $i++
        }
        "--repo-root" {
            if ($i + 1 -ge $Arguments.Count) {
                throw "Missing value for $arg"
            }
            $RepoRoot = $Arguments[$i + 1]
            $i++
        }
        "--print-repo-root" {
            Write-Output $RepoRoot
            exit 0
        }
        "-V" {
            Write-Output "oooconf $(Get-Version)"
            Write-Output $RepoRoot
            exit 0
        }
        "--version" {
            Write-Output "oooconf $(Get-Version)"
            Write-Output $RepoRoot
            exit 0
        }
        "-h" {
            if ($i + 1 -lt $Arguments.Count -and -not $Arguments[$i + 1].StartsWith("-")) {
                Show-CommandUsage (Resolve-CommandAlias -CommandName $Arguments[$i + 1])
            } else {
                Show-Usage
            }
            exit 0
        }
        "--help" {
            if ($i + 1 -lt $Arguments.Count -and -not $Arguments[$i + 1].StartsWith("-")) {
                Show-CommandUsage (Resolve-CommandAlias -CommandName $Arguments[$i + 1])
            } else {
                Show-Usage
            }
            exit 0
        }
        "-n" {
            $dryRunRequested = $true
        }
        "--dry-run" {
            $dryRunRequested = $true
        }
        "--yes-optional" {
            $yesOptionalRequested = $true
        }
        "help" {
            if ($i + 1 -lt $Arguments.Count) {
                Show-CommandUsage (Resolve-CommandAlias -CommandName $Arguments[$i + 1])
            } else {
                Show-Usage
            }
            exit 0
        }
        "version" {
            Write-Output "oooconf $(Get-Version)"
            Write-Output $RepoRoot
            exit 0
        }
        default {
            $command = Resolve-CommandAlias -CommandName $arg
            for ($j = $i + 1; $j -lt $Arguments.Count; $j++) {
                $remaining.Add($Arguments[$j])
            }
            break
        }
    }

    if ($command) {
        break
    }
}

if (-not $command) {
    if ($dryRunRequested) {
        $command = "install"
    } else {
        Show-Usage
        exit 0
    }
}

$env:OOODNAKOV_REPO_ROOT = $RepoRoot
if ($yesOptionalRequested) {
    $env:OOODNAKOV_INSTALL_OPTIONAL = "always"
}

switch ($command) {
    "install" {
        if ($dryRunRequested) {
            & $SetupScript install -DryRun @remaining
        } else {
            & $SetupScript install @remaining
        }
    }
    "deps" {
        if ($dryRunRequested) {
            & $SetupScript deps -DryRun @remaining
        } else {
            & $SetupScript deps @remaining
        }
    }
    "update" {
        if ($dryRunRequested) {
            & $SetupScript update -DryRun @remaining
        } else {
            & $SetupScript update @remaining
        }
    }
    "doctor" {
        if ($dryRunRequested) {
            throw "--dry-run is not supported for doctor"
        }
        & $SetupScript doctor @remaining
    }
    "dry-run" {
        if ($dryRunRequested) {
            throw "Use either dry-run or --dry-run, not both"
        }
        & $SetupScript install -DryRun @remaining
    }
    "lock" {
        if ($dryRunRequested) {
            throw "--dry-run is not supported for lock"
        }
        Run-Python -ScriptPath $GenerateLockScript -ScriptArgs $remaining
    }
    "update-pins" {
        if ($dryRunRequested) {
            throw "--dry-run is not supported for update-pins"
        }
        Run-Python -ScriptPath $UpdatePinsScript -ScriptArgs $remaining
    }
    "secrets" {
        Run-Python -ScriptPath $RenderSecretsScript -ScriptArgs (@("--repo-root", $RepoRoot) + $remaining)
    }
    "shell" {
        Invoke-ShellCommand -ShellArgs $remaining
    }
    "agents" {
        if ($dryRunRequested) {
            throw "--dry-run is not supported for agents"
        }
        Require-Python3
        & python3 $AgentsToolScript --repo-root $RepoRoot @remaining
    }
    default {
        $suggestion = Get-CommandSuggestion -InputCommand $command
        Write-UnknownCommandMessage -Message "Unknown command: $command" -Suggestion $suggestion
        throw "Unknown command: $command"
    }
}

exit $LASTEXITCODE
