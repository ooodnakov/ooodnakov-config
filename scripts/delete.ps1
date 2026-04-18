param(
    [Parameter(Position = 0)]
    [ValidateSet("restore", "remove")]
    [string]$Mode = "restore"
)

$ErrorActionPreference = "Stop"

$RepoRoot = if ($env:OOODNAKOV_REPO_ROOT) { $env:OOODNAKOV_REPO_ROOT } else { (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }
$HomeDir = if ($env:HOME) { $env:HOME } else { $HOME }
$ConfigHome = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HomeDir ".config" }
$BackupRoot = if ($env:OOODNAKOV_BACKUP_ROOT) { $env:OOODNAKOV_BACKUP_ROOT } else { Join-Path $HomeDir ".local/state/ooodnakov-config/backups" }

function Write-UiLine {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("ok", "info", "section", "hint")]
        [string]$Role,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $isInteractive = [Environment]::UserInteractive
    if (-not $isInteractive -or $env:NO_COLOR) {
        $icon = switch ($Role) {
            "ok" { "✓" }
            "info" { "ℹ" }
            "section" { "▸" }
            "hint" { "💡" }
            default { "✗" }
        }
        Write-Output "$icon $Message"
        return
    }

    $iconCode = switch ($Role) {
        "ok" { "`e[1;38;5;78m✓`e[0m" }
        "info" { "`e[1;38;5;117mℹ`e[0m" }
        "section" { "`e[1;38;5;111m▸`e[0m" }
        "hint" { "`e[1;38;5;220m💡`e[0m" }
        default { "`e[1;38;5;203m✗`e[0m" }
    }

    $textColorCode = switch ($Role) {
        "ok" { "`e[1;38;5;78m" }
        "info" { "`e[1;38;5;117m" }
        "section" { "`e[1;38;5;111m" }
        "hint" { "`e[1;38;5;220m" }
        default { "`e[1;38;5;203m" }
    }

    Write-Output "$iconCode $textColorCode$Message`e[0m"
}

function Remove-ManagedLink {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    if (Test-Path -Path $Target) {
        $item = Get-Item -Path $Target -ErrorAction SilentlyContinue
        if ($item.LinkType) {
            $currentTarget = $item.Target
            # Compare paths taking into account directory separators
            if (($currentTarget -replace '\\', '/') -eq ($Source -replace '\\', '/')) {
                Remove-Item -Path $Target -Force
                Write-UiLine -Role ok -Message "removed $Target"
            }
        }
    }
}

function Get-LatestBackup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    $targetDir = Split-Path $Target
    $targetName = Split-Path $Target -Leaf

    # Strip drive letter for backup dir creation if on Windows
    $relativeTargetDir = if ($targetDir -match "^[A-Za-z]:\\(.*)") { $matches[1] } elseif ($targetDir -match "^/(.*)") { $matches[1] } else { $targetDir }
    # Normalize path separators
    $relativeTargetDir = $relativeTargetDir -replace '\\', '/'

    $backupDir = Join-Path $BackupRoot $relativeTargetDir

    if (-not (Test-Path -Path $backupDir)) {
        return $null
    }

    $backups = Get-ChildItem -Path $backupDir -Filter "$targetName.*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($backups.Count -gt 0) {
        return $backups[0].FullName
    }

    return $null
}

function Restore-Backup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    $backup = Get-LatestBackup -Target $Target
    if ($backup -and -not (Test-Path -Path $Target)) {
        Move-Item -Path $backup -Destination $Target
        Write-UiLine -Role ok -Message "restored $Target"
    }
}

function Remove-FontDir {
    $dataHome = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path $HomeDir ".local/share" }
    $fontDir = Join-Path (Join-Path $dataHome "fonts") "ooodnakov"
    if (Test-Path -Path $fontDir) {
        Remove-Item -Path $fontDir -Recurse -Force
        Write-UiLine -Role ok -Message "removed $fontDir"
    }
}

$LocalBinDir = Join-Path $HomeDir ".local/bin"
$ActivePowerShellProfile = $PROFILE.CurrentUserCurrentHost

# Remove managed links
Remove-ManagedLink -Source (Join-Path $RepoRoot "home/.config/wezterm") -Target (Join-Path $ConfigHome "wezterm")
Remove-ManagedLink -Source (Join-Path $RepoRoot "home/.config/lazygit") -Target (Join-Path $ConfigHome "lazygit")
Remove-ManagedLink -Source (Join-Path $RepoRoot "home/.config/nvim") -Target (Join-Path $ConfigHome "nvim")
Remove-ManagedLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov") -Target (Join-Path $ConfigHome "ooodnakov")
Remove-ManagedLink -Source (Join-Path $RepoRoot "home/.config/ohmyposh/ooodnakov.omp.json") -Target (Join-Path $ConfigHome "ohmyposh/ooodnakov.omp.json")
Remove-ManagedLink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target (Join-Path $ConfigHome "powershell/Microsoft.PowerShell_profile.ps1")
Remove-ManagedLink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target $ActivePowerShellProfile
Remove-ManagedLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/oooconf.ps1") -Target (Join-Path $LocalBinDir "oooconf.ps1")
Remove-ManagedLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/oooconf.cmd") -Target (Join-Path $LocalBinDir "oooconf.cmd")

Remove-FontDir

if ($Mode -eq "restore") {
    Restore-Backup -Target (Join-Path $ConfigHome "wezterm")
    Restore-Backup -Target (Join-Path $ConfigHome "lazygit")
    Restore-Backup -Target (Join-Path $ConfigHome "nvim")
    Restore-Backup -Target (Join-Path $ConfigHome "ooodnakov")
    Restore-Backup -Target (Join-Path $ConfigHome "ohmyposh/ooodnakov.omp.json")
    Restore-Backup -Target (Join-Path $ConfigHome "powershell/Microsoft.PowerShell_profile.ps1")
    Restore-Backup -Target $ActivePowerShellProfile
}

Write-Output ""
Write-UiLine -Role ok -Message "Managed config removed."
Write-UiLine -Role info -Message "Repo checkout was left in place at $RepoRoot."
