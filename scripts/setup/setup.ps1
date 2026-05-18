param(
    [string]$Command = "",
    [switch]$DryRun,
    [switch]$Help,
    [switch]$SkipDeps,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$DependencyKeys = @()
)

# Extract any stray global flags that PowerShell parameter binding leaked into ValueFromRemainingArguments
$filteredKeys = @()
foreach ($key in $DependencyKeys) {
    if ($key -eq "--dry-run" -or $key -eq "-n" -or $key -eq "-DryRun") {
        $DryRun = $true
    } elseif ($key -eq "--yes-optional") {
        $env:OOODNAKOV_INSTALL_OPTIONAL = "always"
    } elseif ($key -eq "--skip-deps") {
        $SkipDeps = $true
    } elseif ($key -eq "--all") {
        $filteredKeys += $key
    } else {
        $filteredKeys += $key
    }
}
$DependencyKeys = $filteredKeys

$ErrorActionPreference = "Stop"

# Allow syntax/import checks to dot-source this script without executing setup actions.
if ($MyInvocation.InvocationName -eq ".") {
    return
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path

# Dot-source ooodnakov.ps1 for shared UI functions
$OooconfPs1Path = Join-Path $RepoRoot "scripts/setup/ooodnakov.ps1"
if (Test-Path $OooconfPs1Path) {
    . $OooconfPs1Path
}

$OptionalDepsScript = Join-Path $RepoRoot "scripts/cli/read_optional_deps.py"
$AutogenCompletionsManifest = Join-Path $RepoRoot "scripts/generate/autogen-completions.txt"
$OooconfCompletionsGenerator = Join-Path $RepoRoot "scripts/cli/generate_oooconf_completions.py"
$HomeDir = $HOME
$ConfigHome = Join-Path $HomeDir ".config"
$DataHome = Join-Path $HomeDir ".local/share"
$StateHome = Join-Path $HomeDir ".local/state/ooodnakov-config"
$CacheHome = Join-Path $HomeDir ".cache/ooodnakov-config"
$ShareHome = Join-Path $HomeDir ".local/share/ooodnakov-config"
$LocalBinDir = Join-Path $HomeDir ".local/bin"
$OhMyPoshDir = Join-Path $ConfigHome "ohmyposh"
$PowerShellConfigDir = Join-Path $ConfigHome "powershell"
$PowerShellProfileTarget = Join-Path $PowerShellConfigDir "Microsoft.PowerShell_profile.ps1"
$ActivePowerShellProfile = $PROFILE.CurrentUserCurrentHost
$SshDir = Join-Path $HomeDir ".ssh"
$InteractiveMode = if ($env:OOODNAKOV_INTERACTIVE) { $env:OOODNAKOV_INTERACTIVE } else { "auto" }
$InstallOptionalMode = if ($env:OOODNAKOV_INSTALL_OPTIONAL) { $env:OOODNAKOV_INSTALL_OPTIONAL } else { "prompt" }
$VerboseMode = if ($env:OOODNAKOV_VERBOSE) { $env:OOODNAKOV_VERBOSE } else { "0" }
$BackupRoot = if ($env:OOODNAKOV_BACKUP_ROOT) { $env:OOODNAKOV_BACKUP_ROOT } else { Join-Path $HomeDir ".local/state/ooodnakov-config/backups" }
$LogRoot = if ($env:OOODNAKOV_LOG_ROOT) { $env:OOODNAKOV_LOG_ROOT } else { Join-Path $HomeDir ".local/state/ooodnakov-config/logs" }
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

# All versions/pins now live in optional-deps.toml ONLY (sole source of truth).
# These variables are removed. Use Get-DepInfo or Get-ManagedTool instead.
. (Join-Path $RepoRoot "scripts/setup/lib/setup-installers.ps1")
. (Join-Path $RepoRoot "scripts/setup/lib/setup-ui.ps1")
. (Join-Path $RepoRoot "scripts/setup/lib/setup-optional-deps.ps1")
. (Join-Path $RepoRoot "scripts/setup/lib/setup-summary.ps1")
. (Join-Path $RepoRoot "scripts/setup/lib/setup-links.ps1")
. (Join-Path $RepoRoot "scripts/setup/lib/setup-completions.ps1")
. (Join-Path $RepoRoot "scripts/setup/lib/setup-doctor.ps1")
. (Join-Path $RepoRoot "scripts/setup/lib/setup-dispatch.ps1")
try {
    $allPresent = $false
    $requestedDependencyKeys = @($DependencyKeys | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    # Handle --minimal flag
    if ($requestedDependencyKeys -contains "--minimal") {
        $minimalKeys = Run-Python (Join-Path $RepoRoot "scripts/cli/read_optional_deps.py") @("minimal")
        $requestedDependencyKeys = @($minimalKeys -split ' ' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        Write-Information "Installing minimal setup: $($requestedDependencyKeys -join ', ')" -InformationAction Continue
    } elseif ($Command -eq "deps" -and $requestedDependencyKeys -contains "--all") {
        $allKeys = @((Get-AllOptionalDependencySpecs).Key | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $requestedDependencyKeys = @($allKeys)
        Write-Information "Installing all optional dependencies: $($requestedDependencyKeys -join ', ')" -InformationAction Continue
    }

    if ($requestedDependencyKeys.Count -gt 0) {
        # Validate against ALL specs (including platform-inapplicable ones)
        $allKeys = @((Get-AllOptionalDependencySpecs).Key | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        foreach ($key in $requestedDependencyKeys) {
            if ($allKeys -notcontains $key) {
                $suggestion = Get-ClosestSuggestion -InputText $key -Candidates $allKeys
                if ($suggestion) {
                    throw "Unknown dependency key: $key`nDid you mean: $suggestion"
                }
                throw "Unknown dependency key: $key"
            }
            # Warn if the dep is not applicable to the current platform
            $spec = Get-AllOptionalDependencySpecs | Where-Object { $_.Key -eq $key }
            if (-not (Test-OptionalDependencyApplicable -Spec $spec)) {
                $platform = Detect-Platform
                Write-Information "Note: $key is not applicable on $platform; skipping." -InformationAction Continue
            }
        }
        $script:SelectedOptionalKeys = @($requestedDependencyKeys)
        $InstallOptionalMode = "always"
    } elseif ($Command -eq "deps") {
        if (-not (Test-Interactive)) {
            throw "oooconf deps needs explicit dependency keys in non-interactive mode."
        }

        $selected = @(Select-OptionalDependenciesWithGum)
        # $null means gum not available, fall back to text prompt
        if ($selected.Count -eq 1 -and $selected[0] -eq $null) {
            $selected = @(Select-OptionalDependenciesWithoutGum)
        }
        if ($selected.Count -eq 1 -and $selected[0] -eq "__all_present__") {
            $allPresent = $true
        }
        # User cancelled (Esc in gum picker, or empty input in text prompt) — exit cleanly
        if (-not $allPresent -and $selected.Count -eq 0) {
            Write-Output "No optional dependencies selected."
            return
        }
        if (-not $allPresent) {
            $script:SelectedOptionalKeys = $selected
            $InstallOptionalMode = "always"
        }
    }

    switch ($Command) {
        "install" {
            Invoke-Install
        }
        "update" {
            Start-StepProgress -Total 7 -Activity "oooconf update"
            Step-Progress -Status "Pulling latest repository changes"
            if ($DryRun) {
                Write-Output "[dry-run] git -C $RepoRoot pull --ff-only"
            } else {
                Invoke-ActionWithSpinner -Description "Pulling repository" -Action {
                    git -C $RepoRoot pull --ff-only
                }
            }
            Invoke-Install -ContinueProgress
        }
        "doctor" {
            if ($DryRun) {
                Write-Output "[dry-run] would run doctor checks"
                return
            }
            Test-Doctor
        }
        "deps" {
            if ($allPresent) {
                Write-Output "Optional dependency install complete."
                break
            }

            Start-StepProgress -Total 4 -Activity "oooconf deps"
            Step-Progress -Status "Preparing dependency install paths"
            foreach ($dir in @($DataHome, $StateHome, $ShareHome, (Join-Path $ShareHome "bin"), $LocalBinDir)) {
                if ($DryRun) {
                    Write-Output "[dry-run] ensure directory $dir"
                } else {
                    Ensure-Directory -Path $dir | Out-Null
                }
            }

            Step-Progress -Status "Installing selected optional dependencies"
            if ($DryRun) {
                Write-Output "[dry-run] install optional dependencies: $($script:SelectedOptionalKeys -join ', ')"
            } else {
                Install-OptionalDependencies
            }
            Step-Progress -Status "Writing dependency summary"
            Write-Summary
            Write-Output ""
            Write-Output "Optional dependency install complete."
            Step-Progress -Status "Done"
        }
        "completions" {
            Start-StepProgress -Total 4 -Activity "oooconf completions"
            Step-Progress -Status "Preparing completion output path"
            $completionsDir = Join-Path $RepoRoot "home/.config/ooodnakov/zsh/completions/autogen"
            if ($DryRun) {
                Write-Output "[dry-run] ensure directory $completionsDir"
            } else {
                Ensure-Directory -Path $completionsDir | Out-Null
            }
            Step-Progress -Status "Generating tracked autogen completions"
            if (-not $DryRun) {
                Generate-AutogenCompletions
            }
            Step-Progress -Status "Generating oooconf command completions"
            if (-not $DryRun) {
                Generate-OooconfCompletions
            }
            Write-Output ""
            Write-Output "Completion generation complete."
            Step-Progress -Status "Done"
        }
        "minimal" {
            if ($DryRun) {
                Write-Output "[dry-run] would run minimal-setup.sh"
                return
            }
            & (Join-Path $RepoRoot "scripts/setup/minimal-setup.ps1")
        }
        "link" {
            if ($DryRun) {
                Write-Output "[dry-run] would link:"
            }
            $linkOutput = Run-Python -ScriptPath (Join-Path $RepoRoot "scripts/link_manager.py") -ScriptArgs @("--repo-root", "$RepoRoot", "--format", "text") 2>$null
            if ($DryRun) {
                $linkOutput -split "`n" | ForEach-Object {
                    if ([string]::IsNullOrWhiteSpace($_)) { return }
                    $parts = $_ -split '\|'
                    if ($parts.Count -ge 3) {
                        Write-Output "[dry-run]   $($parts[2]) -> $($parts[1])"
                    }
                }
                return
            }
            $created = 0
            $existing = 0
            $failed = 0
            if (-not $DryRun) {
                Write-UiLine -Role info -Message "Linking managed configs..."
            }
            $linkOutput -split "`n" | ForEach-Object {
                if ([string]::IsNullOrWhiteSpace($_)) { return }
                $parts = $_ -split '\|'
                if ($parts.Count -ge 3) {
                    $key = $parts[0]
                    $source = $parts[1]
                    $target = $parts[2]
                    if (Test-LinkMatches -Source $source -Target $target) {
                        Write-UiLine -Role hint -Message "[skip] $key -> $target"
                        $existing++
                    } else {
                        if (New-Symlink -Source $source -Target $target) {
                            Write-UiLine -Role ok -Message "[link] $key -> $target"
                            $created++
                        } else {
                            Write-UiLine -Role fail -Message "[fail] $key -> $target"
                            $failed++
                        }
                    }
                }
            }
            Write-Output ""
            if ($failed -gt 0) {
                Write-UiLine -Role fail -Message "Failed: $failed | Linked: $created | Skipped: $existing"
            } elseif ($created -gt 0) {
                Write-UiLine -Role ok -Message "Linked: $created | Skipped: $existing"
            } else {
                Write-UiLine -Role hint -Message "All $existing links already exist"
            }
        }
    }
} finally {
    if ($script:LogFile) {
        Write-Output "Log file: $script:LogFile"
    }
    Stop-SetupLogging
}

if ($script:Failures.Count -gt 0) {
    exit 1
}
