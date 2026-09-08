# Dot-sourced by scripts/setup/setup.ps1; do not execute directly.

function Invoke-Install {
    param(
        [switch]$ContinueProgress
    )

    Run-Python -ScriptPath (Join-Path $RepoRoot "scripts/cli/operation_plan.py") -ScriptArgs @("--repo-root", "$RepoRoot", "--scope", "links", "--emit-links") | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Managed link plan validation failed before setup mutation"
    }

    if (-not $ContinueProgress) {
        Start-StepProgress -Total 6 -Activity "oooconf $Command"
    }
    Step-Progress -Status "Preparing directories"
    foreach ($dir in @($ConfigHome, $DataHome, $CacheHome, $StateHome, $ShareHome, (Join-Path $ShareHome "bin"), $LocalBinDir, $OhMyPoshDir, $PowerShellConfigDir)) {
        if (Ensure-Directory -Path $dir) {
            Add-ToolSummary "ensured directory: $dir"
        }
    }

    Step-Progress -Status "Checking/installing optional dependencies"
    Install-OptionalDependencies

    Step-Progress -Status "Linking managed configuration"
    Run-Python -ScriptPath (Join-Path $RepoRoot "scripts/cli/transaction_apply.py") -ScriptArgs @("--repo-root", "$RepoRoot", "apply")
    if ($LASTEXITCODE -ne 0) {
        throw "Managed link transaction failed"
    }

    # Sync LazyVim plugins non-interactively (nvim post-link hook)
    if ((Test-LinkMatches -Source (Join-Path $RepoRoot "home/.config/nvim") -Target (Join-Path $ConfigHome "nvim")) -and (Get-Command nvim -ErrorAction SilentlyContinue)) {
        $syncExitCode = Invoke-WithProgress -Description "Syncing LazyVim plugins" -Action {
            param($stdoutLog, $stderrLog)
            Start-Process -FilePath "nvim" `
                -ArgumentList @("--headless", "+Lazy! sync", "+qa") `
                -NoNewWindow `
                -RedirectStandardOutput $stdoutLog `
                -RedirectStandardError $stderrLog `
                -PassThru
        }

        if ($syncExitCode -eq 0) {
            Add-ToolSummary "nvim: plugins synced"
        } else {
            Write-Warning "LazyVim plugin sync exited with code $syncExitCode"
        }
    }

    if (Ensure-UserPathContains -PathEntry $LocalBinDir) {
        Add-ToolSummary "user PATH: ensured $LocalBinDir"
    }
    if (Add-SshInclude) {
        Add-ToolSummary "ssh include: ensured"
    }

    Step-Progress -Status "Generating completion files and platform integrations"
    Generate-TrackedCompletions

    Step-Progress -Status "Writing setup summary"
    Write-Summary
    Write-Output ""
    Write-Output "Bootstrap complete."
    Write-Output "If needed, create local overrides in $ConfigHome/ooodnakov/local."
    Step-Progress -Status "Done"
}

Start-SetupLogging
