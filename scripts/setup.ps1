param(
    [ValidateSet("install", "update", "doctor")]
    [string]$Command = "install",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ConfigHome = Join-Path $HOME ".config"
$OhMyPoshDir = Join-Path $ConfigHome "ohmyposh"
$PowerShellDir = Join-Path $HOME "Documents/PowerShell"
$SshDir = Join-Path $HOME ".ssh"
$InteractiveMode = if ($env:OOODNAKOV_INTERACTIVE) { $env:OOODNAKOV_INTERACTIVE } else { "auto" }
$BackupRoot = if ($env:OOODNAKOV_BACKUP_ROOT) { $env:OOODNAKOV_BACKUP_ROOT } else { Join-Path $HOME ".local/state/ooodnakov-config/backups" }
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$PnpmVersion = "10.18.3"

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

function Install-Chocolatey {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        return
    }

    if (Confirm-Install "Install Chocolatey?") {
        if ($DryRun) { Write-Output "[dry-run] Install Chocolatey"; return }
        Write-Output "Installing Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        # Suppress PSAvoidUsingInvokeExpression as it is the official installation method for Chocolatey
        Invoke-RestMethod -Uri 'https://community.chocolatey.org/install.ps1' | Invoke-Expression
    }
}

function Install-ChocoPackageIfMissing {
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)][string]$ChocoId,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if (Get-Command $CommandName -ErrorAction SilentlyContinue) {
        return
    }

    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Output "choco is not available; skipping $Description"
        return
    }

    if (Confirm-Install "Install $Description with Chocolatey?") {
        if ($DryRun) { Write-Output "[dry-run] choco install $ChocoId -y"; return }
        choco install $ChocoId -y
    }
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
        if ($DryRun) { Write-Output "[dry-run] winget install --exact --id $WingetId"; return }
        winget install --exact --id $WingetId --accept-package-agreements --accept-source-agreements
    }
}

function Install-PnpmIfMissing {
    if (Get-Command pnpm -ErrorAction SilentlyContinue) {
        return
    }

    if (-not (Confirm-Install "Install pnpm package manager?")) {
        Write-Output "skipping pnpm"
        return
    }

    $pnpmHome = if ($env:PNPM_HOME) { $env:PNPM_HOME } else { Join-Path $HOME ".local/share/pnpm" }
    if (-not (Test-Path $pnpmHome)) {
        if ($DryRun) {
            Write-Output "[dry-run] mkdir $pnpmHome"
        } else {
            New-Item -ItemType Directory -Force -Path $pnpmHome | Out-Null
        }
    }

    $env:PNPM_HOME = $pnpmHome
    if ($env:PATH -notlike "*$pnpmHome*") {
        $env:PATH = "$pnpmHome$([IO.Path]::PathSeparator)$env:PATH"
    }

    if (Get-Command corepack -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Output "[dry-run] corepack enable --install-directory $pnpmHome pnpm"
            Write-Output "[dry-run] corepack prepare pnpm@$PnpmVersion --activate"
            return
        }
        & corepack enable --install-directory $pnpmHome pnpm
        & corepack prepare "pnpm@$PnpmVersion" --activate
        return
    }

    if (Get-Command npm -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Output "[dry-run] npm install --global pnpm@$PnpmVersion --prefix $pnpmHome"
            return
        }
        & npm install --global "pnpm@$PnpmVersion" --prefix $pnpmHome
        return
    }

    Write-Output "pnpm install skipped because neither corepack nor npm is available"
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
    $pathWithoutDrive = Split-Path -Path $targetDir -NoQualifier
    if ($pathWithoutDrive.StartsWith("\") -or $pathWithoutDrive.StartsWith("/")) {
        $pathWithoutDrive = $pathWithoutDrive.Substring(1)
    }
    $backupDir = Join-Path $BackupRoot $pathWithoutDrive

    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    }

    $backupPath = Join-Path $backupDir "$targetName.$Timestamp"
    if ($DryRun) {
        Write-Output "[dry-run] backup $Target -> $backupPath"
        return
    }
    Move-Item -Path $Target -Destination $backupPath -Force
    Write-Output "backed up $Target -> $backupPath"
}

function New-Symlink {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Target
    )

    if ($PSCmdlet.ShouldProcess($Target, "Create symlink to $Source")) {
        $parent = Split-Path -Parent $Target
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }

        Backup-Target -Source $Source -Target $Target

        if (Test-Path $Target) {
            Remove-Item -Force $Target
        }

        if ($DryRun) {
            Write-Output "[dry-run] link $Target -> $Source"
            return
        }
        New-Item -ItemType SymbolicLink -Path $Target -Target $Source | Out-Null
        Write-Output "linked $Target"
    }
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
        if ($DryRun) {
            Write-Output "[dry-run] prepend Include to $configPath"
            return
        }
        @($includeLine, "") + $existing | Set-Content -Path $configPath
    }
}

function Test-Doctor {
    $failures = 0
    $checks = @(
        @{ Source = (Join-Path $RepoRoot "home/.config/wezterm"); Target = (Join-Path $ConfigHome "wezterm") },
        @{ Source = (Join-Path $RepoRoot "home/.config/nvim"); Target = (Join-Path $ConfigHome "nvim") },
        @{ Source = (Join-Path $RepoRoot "home/.config/ooodnakov"); Target = (Join-Path $ConfigHome "ooodnakov") },
        @{ Source = (Join-Path $RepoRoot "home/.config/ohmyposh/ooodnakov.omp.json"); Target = (Join-Path $OhMyPoshDir "ooodnakov.omp.json") },
        @{ Source = (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1"); Target = (Join-Path $PowerShellDir "Microsoft.PowerShell_profile.ps1") }
    )
    foreach ($check in $checks) {
        $item = Get-Item -Path $check.Target -ErrorAction SilentlyContinue
        if ($item -and $item.LinkType -eq "SymbolicLink" -and $item.Target -eq $check.Source) {
            Write-Output "[ok] $($check.Target)"
        } else {
            Write-Output "[missing] $($check.Target)"
            $failures++
        }
    }
    foreach ($cmd in @("git", "wezterm", "nvim")) {
        if (Get-Command $cmd -ErrorAction SilentlyContinue) {
            Write-Output "[ok] command: $cmd"
        } else {
            Write-Output "[missing] command: $cmd"
            $failures++
        }
    }
    if ($failures -gt 0) { throw "Doctor found $failures issue(s)." }
}

function Invoke-Install {
    Install-WingetPackageIfMissing -CommandName "wezterm" -WingetId "wez.wezterm" -Description "WezTerm"
    Install-WingetPackageIfMissing -CommandName "nvim" -WingetId "Neovim.Neovim" -Description "Neovim"
    Install-WingetPackageIfMissing -CommandName "oh-my-posh" -WingetId "JanDeDobbeleer.OhMyPosh" -Description "oh-my-posh"
    Install-WingetPackageIfMissing -CommandName "git" -WingetId "Git.Git" -Description "Git"
    Install-WingetPackageIfMissing -CommandName "node" -WingetId "OpenJS.NodeJS.LTS" -Description "Node.js LTS"

    Install-Chocolatey
    Install-ChocoPackageIfMissing -CommandName "gsudo" -ChocoId "gsudo" -Description "gsudo (sudo for Windows)"
    Install-ChocoPackageIfMissing -CommandName "rg" -ChocoId "ripgrep" -Description "ripgrep"
    Install-ChocoPackageIfMissing -CommandName "fd" -ChocoId "fd" -Description "fd"
    Install-PnpmIfMissing

    New-Symlink -Source (Join-Path $RepoRoot "home/.config/wezterm") -Target (Join-Path $ConfigHome "wezterm")
    New-Symlink -Source (Join-Path $RepoRoot "home/.config/nvim") -Target (Join-Path $ConfigHome "nvim")
    New-Symlink -Source (Join-Path $RepoRoot "home/.config/ooodnakov") -Target (Join-Path $ConfigHome "ooodnakov")
    New-Symlink -Source (Join-Path $RepoRoot "home/.config/ohmyposh/ooodnakov.omp.json") -Target (Join-Path $OhMyPoshDir "ooodnakov.omp.json")
    New-Symlink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target (Join-Path $PowerShellDir "Microsoft.PowerShell_profile.ps1")

    Add-SshInclude
    Write-Output ""
    Write-Output "Bootstrap complete."
    Write-Output "If needed, create local overrides in $ConfigHome/ooodnakov/local."
}

switch ($Command) {
    "install" { Invoke-Install }
    "update" {
        if ($DryRun) {
            Write-Output "[dry-run] git -C $RepoRoot pull --ff-only"
        } else {
            git -C $RepoRoot pull --ff-only
        }
        Invoke-Install
    }
    "doctor" { Test-Doctor }
}
