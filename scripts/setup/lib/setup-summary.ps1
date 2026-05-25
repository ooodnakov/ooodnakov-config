# Dot-sourced by scripts/setup/setup.ps1; do not execute directly.

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
    Write-UiLine -Role fail -Message "[failed] $Item"
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

    if (Test-VerboseMode) {
        Write-Output "Logging to $script:LogFile"
    }
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


function Update-SessionEnvironment {
    # Refresh PATH from registry to see newly installed tools without restarting the shell.
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")

    $newPath = @()
    if ($machinePath) { $newPath += $machinePath -split ';' }
    if ($userPath) { $newPath += $userPath -split ';' }
    if ($newPath.Count -eq 0 -and $env:PATH) {
        $separator = [System.IO.Path]::PathSeparator
        $newPath += $env:PATH -split [regex]::Escape([string]$separator)
    }

    $uniquePath = @($newPath | Where-Object { $_ } | Select-Object -Unique)
    if ($uniquePath.Count -gt 0) {
        $env:PATH = [string]::Join([System.IO.Path]::PathSeparator, $uniquePath)
    }

    if (Test-VerboseMode) {
        Write-UiLine -Role ok -Message "Refreshed session PATH."
    }
}

function Invoke-ActionWithSpinner {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action,
        [object[]]$ArgumentList = @()
    )

    if ($DryRun) {
        Write-UiLine -Role hint -Message "[dry-run] $Description"
        return $true
    }

    if (-not (Test-VerboseMode)) {
        if (Test-Interactive) {
            Write-Host -NoNewline "[-] $Description..."
        }

        $stdoutLog = Join-Path ([System.IO.Path]::GetTempPath()) ("oooconf-{0}.stdout.log" -f ([guid]::NewGuid().ToString("N")))
        $stderrLog = Join-Path ([System.IO.Path]::GetTempPath()) ("oooconf-{0}.stderr.log" -f ([guid]::NewGuid().ToString("N")))

        try {
            & $Action @ArgumentList > $stdoutLog 2> $stderrLog
            if (Test-Interactive) {
                Write-Host ("`r[ok] $Description")
            } else {
                Write-UiLine -Role ok -Message "[ok] $Description"
            }
            return $true
        } catch {
            if (Test-Interactive) {
                Write-Host ("`r[failed] $Description")
            } else {
                Write-UiLine -Role fail -Message "[failed] $Description"
            }
            if (Test-Path $stdoutLog) {
                Get-Content -LiteralPath $stdoutLog -ErrorAction SilentlyContinue | Write-Output
            }
            if (Test-Path $stderrLog) {
                Get-Content -LiteralPath $stderrLog -ErrorAction SilentlyContinue | Write-Output
            }
            Write-Output $_
            Add-Failure $Description
            return $false
        } finally {
            if (Test-Path $stdoutLog) { Remove-Item -LiteralPath $stdoutLog -Force -ErrorAction SilentlyContinue }
            if (Test-Path $stderrLog) { Remove-Item -LiteralPath $stderrLog -Force -ErrorAction SilentlyContinue }
        }
    }

    $interactive = Test-Interactive

    if (-not $interactive) {
        Write-Output "[-] $Description..."
    } else {
        Write-Host "[-] $Description..." -NoNewline
    }

    $ps = [PowerShell]::Create()

    $null = $ps.AddCommand("Set-Item").AddParameter("Path", "Env:PATH").AddParameter("Value", $env:PATH).AddStatement()

    $null = $ps.AddScript($Action)
    if ($ArgumentList.Count -gt 0) {
        foreach ($arg in $ArgumentList) {
            $null = $ps.AddArgument($arg)
        }
    }

    $asyncResult = $ps.BeginInvoke()
    $frames = @("-", "\", "|", "/")
    $i = 0
    while (-not $asyncResult.IsCompleted) {
        if ($interactive) {
            Write-Host "`r[$($frames[$i])] $Description..." -NoNewline
            $i = ($i + 1) % $frames.Length
            Start-Sleep -Milliseconds 120
        } else {
            Start-Sleep -Milliseconds 1000
        }
    }

    try {
        $results = $ps.EndInvoke($asyncResult)
        $hadErrors = $ps.HadErrors

        # Streams.Error might contain non-terminating errors from native commands (like winget).
        # We'll just echo them instead of failing immediately.
        foreach ($err in $ps.Streams.Error) {
            Write-Output "Message: $err"
        }
    } catch {
        $hadErrors = $true
        Write-Output $_
    } finally {
        $ps.Dispose()
    }

    if (-not $hadErrors) {
        if ($interactive) {
            Write-Host "`r[ok] $Description                            "
        } else {
            Write-UiLine -Role ok -Message "[ok] $Description"
        }
        return $true
    } else {
        if ($interactive) {
            Write-Host "`r[failed] $Description                        "
        } else {
            Write-UiLine -Role fail -Message "[failed] $Description"
        }
        Add-Failure $Description
        return $false
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
        Write-UiLine -Role hint -Message "[dry-run] $Description"
        return $true
    }

    try {
        & $Action
        return $true
    } catch {
        Write-UiLine -Role fail -Message "[failed] $Description"
        Add-Failure $Description
        return $false
    }
}


function Write-Summary {
    Write-UiSpacer
    if ($script:DependencySummary.Count -gt 0) {
        Write-UiSectionFancy -IconName "install" -Title "Dependency summary"
        foreach ($item in $script:DependencySummary) {
            if (-not (Test-VerboseMode) -and ($item -match ": present$" -or $item -match ": skipped$")) {
                continue
            }
            Write-UiLine -Role ok -Message "  - $item"
        }
    }

    if ($script:ToolSummary.Count -gt 0) {
        Write-UiSectionFancy -IconName "tool" -Title "Managed setup"
        foreach ($item in $script:ToolSummary) {
            if (-not (Test-VerboseMode) -and ($item -match ": linked$" -or $item -match ": linked into " -or $item -match "^ensured directory: " -or $item -match ": plugins synced$")) {
                continue
            }
            Write-UiLine -Role ok -Message "  - $item"
        }
    }

    if ($script:Failures.Count -gt 0) {
        Write-UiSectionFancy -IconName "fail" -Title "Failures"
        foreach ($item in $script:Failures) {
            Write-UiLine -Role fail -Message "  - $item"
        }
    }
}
