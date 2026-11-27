# Dot-sourced by scripts/setup/ooodnakov.ps1; do not execute directly.

function Test-HelpPythonAvailable {
    $renderHelp = Join-Path $RepoRoot "scripts/cli/render_help.py"
    if (-not (Test-Path -LiteralPath $renderHelp)) {
        return $false
    }
    $pyprojectPath = Join-Path $RepoRoot "pyproject.toml"
    if ((Get-Command uv -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $pyprojectPath)) {
        return $true
    }
    foreach ($candidate in @("python3", "python", "py")) {
        if (Get-Command $candidate -ErrorAction SilentlyContinue) {
            return $true
        }
    }
    return $false
}

function Get-KnownCommands {
    $fallback = @("install", "deps", "update", "doctor", "status", "snapshot", "dry-run", "delete", "remove", "lock", "update-pins", "completions", "agents", "fleet", "secrets", "shell", "color", "delta", "version", "check", "preview", "upgrade")
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
            if ($Scope -in @("shell", "wm", "wm bar", "color", "delta")) {
                Show-CommandUsage $Scope
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

    if ($Left -ceq $Right) { return 0 }
    return [Math]::Abs($Left.Length - $Right.Length) + 1
}

function Get-FallbackSuggestion {
    param(
        [string]$InputValue,
        [string[]]$Candidates
    )

    if ([string]::IsNullOrWhiteSpace($InputValue)) { return $null }
    foreach ($candidate in @($Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        if ([string]$candidate -ceq $InputValue) { return [string]$candidate }
    }
    foreach ($candidate in @($Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        if (([string]$candidate).StartsWith($InputValue)) { return [string]$candidate }
    }
    return $null
}

function Get-CommandSuggestion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputCommand
    )

    if (-not [string]::IsNullOrWhiteSpace($InputCommand) -and (Test-HelpPythonAvailable)) {
        $renderHelp = Join-Path $RepoRoot "scripts/cli/render_help.py"
        $result = Run-Python -ScriptPath $renderHelp -ScriptArgs @("--mode", "suggest", "--repo-root", $RepoRoot, "--platform", "windows", "--input", $InputCommand)
        if ($global:LASTEXITCODE -eq 0) {
            $text = (($result | Out-String).Trim())
            if ($text) { return $text }
            return $null
        }
    }

    return Get-FallbackSuggestion -InputValue $InputCommand -Candidates $KnownCommands
}

function Get-SuggestionFromList {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputValue,
        [Parameter(Mandatory = $true)]
        [string[]]$Candidates
    )

    if (-not [string]::IsNullOrWhiteSpace($InputValue) -and $Candidates.Count -gt 0 -and (Test-HelpPythonAvailable)) {
        $renderHelp = Join-Path $RepoRoot "scripts/cli/render_help.py"
        $scriptArgs = @("--mode", "suggest", "--repo-root", $RepoRoot, "--input", $InputValue, "--candidates") + $Candidates
        $result = Run-Python -ScriptPath $renderHelp -ScriptArgs $scriptArgs
        if ($global:LASTEXITCODE -eq 0) {
            $text = (($result | Out-String).Trim())
            if ($text) { return $text }
            return $null
        }
    }

    return Get-FallbackSuggestion -InputValue $InputValue -Candidates $Candidates
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

function Get-RenderHelpCommonArgs {
    $argsList = @("--repo-root", $RepoRoot, "--platform", "windows")
    if ((Test-UiInteractive) -and (${env:OOOCONF_UI} -notin @("stdout", "off", "never"))) {
        $argsList += "--interactive"
    }
    return $argsList
}

function Show-UsageFallback {
    Write-Output @"
Usage: oooconf [global options] <command> [command options]

Setup: bootstrap (Unix), install, deps, update
Inspect: doctor, status, snapshot, plan, apply, rollback, dry-run, version
Manage: delete, remove, lock, update-pins, completions, link
Tools: shell, color, delta, secrets, env, agents, fleet, wm
Aliases: check -> doctor, preview -> dry-run, upgrade -> update
Repo root: $RepoRoot
"@
}

function Show-Usage {
    if (Test-HelpPythonAvailable) {
        $renderHelp = Join-Path $RepoRoot "scripts/cli/render_help.py"
        $scriptArgs = @("--mode", "main") + (Get-RenderHelpCommonArgs)
        $output = Run-Python -ScriptPath $renderHelp -ScriptArgs $scriptArgs
        if ($global:LASTEXITCODE -eq 0) {
            $output | ForEach-Object { Write-Output $_ }
            return
        }
    }
    Show-UsageFallback
}

function Show-CommandUsage {
    param([string]$command = "")

    $resolved = Resolve-CommandAlias -CommandName ([string]$command)
    if ($resolved -in @("", "help", "-h", "--help")) {
        Show-Usage
        return
    }

    if (Test-HelpPythonAvailable) {
        $renderHelp = Join-Path $RepoRoot "scripts/cli/render_help.py"
        $scriptArgs = @("--mode", "command", "--command", $resolved, "--quiet-unknown") + (Get-RenderHelpCommonArgs)
        $output = Run-Python -ScriptPath $renderHelp -ScriptArgs $scriptArgs
        if ($global:LASTEXITCODE -eq 0) {
            $output | ForEach-Object { Write-Output $_ }
            return
        }
        if ($global:LASTEXITCODE -eq 2) {
            $suggestion = Get-CommandSuggestion -InputCommand $resolved
            Write-UnknownCommandMessage -Message "Unknown command: $resolved" -Suggestion $suggestion
            throw "Unknown command: $resolved"
        }
    }

    if ($resolved -eq "delta") {
        Invoke-DeltaCommand -DeltaArgs @("help")
        return
    }

    $known = Get-KnownCommands
    if ($resolved -in ($known + @("plan", "apply", "rollback", "link", "wm", "wm bar", "komorebi"))) {
        Write-UiSection -Title "oooconf $resolved"
        Show-UsageFallback
        return
    }

    $suggestion = Get-CommandSuggestion -InputCommand $resolved
    Write-UnknownCommandMessage -Message "Unknown command: $resolved" -Suggestion $suggestion
    throw "Unknown command: $resolved"
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
