$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ConfigHome = Join-Path $HOME ".config"
$OhMyPoshDir = Join-Path $ConfigHome "ohmyposh"
$PowerShellDir = Join-Path $HOME "Documents/PowerShell"
$SshDir = Join-Path $HOME ".ssh"
$InteractiveMode = if ($env:OOODNAKOV_INTERACTIVE) { $env:OOODNAKOV_INTERACTIVE } else { "auto" }
$BackupRoot = if ($env:OOODNAKOV_BACKUP_ROOT) { $env:OOODNAKOV_BACKUP_ROOT } else { Join-Path $HOME ".local/state/ooodnakov-config/backups" }
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

function Test-Interactive {
    switch ($InteractiveMode) {
        "always" { return $true }
        "never" { return $false }
        default { return $Host.Name -ne "ServerRemoteHost" }
    }
}

function Confirm-Install {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt
    )

    if (-not (Test-Interactive)) {
        return $false
    }

    $reply = Read-Host "$Prompt [y/N]"
    return $reply -match '^(?i:y|yes)$'
}

function Install-WingetPackageIfMissing {
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)][string]$WingetId,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if (Get-Command $CommandName -ErrorAction SilentlyContinue) {
        return
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Output "winget is not available; skipping $Description"
        return
    }

    if (Confirm-Install "Install $Description with winget?") {
        winget install --exact --id $WingetId --accept-package-agreements --accept-source-agreements
    }
}

function Backup-Target {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Target
    )

    if (Test-Path $Target -PathType Container) {
        # Keep directories if they aren't symlinks and we aren't symlinking a directory?
        # Actually New-Symlink removes existing things
    }

    $item = Get-Item -Path $Target -ErrorAction SilentlyContinue
    if (-not $item) { return }

    if ($item.LinkType -eq "SymbolicLink") {
        if ($item.Target -eq $Source) { return }
    }

    $targetDir = Split-Path -Parent $Target
    $targetName = Split-Path -Leaf $Target

    # Calculate backup dir relative path or just flat backup root + target dir?
    # In bash setup.sh: backup_dir="$BACKUP_ROOT$target_dir"
    # But for Windows we should trim drive letter? Let's just use absolute path structure
    $drive = (Get-Item $targetDir).PSDrive.Name
    $pathWithoutDrive = $targetDir.Substring($drive.Length + 1)
    if ($pathWithoutDrive.StartsWith("\")) { $pathWithoutDrive = $pathWithoutDrive.Substring(1) }
    $backupDir = Join-Path $BackupRoot $pathWithoutDrive

    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    }

    $backupPath = Join-Path $backupDir "$targetName.$Timestamp"
    Move-Item -Path $Target -Destination $backupPath -Force
    Write-Output "backed up $Target -> $backupPath"
}

function New-Symlink {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Target
    )

    $parent = Split-Path -Parent $Target
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    Backup-Target -Source $Source -Target $Target

    if (Test-Path $Target) {
        Remove-Item -Force $Target
    }

    New-Item -ItemType SymbolicLink -Path $Target -Target $Source | Out-Null
    Write-Output "linked $Target"
}

function Add-SshInclude {
    $configPath = Join-Path $SshDir "config"
    $includeLine = "Include ~/.config/ooodnakov/ssh/config"

    if (-not (Test-Path $SshDir)) {
        New-Item -ItemType Directory -Force -Path $SshDir | Out-Null
    }

    if (-not (Test-Path $configPath)) {
        New-Item -ItemType File -Path $configPath | Out-Null
    }

    $existing = Get-Content -Path $configPath -ErrorAction SilentlyContinue
    if ($existing -notcontains $includeLine) {
        @($includeLine, "") + $existing | Set-Content -Path $configPath
    }
}

Install-WingetPackageIfMissing -CommandName "wezterm" -WingetId "wez.wezterm" -Description "WezTerm"
Install-WingetPackageIfMissing -CommandName "oh-my-posh" -WingetId "JanDeDobbeleer.OhMyPosh" -Description "oh-my-posh"
Install-WingetPackageIfMissing -CommandName "git" -WingetId "Git.Git" -Description "Git"

New-Symlink -Source (Join-Path $RepoRoot "home/.config/wezterm") -Target (Join-Path $ConfigHome "wezterm")
New-Symlink -Source (Join-Path $RepoRoot "home/.config/ooodnakov") -Target (Join-Path $ConfigHome "ooodnakov")
New-Symlink -Source (Join-Path $RepoRoot "home/.config/ohmyposh/ooodnakov.omp.json") -Target (Join-Path $OhMyPoshDir "ooodnakov.omp.json")
New-Symlink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target (Join-Path $PowerShellDir "Microsoft.PowerShell_profile.ps1")

Add-SshInclude

Write-Output ""
Write-Output "Bootstrap complete."
Write-Output "If needed, create local overrides in $ConfigHome/ooodnakov/local."
