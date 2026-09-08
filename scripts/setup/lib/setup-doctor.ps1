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
