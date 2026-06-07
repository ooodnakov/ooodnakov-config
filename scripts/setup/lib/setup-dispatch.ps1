# Dot-sourced by scripts/setup/setup.ps1; do not execute directly.

function Invoke-Install {
    param(
        [switch]$ContinueProgress
    )

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
    $linkOutput = Run-Python -ScriptPath (Join-Path $RepoRoot "scripts/link_manager.py") -ScriptArgs --repo-root "$RepoRoot" --format text 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($linkOutput)) {
        Write-Output "[warn] link_manager.py failed or returned no output; falling back to hardcoded links"
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/wezterm") -Target (Join-Path $ConfigHome "wezterm")) {
            Add-ToolSummary "wezterm: linked"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/yazi") -Target (Join-Path $ConfigHome "yazi")) {
            Add-ToolSummary "yazi: linked"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/lazygit") -Target (Join-Path $ConfigHome "lazygit")) {
            Add-ToolSummary "lazygit: linked"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/noctalia") -Target (Join-Path $ConfigHome "noctalia")) {
            Add-ToolSummary "noctalia: linked"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/nvim") -Target (Join-Path $ConfigHome "nvim")) {
            Add-ToolSummary "nvim: linked"

            # Sync LazyVim plugins non-interactively
            if (Get-Command nvim -ErrorAction SilentlyContinue) {
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
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/ooodnakov") -Target (Join-Path $ConfigHome "ooodnakov")) {
            Add-ToolSummary "ooodnakov config: linked"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/ohmyposh/ooodnakov.omp.json") -Target (Join-Path $OhMyPoshDir "ooodnakov.omp.json")) {
            Add-ToolSummary "oh-my-posh config: linked"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target $PowerShellProfileTarget) {
            Add-ToolSummary "PowerShell XDG profile: linked"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target $ActivePowerShellProfile) {
            Add-ToolSummary "PowerShell active profile: linked"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/oooconf.ps1") -Target (Join-Path $LocalBinDir "oooconf.ps1")) {
            Add-ToolSummary "oooconf.ps1: linked into $LocalBinDir"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/oooconf.cmd") -Target (Join-Path $LocalBinDir "oooconf.cmd")) {
            Add-ToolSummary "oooconf.cmd: linked into $LocalBinDir"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/o.ps1") -Target (Join-Path $LocalBinDir "o.ps1")) {
            Add-ToolSummary "o.ps1: linked into $LocalBinDir"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/o.cmd") -Target (Join-Path $LocalBinDir "o.cmd")) {
            Add-ToolSummary "o.cmd: linked into $LocalBinDir"
        }

        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/komorebi/komorebi.json") -Target (Join-Path $HomeDir "komorebi.json")) {
            Add-ToolSummary "komorebi: linked config"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/komorebi/komorebi.bar.json") -Target (Join-Path $HomeDir "komorebi.bar.json")) {
            Add-ToolSummary "komorebi-bar: linked config"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/komorebi/applications.json") -Target (Join-Path $HomeDir "applications.json")) {
            Add-ToolSummary "komorebi-applications: linked config"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/komorebi/whkdrc") -Target (Join-Path $ConfigHome "whkdrc")) {
            Add-ToolSummary "whkd: linked config"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.glzr/glazewm") -Target (Join-Path $HomeDir ".glzr/glazewm")) {
            Add-ToolSummary "glazewm: linked config directory"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.glzr/zebar") -Target (Join-Path $HomeDir ".glzr/zebar")) {
            Add-ToolSummary "zebar: linked config directory"
        }
    } else {
        $linkOutput -split "`n" | ForEach-Object {
            if ([string]::IsNullOrWhiteSpace($_)) { return }
            $parts = $_ -split '\|'
            if ($parts.Count -lt 3) { return }
            $key = $parts[0]
            $source = $parts[1]
            $target = $parts[2]
            if (New-Symlink -Source $source -Target $target) {
                Add-ToolSummary "linked: $key"
            }
        }

        # Sync LazyVim plugins non-interactively (nvim post-link hook)
        if (Get-Command nvim -ErrorAction SilentlyContinue) {
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
