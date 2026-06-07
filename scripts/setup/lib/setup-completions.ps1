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

function Generate-TrackedCompletions {
    Initialize-CompletionOutputPath
    Generate-AutogenCompletions
    Generate-OooconfCompletions
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
