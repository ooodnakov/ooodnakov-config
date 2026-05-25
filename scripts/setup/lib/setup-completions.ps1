# Dot-sourced by scripts/setup/setup.ps1; do not execute directly.

function Generate-AutogenCompletions {
    $targetDir = Join-Path $RepoRoot "home/.config/ooodnakov/zsh/completions/autogen"
    if ($DryRun) {
        Write-Output "[dry-run] Generating autogen completions in $targetDir"
        return
    }

    Ensure-Directory -Path $targetDir | Out-Null

    if (-not (Test-Path $AutogenCompletionsManifest)) {
        Add-ToolSummary "autogen completions: manifest missing ($AutogenCompletionsManifest)"
        return
    }

    $completionSpecs = Get-Content -Path $AutogenCompletionsManifest -ErrorAction SilentlyContinue
    foreach ($line in $completionSpecs) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.Trim().StartsWith("#")) {
            continue
        }

        $parts = $line -split "\|", 4
        if ($parts.Count -lt 4) {
            continue
        }
        $commandName = $parts[0].Trim()
        $description = $parts[1].Trim()
        $outputFile = Join-Path $targetDir ($parts[2].Trim())
        $commandLine = $parts[3].Trim()

        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            continue
        }

        Invoke-ActionWithSpinner -Description $description -Action {
            param($lineToRun, $targetFile, $workingDirectory)
            Push-Location $workingDirectory
            try {
                $content = @(Invoke-Expression $lineToRun)
                $normalized = [string]::Join("`n", $content) + "`n"
                [System.IO.File]::WriteAllText($targetFile, $normalized, (New-Object System.Text.UTF8Encoding $false))
            } finally {
                Pop-Location
            }
        } -ArgumentList $commandLine, $outputFile, $RepoRoot
    }
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
