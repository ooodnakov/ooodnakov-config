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

oooconf - reproducible cross-platform dotfiles manager

Global options:
  -C, --repo-root PATH  run against a specific repo checkout
  -h, --help            show this help
  -n, --dry-run         add --dry-run to install or update
      --yes-optional    auto-accept optional dependency installs
  -V, --version         show CLI version information
      --print-repo-root print the resolved repo root and exit

Commands:
  Setup:
    install               apply managed config and optional dependency installs
    deps                  install optional dependencies only
    update                pull repo with --ff-only, then re-run install

  Inspect & Validate:
    doctor                validate managed symlinks and required commands
    dry-run               preview install flow without mutating filesystem
    version               print CLI version and repo root

  Manage State:
    lock                  regenerate dependency lock artifacts from pinned refs
    update-pins           compare/update pinned refs and refresh lock artifacts

  Secrets:
    secrets               sync or validate local secret env files

Note:
  bootstrap, delete, and remove commands are available in the Unix
  version only. On Windows, use setup.ps1 directly for bootstrap,
  and manual cleanup for delete/remove scenarios.

Getting help:
  oooconf --help                     show this message
  oooconf help <command>             show command-specific help
  oooconf help secrets               show secrets subcommand help

Common workflows:
  # Initial setup on a new machine:
  oooconf bootstrap

  # Preview what install would do:
  oooconf dry-run

  # Apply config and install dependencies:
  oooconf install
  oooconf deps

  # Check if everything is set up correctly:
  oooconf doctor

  # Update to latest config:
  oooconf update

Repo root:
  `$RepoRoot
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

Creates symlinks from tracked config in home/ to their target locations,
backing up any replaced files. Optionally installs dependencies when
allowed.

Examples:
  oooconf install                      # interactive dependency prompts
  oooconf install --yes-optional       # auto-accept all optional installs
  oooconf install --dry-run            # preview without making changes
"@
        }
        "deps" {
            @"
Usage: oooconf deps [--dry-run] [dependency-key...]

Install optional dependencies only. Without dependency keys, an interactive
gum-based multi-select picker is used when available.

Dependency keys match those defined in deps.lock.json. Common keys include:
bat, delta, eza, fd, fzf, gum, glow, ripgrep, zoxide, and others.

Examples:
  oooconf deps                         # interactive picker (when gum available)
  oooconf deps bat delta fd ripgrep    # install specific tools
  oooconf deps --dry-run               # preview installation
"@
        }
        "update" {
            @"
Usage: oooconf update [--dry-run] [--yes-optional]

Pull the repo with --ff-only, then re-run the install flow.

Use this to update your config to the latest tracked state. It performs
a fast-forward pull only, failing if local changes would prevent it.

Examples:
  oooconf update                       # pull and reinstall
  oooconf update --yes-optional        # also install missing dependencies
  oooconf update --dry-run             # preview pull and install
"@
        }
        "doctor" {
            @"
Usage: oooconf doctor

Validate managed symlinks and required commands.

Checks that all managed config links point to valid targets and that
key tools (git, zsh, wezterm, nvim, etc.) are available on PATH.

Examples:
  oooconf doctor                       # run all checks
"@
        }
        "dry-run" {
            @"
Usage: oooconf dry-run

Preview the install flow without mutating the filesystem.

Shows what links would be created, what files would be backed up, and
what dependencies would be installed, without making any changes.

Examples:
  oooconf dry-run                      # preview install
  oooconf --yes-optional dry-run       # preview with dependency installs
"@
        }
        "lock" {
            @"
Usage: oooconf lock

Regenerate dependency lock artifacts from pinned refs in setup scripts.

Reads pinned versions from scripts/setup.ps1 (or setup.sh) and writes
the resolved lock file to deps.lock.json.

Examples:
  oooconf lock                         # regenerate lock artifact
"@
        }
        "update-pins" {
            @"
Usage: oooconf update-pins [--apply]

Compare pinned git refs to upstream HEAD and refresh lock artifacts.

Without --apply, only reports differences. With --apply, updates the
pinned refs in setup scripts and regenerates lock artifacts.

Examples:
  oooconf update-pins                  # check for pin drift
  oooconf update-pins --apply          # update pins and regenerate lock
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

Print the CLI version (git describe or commit SHA) and resolved repo root.

Examples:
  oooconf version                      # show version and repo path
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
