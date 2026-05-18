# Dot-sourced by scripts/setup/ooodnakov.ps1; do not execute directly.

function Test-ShouldNormalizeGlobalFlags {
    param([Parameter(Mandatory = $true)][string]$CommandName)
    return $CommandName -in @("bootstrap", "install", "deps", "update", "doctor", "completions", "dry-run", "delete", "remove", "lock", "update-pins", "agents", "link")
}

function Invoke-SetupCommand {
    param(
        [Parameter(Mandatory = $true)][string]$SetupCommand,
        [switch]$SupportsDryRun,
        [string[]]$RemainingArgs = @()
    )

    $setupArgs = @()
    if ($allDepsRequested -and $SetupCommand -eq "deps") {
        $setupArgs += "--all"
    }
    $setupArgs += $RemainingArgs

    if ($dryRunRequested) {
        if (-not $SupportsDryRun) {
            throw "--dry-run is not supported for $SetupCommand"
        }
        & $SetupScript $SetupCommand -DryRun -SkipDeps:$skipDepsRequested @setupArgs
        if ($LASTEXITCODE -ne 0) {
            throw "setup $SetupCommand failed with exit code $LASTEXITCODE"
        }
        return
    }

    & $SetupScript $SetupCommand -SkipDeps:$skipDepsRequested @setupArgs
    if ($LASTEXITCODE -ne 0) {
        throw "setup $SetupCommand failed with exit code $LASTEXITCODE"
    }
}

function Assert-NoDryRun {
    param([Parameter(Mandatory = $true)][string]$CommandName)
    if ($dryRunRequested) {
        throw "--dry-run is not supported for $CommandName"
    }
}

function Invoke-DeleteCommand {
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)][string]$DeleteMode,
        [string[]]$RemainingArgs = @()
    )
    $env:OOODNAKOV_REPO_ROOT = $RepoRoot
    if ($dryRunRequested) {
        $RemainingArgs = @("--dry-run") + $RemainingArgs
    }
    & $DeleteScript $DeleteMode @RemainingArgs
}
