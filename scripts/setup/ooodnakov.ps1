param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments = @()
)

$ErrorActionPreference = "Stop"
if ($null -eq $IsWindows) { $IsWindows = $true }

$RepoRoot = if ($env:OOODNAKOV_REPO_ROOT) {
    $env:OOODNAKOV_REPO_ROOT
} else {
    (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
}
$SetupScript = Join-Path $RepoRoot "scripts/setup/setup.ps1"
$DeleteScript = Join-Path $RepoRoot "scripts/setup/delete.ps1"
$GenerateLockScript = Join-Path $RepoRoot "scripts/generate/generate_dependency_lock.py"
$UpdatePinsScript = Join-Path $RepoRoot "scripts/update/update_pins.py"
$RenderSecretsScript = Join-Path $RepoRoot "scripts/generate/render_secrets.py"
$AgentsToolScript = Join-Path $RepoRoot "scripts/cli/agents_tool.py"
$SyncColorThemeScript = Join-Path $RepoRoot "scripts/lib/sync_color_theme.py"
$CommandsFile = Join-Path $RepoRoot "scripts/cli/oooconf-commands.txt"

$KnownShellSubcommands = @("status", "prompt", "prompt-style", "forgit-aliases", "typo-handling", "psfzf-tab", "psfzf-git", "auto-uv-env")
$KnownShellForgitModes = @("plain", "forgit", "status")
$KnownShellTypoModes = @("silent", "suggest", "help", "status")
$KnownShellPsfzfModes = @("enabled", "disabled", "status")
$KnownShellAutoUvModes = @("enabled", "quiet", "status")
$KnownShellPromptModes = @("p10k", "ohmyposh", "status")
$KnownShellPromptStyleModes = @("verbose", "concise", "status")
$KnownColorThemes = @("default", "catppuccin", "gruvbox", "nord", "tokyonight", "noctalia")
$KnownColorModes = @("dark", "light")
$KnownWmSubcommands = @("status", "set", "start", "stop", "reload", "bar", "komorebi")
$KnownWmOptions = @("komorebi", "glazewm")
$KnownBarSubcommands = @("set", "zebar-config", "stop", "start", "reload")
$KnownBarTypes = @("zebar", "yabs")
$LocalOverridesStart = "# --- LOCAL OVERRIDES START ---"
$LocalOverridesEnd = "# --- LOCAL OVERRIDES END ---"
$ForgitAliasVar = "OOODNAKOV_FORGIT_ALIAS_MODE"
$TypoHandlingVar = "OOODNAKOV_TYPO_HANDLING_MODE"
$PsfzfTabVar = "OOODNAKOV_PSFZF_TAB"
$PsfzfGitVar = "OOODNAKOV_PSFZF_GIT"
$AutoUvEnvVar = "AUTO_UV_ENV_QUIET"
$OooconfThemeVar = "OOOCONF_THEME"
$OooconfColorModeVar = "OOOCONF_COLOR_MODE"
$OooconfOmpConfigVar = "OOOCONF_OMP_CONFIG"
$OooconfZshPromptVar = "OOOCONF_ZSH_PROMPT"
$OooconfPromptStyleVar = "OOOCONF_PROMPT_STYLE"
$UiAscii = @{
    section = "=="
    ok = "[ok]"
    warn = "[warn]"
    fail = "[fail]"
    missing = "[missing]"
    info = "[info]"
    hint = "->"
}
$UiNerd = @{
    section = 0x25B8
    ok = 0x2713
    warn = 0x26A0
    fail = 0x2717
    missing = 0x2717
    info = 0x2139
    hint = 0x2192
}
$UiAnsi = @{
    Reset = "$([char]27)[0m"
    Bold = "$([char]27)[1m"
    Section = ""
    Ok = ""
    Warn = ""
    Fail = ""
    Info = ""
    Muted = ""
}

# Run a Python script, preferring `uv run` when available.
. (Join-Path $RepoRoot "scripts/setup/lib/oooconf-ui.ps1")
. (Join-Path $RepoRoot "scripts/setup/lib/oooconf-shell.ps1")
. (Join-Path $RepoRoot "scripts/setup/lib/oooconf-color.ps1")
. (Join-Path $RepoRoot "scripts/setup/lib/oooconf-wm.ps1")
. (Join-Path $RepoRoot "scripts/setup/lib/oooconf-bar.ps1")
. (Join-Path $RepoRoot "scripts/setup/lib/oooconf-help.ps1")
. (Join-Path $RepoRoot "scripts/setup/lib/oooconf-delta.ps1")
. (Join-Path $RepoRoot "scripts/setup/lib/oooconf-dispatch.ps1")
$KnownCommands = Get-KnownCommands


if ($MyInvocation.InvocationName -eq ".") {
    return
}

$dryRunRequested = $false
$yesOptionalRequested = $false
$skipDepsRequested = $false
$allDepsRequested = $false
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
            Write-UiLine -Role info -Message $RepoRoot
            exit 0
        }
        "-V" {
            Write-UiLine -Role info -Message "oooconf $(Get-Version)"
            Write-UiLine -Role info -Message $RepoRoot
            exit 0
        }
        "--version" {
            Write-UiLine -Role info -Message "oooconf $(Get-Version)"
            Write-UiLine -Role info -Message $RepoRoot
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
        "--skip-deps" {
            $skipDepsRequested = $true
        }
        "--all" {
            $allDepsRequested = $true
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
            Write-UiLine -Role info -Message "oooconf $(Get-Version)"
            Write-UiLine -Role info -Message $RepoRoot
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


if (Test-ShouldNormalizeGlobalFlags -CommandName $command) {
    $normalizedRemaining = @()
    foreach ($arg in $remaining) {
        switch ($arg) {
            "-n" { $dryRunRequested = $true }
            "--dry-run" { $dryRunRequested = $true }
            "--yes-optional" { $yesOptionalRequested = $true }
            "--skip-deps" { $skipDepsRequested = $true }
            "--all" { $allDepsRequested = $true }
            default { $normalizedRemaining += $arg }
        }
    }
    $remaining = $normalizedRemaining
}

$env:OOODNAKOV_REPO_ROOT = $RepoRoot
if ($yesOptionalRequested) {
    $env:OOODNAKOV_INSTALL_OPTIONAL = "always"
}


switch ($command) {
    "install" {
        Invoke-SetupCommand -SetupCommand "install" -SupportsDryRun -RemainingArgs $remaining
    }
    "deps" {
        Invoke-SetupCommand -SetupCommand "deps" -SupportsDryRun -RemainingArgs $remaining
    }
    "update" {
        Invoke-SetupCommand -SetupCommand "update" -SupportsDryRun -RemainingArgs $remaining
    }
    "delete" {
        Invoke-DeleteCommand -CommandName "delete" -DeleteMode "restore" -RemainingArgs $remaining
    }
    "remove" {
        Invoke-DeleteCommand -CommandName "remove" -DeleteMode "remove" -RemainingArgs $remaining
    }
    "doctor" {
        Invoke-SetupCommand -SetupCommand "doctor" -RemainingArgs $remaining
    }
    "dry-run" {
        if ($dryRunRequested) {
            throw "Use either dry-run or --dry-run, not both"
        }
        & $SetupScript install -DryRun @remaining
    }
    "lock" {
        $lockArgs = $remaining
        if ($dryRunRequested) {
            $lockArgs = @("--dry-run") + $lockArgs
        }
        Run-Python -ScriptPath $GenerateLockScript -ScriptArgs $lockArgs
    }
    "update-pins" {
        $updatePinsArgs = $remaining
        if ($dryRunRequested) {
            $updatePinsArgs = @("--dry-run") + $updatePinsArgs
        }
        Run-Python -ScriptPath $UpdatePinsScript -ScriptArgs $updatePinsArgs
    }
    "completions" {
        Invoke-SetupCommand -SetupCommand "completions" -SupportsDryRun -RemainingArgs $remaining
    }
    "secrets" {
        Run-Python -ScriptPath $RenderSecretsScript -ScriptArgs (@("--repo-root", $RepoRoot) + $remaining)
    }
    "shell" {
        Invoke-ShellCommand -ShellArgs $remaining
    }
    "color" {
        Invoke-ColorCommand -ColorArgs $remaining
    }
    "delta" {
        Invoke-DeltaCommand -DeltaArgs $remaining
    }
    "agents" {
        Assert-NoDryRun -CommandName "agents"
        if ($remaining.Count -eq 0 -or $remaining[0] -in @("-h", "--help", "help")) {
            Show-CommandUsage "agents"
            exit 0
        }
        Require-PythonRuntime
        Run-Python -ScriptPath $AgentsToolScript -ScriptArgs (@("--repo-root", $RepoRoot) + $remaining)
    }
    "wm" {
        if ($remaining.Count -ge 2 -and $remaining[0] -eq "bar" -and $remaining[1] -in @("-h", "--help")) {
            Show-CommandUsage "wm bar"
            exit 0
        }
        if ($remaining.Count -ge 1 -and $remaining[0] -in @("-h", "--help")) {
            Show-CommandUsage "wm"
            exit 0
        }
        Invoke-WmCommand -WmArgs $remaining
    }
    "link" {
        if ($remaining.Count -gt 0 -and $remaining[0] -in @("-h", "--help", "help")) {
            Run-Python -ScriptPath (Join-Path $RepoRoot "scripts/link_manager.py") -ScriptArgs @("--help")
        } else {
            Invoke-SetupCommand -SetupCommand "link" -SupportsDryRun -RemainingArgs $remaining
        }
    }
    default {
        $suggestion = Get-CommandSuggestion -InputCommand $command
        Write-UnknownCommandMessage -Message "Unknown command: $command" -Suggestion $suggestion
        throw "Unknown command: $command"
    }
}

exit $LASTEXITCODE
