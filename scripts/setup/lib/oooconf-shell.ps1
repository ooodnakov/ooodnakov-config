# Dot-sourced by scripts/setup/ooodnakov.ps1; do not execute directly.

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

function Get-ZshPromptMode {
    if ($env:OOOCONF_ZSH_PROMPT) {
        return $env:OOOCONF_ZSH_PROMPT
    }

    $envPath = Get-LocalEnvZshPath
    if (Test-Path -LiteralPath $envPath) {
        foreach ($line in Get-Content -LiteralPath $envPath) {
            if ($line -match "^export $([regex]::Escape($OooconfZshPromptVar))=""([^""]+)""$") {
                return $Matches[1]
            }
        }
    }
    return "p10k"
}

function Get-PromptStyleMode {
    if ($env:OOOCONF_PROMPT_STYLE) {
        return $env:OOOCONF_PROMPT_STYLE
    }

    $envZshPath = Get-LocalEnvZshPath
    if (Test-Path -LiteralPath $envZshPath) {
        foreach ($line in Get-Content -LiteralPath $envZshPath) {
            if ($line -match ('^export ' + [regex]::Escape($OooconfPromptStyleVar) + '="([^"]+)"$')) {
                return $Matches[1]
            }
        }
    }

    $envPs1Path = Get-LocalEnvPs1Path
    if (Test-Path -LiteralPath $envPs1Path) {
        foreach ($line in Get-Content -LiteralPath $envPs1Path) {
            if ($line -match ('^\$env:' + [regex]::Escape($OooconfPromptStyleVar) + " = '([^']+)'$")) {
                return $Matches[1]
            }
        }
    }

    return "verbose"
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

    return "suggest"
}

function Get-PsfzfTabMode {
    $envPath = Get-LocalEnvPs1Path
    if (Test-Path -LiteralPath $envPath) {
        foreach ($line in Get-Content -LiteralPath $envPath) {
            if ($line -match ('^\$env:' + [regex]::Escape($PsfzfTabVar) + " = '([^']+)'$")) {
                return $Matches[1]
            }
        }
    }
    return "enabled"
}

function Get-PsfzfGitMode {
    $envPath = Get-LocalEnvPs1Path
    if (Test-Path -LiteralPath $envPath) {
        foreach ($line in Get-Content -LiteralPath $envPath) {
            if ($line -match ('^\$env:' + [regex]::Escape($PsfzfGitVar) + " = '([^']+)'$")) {
                return $Matches[1]
            }
        }
    }
    return "enabled"
}

function Get-AutoUvEnvMode {
    if ($env:OOODNAKOV_AUTO_UV_ENV_MODE -in @("disabled", "existing", "enabled", "quiet")) {
        return $env:OOODNAKOV_AUTO_UV_ENV_MODE
    }

    $envZshPath = Get-LocalEnvZshPath
    if (Test-Path -LiteralPath $envZshPath) {
        foreach ($line in Get-Content -LiteralPath $envZshPath) {
            if ($line -match "^export $([regex]::Escape($OoodnakovAutoUvEnvModeVar))=""([^""]+)""$") {
                return $Matches[1]
            }
            if ($line -match "^export $([regex]::Escape($AutoUvEnvVar))=""1""$") {
                return "quiet"
            }
        }
    }

    $envPath = Get-LocalEnvPs1Path
    if (Test-Path -LiteralPath $envPath) {
        foreach ($line in Get-Content -LiteralPath $envPath) {
            if ($line -match ('^\$env:' + [regex]::Escape($OoodnakovAutoUvEnvModeVar) + " = '([^']+)'$")) {
                return $Matches[1]
            }
            if ($line -match ('^\$env:' + [regex]::Escape($AutoUvEnvVar) + " = 1$")) {
                return "quiet"
            }
        }
    }
    return "existing"
}

function Set-ZshPromptMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    if ($Mode -notin @("p10k", "ohmyposh")) {
        throw "Invalid zsh prompt mode: $Mode`nExpected one of: p10k, ohmyposh"
    }

    $envZsh = Get-LocalEnvZshPath
    Set-LocalOverrideLine -Path $envZsh -VariableName $OooconfZshPromptVar -ReplacementLine "export $OooconfZshPromptVar=""$Mode"""

    Write-UiLine -Role ok -Message "zsh prompt set to $Mode"
    Write-UiLine -Role info -Message "zsh: $envZsh"
    Write-UiLine -Role hint -Message "Open a new zsh session or run: exec zsh"
}

function Set-PromptStyleMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    if ($Mode -notin @("verbose", "concise")) {
        throw "Invalid prompt style: $Mode`nExpected one of: verbose, concise"
    }

    $envZsh = Get-LocalEnvZshPath
    $envPs1 = Get-LocalEnvPs1Path
    Set-LocalOverrideLine -Path $envZsh -VariableName $OooconfPromptStyleVar -ReplacementLine "export $OooconfPromptStyleVar=""$Mode"""
    Set-LocalOverrideLine -Path $envPs1 -VariableName $OooconfPromptStyleVar -ReplacementLine "`$env:$OooconfPromptStyleVar = '$Mode'"

    Write-UiLine -Role ok -Message "prompt style set to $Mode"
    Write-UiLine -Role info -Message "zsh: $envZsh"
    Write-UiLine -Role info -Message "pwsh: $envPs1"
    Write-UiLine -Role hint -Message "Open a new shell session to apply the change."
}

function Set-AutoUvEnvMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    if ($Mode -notin @("disabled", "existing", "enabled", "quiet")) {
        throw "Invalid auto-uv-env mode: $Mode`nExpected one of: disabled, existing, enabled, quiet"
    }

    $envZsh = Get-LocalEnvZshPath
    $envPs1 = Get-LocalEnvPs1Path

    $quietValue = if ($Mode -eq "quiet") { "1" } else { "0" }

    Set-LocalOverrideLine -Path $envZsh -VariableName $OoodnakovAutoUvEnvModeVar -ReplacementLine "export $OoodnakovAutoUvEnvModeVar=""$Mode"""
    Set-LocalOverrideLine -Path $envPs1 -VariableName $OoodnakovAutoUvEnvModeVar -ReplacementLine "`$env:$OoodnakovAutoUvEnvModeVar = '$Mode'"
    Set-LocalOverrideLine -Path $envZsh -VariableName $AutoUvEnvVar -ReplacementLine "export $AutoUvEnvVar=""$quietValue"""
    Set-LocalOverrideLine -Path $envPs1 -VariableName $AutoUvEnvVar -ReplacementLine "`$env:$AutoUvEnvVar = $quietValue"

    Write-UiLine -Role ok -Message "auto-uv-env mode set to $Mode"
    Write-UiLine -Role info -Message "zsh: $envZsh"
    Write-UiLine -Role info -Message "pwsh: $envPs1"
    Write-UiLine -Role hint -Message "Open a new shell session to apply the change."
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

    Write-UiLine -Role ok -Message "forgit alias mode set to $Mode"
    Write-UiLine -Role info -Message "zsh: $envZsh"
    Write-UiLine -Role info -Message "pwsh: $envPs1"
    Write-UiLine -Role hint -Message "Open a new shell session to apply the change."
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

    Write-UiLine -Role ok -Message "typo handling mode set to $Mode"
    Write-UiLine -Role info -Message "zsh: $envZsh"
    Write-UiLine -Role info -Message "pwsh: $envPs1"
    Write-UiLine -Role hint -Message "Open a new shell session to apply the change."
}

function Set-PsfzfTabMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    if ($Mode -notin @("enabled", "disabled")) {
        throw "Invalid psfzf-tab mode: $Mode`nExpected one of: enabled, disabled"
    }

    $envPs1 = Get-LocalEnvPs1Path
    Set-LocalOverrideLine -Path $envPs1 -VariableName $PsfzfTabVar -ReplacementLine "`$env:$PsfzfTabVar = '$Mode'"

    Write-UiLine -Role ok -Message "psfzf-tab mode set to $Mode"
    Write-UiLine -Role info -Message "pwsh: $envPs1"
    Write-UiLine -Role hint -Message "Open a new shell session to apply the change."
}

function Set-PsfzfGitMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    if ($Mode -notin @("enabled", "disabled")) {
        throw "Invalid psfzf-git mode: $Mode`nExpected one of: enabled, disabled"
    }

    $envPs1 = Get-LocalEnvPs1Path
    Set-LocalOverrideLine -Path $envPs1 -VariableName $PsfzfGitVar -ReplacementLine "`$env:$PsfzfGitVar = '$Mode'"

    Write-UiLine -Role ok -Message "psfzf-git mode set to $Mode"
    Write-UiLine -Role info -Message "pwsh: $envPs1"
    Write-UiLine -Role hint -Message "Open a new shell session to apply the change."
}

function Show-ShellStatus {
    Write-UiLine -Role info -Message "forgit-aliases: $(Get-ForgitAliasMode)"
    Write-UiLine -Role info -Message "typo-handling: $(Get-TypoHandlingMode)"
    Write-UiLine -Role info -Message "psfzf-tab: $(Get-PsfzfTabMode)"
    Write-UiLine -Role info -Message "psfzf-git: $(Get-PsfzfGitMode)"
    Write-UiLine -Role info -Message "prompt: $(Get-ZshPromptMode)"
    Write-UiLine -Role info -Message "prompt-style: $(Get-PromptStyleMode)"
    Write-UiLine -Role info -Message "auto-uv-env: $(Get-AutoUvEnvMode)"
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
        "status" { Show-ShellStatus; return }

        "prompt" {
            $mode = if ($ShellArgs.Count -gt 1) { $ShellArgs[1] } else { "status" }
            switch ($mode) {
                "status" { Write-Output (Get-ZshPromptMode) }
                "p10k" { Set-ZshPromptMode -Mode $mode }
                "ohmyposh" { Set-ZshPromptMode -Mode $mode }
                default {
                    $suggestion = Get-SuggestionFromList -InputValue $mode -Candidates $KnownShellPromptModes
                    Write-UnknownCommandMessage -Message "Unknown shell option: $mode" -Suggestion $suggestion -Scope shell
                    throw "Unknown shell option: $mode`nExpected one of: p10k, ohmyposh, status"
                }
            }
            return
        }
        "prompt-style" {
            $mode = if ($ShellArgs.Count -gt 1) { $ShellArgs[1] } else { "status" }
            switch ($mode) {
                "status" { Write-Output (Get-PromptStyleMode) }
                "verbose" { Set-PromptStyleMode -Mode $mode }
                "concise" { Set-PromptStyleMode -Mode $mode }
                default {
                    $suggestion = Get-SuggestionFromList -InputValue $mode -Candidates $KnownShellPromptStyleModes
                    Write-UnknownCommandMessage -Message "Unknown shell option: $mode" -Suggestion $suggestion -Scope shell
                    throw "Unknown shell option: $mode`nExpected one of: verbose, concise, status"
                }
            }
            return
        }
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
        "psfzf-tab" {
            $mode = if ($ShellArgs.Count -gt 1) { $ShellArgs[1] } else { "status" }
            switch ($mode) {
                "status" { Write-Output (Get-PsfzfTabMode) }
                "enabled" { Set-PsfzfTabMode -Mode $mode }
                "disabled" { Set-PsfzfTabMode -Mode $mode }
                default {
                    $suggestion = Get-SuggestionFromList -InputValue $mode -Candidates $KnownShellPsfzfModes
                    Write-UnknownCommandMessage -Message "Unknown shell option: $mode" -Suggestion $suggestion -Scope shell
                    throw "Unknown shell option: $mode`nExpected one of: enabled, disabled, status"
                }
            }
            return
        }
        "psfzf-git" {
            $mode = if ($ShellArgs.Count -gt 1) { $ShellArgs[1] } else { "status" }
            switch ($mode) {
                "status" { Write-Output (Get-PsfzfGitMode) }
                "enabled" { Set-PsfzfGitMode -Mode $mode }
                "disabled" { Set-PsfzfGitMode -Mode $mode }
                default {
                    $suggestion = Get-SuggestionFromList -InputValue $mode -Candidates $KnownShellPsfzfModes
                    Write-UnknownCommandMessage -Message "Unknown shell option: $mode" -Suggestion $suggestion -Scope shell
                    throw "Unknown shell option: $mode`nExpected one of: enabled, disabled, status"
                }
            }
            return
        }
        "auto-uv-env" {
            $mode = if ($ShellArgs.Count -gt 1) { $ShellArgs[1] } else { "status" }
            switch ($mode) {
                "status" { Write-Output (Get-AutoUvEnvMode) }
                "disabled" { Set-AutoUvEnvMode -Mode $mode }
                "existing" { Set-AutoUvEnvMode -Mode $mode }
                "enabled" { Set-AutoUvEnvMode -Mode $mode }
                "quiet" { Set-AutoUvEnvMode -Mode $mode }
                default {
                    $suggestion = Get-SuggestionFromList -InputValue $mode -Candidates $KnownShellAutoUvModes
                    Write-UnknownCommandMessage -Message "Unknown shell option: $mode" -Suggestion $suggestion -Scope shell
                    throw "Unknown shell option: $mode`nExpected one of: disabled, existing, enabled, quiet, status"
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
