# Dot-sourced by scripts/setup/setup.ps1; do not execute directly.

function Invoke-WithProgress {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    if ($DryRun) {
        Write-UiLine -Role hint -Message "[dry-run] $Description"
        return 0
    }

    $stdoutLog = Join-Path ([System.IO.Path]::GetTempPath()) ("oooconf-{0}.stdout.log" -f ([guid]::NewGuid().ToString("N")))
    $stderrLog = Join-Path ([System.IO.Path]::GetTempPath()) ("oooconf-{0}.stderr.log" -f ([guid]::NewGuid().ToString("N")))

    try {
        $process = & $Action $stdoutLog $stderrLog
    } catch {
        if (Test-Path $stdoutLog) { Remove-Item -LiteralPath $stdoutLog -Force -ErrorAction SilentlyContinue }
        if (Test-Path $stderrLog) { Remove-Item -LiteralPath $stderrLog -Force -ErrorAction SilentlyContinue }
        throw
    }

    if ($process -isnot [System.Diagnostics.Process]) {
        if (Test-Path $stdoutLog) { Remove-Item -LiteralPath $stdoutLog -Force -ErrorAction SilentlyContinue }
        if (Test-Path $stderrLog) { Remove-Item -LiteralPath $stderrLog -Force -ErrorAction SilentlyContinue }
        throw "Invoke-WithProgress action for '$Description' did not return a process handle."
    }

    $activityId = Get-Random -Minimum 1000 -Maximum 9999

    try {
        while (-not $process.HasExited) {
            Write-Progress -Id $activityId -Activity $Description -Status "Working..." -PercentComplete -1
            Start-Sleep -Milliseconds 125
            $process.Refresh()
        }

        $process.WaitForExit()
        $exitCode = $process.ExitCode
        Write-Progress -Id $activityId -Activity $Description -Completed

        if ($exitCode -ne 0) {
            if (Test-Path $stdoutLog) {
                Get-Content -LiteralPath $stdoutLog -ErrorAction SilentlyContinue | Write-Output
            }
            if (Test-Path $stderrLog) {
                Get-Content -LiteralPath $stderrLog -ErrorAction SilentlyContinue | Write-Output
            }
        }

        return $exitCode
    } finally {
        if (Test-Path $stdoutLog) { Remove-Item -LiteralPath $stdoutLog -Force -ErrorAction SilentlyContinue }
        if (Test-Path $stderrLog) { Remove-Item -LiteralPath $stderrLog -Force -ErrorAction SilentlyContinue }
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
        Write-UiLine -Role ok -Message "backed up $Target -> $backupPath"
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
        if (Test-VerboseMode) {
            Write-UiLine -Role ok -Message "linked $Target"
        }
        return $true
    }

    return (Invoke-Action -Description "Link $Target" -Action {
        New-Item -ItemType SymbolicLink -Path $Target -Target $Source -Force | Out-Null
        if (Test-VerboseMode) {
            Write-UiLine -Role ok -Message "linked $Target"
        }
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
        Write-UiLine -Role ok -Message "updated user PATH with $PathEntry"
    }

    if (($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ }) -notcontains $PathEntry) {
        $env:PATH = "$PathEntry$([IO.Path]::PathSeparator)$env:PATH"
    }

    return $updated
}

function Get-FontRegistryName {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$FontFile
    )

    # Prefer the font's internal family/face names (matches what the Windows
    # font UI registers); fall back to the filename when WPF is unavailable.
    $displayName = $null
    try {
        Add-Type -AssemblyName PresentationCore -ErrorAction Stop
        $typeface = New-Object System.Windows.Media.GlyphTypeface ([Uri]$FontFile.FullName)
        $familyNames = $typeface.Win32FamilyNames
        $faceNames = $typeface.Win32FaceNames
        if ($null -ne $familyNames -and $familyNames.ContainsKey("en-US")) {
            $displayName = [string]$familyNames["en-US"]
            if ($null -ne $faceNames -and $faceNames.ContainsKey("en-US") -and [string]$faceNames["en-US"] -ne "") {
                $displayName = "$displayName $([string]$faceNames['en-US'])"
            }
        }
    } catch {
        $displayName = $null
    }
    if ([string]::IsNullOrWhiteSpace($displayName)) {
        $displayName = ([System.IO.Path]::GetFileNameWithoutExtension($FontFile.Name) -replace "-", " ")
    }
    return "$displayName (TrueType)"
}

function Send-FontChangeBroadcast {
    # Let already-running applications pick up newly registered fonts without
    # waiting for the next logon.
    if (-not ("OooconfFontBroadcast" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class OooconfFontBroadcast {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint message, UIntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
}
"@
    }
    $result = [UIntPtr]::Zero
    [void][OooconfFontBroadcast]::SendMessageTimeout([IntPtr]0xFFFF, 0x001D, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 1000, [ref]$result)
}

function Install-MesloFontsIfMissing {
    # Install the bundled Meslo Nerd Font files per-user (no elevation):
    # %LOCALAPPDATA%\Microsoft\Windows\Fonts plus HKCU registry entries.
    # Git Bash (mintty), Windows Terminal, and WezTerm all resolve fonts
    # through the Windows font store, not the Unix fontconfig path that
    # install_fonts() uses on Linux/macOS.
    $fontSourceDir = Join-Path $RepoRoot "fonts/meslo"
    if (-not (Test-Path $fontSourceDir)) {
        Add-ToolSummary "fonts: nothing bundled at $fontSourceDir"
        return
    }

    $userFontDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    if (-not (Ensure-Directory -Path $userFontDir)) {
        return
    }

    $fontRegistryPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
    if (-not (Test-Path $fontRegistryPath)) {
        New-Item -Path $fontRegistryPath -Force | Out-Null
    }

    $installed = 0
    $present = 0
    foreach ($fontFile in Get-ChildItem -Path $fontSourceDir -Filter "*.ttf") {
        $entryName = Get-FontRegistryName -FontFile $fontFile
        $targetPath = Join-Path $userFontDir $fontFile.Name
        $registered = Get-ItemProperty -Path $fontRegistryPath -Name $entryName -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $targetPath)) {
            Copy-Item -LiteralPath $fontFile.FullName -Destination $targetPath -Force
        }
        if ($null -eq $registered) {
            New-ItemProperty -Path $fontRegistryPath -Name $entryName -Value $targetPath -PropertyType String -Force | Out-Null
            $installed++
        } else {
            $present++
        }
    }

    if ($installed -gt 0) {
        Send-FontChangeBroadcast
        Add-ToolSummary "fonts: installed $installed bundled Meslo font(s) for the current user"
    } else {
        Add-ToolSummary "fonts: bundled Meslo fonts already installed ($present)"
    }
}
