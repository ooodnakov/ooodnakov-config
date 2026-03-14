$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ConfigHome = Join-Path $HOME ".config"
$OhMyPoshDir = Join-Path $ConfigHome "ohmyposh"
$PowerShellDir = Join-Path $HOME "Documents/PowerShell"
$SshDir = Join-Path $HOME ".ssh"

function New-Symlink {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Target
    )

    $parent = Split-Path -Parent $Target
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    if (Test-Path $Target) {
        Remove-Item -Force $Target
    }

    New-Item -ItemType SymbolicLink -Path $Target -Target $Source | Out-Null
    Write-Host "linked $Target"
}

function Ensure-SshInclude {
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

New-Symlink -Source (Join-Path $RepoRoot "home/.config/wezterm") -Target (Join-Path $ConfigHome "wezterm")
New-Symlink -Source (Join-Path $RepoRoot "home/.config/ooodnakov") -Target (Join-Path $ConfigHome "ooodnakov")
New-Symlink -Source (Join-Path $RepoRoot "home/.config/ohmyposh/ooodnakov.omp.json") -Target (Join-Path $OhMyPoshDir "ooodnakov.omp.json")
New-Symlink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target (Join-Path $PowerShellDir "Microsoft.PowerShell_profile.ps1")

Ensure-SshInclude

Write-Host ""
Write-Host "Bootstrap complete."
Write-Host "If needed, create local overrides in $ConfigHome/ooodnakov/local."
