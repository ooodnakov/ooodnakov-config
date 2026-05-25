# Dot-sourced by scripts/setup/ooodnakov.ps1; do not execute directly.

$DELTA_GITCONFIG_BLOCK = @"

[core]
    pager = delta

[interactive]
    diffFilter = delta --color-only

[delta]
    navigate = true
    dark = true

[merge]
    conflictStyle = zdiff3

"@
$DELTA_SECTION_START = "# --- ooodnakov delta start ---"
$DELTA_SECTION_END = "# --- ooodnakov delta end ---"
$DELTA_SECTIONS = @("core", "interactive", "delta", "merge")

function Get-DeltaGitConfigPath {
    if ($env:GIT_CONFIG_GLOBAL) {
        return $env:GIT_CONFIG_GLOBAL
    }
    return Join-Path $HOME ".gitconfig"
}

function Test-DeltaBlockPresent {
    param([string]$GitConfigPath)
    if (-not (Test-Path $GitConfigPath)) { return $false }
    return (Get-Content $GitConfigPath -Raw) -match [regex]::Escape($DELTA_SECTION_START)
}

function Test-DeltaSectionExistsOutsideBlock {
    param([string]$GitConfigPath, [string]$Section)
    $inBlock = $false
    $lines = Get-Content $GitConfigPath
    foreach ($line in $lines) {
        if ($line -eq $DELTA_SECTION_START) { $inBlock = $true; continue }
        if ($line -eq $DELTA_SECTION_END) { $inBlock = $false; continue }
        if ($inBlock) { continue }
        $trimmed = $line.Trim()
        if ($trimmed -eq "[$Section]") { return $true }
    }
    return $false
}

function Remove-DeltaBlock {
    param([string]$GitConfigPath)
    $lines = Get-Content $GitConfigPath
    $inBlock = $false
    $filtered = @()
    foreach ($line in $lines) {
        if ($line -eq $DELTA_SECTION_START) { $inBlock = $true; continue }
        if ($line -eq $DELTA_SECTION_END) { $inBlock = $false; continue }
        if (-not $inBlock) { $filtered += $line }
    }
    Set-Content -Path $GitConfigPath -Value $filtered -NoNewline
    # Ensure trailing newline
    $content = Get-Content $GitConfigPath -Raw
    if ($content -notmatch "`n$") { Add-Content -Path $GitConfigPath -Value "" }
}

function Invoke-DeltaCommand {
    param([string[]]$DeltaArgs)
    $action = if ($DeltaArgs.Count -gt 0) { $DeltaArgs[0] } else { "" }
    $remainingArgs = if ($DeltaArgs.Count -gt 1) { $DeltaArgs[1..($DeltaArgs.Count - 1)] } else { @() }

    if ([string]::IsNullOrWhiteSpace($action) -or $action -eq "help") {
        Write-UiHelpBlock @"
Usage: oooconf delta <inject|status|remove>

Configure git-delta as the git pager and diff viewer.

Subcommands:
  inject          write delta git config to ~/.gitconfig (idempotent, warns if present)
  status          check whether delta is configured in ~/.gitconfig
  remove          remove ooodnakov's delta config block from ~/.gitconfig

Examples:
  oooconf delta inject
  oooconf delta status
  oooconf delta remove
"@
        return
    }

    switch ($action) {
        "inject" { Invoke-DeltaInject -RemainingArgs $remainingArgs }
        "status" { Invoke-DeltaStatus }
        "remove" { Invoke-DeltaRemove }
        default {
            $suggestion = Get-ClosestSuggestion -InputText $action -Candidates @("inject", "status", "remove")
            Write-UiLine -Role fail -Message "Unknown delta action: $action"
            if ($suggestion) { Write-UiLine -Role hint -Message "Did you mean: $suggestion" }
        }
    }
}

function Test-DeltaInstalled {
    return ($null -ne (Get-Command delta -ErrorAction SilentlyContinue))
}

function Test-GitInstalled {
    return ($null -ne (Get-Command git -ErrorAction SilentlyContinue))
}

function Invoke-DeltaInject {
    param([string[]]$RemainingArgs)
    $dryRun = $env:OOODNAKOV_DELTA_DRY_RUN -eq "1"

    if (-not (Test-GitInstalled)) {
        Write-UiLine -Role fail -Message "git is not installed -- cannot update ~/.gitconfig"
        return
    }

    $gitConfigPath = Get-DeltaGitConfigPath

    if (Test-DeltaBlockPresent -GitConfigPath $gitConfigPath) {
        Write-UiLine -Role info -Message "delta config already present in $gitConfigPath (use 'oooconf delta remove' first to replace)"
        return
    }

    if (-not $dryRun) {
        $warned = $false
        foreach ($section in $DELTA_SECTIONS) {
            if (Test-DeltaSectionExistsOutsideBlock -GitConfigPath $gitConfigPath -Section $section) {
                Write-UiLine -Role warn -Message "warning: [$section] already defined in $gitConfigPath -- will not be modified"
                $warned = $true
            }
        }
        if ($warned) {
            Write-UiLine -Role warn -Message "warning: existing [$section] sections were not modified"
            Write-UiLine -Role info -Message "run 'oooconf delta remove' first if you want a clean slate"
        }
    }

    if ($dryRun) {
        Write-UiLine -Role info -Message "[dry-run] would write delta config to $gitConfigPath"
        return
    }

    Add-Content -Path $gitConfigPath -Value ""
    Add-Content -Path $gitConfigPath -Value $DELTA_SECTION_START
    Add-Content -Path $gitConfigPath -Value $DELTA_GITCONFIG_BLOCK
    Add-Content -Path $gitConfigPath -Value $DELTA_SECTION_END

    Write-UiLine -Role ok -Message "delta config injected into $gitConfigPath"

    if (Test-DeltaInstalled) {
        $ver = (delta --version 2>$null) -replace "^delta "
        Write-UiLine -Role ok -Message "delta is installed -- config is active"
    } else {
        Write-UiLine -Role warn -Message "delta is not installed -- run 'oooconf deps delta' to install it"
    }
}

function Invoke-DeltaStatus {
    $gitConfigPath = Get-DeltaGitConfigPath

    if (Test-DeltaBlockPresent -GitConfigPath $gitConfigPath) {
        Write-UiLine -Role ok -Message "delta config: managed block found in $gitConfigPath"
    } else {
        Write-UiLine -Role info -Message "delta config: no managed block in $gitConfigPath"
    }

    if (Test-DeltaInstalled) {
        $ver = (delta --version 2>$null) -replace "^delta " | Select-Object -First 1
        Write-UiLine -Role ok -Message "delta: installed ($ver)"
    } else {
        Write-UiLine -Role warn -Message "delta: not installed (run 'oooconf deps delta' to install)"
    }

    if (Test-GitInstalled) {
        $pager = git config --global core.pager 2>$null
        if ($pager) {
            if ($pager -match "delta") {
                Write-UiLine -Role ok -Message "core.pager: $pager"
            } else {
                Write-UiLine -Role info -Message "core.pager: $pager (not delta)"
            }
        } else {
            Write-UiLine -Role info -Message "core.pager: not set"
        }
    }
}

function Invoke-DeltaRemove {
    $dryRun = $env:OOODNAKOV_DELTA_DRY_RUN -eq "1"
    $gitConfigPath = Get-DeltaGitConfigPath

    if (-not (Test-GitInstalled)) {
        Write-UiLine -Role fail -Message "git is not installed"
        return
    }

    if (-not (Test-DeltaBlockPresent -GitConfigPath $gitConfigPath)) {
        Write-UiLine -Role info -Message "no managed delta config found in $gitConfigPath"
        return
    }

    if ($dryRun) {
        Write-UiLine -Role info -Message "[dry-run] would remove delta config block from $gitConfigPath"
        return
    }

    Remove-DeltaBlock -GitConfigPath $gitConfigPath
    Write-UiLine -Role ok -Message "delta config removed from $gitConfigPath"
}
