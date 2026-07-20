# Dot-sourced by scripts/setup/setup.ps1; do not execute directly.

function Detect-Platform {
    if ($IsWindows) { return "windows" }
    if ($IsMacOS) { return "macos" }
    if ($IsLinux) { return "linux" }
    # Fallback for older PowerShell on Windows
    if ($env:OS -eq "Windows_NT") { return "windows" }
    return "unknown"
}

function Test-OptionalDependencyApplicable {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Spec
    )

    $platform = Detect-Platform
    switch ($platform) {
        "windows" { return $null -ne $Spec.Windows }
        "macos"   { return $null -ne $Spec.Macos }
        "linux"   { return $null -ne $Spec.Linux }
        default   { return $true }
    }
}

function Get-OptionalDepsTomlFallbackData {
    if ($script:OptionalDepsTomlFallbackData) {
        return $script:OptionalDepsTomlFallbackData
    }

    $tomlPath = Join-Path $PSScriptRoot "optional-deps.toml"
    if (-not (Test-Path $tomlPath)) {
        $script:OptionalDepsTomlFallbackData = @{
            Deps        = @()
            MinimalKeys = @()
        }
        return $script:OptionalDepsTomlFallbackData
    }

    $entries = @()
    $minimalKeys = @()
    $current = @{}
    $inMinimalSection = $false
    foreach ($rawLine in (Get-Content -Path $tomlPath -ErrorAction SilentlyContinue)) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
            continue
        }

        if ($line -eq "[minimal]") {
            $inMinimalSection = $true
            continue
        }

        if ($line -match '^\[' -and $line -ne "[minimal]" -and $line -ne "[[deps]]") {
            $inMinimalSection = $false
        }

        if ($inMinimalSection -and $line -match '^keys\s*=\s*\[(.*)\]\s*$') {
            $minimalKeys = @(
                $matches[1] -split ',' |
                    ForEach-Object { $_.Trim().Trim('"').Trim("'") } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
            continue
        }

        if ($line -eq "[[deps]]") {
            if ($current.Count -gt 0) {
                $entries += ,$current
            }
            $current = @{}
            continue
        }

        if ($line -notmatch '^\s*([A-Za-z0-9_.-]+)\s*=\s*"(.*)"\s*$') {
            continue
        }

        $dottedKey = $matches[1]
        $value = $matches[2]
        $current[$dottedKey] = $value
    }
    if ($current.Count -gt 0) {
        $entries += ,$current
    }

    $deps = @($entries | ForEach-Object {
        $entry = $_
        $linux = @{}
        $macos = @{}
        $windows = @{}

        foreach ($k in @("manager", "package", "command", "winget_id", "choco_id", "url", "asset")) {
            $linuxKey = "linux.$k"
            $macosKey = "macos.$k"
            $windowsKey = "windows.$k"
            if ($entry.ContainsKey($linuxKey)) { $linux[$k] = $entry[$linuxKey] }
            if ($entry.ContainsKey($macosKey)) { $macos[$k] = $entry[$macosKey] }
            if ($entry.ContainsKey($windowsKey)) { $windows[$k] = $entry[$windowsKey] }
        }

        [pscustomobject]@{
            Key         = if ($entry.ContainsKey("key")) { $entry["key"] } else { "" }
            DisplayName = if ($entry.ContainsKey("display")) { $entry["display"] } elseif ($entry.ContainsKey("key")) { $entry["key"] } else { "" }
            Description = if ($entry.ContainsKey("description")) { $entry["description"] } else { "" }
            Handler     = if ($entry.ContainsKey("handler")) { $entry["handler"] } else { "" }
            Ver         = if ($entry.ContainsKey("ver")) { $entry["ver"] } else { "" }
            Url         = if ($entry.ContainsKey("url")) { $entry["url"] } else { "" }
            Asset       = if ($entry.ContainsKey("asset")) { $entry["asset"] } else { "" }
            Bin         = if ($entry.ContainsKey("bin")) { $entry["bin"] } else { "" }
            Check       = if ($entry.ContainsKey("check")) { $entry["check"] } else { "" }
            After       = if ($entry.ContainsKey("after")) { $entry["after"] } else { "" }
            Linux       = if ($linux.Count -gt 0) { $linux } else { $null }
            Macos       = if ($macos.Count -gt 0) { $macos } else { $null }
            Windows     = if ($windows.Count -gt 0) { $windows } else { $null }
        }
    })

    $script:OptionalDepsTomlFallbackData = @{
        Deps        = $deps
        MinimalKeys = @($minimalKeys | Select-Object -Unique)
    }
    return $script:OptionalDepsTomlFallbackData
}

function Get-OptionalDependencySpecsFromTomlFallback {
    return @((Get-OptionalDepsTomlFallbackData).Deps)
}

function Get-OptionalDependencySpecs {
    if ($script:OptionalDependencySpecsCache) {
        return $script:OptionalDependencySpecsCache
    }

    $json = $null
    try {
        $json = Run-Python -ScriptPath $OptionalDepsScript -ScriptArgs @("json") 2>$null
    } catch {
    }

    if (-not $json) {
        # Fallback: parse optional-deps.toml directly when Python is unavailable.
        $specs = @(Get-OptionalDependencySpecsFromTomlFallback)
        $script:OptionalDependencySpecsCache = $specs
        return @($specs | Where-Object { Test-OptionalDependencyApplicable -Spec $_ })
    }

    $raw = $json | ConvertFrom-Json
    $specs = @($raw | ForEach-Object {
        [pscustomobject]@{
            Key         = $_.key
            DisplayName = $_.display
            Description = $_.description
            Handler     = $_.handler
            Ver         = $_.ver
            Url         = $_.url
            Asset       = $_.asset
            Bin         = $_.bin
            Check       = $_.check
            WindowsOnly = ($null -eq $_.linux -and $null -eq $_.macos -and $null -ne $_.windows)
            Linux       = if ($_.linux) { $_.linux } else { $null }
            Macos       = if ($_.macos) { $_.macos } else { $null }
            Windows     = if ($_.windows) { $_.windows } else { $null }
        }
    })

    $script:OptionalDependencySpecsCache = $specs
    return @($specs | Where-Object { Test-OptionalDependencyApplicable -Spec $_ })
}

function Get-AllOptionalDependencySpecs {
    # Return all specs including platform-inapplicable ones (for validation).
    $json = $null
    try {
        $json = Run-Python -ScriptPath $OptionalDepsScript -ScriptArgs @("json") 2>$null
    } catch {}
    if ($json) {
        $raw = $json | ConvertFrom-Json
        return @($raw | ForEach-Object {
            [pscustomobject]@{
                Key         = $_.key
                DisplayName = $_.display
                Description = $_.description
                Handler     = $_.handler
                Ver         = $_.ver
                Url         = $_.url
                Asset       = $_.asset
                Bin         = $_.bin
                Check       = $_.check
                Linux       = if ($_.linux) { $_.linux } else { $null }
                Macos       = if ($_.macos) { $_.macos } else { $null }
                Windows     = if ($_.windows) { $_.windows } else { $null }
            }
        })
    }

    if (-not $script:OptionalDependencySpecsCache) {
        $null = Get-OptionalDependencySpecs
    }

    # Fallback: return filtered (applicable only) specs
    return $script:OptionalDependencySpecsCache
}

$script:SelectedOptionalKeys = @()

function Test-OptionalDependencySelected {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if (-not $script:SelectedOptionalKeys -or $script:SelectedOptionalKeys.Count -eq 0) {
        return $true
    }

    return $script:SelectedOptionalKeys -contains $Key
}

function Get-OptionalDependencyCommandNames {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ($Key -eq "posh-git" -or $Key -eq "psfzf") {
        return @()
    }

    $names = [System.Collections.Generic.List[string]]::new()
    $names.Add($Key)

    $spec = Get-AllOptionalDependencySpecs | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
    if (-not $spec) {
        return @($names)
    }

    # 1. explicit binary name
    if ($spec.Bin -and $names -notcontains $spec.Bin) { $names.Add($spec.Bin) }

    # 2. Extract from check command (e.g. "nvim --version" -> "nvim")
    if ($spec.Check -and $spec.Check -match '^\s*([A-Za-z0-9_.-]+)') {
        $cmdFromCheck = $matches[1]
        if ($names -notcontains $cmdFromCheck) { $names.Add($cmdFromCheck) }
    }

    # 3. Platform specific info
    $platformConfig = Get-OptionalDependencyPlatformConfig -Spec $spec
    if ($platformConfig) {
        # Only add command if it's a single word (no spaces, which indicates descriptive text)
        if ($platformConfig.command -and $platformConfig.command -notmatch '\s') {
            if ($names -notcontains $platformConfig.command) { $names.Add($platformConfig.command) }
        }
        # Often package name matches command name (except for cargo where it's a URL or repo)
        if ($platformConfig.package -and $platformConfig.manager -notin @("cargo", "github-release") -and $platformConfig.package -notmatch '\s') {
            if ($names -notcontains $platformConfig.package) { $names.Add($platformConfig.package) }
        }
    }

    # Special handling for python3
    if ($Key -eq "python3" -and ($names -notcontains "python")) {
        $names.Add("python")
    }

    return @($names)
}

function Test-OptionalDependencyPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ([string]::IsNullOrWhiteSpace($Key)) {
        return $false
    }

    if ($Key -eq "posh-git") {
        return [bool](Get-Module -ListAvailable -Name posh-git)
    }
    if ($Key -eq "psfzf") {
        return [bool](Get-Module -ListAvailable -Name PSFzf)
    }

    $spec = Get-AllOptionalDependencySpecs | Where-Object { $_.Key -eq $Key } | Select-Object -First 1

    # If a custom check string with arguments is provided, execute it literally.
    if ($spec -and $spec.Check -and $spec.Check -match '\s') {
        try {
            # Execute in a way that suppresses ALL output (stdout and stderr)
            & { Invoke-Expression $spec.Check } > $null 2>&1
            return ($LASTEXITCODE -eq 0)
        } catch {
            return $false
        }
    }

    $commandNames = @(Get-OptionalDependencyCommandNames -Key $Key | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($commandNames.Count -eq 0) {
        return $false
    }

    return Test-AnyCommand -Names $commandNames
}

function Invoke-SelectedOptionalDependency {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    if (-not (Test-OptionalDependencySelected -Key $Key)) {
        return $false
    }

    & $Action
    return $true
}

function Get-OptionalDependencyPlatformConfig {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Spec
    )

    $platform = Detect-Platform
    switch ($platform) {
        "windows" { return $Spec.Windows }
        "macos"   { return $Spec.Macos }
        "linux"   { return $Spec.Linux }
        default   { return $null }
    }
}

function Install-OptionalDependencyFromSpec {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Spec
    )

    $key = $Spec.Key
    if (-not (Test-OptionalDependencySelected -Key $key)) {
        return $false
    }

    $handler = if ($Spec.PSObject.Properties.Name -contains "Handler") { [string]$Spec.Handler } else { "" }

    switch ($handler) {
        "choco" { return (Install-Chocolatey) }
        "brew" { return (Install-HomebrewIfMissing) }
        "posh-git" { return (Install-PoshGitIfMissing) }
        "psfzf" { return (Install-PSFzfIfMissing) }
        "bw" { return (Install-BitwardenCliIfMissing) }
        "node" { return (Install-NodeIfMissing) }
        "pnpm" { return (Install-PnpmIfMissing) }
        "cargo" { return (Install-CargoIfMissing) }
        "dua" { return (Install-DuaIfMissing) }
        "nvim" { return (Install-NeovimIfMissing) }
        "rtk" { return (Install-RtkIfMissing) }
        "tectonic" { return (Install-TectonicIfMissing) }
        "zebar-pack-overline" {
            if (-not $IsWindows) {
                Add-DependencySummary "overline-zebar: skipped (Windows only)"
                return $false
            }

            $cliScript = Join-Path $PSScriptRoot "ooodnakov.ps1"
            $alreadyInstalled = & pwsh -NoProfile -File $cliScript wm zebar-config list 2>$null | Where-Object { $_ -match "^\*\s+overline" }
            if ($alreadyInstalled) {
                Add-DependencySummary "overline-zebar: already installed"
                return $true
            }

            $res = Invoke-ActionWithSpinner -Description "Installing overline-zebar" -Action {
                param($scriptPath)
                & pwsh -NoProfile -File $scriptPath wm zebar-config install overline-zebar | Out-Null
            } -ArgumentList $cliScript
            if ($res) {
                Add-DependencySummary "overline-zebar: installed"
            } else {
                Add-DependencySummary "overline-zebar: install attempted"
            }
            return $res
        }
        "k" {
            Write-Warning "k is not available on Windows."
            Add-DependencySummary "k: skipped"
            return $false
        }
    }

    switch ($key) {
        "zsh" {
            Write-Warning "zsh is not natively supported on Windows; use WSL or a custom build."
            Add-DependencySummary "zsh: skipped"
            return $false
        }
    }

    $platformConfig = Get-OptionalDependencyPlatformConfig -Spec $Spec
    if (-not $platformConfig) {
        Add-DependencySummary "${key}: skipped (not applicable on this platform)"
        return $false
    }

    $commandNames = @(Get-OptionalDependencyCommandNames -Key $key | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($commandNames.Count -eq 0) {
        $commandNames = @($key)
    }

    $summaryName = $key
    $description = if ($Spec.DisplayName) { [string]$Spec.DisplayName } else { $key }
    $manager = if ($platformConfig.manager) { [string]$platformConfig.manager } else { "" }
    $packageName = if ($platformConfig.package) { [string]$platformConfig.package } else { "" }
    $wingetId = if ($platformConfig.winget_id) { [string]$platformConfig.winget_id } elseif ($manager -eq "winget") { $packageName } else { "" }
    $chocoId = if ($platformConfig.choco_id) { [string]$platformConfig.choco_id } elseif ($manager -eq "choco") { $packageName } else { "" }
    $cargoGitUrl = if ($manager -eq "cargo") { $packageName } else { "" }
    $scoopPackage = if ($manager -eq "scoop") { $packageName } else { "" }

    switch ($manager) {
        "custom" {
            Add-DependencySummary "${summaryName}: skipped (manual installer)"
            return $false
        }
        "curl" {
            Add-DependencySummary "${summaryName}: skipped (manual curl installer)"
            return $false
        }
        "winget" {
            return (Install-PackageIfMissing -CommandNames $commandNames -WingetId $wingetId -Description $description -SummaryName $summaryName)
        }
        "choco" {
            return (Install-PackageIfMissing -CommandNames $commandNames -ChocoId $chocoId -Description $description -SummaryName $summaryName)
        }
        "cargo" {
            return (Install-PackageIfMissing -CommandNames $commandNames -CargoGitUrl $cargoGitUrl -Description $description -SummaryName $summaryName)
        }
        "scoop" {
            return (Install-PackageIfMissing -CommandNames $commandNames -ScoopPackage $scoopPackage -Description $description -SummaryName $summaryName)
        }
        "pnpm" {
            $res = (Invoke-ActionWithSpinner -Description "Installing $description via pnpm" -Action {
                param($pkg)
                pnpm add --global $pkg | Out-Null
            } -ArgumentList $packageName)
            Update-SessionEnvironment
            if ($res) { Add-NewlyAvailableCommand -CommandNames $commandNames }
            return $res
        }
        "github-release" {
            return (Install-GitHubReleaseDependencyIfMissing -Spec $Spec -PlatformConfig $platformConfig -CommandNames $commandNames -Description $description -SummaryName $summaryName)
        }
        "pip" {
            if (Test-DependencyStatus -CommandName $commandNames[0] -SummaryName $summaryName) { return $true }

            $pythonCommand = Get-PythonCommand
            if (-not $pythonCommand) {
                Add-DependencySummary "${summaryName}: missing (Python unavailable for pip)"
                return $false
            }

            $res = (Invoke-ActionWithSpinner -Description "Installing $description via pip" -Action {
                param($pkg, $pythonExe)
                if ($pythonExe -eq "py") {
                    & $pythonExe -3 -m pip install --upgrade $pkg | Out-Null
                } else {
                    & $pythonExe -m pip install --upgrade $pkg | Out-Null
                }
            } -ArgumentList $packageName, $pythonCommand)
            Update-SessionEnvironment
            if ($res) { Add-NewlyAvailableCommand -CommandNames $commandNames }
            return $res
        }
        default {
            Add-DependencySummary "${summaryName}: skipped (unsupported manager: $manager)"
            return $false
        }
    }
}

function Ensure-GumForDependencySelector {
    if (Get-Command gum -ErrorAction SilentlyContinue) {
        return $true
    }

    if (-not (Test-Interactive)) {
        return $false
    }

    if (-not (Confirm-Install "Install gum with winget for the dependency picker?")) {
        return $false
    }

    $previousMode = $InstallOptionalMode
    $script:SelectedOptionalKeys = @("gum")
    $script:DependencySummary.Clear()
    $InstallOptionalMode = "always"
    try {
        Install-PackageIfMissing -CommandNames @("gum") -WingetId "charmbracelet.gum" -Description "gum" -SummaryName "gum" | Out-Null
    } finally {
        $InstallOptionalMode = $previousMode
        $script:SelectedOptionalKeys = @()
        $script:DependencySummary.Clear()
    }

    return [bool](Get-Command gum -ErrorAction SilentlyContinue)
}

function Select-OptionalDependenciesWithoutGum {
    $allPresent = $true
    $available = @(Get-OptionalDependencySpecs | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.Key) -and -not (Test-OptionalDependencyPresent -Key $_.Key)
    })

    if ($available.Count -eq 0) {
        Write-Information "All optional dependencies are already present." -InformationAction Continue
        return @("__all_present__")
    }

    Write-Information "Available optional dependencies:" -InformationAction Continue
    foreach ($spec in $available) {
        Write-Information ("  {0,-12} {1}" -f $spec.Key, $spec.DisplayName) -InformationAction Continue
    }
    Write-Information "" -InformationAction Continue

    $input_str = Read-Host "Enter space/comma-separated keys to install (or empty to skip)"
    $wanted = @($input_str -split '[ ,]+' | Where-Object { $_ })

    if ($wanted.Count -eq 0) {
        Write-Information "No optional dependencies selected." -InformationAction Continue
        return @()
    }

    $validKeys = @($available | ForEach-Object { $_.Key })
    foreach ($key in $wanted) {
        if ($validKeys -notcontains $key) {
            Write-Error "Unknown dependency key: $key"
            return @()
        }
    }

    Write-Information "Selected: $($wanted -join ', ')" -InformationAction Continue
    return $wanted
}

function Select-OptionalDependenciesWithGum {
    if (-not (Ensure-GumForDependencySelector)) {
        return $null
    }

    $options = foreach ($spec in Get-OptionalDependencySpecs) {
        if ([string]::IsNullOrWhiteSpace($spec.Key)) {
            continue
        }
        if (Test-OptionalDependencyPresent -Key $spec.Key) {
            continue
        }
        "$($spec.Key)`t$($spec.DisplayName)`t$($spec.Description)"
    }

    if (-not $options) {
        Write-Output "All optional dependencies are already present."
        return @("__all_present__")
    }

    # Stop transcript if active, as it can interfere with interactive TUI tools like gum on Windows
    $transcriptActive = $script:TranscriptStarted
    if ($transcriptActive) {
        try { Stop-Transcript | Out-Null } catch {}
    }

    try {
        # Make the picker searchable: pipe the full list through gum filter (live fuzzy
        # search), then into gum choose for toggle/checkbox-style multi-select. Each step
        # runs separately (not via a single shell pipeline) for reliability on Windows.
        $filtered = $options | & gum filter --no-limit --placeholder "Type to filter dependencies (tab toggles match, enter confirms)..."
        if ($LASTEXITCODE -ne 0) {
            return @()
        }

        if (-not $filtered) {
            # User cleared the filter or cancelled; nothing to choose from.
            return @()
        }

        $selection = $filtered | & gum choose --no-limit --height 20 --header "Select optional dependencies. Use arrows to move, x to toggle, enter to continue." 2>$null
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0 -or -not $selection) {
            return @()
        }

        return @($selection | ForEach-Object { ($_ -split "`t")[0] })
    } finally {
        # Restart transcript if it was previously active
        if ($transcriptActive) {
            try { Start-Transcript -Path $script:LogFile -Append | Out-Null } catch {}
        }
    }
}
