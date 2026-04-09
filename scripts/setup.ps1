param(
    [ValidateSet("install", "update", "doctor")]
    [string]$Command = "install",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
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
$BackupRoot = if ($env:OOODNAKOV_BACKUP_ROOT) { $env:OOODNAKOV_BACKUP_ROOT } else { Join-Path $HomeDir ".local/state/ooodnakov-config/backups" }
$LogRoot = if ($env:OOODNAKOV_LOG_ROOT) { $env:OOODNAKOV_LOG_ROOT } else { Join-Path $HomeDir ".local/state/ooodnakov-config/logs" }
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$PnpmVersion = "10.18.3"

$script:DependencySummary = [System.Collections.Generic.List[string]]::new()
$script:ToolSummary = [System.Collections.Generic.List[string]]::new()
$script:Failures = [System.Collections.Generic.List[string]]::new()
$script:LogFile = $null
$script:LatestLogFile = $null
$script:TranscriptStarted = $false

function Test-Interactive {
    switch ($InteractiveMode) {
        "always" { return $true }
        "never" { return $false }
        default { return $Host.Name -ne "ServerRemoteHost" }
    }
}

function Confirm-Install {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    if (-not (Test-Interactive)) {
        return $false
    }

    $reply = Read-Host "$Prompt [y/N]"
    return $reply -match '^(?i:y|yes)$'
}

function Add-DependencySummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Item
    )

    $script:DependencySummary.Add($Item) | Out-Null
}

function Add-ToolSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Item
    )

    $script:ToolSummary.Add($Item) | Out-Null
}

function Add-Failure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Item
    )

    $script:Failures.Add($Item) | Out-Null
    Write-Output "[failed] $Item"
}

function Start-SetupLogging {
    $resolvedLogRoot = $LogRoot

    try {
        if (-not (Test-Path $resolvedLogRoot)) {
            New-Item -ItemType Directory -Force -Path $resolvedLogRoot | Out-Null
        }
    } catch {
        $resolvedLogRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ooodnakov-config-logs"
        try {
            if (-not (Test-Path $resolvedLogRoot)) {
                New-Item -ItemType Directory -Force -Path $resolvedLogRoot | Out-Null
            }
        } catch {
            Write-Warning "Failed to create log directory under $LogRoot or $resolvedLogRoot"
            return
        }
    }

    $script:LatestLogFile = Join-Path $resolvedLogRoot "setup-latest.log"
    $script:LogFile = Join-Path $resolvedLogRoot "setup-$Command-$Timestamp.log"

    try {
        Start-Transcript -Path $script:LogFile -Force | Out-Null
        $script:TranscriptStarted = $true
    } catch {
        $script:TranscriptStarted = $false
        "Failed to start transcript logging at $script:LogFile: $($_.Exception.Message)" | Out-File -FilePath $script:LogFile -Encoding utf8 -Append
    }

    Write-Output "Logging to $script:LogFile"
}

function Stop-SetupLogging {
    if ($script:TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        } catch {
        }
    }

    if ($script:LogFile -and (Test-Path $script:LogFile)) {
        Copy-Item -Path $script:LogFile -Destination $script:LatestLogFile -Force
    }
}

function Invoke-Action {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    if ($DryRun) {
        Write-Output "[dry-run] $Description"
        return $true
    }

    try {
        & $Action
        return $true
    } catch {
        Write-Output $_
        Add-Failure $Description
        return $false
    }
}

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path $Path) {
        return $true
    }

    return (Invoke-Action -Description "Create directory $Path" -Action {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    })
}

function Get-ExistingItem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Test-LinkMatches {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    $item = Get-ExistingItem -Path $Target
    if (-not $item -or $item.LinkType -ne "SymbolicLink") {
        return $false
    }

    $expected = (Resolve-Path -LiteralPath $Source).Path
    $candidates = @($item.Target | ForEach-Object {
        if (-not $_) {
            return
        }

        $candidateText = [string]$_
        if (-not [System.IO.Path]::IsPathRooted($candidateText)) {
            $candidateText = Join-Path (Split-Path -Parent $Target) $candidateText
        }

        $candidateText
    })

    foreach ($candidateText in $candidates) {
        try {
            if ((Resolve-Path -LiteralPath $candidateText -ErrorAction Stop).Path -eq $expected) {
                return $true
            }
        } catch {
        }
    }

    return $false
}

function Backup-Target {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    if (Test-LinkMatches -Source $Source -Target $Target) {
        return $true
    }

    $item = Get-ExistingItem -Path $Target
    if (-not $item) {
        return $true
    }

    $targetDir = Split-Path -Parent $Target
    $targetName = Split-Path -Leaf $Target
    $pathWithoutDrive = Split-Path -Path $targetDir -NoQualifier
    if ($pathWithoutDrive.StartsWith("\") -or $pathWithoutDrive.StartsWith("/")) {
        $pathWithoutDrive = $pathWithoutDrive.Substring(1)
    }
    $backupDir = Join-Path $BackupRoot $pathWithoutDrive
    $backupPath = Join-Path $backupDir "$targetName.$Timestamp"

    if (-not (Ensure-Directory -Path $backupDir)) {
        return $false
    }

    return (Invoke-Action -Description "Backup $Target to $backupPath" -Action {
        Move-Item -LiteralPath $Target -Destination $backupPath -Force
        Write-Output "backed up $Target -> $backupPath"
    })
}

function New-Symlink {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    if (-not (Ensure-Directory -Path (Split-Path -Parent $Target))) {
        return $false
    }

    if (-not (Backup-Target -Source $Source -Target $Target)) {
        return $false
    }

    if (Test-LinkMatches -Source $Source -Target $Target) {
        Write-Output "linked $Target"
        return $true
    }

    return (Invoke-Action -Description "Link $Target" -Action {
        New-Item -ItemType SymbolicLink -Path $Target -Target $Source -Force | Out-Null
        Write-Output "linked $Target"
    })
}

function Add-SshInclude {
    $configPath = Join-Path $SshDir "config"
    $includeLine = "Include ~/.config/ooodnakov/ssh/config"

    if (-not (Ensure-Directory -Path $SshDir)) {
        return $false
    }

    if (-not (Test-Path $configPath)) {
        if (-not (Invoke-Action -Description "Create SSH config at $configPath" -Action {
            New-Item -ItemType File -Path $configPath | Out-Null
        })) {
            return $false
        }
    }

    $existing = @(Get-Content -Path $configPath -ErrorAction SilentlyContinue)
    if ($existing -contains $includeLine) {
        return $true
    }

    return (Invoke-Action -Description "Ensure SSH include in $configPath" -Action {
        @($includeLine, "") + $existing | Set-Content -Path $configPath
    })
}

function Ensure-UserPathContains {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathEntry
    )

    if (-not (Ensure-Directory -Path $PathEntry)) {
        return $false
    }

    $currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $pathParts = @($currentUserPath -split [IO.Path]::PathSeparator | Where-Object { $_ })
    if ($pathParts -contains $PathEntry) {
        if (($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ }) -notcontains $PathEntry) {
            $env:PATH = "$PathEntry$([IO.Path]::PathSeparator)$env:PATH"
        }
        return $true
    }

    $updatedUserPath = if ([string]::IsNullOrWhiteSpace($currentUserPath)) {
        $PathEntry
    } else {
        "$PathEntry$([IO.Path]::PathSeparator)$currentUserPath"
    }

    $updated = Invoke-Action -Description "Add $PathEntry to user PATH" -Action {
        [Environment]::SetEnvironmentVariable("Path", $updatedUserPath, "User")
        Write-Output "updated user PATH with $PathEntry"
    }

    if (($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ }) -notcontains $PathEntry) {
        $env:PATH = "$PathEntry$([IO.Path]::PathSeparator)$env:PATH"
    }

    return $updated
}

function Test-AnyCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        if (Get-Command $name -ErrorAction SilentlyContinue) {
            return $true
        }
    }

    return $false
}

function Install-Chocolatey {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Add-DependencySummary "choco: present"
        return $true
    }

    if (-not (Confirm-Install "Install Chocolatey for optional Windows CLI packages?")) {
        Add-DependencySummary "choco: skipped"
        return $false
    }

    if ($DryRun) {
        Write-Output "[dry-run] Install Chocolatey"
        Add-DependencySummary "choco: install preview"
        return $false
    }

    try {
        Write-Output "Installing Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-RestMethod -Uri "https://community.chocolatey.org/install.ps1" | Invoke-Expression
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Add-DependencySummary "choco: installed"
            return $true
        }
    } catch {
        Write-Output $_
        Add-Failure "Installing Chocolatey"
    }

    Add-DependencySummary "choco: install attempted"
    return $false
}

function Install-PackageIfMissing {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CommandNames,
        [string]$WingetId,
        [string]$ChocoId,
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [string]$SummaryName
    )

    if (Test-AnyCommand -Names $CommandNames) {
        Add-DependencySummary "${SummaryName}: present"
        return $true
    }

    if ($WingetId -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        if (Confirm-Install "Install $Description with winget?") {
            if ($DryRun) {
                Write-Output "[dry-run] winget install --exact --id $WingetId"
                Add-DependencySummary "${SummaryName}: install preview via winget"
                return $false
            }

            try {
                winget install --exact --id $WingetId --accept-package-agreements --accept-source-agreements
            } catch {
                Write-Output $_
            }

            if (Test-AnyCommand -Names $CommandNames) {
                Add-DependencySummary "${SummaryName}: installed via winget"
                return $true
            }

            Add-DependencySummary "${SummaryName}: install attempted via winget"
            return $false
        }

        Add-DependencySummary "${SummaryName}: skipped"
        return $false
    }

    if ($ChocoId -and (Get-Command choco -ErrorAction SilentlyContinue)) {
        if (Confirm-Install "Install $Description with Chocolatey?") {
            if ($DryRun) {
                Write-Output "[dry-run] choco install $ChocoId -y"
                Add-DependencySummary "${SummaryName}: install preview via choco"
                return $false
            }

            try {
                choco install $ChocoId -y
            } catch {
                Write-Output $_
            }

            if (Test-AnyCommand -Names $CommandNames) {
                Add-DependencySummary "${SummaryName}: installed via choco"
                return $true
            }

            Add-DependencySummary "${SummaryName}: install attempted via choco"
            return $false
        }

        Add-DependencySummary "${SummaryName}: skipped"
        return $false
    }

    Add-DependencySummary "${SummaryName}: missing (no supported package manager)"
    return $false
}

function Install-PnpmIfMissing {
    if (Get-Command pnpm -ErrorAction SilentlyContinue) {
        Add-DependencySummary "pnpm: present"
        return $true
    }

    if (-not (Confirm-Install "Install pnpm package manager?")) {
        Add-DependencySummary "pnpm: skipped"
        return $false
    }

    $pnpmHome = if ($env:PNPM_HOME) { $env:PNPM_HOME } else { Join-Path $HomeDir ".local/share/pnpm" }
    $env:PNPM_HOME = $pnpmHome

    if (-not (Ensure-Directory -Path $pnpmHome)) {
        Add-DependencySummary "pnpm: install failed"
        return $false
    }

    if (($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ }) -notcontains $pnpmHome) {
        $env:PATH = "$pnpmHome$([IO.Path]::PathSeparator)$env:PATH"
    }

    if (Get-Command corepack -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Output "[dry-run] corepack enable --install-directory $pnpmHome pnpm"
            Write-Output "[dry-run] corepack prepare pnpm@$PnpmVersion --activate"
            Add-DependencySummary "pnpm: install preview via corepack"
            return $false
        }

        try {
            & corepack enable --install-directory $pnpmHome pnpm
            & corepack prepare "pnpm@$PnpmVersion" --activate
        } catch {
            Write-Output $_
        }
    } elseif (Get-Command npm -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Output "[dry-run] npm install --global pnpm@$PnpmVersion --prefix $pnpmHome"
            Add-DependencySummary "pnpm: install preview via npm"
            return $false
        }

        try {
            & npm install --global "pnpm@$PnpmVersion" --prefix $pnpmHome
        } catch {
            Write-Output $_
        }
    } else {
        Add-DependencySummary "pnpm: missing (requires corepack or npm)"
        return $false
    }

    if (Get-Command pnpm -ErrorAction SilentlyContinue) {
        Add-DependencySummary "pnpm: installed"
        return $true
    }

    Add-DependencySummary "pnpm: install attempted"
    return $false
}

function Install-OptionalDependencies {
    Write-Output "Dependency check:"

    Install-PackageIfMissing -CommandNames @("git") -WingetId "Git.Git" -Description "Git" -SummaryName "git" | Out-Null
    Install-PackageIfMissing -CommandNames @("wezterm") -WingetId "wez.wezterm" -Description "WezTerm" -SummaryName "wezterm" | Out-Null
    Install-PackageIfMissing -CommandNames @("nvim") -WingetId "Neovim.Neovim" -Description "Neovim" -SummaryName "nvim" | Out-Null
    Install-PackageIfMissing -CommandNames @("oh-my-posh") -WingetId "JanDeDobbeleer.OhMyPosh" -Description "oh-my-posh" -SummaryName "oh-my-posh" | Out-Null
    Install-PackageIfMissing -CommandNames @("node") -WingetId "OpenJS.NodeJS.LTS" -Description "Node.js LTS" -SummaryName "node" | Out-Null

    Install-Chocolatey | Out-Null
    Install-PackageIfMissing -CommandNames @("gsudo") -ChocoId "gsudo" -Description "gsudo" -SummaryName "gsudo" | Out-Null
    Install-PackageIfMissing -CommandNames @("rg") -ChocoId "ripgrep" -Description "ripgrep" -SummaryName "rg" | Out-Null
    Install-PackageIfMissing -CommandNames @("fd") -ChocoId "fd" -Description "fd" -SummaryName "fd" | Out-Null
    Install-PackageIfMissing -CommandNames @("direnv") -ChocoId "direnv" -Description "direnv" -SummaryName "direnv" | Out-Null
    Install-PackageIfMissing -CommandNames @("fzf") -ChocoId "fzf" -Description "fzf" -SummaryName "fzf" | Out-Null
    Install-PackageIfMissing -CommandNames @("eza") -ChocoId "eza" -Description "eza" -SummaryName "eza" | Out-Null
    Install-PackageIfMissing -CommandNames @("uv") -ChocoId "uv" -Description "uv" -SummaryName "uv" | Out-Null
    Install-PackageIfMissing -CommandNames @("python3", "python") -ChocoId "python" -Description "Python 3" -SummaryName "python3" | Out-Null
    Install-PnpmIfMissing | Out-Null
}

function Write-Summary {
    Write-Output ""
    Write-Output "Dependency summary:"
    foreach ($item in $script:DependencySummary) {
        Write-Output "  - $item"
    }

    Write-Output "Managed setup:"
    foreach ($item in $script:ToolSummary) {
        Write-Output "  - $item"
    }

    if ($script:Failures.Count -gt 0) {
        Write-Output "Failures:"
        foreach ($item in $script:Failures) {
            Write-Output "  - $item"
        }
    }
}

function Test-DoctorLink {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    if (Test-LinkMatches -Source $Source -Target $Target) {
        Write-Output "[ok] $Target -> $Source"
        return
    }

    Write-Output "[missing] $Target (expected symlink to $Source)"
    $script:Failures.Add("doctor link $Target") | Out-Null
}

function Test-DoctorCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (Get-Command $Name -ErrorAction SilentlyContinue) {
        Write-Output "[ok] command: $Name"
        return
    }

    Write-Output "[missing] command: $Name"
    $script:Failures.Add("doctor command $Name") | Out-Null
}

function Test-Doctor {
    Write-Output "Running doctor checks..."

    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/wezterm") -Target (Join-Path $ConfigHome "wezterm")
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/nvim") -Target (Join-Path $ConfigHome "nvim")
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov") -Target (Join-Path $ConfigHome "ooodnakov")
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ohmyposh/ooodnakov.omp.json") -Target (Join-Path $OhMyPoshDir "ooodnakov.omp.json")
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target $PowerShellProfileTarget
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target $ActivePowerShellProfile
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/oooconf.ps1") -Target (Join-Path $LocalBinDir "oooconf.ps1")
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/oooconf.cmd") -Target (Join-Path $LocalBinDir "oooconf.cmd")

    Test-DoctorCommand -Name "git"
    Test-DoctorCommand -Name "wezterm"
    Test-DoctorCommand -Name "nvim"
    Test-DoctorCommand -Name "oh-my-posh"
    Test-DoctorCommand -Name "oooconf"

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $userPathParts = @($userPath -split [IO.Path]::PathSeparator | Where-Object { $_ })
    if ($userPathParts -contains $LocalBinDir) {
        Write-Output "[ok] user PATH contains $LocalBinDir"
    } else {
        Write-Output "[missing] user PATH entry: $LocalBinDir"
        $script:Failures.Add("doctor user PATH") | Out-Null
    }

    if ($script:Failures.Count -gt 0) {
        throw "Doctor found $($script:Failures.Count) issue(s)."
    }

    Write-Output "Doctor checks passed."
}

function Invoke-Install {
    foreach ($dir in @($ConfigHome, $DataHome, $CacheHome, $StateHome, $ShareHome, (Join-Path $ShareHome "bin"), $LocalBinDir, $OhMyPoshDir, $PowerShellConfigDir)) {
        if (Ensure-Directory -Path $dir) {
            Add-ToolSummary "ensured directory: $dir"
        }
    }

    Install-OptionalDependencies

    if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/wezterm") -Target (Join-Path $ConfigHome "wezterm")) {
        Add-ToolSummary "wezterm: linked"
    }
    if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/nvim") -Target (Join-Path $ConfigHome "nvim")) {
        Add-ToolSummary "nvim: linked"
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

    if (Ensure-UserPathContains -PathEntry $LocalBinDir) {
        Add-ToolSummary "user PATH: ensured $LocalBinDir"
    }
    if (Add-SshInclude) {
        Add-ToolSummary "ssh include: ensured"
    }

    Write-Summary
    Write-Output ""
    Write-Output "Bootstrap complete."
    Write-Output "If needed, create local overrides in $ConfigHome/ooodnakov/local."
}

Start-SetupLogging
try {
    switch ($Command) {
        "install" {
            Invoke-Install
        }
        "update" {
            if ($DryRun) {
                Write-Output "[dry-run] git -C $RepoRoot pull --ff-only"
            } else {
                git -C $RepoRoot pull --ff-only
            }
            Invoke-Install
        }
        "doctor" {
            Test-Doctor
        }
    }
} finally {
    if ($script:LogFile) {
        Write-Output "Log file: $script:LogFile"
    }
    Stop-SetupLogging
}

if ($script:Failures.Count -gt 0 -and $Command -ne "doctor") {
    exit 1
}
