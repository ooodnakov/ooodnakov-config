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
        $raw = Run-Python (Join-Path $RepoRoot "scripts/cli/read_optional_deps.py") @("minimal", (Detect-Platform)) 2>$null
        if ($raw) {
            $keys = @($raw -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    } catch {
    }

    if ($keys.Count -eq 0) {
        $fallbackData = Get-OptionalDepsTomlFallbackData
        $keys = @($fallbackData.MinimalKeys)
        if ($IsWindows -and $fallbackData.WindowsMinimalKeys) {
            $keys = @($keys + @($fallbackData.WindowsMinimalKeys))
        }
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

function Test-DoctorLinuxToolset {
    if (-not $IsLinux) {
        return
    }

    $entries = @()
    try {
        $raw = Run-Python -ScriptPath $OptionalDepsScript -ScriptArgs @("linux-toolset") 2>$null
        if ($raw) {
            $entries = @($raw -split "`n" |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    ForEach-Object {
                        $parts = $_ -split '\|'
                        if ($parts.Count -lt 4) { return }
                        [pscustomobject]@{ Key = $parts[0]; Requirement = $parts[1]; Display = $parts[2]; Bin = $parts[3] }
                    })
        }
    } catch {
    }

    if ($entries.Count -eq 0) {
        $entries = @((Get-OptionalDepsTomlFallbackData).LinuxToolset |
                ForEach-Object { [pscustomobject]@{ Key = $_.Key; Requirement = $_.Requirement; Display = $_.Key; Bin = $_.Key } })
    }

    $requiredMissing = @()
    $suggestedMissing = @()
    foreach ($entry in $entries) {
        $binary = if ([string]::IsNullOrWhiteSpace($entry.Bin)) { $entry.Key } else { $entry.Bin }
        if (Test-AnyCommand -Names @($binary)) {
            continue
        }
        if ($entry.Requirement -eq "required") {
            Write-UiLine -Role missing -Message "linux toolset: $($entry.Display) (required)"
            $requiredMissing += $entry.Key
        } else {
            Write-UiLine -Role hint -Message "linux toolset: $($entry.Display) (suggested)"
            $suggestedMissing += $entry.Key
        }
    }

    if ($requiredMissing.Count -gt 0) {
        Write-UiLine -Role hint -Message "repair: oooconf deps $($requiredMissing -join ' ')"
        $script:Failures.Add("doctor linux required toolset") | Out-Null
    }
    if ($suggestedMissing.Count -gt 0) {
        Write-UiLine -Role hint -Message "minimal install: oooconf deps $($suggestedMissing -join ' ')"
    }
}

function Test-Doctor {
    Write-UiLine -Role info -Message "Running doctor checks..."

    Run-Python -ScriptPath (Join-Path $RepoRoot "scripts/cli/transaction_apply.py") -ScriptArgs @("--repo-root", "$RepoRoot", "status", "--check-incomplete")
    if ($LASTEXITCODE -ne 0) {
        Write-UiLine -Role missing -Message "incomplete managed-link transaction"
        Write-UiLine -Role hint -Message "repair: oooconf rollback --last"
        $script:Failures.Add("doctor incomplete transaction") | Out-Null
    }

    # Resolve the same profile-filtered link set used by transactional apply.
    $linkOutput = Run-Python -ScriptPath (Join-Path $RepoRoot "scripts/cli/operation_plan.py") -ScriptArgs @("--repo-root", "$RepoRoot", "--scope", "links", "--emit-managed-links") 2>$null
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
        Write-UiLine -Role missing -Message "unable to resolve managed profile links"
        $script:Failures.Add("doctor profile links") | Out-Null
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

    Test-DoctorLinuxToolset

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
