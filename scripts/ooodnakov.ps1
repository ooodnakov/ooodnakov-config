param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments = @()
)

$ErrorActionPreference = "Stop"

$RepoRoot = if ($env:OOODNAKOV_REPO_ROOT) {
    $env:OOODNAKOV_REPO_ROOT
} else {
    (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}
$SetupScript = Join-Path $PSScriptRoot "setup.ps1"
$GenerateLockScript = Join-Path $PSScriptRoot "generate-dependency-lock.py"
$UpdatePinsScript = Join-Path $PSScriptRoot "update-pins.py"
$RenderSecretsScript = Join-Path $PSScriptRoot "render-secrets.py"

function Get-Version {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        try {
            $version = git -C $RepoRoot describe --always --dirty --tags 2>$null
            if ($LASTEXITCODE -eq 0 -and $version) {
                return $version.Trim()
            }
        } catch {
        }

        try {
            $version = git -C $RepoRoot rev-parse --short HEAD 2>$null
            if ($LASTEXITCODE -eq 0 -and $version) {
                return $version.Trim()
            }
        } catch {
        }
    }

    return "unknown"
}

function Show-Usage {
    @"
Usage: oooconf [global options] <command> [command options]

Global options:
  -C, --repo-root PATH  run against a specific repo checkout
  -h, --help            show this help
  -n, --dry-run         add --dry-run to install or update
      --yes-optional    auto-accept optional dependency installs
  -V, --version         show CLI version information
      --print-repo-root print the resolved repo root and exit

Commands:
  install               run setup install
  deps                  install optional dependencies only
  update                run setup update
  doctor                run setup doctor
  dry-run               run setup install --dry-run
  lock                  regenerate dependency lock artifacts
  update-pins           check/update pinned refs and refresh lock artifacts
  secrets               sync or validate local secret env files
  help [command]        show general or command-specific help
  version               show CLI version information

Repo root:
  $RepoRoot
"@
}

function Show-CommandUsage {
    param(
        [string]$CommandName
    )

    switch ($CommandName) {
        "install" {
            @"
Usage: oooconf install [--dry-run] [--yes-optional]

Apply managed config and optional dependency installation.
"@
        }
        "deps" {
            @"
Usage: oooconf deps [--dry-run] [dependency-key...]

Install optional dependencies only. Without dependency keys, an interactive
gum-based multi-select picker is used when available.
"@
        }
        "update" {
            @"
Usage: oooconf update [--dry-run] [--yes-optional]

Pull the repo with --ff-only, then re-run the install flow.
"@
        }
        "doctor" {
            @"
Usage: oooconf doctor

Validate managed symlinks and required commands.
"@
        }
        "dry-run" {
            @"
Usage: oooconf dry-run

Preview the install flow without mutating the filesystem.
"@
        }
        "lock" {
            @"
Usage: oooconf lock

Regenerate dependency lock artifacts from pinned refs in scripts/setup.sh.
"@
        }
        "update-pins" {
            @"
Usage: oooconf update-pins [--apply]

Compare pinned git refs to upstream HEAD and refresh lock artifacts.
"@
        }
        "secrets" {
            @"
Usage: oooconf secrets <sync|doctor|list|status|login|unlock|logout> [options]

Render or validate local secret env files from the tracked template.
Examples:
  oooconf secrets login
  oooconf secrets unlock --shell pwsh | Invoke-Expression
  oooconf secrets sync
  oooconf secrets sync --dry-run
  oooconf secrets list
  oooconf secrets list --resolved
  oooconf secrets status
  oooconf secrets doctor
  oooconf secrets logout

Environment overrides:
  OOODNAKOV_SECRETS_BACKEND
  OOODNAKOV_BW_SERVER
"@
        }
        "version" {
            @"
Usage: oooconf version

Print the CLI version and resolved repo root.
"@
        }
        "" { Show-Usage }
        "help" { Show-Usage }
        "-h" { Show-Usage }
        "--help" { Show-Usage }
        default { throw "Unknown command: $CommandName" }
    }
}

function Require-Python3 {
    if (-not (Get-Command python3 -ErrorAction SilentlyContinue)) {
        throw "python3 is required."
    }
}

$dryRunRequested = $false
$yesOptionalRequested = $false
$command = $null
$remaining = [System.Collections.Generic.List[string]]::new()

for ($i = 0; $i -lt $Arguments.Count; $i++) {
    $arg = $Arguments[$i]
    switch ($arg) {
        "-C" {
            if ($i + 1 -ge $Arguments.Count) {
                throw "Missing value for $arg"
            }
            $RepoRoot = $Arguments[$i + 1]
            $i++
        }
        "--repo-root" {
            if ($i + 1 -ge $Arguments.Count) {
                throw "Missing value for $arg"
            }
            $RepoRoot = $Arguments[$i + 1]
            $i++
        }
        "--print-repo-root" {
            Write-Output $RepoRoot
            exit 0
        }
        "-V" {
            Write-Output "oooconf $(Get-Version)"
            Write-Output $RepoRoot
            exit 0
        }
        "--version" {
            Write-Output "oooconf $(Get-Version)"
            Write-Output $RepoRoot
            exit 0
        }
        "-h" {
            if ($i + 1 -lt $Arguments.Count -and -not $Arguments[$i + 1].StartsWith("-")) {
                Show-CommandUsage $Arguments[$i + 1]
            } else {
                Show-Usage
            }
            exit 0
        }
        "--help" {
            if ($i + 1 -lt $Arguments.Count -and -not $Arguments[$i + 1].StartsWith("-")) {
                Show-CommandUsage $Arguments[$i + 1]
            } else {
                Show-Usage
            }
            exit 0
        }
        "-n" {
            $dryRunRequested = $true
        }
        "--dry-run" {
            $dryRunRequested = $true
        }
        "--yes-optional" {
            $yesOptionalRequested = $true
        }
        "help" {
            if ($i + 1 -lt $Arguments.Count) {
                Show-CommandUsage $Arguments[$i + 1]
            } else {
                Show-Usage
            }
            exit 0
        }
        "version" {
            Write-Output "oooconf $(Get-Version)"
            Write-Output $RepoRoot
            exit 0
        }
        default {
            $command = $arg
            for ($j = $i + 1; $j -lt $Arguments.Count; $j++) {
                $remaining.Add($Arguments[$j])
            }
            break
        }
    }

    if ($command) {
        break
    }
}

if (-not $command) {
    if ($dryRunRequested) {
        $command = "install"
    } else {
        Show-Usage
        exit 0
    }
}

$env:OOODNAKOV_REPO_ROOT = $RepoRoot
if ($yesOptionalRequested) {
    $env:OOODNAKOV_INSTALL_OPTIONAL = "always"
}

switch ($command) {
    "install" {
        if ($dryRunRequested) {
            & $SetupScript install -DryRun @remaining
        } else {
            & $SetupScript install @remaining
        }
    }
    "deps" {
        if ($dryRunRequested) {
            & $SetupScript deps -DryRun @remaining
        } else {
            & $SetupScript deps @remaining
        }
    }
    "update" {
        if ($dryRunRequested) {
            & $SetupScript update -DryRun @remaining
        } else {
            & $SetupScript update @remaining
        }
    }
    "doctor" {
        if ($dryRunRequested) {
            throw "--dry-run is not supported for doctor"
        }
        & $SetupScript doctor @remaining
    }
    "dry-run" {
        if ($dryRunRequested) {
            throw "Use either dry-run or --dry-run, not both"
        }
        & $SetupScript install -DryRun @remaining
    }
    "lock" {
        if ($dryRunRequested) {
            throw "--dry-run is not supported for lock"
        }
        Require-Python3
        & python3 $GenerateLockScript @remaining
    }
    "update-pins" {
        if ($dryRunRequested) {
            throw "--dry-run is not supported for update-pins"
        }
        Require-Python3
        & python3 $UpdatePinsScript @remaining
    }
    "secrets" {
        Require-Python3
        & python3 $RenderSecretsScript --repo-root $RepoRoot @remaining
    }
    default {
        throw "Unknown command: $command"
    }
}

exit $LASTEXITCODE
