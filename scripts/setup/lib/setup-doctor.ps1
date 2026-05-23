# Dot-sourced by scripts/setup/setup.ps1; do not execute directly.

function Test-DoctorLink {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    if (Test-LinkMatches -Source $Source -Target $Target) {
        Write-UiLine -Role ok -Message "$Target -> $Source"
        return
    }

    Write-UiLine -Role missing -Message "$Target (expected symlink to $Source)"
    $script:Failures.Add("doctor link $Target") | Out-Null
}

function Test-DoctorCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (Test-AnyCommand -Names @($Name)) {
        Write-UiLine -Role ok -Message "command: $Name"
        return
    }

    Write-UiLine -Role missing -Message "command: $Name"
    $script:Failures.Add("doctor command $Name") | Out-Null
}

function Get-MinimalDependencyKeys {
    if ($script:MinimalDependencyKeysCache) {
        return $script:MinimalDependencyKeysCache
    }

    $keys = @()
    try {
        $raw = Run-Python (Join-Path $RepoRoot "scripts/cli/read_optional_deps.py") @("minimal") 2>$null
        if ($raw) {
            $keys = @($raw -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    } catch {
    }

    if ($keys.Count -eq 0) {
        $keys = @((Get-OptionalDepsTomlFallbackData).MinimalKeys)
    }

    $script:MinimalDependencyKeysCache = @($keys | Select-Object -Unique)
    return $script:MinimalDependencyKeysCache
}

function Test-DoctorDependency {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Spec,
        [switch]$Required
    )

    if (-not $Spec -or [string]::IsNullOrWhiteSpace($Spec.Key)) {
        return
    }

    if (Test-OptionalDependencyPresent -Key $Spec.Key) {
        Write-UiLine -Role ok -Message "dependency: $($Spec.Key)"
        return
    }

    if ($Required) {
        Write-UiLine -Role missing -Message "dependency: $($Spec.Key)"
        $script:Failures.Add("doctor dependency $($Spec.Key)") | Out-Null
        return
    }

    Write-UiLine -Role hint -Message "dependency: $($Spec.Key) not installed"
}

function Test-DoctorOptionalCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (Test-AnyCommand -Names @($Name)) {
        Write-UiLine -Role ok -Message "optional command: $Name"
        return
    }

    Write-UiLine -Role hint -Message "command: $Name not installed"
}

function Test-Doctor {
    Write-UiLine -Role info -Message "Running doctor checks..."

    # Read links from manifest via link_manager.py for doctor checks
    $linkOutput = Run-Python -ScriptPath (Join-Path $RepoRoot "scripts/link_manager.py") -ScriptArgs --repo-root "$RepoRoot" --format text 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($linkOutput)) {
        $linkOutput -split "`n" | ForEach-Object {
            if ([string]::IsNullOrWhiteSpace($_)) { return }
            $parts = $_ -split '\|'
            if ($parts.Count -lt 3) { return }
            $key = $parts[0]
            $source = $parts[1]
            $target = $parts[2]
            Test-DoctorLink -Source $source -Target $target
        }
    } else {
        # Fallback to hardcoded links for older versions
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/wezterm") -Target (Join-Path $ConfigHome "wezterm")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/yazi") -Target (Join-Path $ConfigHome "yazi")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/lazygit") -Target (Join-Path $ConfigHome "lazygit")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/noctalia") -Target (Join-Path $ConfigHome "noctalia")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/nvim") -Target (Join-Path $ConfigHome "nvim")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov") -Target (Join-Path $ConfigHome "ooodnakov")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ohmyposh/ooodnakov.omp.json") -Target (Join-Path $OhMyPoshDir "ooodnakov.omp.json")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target $PowerShellProfileTarget
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target $ActivePowerShellProfile
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/oooconf.ps1") -Target (Join-Path $LocalBinDir "oooconf.ps1")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/oooconf.cmd") -Target (Join-Path $LocalBinDir "oooconf.cmd")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/o.ps1") -Target (Join-Path $LocalBinDir "o.ps1")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/o.cmd") -Target (Join-Path $LocalBinDir "o.cmd")

        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/komorebi/komorebi.json") -Target (Join-Path $HomeDir "komorebi.json")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/komorebi/komorebi.bar.json") -Target (Join-Path $HomeDir "komorebi.bar.json")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/komorebi/applications.json") -Target (Join-Path $HomeDir "applications.json")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/komorebi/whkdrc") -Target (Join-Path $ConfigHome "whkdrc")

        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.glzr/glazewm") -Target (Join-Path $HomeDir ".glzr/glazewm")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.glzr/zebar") -Target (Join-Path $HomeDir ".glzr/zebar")
    }

    Test-DoctorCommand -Name "oooconf"
    Test-DoctorCommand -Name "o"

    $requiredDependencyKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in (Get-MinimalDependencyKeys)) {
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $null = $requiredDependencyKeys.Add($key)
        }
    }
    foreach ($key in @("wezterm", "yazi", "nvim")) {
        $null = $requiredDependencyKeys.Add($key)
    }

    foreach ($spec in @(Get-OptionalDependencySpecs | Sort-Object Key)) {
        Test-DoctorDependency -Spec $spec -Required:$requiredDependencyKeys.Contains($spec.Key)
    }

    foreach ($commandName in @("komorebic", "whkd")) {
        Test-DoctorOptionalCommand -Name $commandName
    }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $userPathParts = @($userPath -split [IO.Path]::PathSeparator | Where-Object { $_ })
    if ($userPathParts -contains $LocalBinDir) {
        Write-UiLine -Role ok -Message "user PATH contains $LocalBinDir"
    } else {
        Write-UiLine -Role missing -Message "user PATH entry: $LocalBinDir"
        $script:Failures.Add("doctor user PATH") | Out-Null
    }

    if ($script:Failures.Count -gt 0) {
        Write-UiSpacer
        Write-UiLine -Role fail -Message "Doctor found $($script:Failures.Count) issue(s). Run 'oooconf install' to try fixing them."
        return
    }

    Write-UiLine -Role ok -Message "Doctor checks passed."
}
