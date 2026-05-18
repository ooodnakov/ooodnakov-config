# Dot-sourced by scripts/setup/ooodnakov.ps1; do not execute directly.

function Get-OooconfColorMode {
    if ($env:OOOCONF_COLOR_MODE -in $KnownColorModes) {
        return $env:OOOCONF_COLOR_MODE
    }

    $envZsh = Get-LocalEnvZshPath
    if (Test-Path -LiteralPath $envZsh) {
        foreach ($line in Get-Content -LiteralPath $envZsh) {
            if ($line -match ('^export ' + [regex]::Escape($OooconfColorModeVar) + '="([^"]+)"$') -and $Matches[1] -in $KnownColorModes) {
                return $Matches[1]
            }
        }
    }

    $envPs1 = Get-LocalEnvPs1Path
    if (Test-Path -LiteralPath $envPs1) {
        foreach ($line in Get-Content -LiteralPath $envPs1) {
            if ($line -match ('^\$env:' + [regex]::Escape($OooconfColorModeVar) + " = '([^']+)'$") -and $Matches[1] -in $KnownColorModes) {
                return $Matches[1]
            }
        }
    }

    return "dark"
}

function Get-OooconfTheme {
    if ($env:OOOCONF_THEME) {
        return $env:OOOCONF_THEME
    }

    $envPath = Get-LocalEnvZshPath
    if (Test-Path -LiteralPath $envPath) {
        foreach ($line in Get-Content -LiteralPath $envPath) {
            if ($line -match "^export $([regex]::Escape($OooconfThemeVar))=""([^""]+)""$") {
                return $Matches[1]
            }
        }
    }
    $repoTheme = Get-RepoColorTheme
    if ($repoTheme) {
        return $repoTheme
    }
    return "default"
}

function Get-RepoColorTheme {
    $weztermMain = Join-Path $RepoRoot "home/.config/wezterm/wezterm.lua"
    if (Test-Path -LiteralPath $weztermMain) {
        $raw = Get-Content -LiteralPath $weztermMain -Raw
        if ($raw -match "Noctalia") {
            return "noctalia"
        }
    }

    $weztermGeneral = Join-Path $RepoRoot "home/.config/wezterm/config/general.lua"
    if (Test-Path -LiteralPath $weztermGeneral) {
        $raw = Get-Content -LiteralPath $weztermGeneral -Raw
        if ($raw -match "(?i)catppuccin") {
            return "catppuccin"
        }
    }

    $nvimColors = Join-Path $RepoRoot "home/.config/nvim/lua/plugins/colorscheme.lua"
    if (Test-Path -LiteralPath $nvimColors) {
        $raw = Get-Content -LiteralPath $nvimColors -Raw
        if ($raw -match "(?i)catppuccin") {
            return "catppuccin"
        }
    }

    return $null
}

function Set-OooconfTheme {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Theme,
        [string]$Mode = (Get-OooconfColorMode)
    )

    if ($Theme -notin $KnownColorThemes) {
        throw "Invalid theme: $Theme`nExpected one of: $($KnownColorThemes -join ', ')"
    }
    if ($Mode -notin $KnownColorModes) {
        throw "Invalid color mode: $Mode`nExpected one of: $($KnownColorModes -join ', ')"
    }

    $envZsh = Get-LocalEnvZshPath
    $envPs1 = Get-LocalEnvPs1Path
    $ompConfigPath = Join-Path (Get-ShellConfigHome) "local/ohmyposh/$Theme-$Mode.omp.json"
    Set-LocalOverrideLine -Path $envZsh -VariableName $OooconfThemeVar -ReplacementLine "export $OooconfThemeVar=""$Theme"""
    Set-LocalOverrideLine -Path $envPs1 -VariableName $OooconfThemeVar -ReplacementLine "`$env:$OooconfThemeVar = '$Theme'"
    Set-LocalOverrideLine -Path $envZsh -VariableName $OooconfColorModeVar -ReplacementLine "export $OooconfColorModeVar=""$Mode"""
    Set-LocalOverrideLine -Path $envPs1 -VariableName $OooconfColorModeVar -ReplacementLine "`$env:$OooconfColorModeVar = '$Mode'"
    Set-LocalOverrideLine -Path $envZsh -VariableName $OooconfOmpConfigVar -ReplacementLine "export $OooconfOmpConfigVar=""$ompConfigPath"""
    Set-LocalOverrideLine -Path $envPs1 -VariableName $OooconfOmpConfigVar -ReplacementLine "`$env:$OooconfOmpConfigVar = '$ompConfigPath'"

    Write-UiLine -Role ok -Message "oooconf theme set to $Theme ($Mode)"
    Write-UiLine -Role info -Message "zsh: $envZsh"
    Write-UiLine -Role info -Message "pwsh: $envPs1"
    Run-Python -ScriptPath $SyncColorThemeScript -ScriptArgs @("apply", "--theme", $Theme, "--mode", $Mode)
    Write-UiLine -Role hint -Message "Open a new shell session to apply the theme globally."
}

function Set-OooconfColorMode {
    param([Parameter(Mandatory = $true)][string]$Mode)
    if ($Mode -notin $KnownColorModes) {
        throw "Invalid color mode: $Mode`nExpected one of: $($KnownColorModes -join ', ')"
    }
    Set-OooconfTheme -Theme (Get-OooconfTheme) -Mode $Mode
}

function Invoke-ColorCommand {
    param(
        [string[]]$ColorArgs
    )

    $action = if ($ColorArgs.Count -gt 0) { $ColorArgs[0] } else { "status" }
    switch ($action) {
        "status" {
            Write-Output "theme=$(Get-OooconfTheme)"
            Write-Output "mode=$(Get-OooconfColorMode)"
            Run-Python -ScriptPath $SyncColorThemeScript -ScriptArgs @("status")
        }
        "list" {
            $KnownColorThemes + $KnownColorModes | ForEach-Object { Write-Output $_ }
        }
        "help" { Show-CommandUsage "color" }
        "-h" { Show-CommandUsage "color" }
        "--help" { Show-CommandUsage "color" }
        "dark" { Set-OooconfColorMode -Mode $action }
        "light" { Set-OooconfColorMode -Mode $action }
        default { Set-OooconfTheme -Theme $action }
    }
}
