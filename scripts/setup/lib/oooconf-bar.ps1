# Dot-sourced by scripts/setup/ooodnakov.ps1; do not execute directly.

function Invoke-BarCommand {
    param([string[]]$BarArgs)
    $action = if ($BarArgs.Count -gt 0) { $BarArgs[0] } else { "" }
    $remainingArgs = if ($BarArgs.Count -gt 1) { $BarArgs[1..($BarArgs.Count - 1)] } else { @() }
    switch ($action) {
        "-h" { $action = "help" }
        "--help" { $action = "help" }
        "" {
            Write-UiHelpBlock @"
Usage: oooconf wm bar set <type>
       oooconf wm bar zebar-config status
       oooconf wm bar zebar-config list
       oooconf wm bar zebar-config set <name>

Set or inspect the default bar type (zebar/yabs) used when activating a WM.
Bar type determines which bar loads on wm start:
  zebar  - loads komorebi-bar with zebar provider (default)
  yabs   - future replacement bar (not implemented yet)

Subcommands:
  set           set or show default bar type
  zebar-config  manage zebar configs (status, list, set)
Examples:
  oooconf wm bar set              # show current bar type
  oooconf wm bar set zebar        # set to zebar
  oooconf wm bar set yabs         # set to yabs (future)
  oooconf wm bar zebar-config list
"@
            return
        }
        "set" {
            Invoke-BarSetCommand $remainingArgs
            return
        }
        "zebar-config" { Invoke-ZebarConfigCommand -ZebarArgs $remainingArgs; return }
        "stop" {
            Stop-Process -Name "komorebi-bar" -ErrorAction SilentlyContinue
            Stop-Process -Name "zebar" -ErrorAction SilentlyContinue
            Write-UiLine -Role ok -Message "Bar stopped."
            return
        }
        "start" {
            $zebarCommand = Get-Command zebar -ErrorAction SilentlyContinue
            if (-not $zebarCommand) {
                Write-UiLine -Role warn -Message "Zebar is not installed. Run 'oooconf deps zebar' first."
                return
            }
            & $zebarCommand.Source startup *> $null
            Write-UiLine -Role ok -Message "Bar started."
            return
        }
        "reload" {
            Stop-Process -Name "komorebi-bar" -ErrorAction SilentlyContinue
            Stop-Process -Name "zebar" -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
            $zebarCommand = Get-Command zebar -ErrorAction SilentlyContinue
            if ($zebarCommand) {
                & $zebarCommand.Source startup *> $null
            }
            Write-UiLine -Role ok -Message "Bar reloaded."
            return
        }
        "help" {
            Write-UiHelpBlock @"
Usage: oooconf wm bar set <type>
       oooconf wm bar zebar-config status
       oooconf wm bar zebar-config list
       oooconf wm bar zebar-config set <name>

Subcommands:
  set           set or show default bar type
  zebar-config  manage zebar configs (status, list, set)
  stop          stop zebar and komorebi-bar (keep komorebi running)
  start         start zebar with configured settings
  reload        restart zebar (stop then start)
  help          show this help
"@
            return
        }
        default {
            $suggestion = Get-SuggestionFromList -InputValue $action -Candidates $KnownBarSubcommands
            Write-UnknownCommandMessage -Message "Unknown bar subcommand: $action" -Suggestion $suggestion -Scope "wm bar"
            throw "Unknown bar subcommand: $action"
        }
    }
}

function Get-DefaultBarType {
    $configPath = Get-ZebarConfigRoot
    $settingsPath = Join-Path $configPath "config.yaml"
    if (-not (Test-Path $settingsPath)) {
        return "zebar"  # default
    }
    $content = Get-Content -Path $settingsPath -Raw
    if ($content -match 'default_bar_type:\s*(\S+)') {
        return $matches[1]
    }
    return "zebar"  # default
}

function Set-DefaultBarType {
    param([string]$Type)
    if ($Type -notin $KnownBarTypes) {
        Write-UiLine -Role fail -Message "Unknown bar type: $Type. Available: $($KnownBarTypes -join ', ')"
        return $false
    }
    $configPath = Get-ZebarConfigRoot
    $settingsPath = Join-Path $configPath "config.yaml"
    if (-not (Test-Path $settingsPath)) {
        Write-UiLine -Role fail -Message "Zebar config.yaml not found at $settingsPath."
        return $false
    }
    $content = Get-Content -Path $settingsPath -Raw
    if ($content -match 'default_bar_type:\s*\S+') {
        $content = $content -replace 'default_bar_type:\s*\S+', "default_bar_type: $Type"
    } else {
        $content = $content -replace '(?m)^(window:)', ("default_bar_type: $Type`n`$1")
    }
    Set-Content -Path $settingsPath -Value $content
    return $true
}

function Invoke-BarSetCommand {
    if ($Args.Count -eq 0 -or $Args[0] -notin $KnownBarTypes) {
        $current = Get-DefaultBarType
        Write-UiLine -Role info -Message "Current default bar type: $current"
        Write-UiLine -Role hint -Message "Usage: wm bar set <type>  (available: $($KnownBarTypes -join ', '))"
        return
    }
    $type = $Args[0]
    $result = Set-DefaultBarType -Type $type
    if ($result) {
        Write-UiLine -Role ok -Message "Default bar type set to $type."
    }
}
