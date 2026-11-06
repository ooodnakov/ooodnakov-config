# Dot-sourced by scripts/setup/setup.ps1; do not execute directly.

function Get-AutogenCompletionsTargetDir {
    Join-Path $RepoRoot "home/.config/ooodnakov/zsh/completions/autogen"
}

function Initialize-CompletionOutputPath {
    $targetDir = Get-AutogenCompletionsTargetDir
    if ($DryRun) {
        Write-Output "[dry-run] ensure directory $targetDir"
        return
    }

    Ensure-Directory -Path $targetDir | Out-Null
}

function Generate-AutogenCompletions {
    if (-not (Test-Path $AutogenCompletionsGenerator)) {
        Add-ToolSummary "autogen completions: generator missing ($AutogenCompletionsGenerator)"
        return
    }

    if ($DryRun) {
        Run-Python -ScriptPath $AutogenCompletionsGenerator -ScriptArgs @("--dry-run")
        return
    }

    Invoke-ActionWithSpinner -Description "Generating autogen tool completions" -Action {
        param($scriptPath)
        $null = Run-Python -ScriptPath $scriptPath -ScriptArgs @()
    } -ArgumentList $AutogenCompletionsGenerator
}

function Generate-OooconfCompletions {
    if ($DryRun) {
        Write-Output "[dry-run] Generating oooconf command completions"
        return
    }

    if (-not (Test-Path $OooconfCompletionsGenerator)) {
        Add-ToolSummary "oooconf completions: generator missing ($OooconfCompletionsGenerator)"
        return
    }

    Invoke-ActionWithSpinner -Description "Generating oooconf command completions" -Action {
        param($scriptPath)
        $null = Run-Python -ScriptPath $scriptPath -ScriptArgs @()
    } -ArgumentList $OooconfCompletionsGenerator
}

function Generate-PowerShellCompletions {
    $generator = Join-Path $RepoRoot "scripts/generate/generate_powershell_completions.ps1"
    if (-not (Test-Path -LiteralPath $generator)) {
        Add-ToolSummary "PowerShell completions: generator missing ($generator)"
        return
    }

    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCommand) {
        Add-ToolSummary "PowerShell completions: pwsh not found"
        return
    }

    if ($DryRun) {
        Write-Output "[dry-run] Generating PowerShell completion cache"
        return
    }

    Invoke-ActionWithSpinner -Description "Generating PowerShell completion cache" -Action {
        param($pwshPath, $scriptPath)
        & $pwshPath -NoLogo -NoProfile -File $scriptPath
    } -ArgumentList @($pwshCommand.Source, $generator) | Out-Null
}

function Generate-TrackedCompletions {
    Initialize-CompletionOutputPath
    Generate-AutogenCompletions
    Generate-OooconfCompletions
    Generate-PowerShellCompletions
}

function Add-NewlyAvailableCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CommandNames
    )
    foreach ($cmd in $CommandNames) {
        if ($null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            if ($script:NewlyAvailableCommands -notcontains $cmd) {
                $script:NewlyAvailableCommands.Add($cmd)
            }
            return
        }
    }
}
