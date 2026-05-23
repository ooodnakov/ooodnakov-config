# Dot-sourced by scripts/setup/setup.ps1; do not execute directly.

function Get-EditDistance {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Left,
        [Parameter(Mandatory = $true)]
        [string]$Right
    )

    $Left = [string]$Left
    $Right = [string]$Right

    $rightLength = $Right.Length
    $previous = New-Object int[] ($rightLength + 1)
    for ($j = 0; $j -le $rightLength; $j++) {
        $previous[$j] = $j
    }

    for ($i = 1; $i -le $Left.Length; $i++) {
        $current = New-Object int[] ($rightLength + 1)
        $current[0] = $i
        $leftChar = $Left.Substring($i - 1, 1)

        for ($j = 1; $j -le $rightLength; $j++) {
            $rightChar = $Right.Substring($j - 1, 1)
            $cost = if ($leftChar -ceq $rightChar) { 0 } else { 1 }
            $deletion = $previous[$j] + 1
            $insertion = $current[$j - 1] + 1
            $substitution = $previous[$j - 1] + $cost
            $current[$j] = [Math]::Min([Math]::Min($deletion, $insertion), $substitution)
        }

        $previous = $current
    }

    return $previous[$rightLength]

}

function Get-ClosestSuggestion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputText,
        [Parameter(Mandatory = $true)]
        [string[]]$Candidates
    )

    $bestCandidate = $null
    $bestDistance = [int]::MaxValue

    foreach ($candidate in $Candidates) {
        $candidateText = [string]$candidate
        if ([string]::IsNullOrWhiteSpace($candidateText)) { continue }
        $distance = Get-EditDistance -Left $InputText -Right $candidateText
        if ($distance -lt $bestDistance) {
            $bestDistance = $distance
            $bestCandidate = $candidate
        }
    }

    $threshold = if ($InputText.Length -le 4) { 2 } else { 3 }
    if ($bestDistance -le $threshold) {
        return $bestCandidate
    }

    return $null
}

function Show-SetupHelp {
    Write-UiBanner
    Write-UiSpacer
    Write-UiSectionFancy -IconName "version" -Title "Global options"
    @"
  -C, --repo-root PATH  run against a specific repo checkout
  -h, --help            show this help
  -n, --dry-run         add --dry-run to install or update
      --yes-optional    auto-accept optional dependency installs
      --skip-deps       skip dependency installation
  -V, --version         show CLI version information
      --print-repo-root print the resolved repo root and exit
"@

    Write-UiSpacer
    Write-UiSeparator
    Write-UiSectionFancy -IconName "install" -Title "Setup"
    Write-UiCommandRow -CommandName "bootstrap" -Description "clone/update repo then run install"
    Write-UiCommandRow -CommandName "install" -Description "apply managed config and optional dependency installs"
    Write-UiCommandRow -CommandName "deps" -Description "install optional dependencies only"
    Write-UiCommandRow -CommandName "update" -Description "pull repo with --ff-only, then re-run install"

    Write-UiSpacer
    Write-UiSectionFancy -IconName "doctor" -Title "Inspect & Validate"
    Write-UiCommandRow -CommandName "doctor" -Description "validate managed symlinks and required commands"
    Write-UiCommandRow -CommandName "dry-run" -Description "preview install flow without mutating filesystem"
    Write-UiCommandRow -CommandName "version" -Description "print CLI version and repo root"

    Write-UiSpacer
    Write-UiSectionFancy -IconName "lock" -Title "Manage State"
    Write-UiCommandRow -CommandName "delete" -Description "remove managed links and restore latest backups"
    Write-UiCommandRow -CommandName "remove" -Description "remove managed links only (no backup restore)"
    Write-UiCommandRow -CommandName "lock" -Description "regenerate dependency lock artifacts from pinned refs"
    Write-UiCommandRow -CommandName "update-pins" -Description "compare/update pinned refs and refresh lock artifacts"
    Write-UiCommandRow -CommandName "completions" -Description "regenerate tracked shell completions (autogen + oooconf)"
    Write-UiCommandRow -CommandName "link" -Description "inspect or manage links from the symlink manifest"

    Write-UiSpacer
    Write-UiSectionFancy -IconName "shell" -Title "Shell / Secrets / Agents"
    Write-UiCommandRow -CommandName "shell" -Description "manage local shell preferences such as forgit aliases"
    Write-UiCommandRow -CommandName "color" -Description "set a unified oooconf CLI color theme"
    Write-UiCommandRow -CommandName "secrets" -Description "sync or validate local secret env files"
    Write-UiCommandRow -CommandName "agents" -Description "detect/sync/doctor/update AGENTS.md and agent CLI workflows"
    Write-UiCommandRow -CommandName "wm" -Description "switch between or manage window managers (komorebi/glazewm)"

    Write-UiSpacer
    Write-UiSeparator
    Write-UiHelpBlock @"
Aliases:
  check -> doctor
  preview -> dry-run
  upgrade -> update
Note:
  bootstrap is Unix-only in this wrapper.
  On Windows, run ``scripts/setup/setup.ps1 install`` for initial setup.
Getting help:
  ./scripts/setup/setup.ps1 --help              show this message
  ./scripts/setup/setup.ps1 <command> --help   show command-specific help
UI controls:
  `$env:OOOCONF_COLOR='always'       override color output
  `$env:OOOCONF_ASCII='1'            force ASCII icons and borders
  `$env:OOOCONF_THEME='<theme>'      set the CLI color theme for this run
"@
}

if ($Help -or $Command -eq "help" -or $Command -eq "-h" -or $Command -eq "--help") {
    Show-SetupHelp
    exit 0
}

if (-not $Command) {
    $Command = "install"
}

$validCommands = $ValidSetupCommands
if ($validCommands -notcontains $Command) {
    $suggestion = Get-ClosestSuggestion -InputText $Command -Candidates $validCommands
    if ($suggestion) {
        Write-Error "Unknown command: $Command`nDid you mean: $suggestion"
    } else {
        Write-Error "Unknown command: $Command"
    }
    Show-SetupHelp
    exit 1
}

function Test-Interactive {
    switch ($InteractiveMode) {
        "always" { return $true }
        "never" { return $false }
        default {
            if ($Host.Name -eq "ServerRemoteHost") {
                return $false
            }

            try {
                if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
                    return $false
                }
            } catch {
                return $false
            }

            return [Environment]::UserInteractive
        }
    }
}

function Test-VerboseMode {
    return $VerboseMode -match '^(?i:1|true|yes|on|verbose)$'
}

function Start-StepProgress {
    param(
        [Parameter(Mandatory = $true)][int]$Total,
        [Parameter(Mandatory = $true)][string]$Activity
    )

    $script:StepTotal = [Math]::Max($Total, 1)
    $script:StepCurrent = 0
    $script:StepActivity = $Activity
}

function Step-Progress {
    param(
        [Parameter(Mandatory = $true)][string]$Status
    )

    $script:StepCurrent++
    $percent = [Math]::Min([Math]::Floor(($script:StepCurrent * 100) / $script:StepTotal), 100)

    if (Test-Interactive) {
        Write-Output "Step: $Status"
        Write-Progress -Activity $script:StepActivity -Status ("[{0}/{1}] {2}" -f $script:StepCurrent, $script:StepTotal, $Status) -PercentComplete $percent
        if ($script:StepCurrent -ge $script:StepTotal) {
            Write-Progress -Activity $script:StepActivity -Completed
        }
    } else {
        Write-Output ("[{0}/{1}] {2}" -f $script:StepCurrent, $script:StepTotal, $Status)
    }
}

function Confirm-Install {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    switch ($InstallOptionalMode) {
        "always" { return $true }
        "never" { return $false }
        default { }
    }

    if (-not (Test-Interactive)) {
        return $false
    }

    if (Get-Command gum -ErrorAction SilentlyContinue) {
        $transcriptActive = $script:TranscriptStarted
        if ($transcriptActive) {
            try { Stop-Transcript | Out-Null } catch {}
        }
        try {
            & gum confirm $Prompt
            return ($LASTEXITCODE -eq 0)
        } finally {
            if ($transcriptActive) {
                try { Start-Transcript -Path $script:LogFile -Append | Out-Null } catch {}
            }
        }
    }



    $reply = Read-Host "$Prompt [y/N]"
    return $reply -match '^(?i:y|yes)$'
}

$script:OptionalDependencySpecsCache = $null
