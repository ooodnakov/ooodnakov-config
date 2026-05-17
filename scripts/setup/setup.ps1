param(
    [string]$Command = "",
    [switch]$DryRun,
    [switch]$Help,
    [switch]$SkipDeps,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$DependencyKeys = @()
)

# Extract any stray global flags that PowerShell parameter binding leaked into ValueFromRemainingArguments
$filteredKeys = @()
foreach ($key in $DependencyKeys) {
    if ($key -eq "--dry-run" -or $key -eq "-n" -or $key -eq "-DryRun") {
        $DryRun = $true
    } elseif ($key -eq "--yes-optional") {
        $env:OOODNAKOV_INSTALL_OPTIONAL = "always"
    } elseif ($key -eq "--skip-deps") {
        $SkipDeps = $true
    } elseif ($key -eq "--all") {
        $filteredKeys += $key
    } else {
        $filteredKeys += $key
    }
}
$DependencyKeys = $filteredKeys

$ErrorActionPreference = "Stop"

# Allow syntax/import checks to dot-source this script without executing setup actions.
if ($MyInvocation.InvocationName -eq ".") {
    return
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path

# Dot-source ooodnakov.ps1 for shared UI functions
$OooconfPs1Path = Join-Path $RepoRoot "scripts/setup/ooodnakov.ps1"
if (Test-Path $OooconfPs1Path) {
    . $OooconfPs1Path
}

$OptionalDepsScript = Join-Path $RepoRoot "scripts/cli/read_optional_deps.py"
$AutogenCompletionsManifest = Join-Path $RepoRoot "scripts/generate/autogen-completions.txt"
$OooconfCompletionsGenerator = Join-Path $RepoRoot "scripts/cli/generate_oooconf_completions.py"
$HomeDir = $HOME
$ConfigHome = Join-Path $HomeDir ".config"
$DataHome = Join-Path $HomeDir ".local/share"
$StateHome = Join-Path $HomeDir ".local/state/ooodnakov-config"
$CacheHome = Join-Path $HomeDir ".cache/ooodnakov-config"
$ShareHome = Join-Path $HomeDir ".local/share/ooodnakov-config"
$LocalBinDir = Join-Path $HomeDir ".local/bin"
$OhMyPoshDir = Join-Path $ConfigHome "ohmyposh"
$PowerShellConfigDir = Join-Path $ConfigHome "powershell"
$PowerShellProfileTarget = Join-Path $PowerShellConfigDir "Microsoft.PowerShell_profile.ps1"
$ActivePowerShellProfile = $PROFILE.CurrentUserCurrentHost
$SshDir = Join-Path $HomeDir ".ssh"
$InteractiveMode = if ($env:OOODNAKOV_INTERACTIVE) { $env:OOODNAKOV_INTERACTIVE } else { "auto" }
$InstallOptionalMode = if ($env:OOODNAKOV_INSTALL_OPTIONAL) { $env:OOODNAKOV_INSTALL_OPTIONAL } else { "prompt" }
$VerboseMode = if ($env:OOODNAKOV_VERBOSE) { $env:OOODNAKOV_VERBOSE } else { "0" }
$BackupRoot = if ($env:OOODNAKOV_BACKUP_ROOT) { $env:OOODNAKOV_BACKUP_ROOT } else { Join-Path $HomeDir ".local/state/ooodnakov-config/backups" }
$LogRoot = if ($env:OOODNAKOV_LOG_ROOT) { $env:OOODNAKOV_LOG_ROOT } else { Join-Path $HomeDir ".local/state/ooodnakov-config/logs" }
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

# All versions/pins now live in optional-deps.toml ONLY (sole source of truth).
# These variables are removed. Use Get-DepInfo or Get-ManagedTool instead.
function Get-ManagedTool {
    param([string]$Name, [string]$Field = "ref")
    $json = Run-Python (Join-Path $RepoRoot "scripts/cli/read_optional_deps.py") @("managed-tools") | ConvertFrom-Json
    if ($json.PSObject.Properties.Name -contains $Name) {
        $json.$Name.$Field
    } else {
        ""
    }
}

function Get-DepInfo {
    param([string]$Key)
    # Returns hashtable with ver, url, bin, check, etc.
    $json = Run-Python (Join-Path $RepoRoot "scripts/cli/read_optional_deps.py") @("json") | ConvertFrom-Json
    $dep = $json | Where-Object { $_.key -eq $Key } | Select-Object -First 1
    if ($dep) { $dep } else { @{} }
}

function Install-Fonts {
    Step-Progress -Status "Installing bundled fonts"
    $fontDir = Join-Path $RepoRoot "fonts/meslo"
    if (-not (Test-Path $fontDir)) {
        Write-Warning "Font directory not found at $fontDir"
        return
    }

    $shellApp = New-Object -ComObject Shell.Application
    $fontsFolder = $shellApp.Namespace(0x14) # CSIDL_FONTS

    $fonts = Get-ChildItem -Path $fontDir -Filter "*.ttf"
    foreach ($font in $fonts) {
        $targetPath = Join-Path $env:SystemRoot "Fonts\$($font.Name)"
        if (-not (Test-Path $targetPath)) {
            Write-Output "Installing font: $($font.Name)"
            $fontsFolder.CopyHere($font.FullName, 0x10)
        } else {
            Write-Verbose "Font already installed: $($font.Name)"
        }
    }
}

$script:DependencySummary = [System.Collections.Generic.List[string]]::new()
$script:NewlyAvailableCommands = [System.Collections.Generic.List[string]]::new()
$script:ToolSummary = [System.Collections.Generic.List[string]]::new()
$script:Failures = [System.Collections.Generic.List[string]]::new()
$script:LogFile = $null
$script:LatestLogFile = $null
$script:TranscriptStarted = $false
$script:StepTotal = 0
$script:StepCurrent = 0
$script:StepActivity = ""
$ValidSetupCommands = @("install", "update", "doctor", "deps", "completions", "minimal", "link")

# Run a Python script, preferring `uv run` when available.
function Run-Python {
    param([string]$ScriptPath, [string[]]$ScriptArgs)
    $pyprojectPath = Join-Path $RepoRoot "pyproject.toml"
    if ((Get-Command uv -ErrorAction SilentlyContinue) -and (Test-Path $pyprojectPath)) {
        $prevErrorAction = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = & uv run $ScriptPath @ScriptArgs 2>$null
            return $output
        } finally {
            $ErrorActionPreference = $prevErrorAction
        }
    } else {
        $pyCmd = Get-PythonCommand
        if ($pyCmd) {
            & $pyCmd $ScriptPath @ScriptArgs
        } else {
            Write-Error "Python not found. Install Python 3.8+ or add it to your PATH."
            exit 1
        }
    }
}


function Get-PythonCommand {
    foreach ($candidate in @("python3", "python", "py")) {
        if (Get-Command $candidate -ErrorAction SilentlyContinue) { return $candidate }
    }
    return $null
}

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

    $reply = Read-Host "$Prompt [y/N]"
    return $reply -match '^(?i:y|yes)$'
}

$script:OptionalDependencySpecsCache = $null

function Detect-Platform {
    if ($IsWindows) { return "windows" }
    if ($IsMacOS) { return "macos" }
    if ($IsLinux) { return "linux" }
    # Fallback for older PowerShell on Windows
    if ($env:OS -eq "Windows_NT") { return "windows" }
    return "unknown"
}

function Test-OptionalDependencyApplicable {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Spec
    )

    $platform = Detect-Platform
    switch ($platform) {
        "windows" { return $null -ne $Spec.Windows }
        "macos"   { return $null -ne $Spec.Macos }
        "linux"   { return $null -ne $Spec.Linux }
        default   { return $true }
    }
}

function Get-OptionalDepsTomlFallbackData {
    if ($script:OptionalDepsTomlFallbackData) {
        return $script:OptionalDepsTomlFallbackData
    }

    $tomlPath = Join-Path $PSScriptRoot "optional-deps.toml"
    if (-not (Test-Path $tomlPath)) {
        $script:OptionalDepsTomlFallbackData = @{
            Deps        = @()
            MinimalKeys = @()
        }
        return $script:OptionalDepsTomlFallbackData
    }

    $entries = @()
    $minimalKeys = @()
    $current = @{}
    $inMinimalSection = $false
    foreach ($rawLine in (Get-Content -Path $tomlPath -ErrorAction SilentlyContinue)) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
            continue
        }

        if ($line -eq "[minimal]") {
            $inMinimalSection = $true
            continue
        }

        if ($line -match '^\[' -and $line -ne "[minimal]" -and $line -ne "[[deps]]") {
            $inMinimalSection = $false
        }

        if ($inMinimalSection -and $line -match '^keys\s*=\s*\[(.*)\]\s*$') {
            $minimalKeys = @(
                $matches[1] -split ',' |
                    ForEach-Object { $_.Trim().Trim('"').Trim("'") } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
            continue
        }

        if ($line -eq "[[deps]]") {
            if ($current.Count -gt 0) {
                $entries += ,$current
            }
            $current = @{}
            continue
        }

        if ($line -notmatch '^\s*([A-Za-z0-9_.-]+)\s*=\s*"(.*)"\s*$') {
            continue
        }

        $dottedKey = $matches[1]
        $value = $matches[2]
        $current[$dottedKey] = $value
    }
    if ($current.Count -gt 0) {
        $entries += ,$current
    }

    $deps = @($entries | ForEach-Object {
        $entry = $_
        $linux = @{}
        $macos = @{}
        $windows = @{}

        foreach ($k in @("manager", "package", "command", "winget_id", "choco_id", "url", "asset")) {
            $linuxKey = "linux.$k"
            $macosKey = "macos.$k"
            $windowsKey = "windows.$k"
            if ($entry.ContainsKey($linuxKey)) { $linux[$k] = $entry[$linuxKey] }
            if ($entry.ContainsKey($macosKey)) { $macos[$k] = $entry[$macosKey] }
            if ($entry.ContainsKey($windowsKey)) { $windows[$k] = $entry[$windowsKey] }
        }

        [pscustomobject]@{
            Key         = if ($entry.ContainsKey("key")) { $entry["key"] } else { "" }
            DisplayName = if ($entry.ContainsKey("display")) { $entry["display"] } elseif ($entry.ContainsKey("key")) { $entry["key"] } else { "" }
            Description = if ($entry.ContainsKey("description")) { $entry["description"] } else { "" }
            Handler     = if ($entry.ContainsKey("handler")) { $entry["handler"] } else { "" }
            Ver         = if ($entry.ContainsKey("ver")) { $entry["ver"] } else { "" }
            Url         = if ($entry.ContainsKey("url")) { $entry["url"] } else { "" }
            Asset       = if ($entry.ContainsKey("asset")) { $entry["asset"] } else { "" }
            Bin         = if ($entry.ContainsKey("bin")) { $entry["bin"] } else { "" }
            Check       = if ($entry.ContainsKey("check")) { $entry["check"] } else { "" }
            After       = if ($entry.ContainsKey("after")) { $entry["after"] } else { "" }
            Linux       = if ($linux.Count -gt 0) { $linux } else { $null }
            Macos       = if ($macos.Count -gt 0) { $macos } else { $null }
            Windows     = if ($windows.Count -gt 0) { $windows } else { $null }
        }
    })

    $script:OptionalDepsTomlFallbackData = @{
        Deps        = $deps
        MinimalKeys = @($minimalKeys | Select-Object -Unique)
    }
    return $script:OptionalDepsTomlFallbackData
}

function Get-OptionalDependencySpecsFromTomlFallback {
    return @((Get-OptionalDepsTomlFallbackData).Deps)
}

function Get-OptionalDependencySpecs {
    if ($script:OptionalDependencySpecsCache) {
        return $script:OptionalDependencySpecsCache
    }

    $json = $null
    try {
        $json = Run-Python -ScriptPath $OptionalDepsScript -ScriptArgs @("json") 2>$null
    } catch {
    }

    if (-not $json) {
        # Fallback: parse optional-deps.toml directly when Python is unavailable.
        $specs = @(Get-OptionalDependencySpecsFromTomlFallback)
        $script:OptionalDependencySpecsCache = $specs
        return @($specs | Where-Object { Test-OptionalDependencyApplicable -Spec $_ })
    }

    $raw = $json | ConvertFrom-Json
    $specs = @($raw | ForEach-Object {
        [pscustomobject]@{
            Key         = $_.key
            DisplayName = $_.display
            Description = $_.description
            Handler     = $_.handler
            Ver         = $_.ver
            Url         = $_.url
            Asset       = $_.asset
            Bin         = $_.bin
            Check       = $_.check
            WindowsOnly = ($null -eq $_.linux -and $null -eq $_.macos -and $null -ne $_.windows)
            Linux       = if ($_.linux) { $_.linux } else { $null }
            Macos       = if ($_.macos) { $_.macos } else { $null }
            Windows     = if ($_.windows) { $_.windows } else { $null }
        }
    })

    $script:OptionalDependencySpecsCache = $specs
    return @($specs | Where-Object { Test-OptionalDependencyApplicable -Spec $_ })
}

function Get-AllOptionalDependencySpecs {
    # Return all specs including platform-inapplicable ones (for validation).
    $json = $null
    try {
        $json = Run-Python -ScriptPath $OptionalDepsScript -ScriptArgs @("json") 2>$null
    } catch {}
    if ($json) {
        $raw = $json | ConvertFrom-Json
        return @($raw | ForEach-Object {
            [pscustomobject]@{
                Key         = $_.key
                DisplayName = $_.display
                Description = $_.description
                Handler     = $_.handler
                Ver         = $_.ver
                Url         = $_.url
                Asset       = $_.asset
                Bin         = $_.bin
                Check       = $_.check
                Linux       = if ($_.linux) { $_.linux } else { $null }
                Macos       = if ($_.macos) { $_.macos } else { $null }
                Windows     = if ($_.windows) { $_.windows } else { $null }
            }
        })
    }

    if (-not $script:OptionalDependencySpecsCache) {
        $null = Get-OptionalDependencySpecs
    }

    # Fallback: return filtered (applicable only) specs
    return $script:OptionalDependencySpecsCache
}

$script:SelectedOptionalKeys = @()

function Test-OptionalDependencySelected {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if (-not $script:SelectedOptionalKeys -or $script:SelectedOptionalKeys.Count -eq 0) {
        return $true
    }

    return $script:SelectedOptionalKeys -contains $Key
}

function Get-OptionalDependencyCommandNames {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ($Key -eq "posh-git" -or $Key -eq "psfzf") {
        return @()
    }

    $names = [System.Collections.Generic.List[string]]::new()
    $names.Add($Key)

    $spec = Get-AllOptionalDependencySpecs | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
    if (-not $spec) {
        return @($names)
    }

    # 1. explicit binary name
    if ($spec.Bin -and $names -notcontains $spec.Bin) { $names.Add($spec.Bin) }

    # 2. Extract from check command (e.g. "nvim --version" -> "nvim")
    if ($spec.Check -and $spec.Check -match '^\s*([A-Za-z0-9_.-]+)') {
        $cmdFromCheck = $matches[1]
        if ($names -notcontains $cmdFromCheck) { $names.Add($cmdFromCheck) }
    }

    # 3. Platform specific info
    $platformConfig = Get-OptionalDependencyPlatformConfig -Spec $spec
    if ($platformConfig) {
        # Only add command if it's a single word (no spaces, which indicates descriptive text)
        if ($platformConfig.command -and $platformConfig.command -notmatch '\s') {
            if ($names -notcontains $platformConfig.command) { $names.Add($platformConfig.command) }
        }
        # Often package name matches command name (except for cargo where it's a URL or repo)
        if ($platformConfig.package -and $platformConfig.manager -notin @("cargo", "github-release") -and $platformConfig.package -notmatch '\s') {
            if ($names -notcontains $platformConfig.package) { $names.Add($platformConfig.package) }
        }
    }

    # Special handling for python3
    if ($Key -eq "python3" -and ($names -notcontains "python")) {
        $names.Add("python")
    }

    return @($names)
}

function Test-OptionalDependencyPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ([string]::IsNullOrWhiteSpace($Key)) {
        return $false
    }

    if ($Key -eq "posh-git") {
        return [bool](Get-Module -ListAvailable -Name posh-git)
    }
    if ($Key -eq "psfzf") {
        return [bool](Get-Module -ListAvailable -Name PSFzf)
    }

    $spec = Get-AllOptionalDependencySpecs | Where-Object { $_.Key -eq $Key } | Select-Object -First 1

    # If a custom check string with arguments is provided, execute it literally.
    if ($spec -and $spec.Check -and $spec.Check -match '\s') {
        try {
            # Execute in a way that suppresses ALL output (stdout and stderr)
            & { Invoke-Expression $spec.Check } > $null 2>&1
            return ($LASTEXITCODE -eq 0)
        } catch {
            return $false
        }
    }

    $commandNames = @(Get-OptionalDependencyCommandNames -Key $Key | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($commandNames.Count -eq 0) {
        return $false
    }

    return Test-AnyCommand -Names $commandNames
}

function Invoke-SelectedOptionalDependency {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    if (-not (Test-OptionalDependencySelected -Key $Key)) {
        return $false
    }

    & $Action
    return $true
}

function Get-OptionalDependencyPlatformConfig {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Spec
    )

    $platform = Detect-Platform
    switch ($platform) {
        "windows" { return $Spec.Windows }
        "macos"   { return $Spec.Macos }
        "linux"   { return $Spec.Linux }
        default   { return $null }
    }
}

function Install-OptionalDependencyFromSpec {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Spec
    )

    $key = $Spec.Key
    if (-not (Test-OptionalDependencySelected -Key $key)) {
        return $false
    }

    $handler = if ($Spec.PSObject.Properties.Name -contains "Handler") { [string]$Spec.Handler } else { "" }

    switch ($handler) {
        "choco" { return (Install-Chocolatey) }
        "brew" { return (Install-HomebrewIfMissing) }
        "posh-git" { return (Install-PoshGitIfMissing) }
        "psfzf" { return (Install-PSFzfIfMissing) }
        "bw" { return (Install-BitwardenCliIfMissing) }
        "node" { return (Install-NodeIfMissing) }
        "pnpm" { return (Install-PnpmIfMissing) }
        "cargo" { return (Install-CargoIfMissing) }
        "dua" { return (Install-DuaIfMissing) }
        "nvim" { return (Install-NeovimIfMissing) }
        "rtk" { return (Install-RtkIfMissing) }
        "tectonic" { return (Install-TectonicIfMissing) }
        "zebar-pack-overline" {
            if (-not $IsWindows) {
                Add-DependencySummary "overline-zebar: skipped (Windows only)"
                return $false
            }

            $cliScript = Join-Path $PSScriptRoot "ooodnakov.ps1"
            $alreadyInstalled = & pwsh -NoProfile -File $cliScript wm zebar-config list 2>$null | Where-Object { $_ -match "^\*\s+overline" }
            if ($alreadyInstalled) {
                Add-DependencySummary "overline-zebar: already installed"
                return $true
            }

            $res = Invoke-ActionWithSpinner -Description "Installing overline-zebar" -Action {
                param($scriptPath)
                & pwsh -NoProfile -File $scriptPath wm zebar-config install overline-zebar | Out-Null
            } -ArgumentList $cliScript
            if ($res) {
                Add-DependencySummary "overline-zebar: installed"
            } else {
                Add-DependencySummary "overline-zebar: install attempted"
            }
            return $res
        }
        "k" {
            Write-Warning "k is not available on Windows."
            Add-DependencySummary "k: skipped"
            return $false
        }
    }

    switch ($key) {
        "zsh" {
            Write-Warning "zsh is not natively supported on Windows; use WSL or a custom build."
            Add-DependencySummary "zsh: skipped"
            return $false
        }
    }

    $platformConfig = Get-OptionalDependencyPlatformConfig -Spec $Spec
    if (-not $platformConfig) {
        Add-DependencySummary "${key}: skipped (not applicable on this platform)"
        return $false
    }

    $commandNames = @(Get-OptionalDependencyCommandNames -Key $key | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($commandNames.Count -eq 0) {
        $commandNames = @($key)
    }

    $summaryName = $key
    $description = if ($Spec.DisplayName) { [string]$Spec.DisplayName } else { $key }
    $manager = if ($platformConfig.manager) { [string]$platformConfig.manager } else { "" }
    $packageName = if ($platformConfig.package) { [string]$platformConfig.package } else { "" }
    $wingetId = if ($platformConfig.winget_id) { [string]$platformConfig.winget_id } elseif ($manager -eq "winget") { $packageName } else { "" }
    $chocoId = if ($platformConfig.choco_id) { [string]$platformConfig.choco_id } elseif ($manager -eq "choco") { $packageName } else { "" }
    $cargoGitUrl = if ($manager -eq "cargo") { $packageName } else { "" }
    $scoopPackage = if ($manager -eq "scoop") { $packageName } else { "" }

    switch ($manager) {
        "custom" {
            Add-DependencySummary "${summaryName}: skipped (manual installer)"
            return $false
        }
        "curl" {
            Add-DependencySummary "${summaryName}: skipped (manual curl installer)"
            return $false
        }
        "winget" {
            return (Install-PackageIfMissing -CommandNames $commandNames -WingetId $wingetId -Description $description -SummaryName $summaryName)
        }
        "choco" {
            return (Install-PackageIfMissing -CommandNames $commandNames -ChocoId $chocoId -Description $description -SummaryName $summaryName)
        }
        "cargo" {
            return (Install-PackageIfMissing -CommandNames $commandNames -CargoGitUrl $cargoGitUrl -Description $description -SummaryName $summaryName)
        }
        "scoop" {
            return (Install-PackageIfMissing -CommandNames $commandNames -ScoopPackage $scoopPackage -Description $description -SummaryName $summaryName)
        }
        "pnpm" {
            $res = (Invoke-ActionWithSpinner -Description "Installing $description via pnpm" -Action {
                param($pkg)
                pnpm add --global $pkg | Out-Null
            } -ArgumentList $packageName)
            Update-SessionEnvironment
            if ($res) { Add-NewlyAvailableCommand -CommandNames $commandNames }
            return $res
        }
        "github-release" {
            return (Install-GitHubReleaseDependencyIfMissing -Spec $Spec -PlatformConfig $platformConfig -CommandNames $commandNames -Description $description -SummaryName $summaryName)
        }
        "pip" {
            if (Test-DependencyStatus -CommandName $commandNames[0] -SummaryName $summaryName) { return $true }

            $pythonCommand = Get-PythonCommand
            if (-not $pythonCommand) {
                Add-DependencySummary "${summaryName}: missing (Python unavailable for pip)"
                return $false
            }

            $res = (Invoke-ActionWithSpinner -Description "Installing $description via pip" -Action {
                param($pkg, $pythonExe)
                if ($pythonExe -eq "py") {
                    & $pythonExe -3 -m pip install --upgrade $pkg | Out-Null
                } else {
                    & $pythonExe -m pip install --upgrade $pkg | Out-Null
                }
            } -ArgumentList $packageName, $pythonCommand)
            Update-SessionEnvironment
            if ($res) { Add-NewlyAvailableCommand -CommandNames $commandNames }
            return $res
        }
        default {
            Add-DependencySummary "${summaryName}: skipped (unsupported manager: $manager)"
            return $false
        }
    }
}

function Ensure-GumForDependencySelector {
    if (Get-Command gum -ErrorAction SilentlyContinue) {
        return $true
    }

    if (-not (Test-Interactive)) {
        return $false
    }

    if (-not (Confirm-Install "Install gum with winget for the dependency picker?")) {
        return $false
    }

    $previousMode = $InstallOptionalMode
    $script:SelectedOptionalKeys = @("gum")
    $script:DependencySummary.Clear()
    $InstallOptionalMode = "always"
    try {
        Install-PackageIfMissing -CommandNames @("gum") -WingetId "charmbracelet.gum" -Description "gum" -SummaryName "gum" | Out-Null
    } finally {
        $InstallOptionalMode = $previousMode
        $script:SelectedOptionalKeys = @()
        $script:DependencySummary.Clear()
    }

    return [bool](Get-Command gum -ErrorAction SilentlyContinue)
}

function Select-OptionalDependenciesWithoutGum {
    $allPresent = $true
    $available = @(Get-OptionalDependencySpecs | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.Key) -and -not (Test-OptionalDependencyPresent -Key $_.Key)
    })

    if ($available.Count -eq 0) {
        Write-Information "All optional dependencies are already present." -InformationAction Continue
        return @("__all_present__")
    }

    Write-Information "Available optional dependencies:" -InformationAction Continue
    foreach ($spec in $available) {
        Write-Information ("  {0,-12} {1}" -f $spec.Key, $spec.DisplayName) -InformationAction Continue
    }
    Write-Information "" -InformationAction Continue

    $input_str = Read-Host "Enter space/comma-separated keys to install (or empty to skip)"
    $wanted = @($input_str -split '[ ,]+' | Where-Object { $_ })

    if ($wanted.Count -eq 0) {
        Write-Information "No optional dependencies selected." -InformationAction Continue
        return @()
    }

    $validKeys = @($available | ForEach-Object { $_.Key })
    foreach ($key in $wanted) {
        if ($validKeys -notcontains $key) {
            Write-Error "Unknown dependency key: $key"
            return @()
        }
    }

    Write-Information "Selected: $($wanted -join ', ')" -InformationAction Continue
    return $wanted
}

function Select-OptionalDependenciesWithGum {
    if (-not (Ensure-GumForDependencySelector)) {
        return $null
    }

    $options = foreach ($spec in Get-OptionalDependencySpecs) {
        if ([string]::IsNullOrWhiteSpace($spec.Key)) {
            continue
        }
        if (Test-OptionalDependencyPresent -Key $spec.Key) {
            continue
        }
        "$($spec.Key)`t$($spec.DisplayName)`t$($spec.Description)"
    }

    if (-not $options) {
        Write-Output "All optional dependencies are already present."
        return @("__all_present__")
    }

    # Stop transcript if active, as it can interfere with interactive TUI tools like gum on Windows
    $transcriptActive = $script:TranscriptStarted
    if ($transcriptActive) {
        try { Stop-Transcript | Out-Null } catch {}
    }

    try {
        # Use arguments instead of pipe for better reliability with interactive TUI on Windows.
        # Splatting @options passes each item as a separate positional argument to gum choose.
        $selection = & gum choose --no-limit --height 20 --header "Select optional dependencies to install. Use arrows to move, x to toggle, enter to continue." @options
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0 -or -not $selection) {
            return @()
        }

        return @($selection | ForEach-Object { ($_ -split "`t")[0] })
    } finally {
        # Restart transcript if it was previously active
        if ($transcriptActive) {
            try { Start-Transcript -Path $script:LogFile -Append | Out-Null } catch {}
        }
    }
}

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

function Test-AnyCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        if (Get-Command $name -ErrorAction SilentlyContinue) {
            return $true
        }
        if ($IsWindows -and -not $name.EndsWith(".exe")) {
            if (Get-Command "$name.exe" -ErrorAction SilentlyContinue) {
                return $true
            }
        }
    }

    return $false
}

function Test-DependencyStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,
        [Parameter(Mandatory = $true)]
        [string]$SummaryName,
        [switch]$IsModule
    )

    if (-not $DryRun -and (Test-VerboseMode)) {
        if (Test-Interactive) {
            Write-Host "[-] Checking $SummaryName..." -NoNewline
        }
    }

    $isPresent = $false
    if ($IsModule) {
        $isPresent = [bool](Get-Module -ListAvailable -Name $CommandName -ErrorAction SilentlyContinue)
    } else {
        $isPresent = (Test-AnyCommand -Names @($CommandName))
    }

    if ($isPresent) {
        if (-not $DryRun) {
            if (Test-Interactive -and (Test-VerboseMode)) {
                Write-Host "`r[ok] $SummaryName is present.             "
            } else {
                Write-Output "[ok] $SummaryName is present."
            }
        }
        Add-DependencySummary "${SummaryName}: present"
        return $true
    }

    if (-not $DryRun -and (Test-Interactive) -and (Test-VerboseMode)) {
        Write-Host "`r" -NoNewline
    }
    return $false
}

function Install-Chocolatey {
    if (Test-DependencyStatus -CommandName "choco" -SummaryName "choco") { return $true }

    if (-not (Confirm-Install "Install Chocolatey for optional Windows CLI packages?")) {
        Add-DependencySummary "choco: skipped"
        return $false
    }

    if ($DryRun) {
        Write-UiLine -Role hint -Message "[dry-run] Install Chocolatey"
        Add-DependencySummary "choco: install preview"
        return $false
    }

    try {
        Write-UiLine -Role info -Message "Installing Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-RestMethod -Uri "https://community.chocolatey.org/install.ps1" | Invoke-Expression
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Add-DependencySummary "choco: installed"
            Add-NewlyAvailableCommand -CommandNames @("choco")
            return $true
        }
    } catch {
        Write-Output $_
        Add-Failure "Installing Chocolatey"
    }

    Add-DependencySummary "choco: install attempted"
    return $false
}

function Add-HomebrewToSessionPath {
    $brewBins = @(
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/home/linuxbrew/.linuxbrew/bin"
    )

    foreach ($binDir in $brewBins) {
        $brewPath = Join-Path $binDir "brew"
        if (Test-Path $brewPath) {
            $pathParts = @($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ })
            if ($pathParts -notcontains $binDir) {
                $env:PATH = "$binDir$([IO.Path]::PathSeparator)$env:PATH"
            }
            return $true
        }
    }

    return $false
}

function Install-HomebrewIfMissing {
    if (Test-DependencyStatus -CommandName "brew" -SummaryName "brew") { return $true }

    $platform = Detect-Platform
    if ($platform -notin @("macos", "linux")) {
        Add-DependencySummary "brew: skipped (macOS/Linux only)"
        return $false
    }

    if (-not (Confirm-Install "Install Homebrew package manager with the official install script?")) {
        Add-DependencySummary "brew: skipped"
        return $false
    }

    if (-not (Get-Command curl -ErrorAction SilentlyContinue)) {
        Add-DependencySummary "brew: missing (curl unavailable)"
        return $false
    }

    if (-not (Test-Path "/bin/bash")) {
        Add-DependencySummary "brew: missing (/bin/bash unavailable)"
        return $false
    }

    $res = Invoke-ActionWithSpinner -Description "Installing Homebrew" -Action {
        & env NONINTERACTIVE=1 /bin/bash -c '$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)'
    }

    if ($DryRun) {
        Add-DependencySummary "brew: install preview"
        return $true
    }

    $null = Add-HomebrewToSessionPath

    if ($res -and (Get-Command brew -ErrorAction SilentlyContinue)) {
        Add-DependencySummary "brew: installed"
        Add-NewlyAvailableCommand -CommandNames @("brew")
        return $true
    }

    Add-DependencySummary "brew: install attempted"
    return $false
}

function Install-PackageIfMissing {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CommandNames,
        [string]$WingetId,
        [string]$ChocoId,
        [string]$CargoGitUrl,
        [string]$ScoopPackage,
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [string]$SummaryName
    )

    if (Test-DependencyStatus -CommandName $CommandNames[0] -SummaryName $SummaryName) { return $true }

    if ($WingetId -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        if (Confirm-Install "Install $Description with winget?") {
            if ($DryRun) {
                Write-Output "[dry-run] winget install --exact --id $WingetId"
                Add-DependencySummary "${SummaryName}: install preview via winget"
                return $false
            }

            Invoke-ActionWithSpinner -Description "Installing $Description via winget" -Action {
                param($wid)
                winget install --exact --id $wid --accept-package-agreements --accept-source-agreements --silent | Out-Null
            } -ArgumentList $WingetId

            Update-SessionEnvironment

            if (Test-AnyCommand -Names $CommandNames) {
                Add-DependencySummary "${SummaryName}: installed via winget"
                Add-NewlyAvailableCommand -CommandNames $CommandNames
                return $true
            }

            Add-DependencySummary "${SummaryName}: install attempted via winget"
            return $false
        }

        Add-DependencySummary "${SummaryName}: skipped"
        return $false
    }

    if ($ChocoId -and (Get-Command choco -ErrorAction SilentlyContinue)) {
        if (Confirm-Install "Install $Description with Chocolatey?") {
            if ($DryRun) {
                Write-Output "[dry-run] choco install $ChocoId -y"
                Add-DependencySummary "${SummaryName}: install preview via choco"
                return $false
            }

            Invoke-ActionWithSpinner -Description "Installing $Description via choco" -Action {
                param($cid)
                choco install $cid -y | Out-Null
            } -ArgumentList $ChocoId

            Update-SessionEnvironment

            if (Test-AnyCommand -Names $CommandNames) {
                Add-DependencySummary "${SummaryName}: installed via choco"
                Add-NewlyAvailableCommand -CommandNames $CommandNames
                return $true
            }

            Add-DependencySummary "${SummaryName}: install attempted via choco"
            return $false
        }

        Add-DependencySummary "${SummaryName}: skipped"
        return $false
    }

    if ($ScoopPackage -and (Get-Command scoop -ErrorAction SilentlyContinue)) {
        if (Confirm-Install "Install $Description with Scoop?") {
            if ($DryRun) {
                Write-Output "[dry-run] scoop install $ScoopPackage"
                Add-DependencySummary "${SummaryName}: install preview via scoop"
                return $false
            }

            Invoke-ActionWithSpinner -Description "Installing $Description via scoop" -Action {
                param($pkg)
                scoop install $pkg | Out-Null
            } -ArgumentList $ScoopPackage

            Update-SessionEnvironment

            if (Test-AnyCommand -Names $CommandNames) {
                Add-DependencySummary "${SummaryName}: installed via scoop"
                Add-NewlyAvailableCommand -CommandNames $CommandNames
                return $true
            }

            Add-DependencySummary "${SummaryName}: install attempted via scoop"
            return $false
        }

        Add-DependencySummary "${SummaryName}: skipped"
        return $false
    }

    if ($CargoGitUrl) {
        if (-not (Install-CargoIfMissing)) {
            Add-DependencySummary "${SummaryName}: missing (cargo unavailable)"
            return $false
        }

        if (Confirm-Install "Install $Description via cargo?") {
            $cargoBinDir = Join-Path $HomeDir ".cargo/bin"
            $cargoExe = Join-Path $cargoBinDir "cargo.exe"
            if (($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ }) -notcontains $cargoBinDir) {
                $env:PATH = "$cargoBinDir$([IO.Path]::PathSeparator)$env:PATH"
            }

            $cargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
            if (-not $cargoCommand -and (Test-Path $cargoExe)) {
                $cargoCommand = $cargoExe
            }

            if (-not $cargoCommand) {
                Add-DependencySummary "${SummaryName}: missing (cargo unavailable)"
                return $false
            }

            if ($DryRun) {
                if ($CargoGitUrl -match "^https?://" -or $CargoGitUrl -match "^git@") {
                    Write-Output "[dry-run] cargo install --locked --git $CargoGitUrl"
                } else {
                    Write-Output "[dry-run] cargo install $CargoGitUrl"
                }
                Add-DependencySummary "${SummaryName}: install preview via cargo"
                return $false
            }

            Invoke-ActionWithSpinner -Description "Installing $Description via cargo" -Action {
                param($url, $cmd)
                if ($url -match "^https?://" -or $url -match "^git@") {
                    & $cmd install --locked --git $url | Out-Null
                } else {
                    & $cmd install $url | Out-Null
                }
            } -ArgumentList $CargoGitUrl, $cargoCommand

            $installedPath = Join-Path $cargoBinDir "$($CommandNames[0]).exe"
            if ((Test-AnyCommand -Names $CommandNames) -or (Test-Path $installedPath)) {
                Add-DependencySummary "${SummaryName}: installed via cargo"
                Add-NewlyAvailableCommand -CommandNames $CommandNames
                return $true
            }

            Add-DependencySummary "${SummaryName}: install attempted via cargo"
            return $false
        }

        Add-DependencySummary "${SummaryName}: skipped"
        return $false
    }

    Add-DependencySummary "${SummaryName}: missing (no supported package manager)"
    return $false
}

function Get-OptionalConfigValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Config -is [hashtable]) {
        if ($Config.ContainsKey($Name)) { return [string]$Config[$Name] }
        return ""
    }

    if ($Config.PSObject.Properties.Name -contains $Name) {
        return [string]$Config.$Name
    }

    return ""
}

function Get-GitHubReleaseArch {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    if ($arch -eq [System.Runtime.InteropServices.Architecture]::X64) { return "x86_64" }
    if ($arch -eq [System.Runtime.InteropServices.Architecture]::Arm64) { return "aarch64" }
    if ($arch -eq [System.Runtime.InteropServices.Architecture]::X86) { return "i686" }
    return ""
}

function Expand-GitHubReleaseTemplate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Template,
        [Parameter(Mandatory = $true)]
        [string]$Version,
        [Parameter(Mandatory = $true)]
        [string]$System,
        [Parameter(Mandatory = $true)]
        [string]$Arch
    )

    return $Template.Replace('${ver}', $Version).Replace('${system}', $System).Replace('${arch}', $Arch)
}

function Install-GitHubReleaseDependencyIfMissing {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Spec,
        [Parameter(Mandatory = $true)]
        [object]$PlatformConfig,
        [Parameter(Mandatory = $true)]
        [string[]]$CommandNames,
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [string]$SummaryName
    )

    if (Test-DependencyStatus -CommandName $CommandNames[0] -SummaryName $SummaryName) { return $true }

    $repo = Get-OptionalConfigValue -Config $PlatformConfig -Name "package"
    $version = if ($Spec.Ver) { [string]$Spec.Ver } else { "" }
    $assetTemplate = Get-OptionalConfigValue -Config $PlatformConfig -Name "asset"
    $urlTemplate = Get-OptionalConfigValue -Config $PlatformConfig -Name "url"
    if ([string]::IsNullOrWhiteSpace($version) -or [string]::IsNullOrWhiteSpace($repo) -or ([string]::IsNullOrWhiteSpace($assetTemplate) -and [string]::IsNullOrWhiteSpace($urlTemplate))) {
        Add-DependencySummary "${SummaryName}: missing (github-release metadata incomplete)"
        return $false
    }

    $system = Detect-Platform
    $arch = Get-GitHubReleaseArch
    if ([string]::IsNullOrWhiteSpace($arch)) {
        Add-DependencySummary "${SummaryName}: unsupported architecture"
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($assetTemplate)) {
        $assetTemplate = Split-Path -Leaf $urlTemplate
    }

    $assetName = Expand-GitHubReleaseTemplate -Template $assetTemplate -Version $version -System $system -Arch $arch
    $releaseUrl = if ([string]::IsNullOrWhiteSpace($urlTemplate)) {
        "https://github.com/$repo/releases/download/v$version/$assetName"
    } else {
        Expand-GitHubReleaseTemplate -Template $urlTemplate -Version $version -System $system -Arch $arch
    }

    if (-not (Confirm-Install "Install $Description from the GitHub release archive?")) {
        Add-DependencySummary "${SummaryName}: skipped"
        return $false
    }

    $binaryName = if ($Spec.Bin) { [string]$Spec.Bin } else { $CommandNames[0] }
    $binaryFile = if ($IsWindows -and -not $binaryName.EndsWith(".exe")) { "$binaryName.exe" } else { $binaryName }
    $installRoot = Join-Path $ShareHome "tools/$SummaryName/v$version"
    $archivePath = Join-Path ([System.IO.Path]::GetTempPath()) $assetName
    $targetBinary = Join-Path $LocalBinDir $binaryFile

    if ($DryRun) {
        Write-Output "[dry-run] Download $releaseUrl"
        Write-Output "[dry-run] Extract $archivePath -> $installRoot"
        Write-Output "[dry-run] Copy $binaryFile -> $targetBinary"
        Add-DependencySummary "${SummaryName}: install preview via GitHub release"
        return $false
    }

    try {
        if (-not (Ensure-Directory -Path $installRoot) -or -not (Ensure-Directory -Path $LocalBinDir)) {
            Add-DependencySummary "${SummaryName}: install attempted"
            return $false
        }

        Invoke-WebRequest -Uri $releaseUrl -OutFile $archivePath
        if ($assetName.EndsWith(".zip")) {
            Expand-Archive -Path $archivePath -DestinationPath $installRoot -Force
        } else {
            tar -xf $archivePath -C $installRoot
        }

        $sourceBinary = Get-ChildItem -Path $installRoot -Recurse -File -Filter $binaryFile | Select-Object -First 1
        if (-not $sourceBinary) {
            Add-DependencySummary "${SummaryName}: install attempted"
            return $false
        }

        Copy-Item -Path $sourceBinary.FullName -Destination $targetBinary -Force
        Update-SessionEnvironment
    } catch {
        Write-Output $_
        Add-Failure "Installing $Description"
    } finally {
        if (Test-Path $archivePath) { Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue }
    }

    if ((Test-AnyCommand -Names $CommandNames) -or (Test-Path $targetBinary)) {
        Add-DependencySummary "${SummaryName}: installed official v$version"
        Add-NewlyAvailableCommand -CommandNames $CommandNames
        return $true
    }

    Add-DependencySummary "${SummaryName}: install attempted"
    return $false
}

function Resolve-PnpmCommand {
    $cmd = Get-Command pnpm -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $pnpmHome = if ($env:PNPM_HOME) { $env:PNPM_HOME } else { Join-Path $HomeDir ".local/share/pnpm" }
    $candidates = @(
        (Join-Path $pnpmHome "pnpm.cmd"),
        (Join-Path $pnpmHome "pnpm.ps1"),
        (Join-Path $pnpmHome "pnpm"),
        (Join-Path $pnpmHome "bin/pnpm.cmd"),
        (Join-Path $pnpmHome "bin/pnpm.ps1"),
        (Join-Path $pnpmHome "bin/pnpm")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    return ""
}

function Install-NodeIfMissing {
    if ((Get-Command node -ErrorAction SilentlyContinue) -and (Get-Command npm -ErrorAction SilentlyContinue)) {
        Add-DependencySummary "node: present"
        return $true
    }

    $nodeVer = (Get-DepInfo "node").ver
    if (-not $nodeVer) { $nodeVer = "24.15.0" }

    if (-not (Confirm-Install "Install Node.js $nodeVer with bundled npm?")) {
        Add-DependencySummary "node: skipped"
        return $false
    }

    $nvmCommand = Get-Command nvm -ErrorAction SilentlyContinue
    if ($nvmCommand) {
        if ($DryRun) {
            Write-Output "[dry-run] nvm install $nodeVer"
            Write-Output "[dry-run] nvm use $nodeVer"
            Add-DependencySummary "node: install preview via nvm"
            return $true
        }

        Invoke-ActionWithSpinner -Description "Installing Node.js $nodeVer via nvm" -Action {
            param($version)
            nvm install $version | Out-Null
            nvm use $version | Out-Null
        } -ArgumentList $nodeVer
        Update-SessionEnvironment
    } elseif ($IsWindows -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        if ($DryRun) {
            Write-Output "[dry-run] winget install --exact --id OpenJS.NodeJS.LTS --version $nodeVer --accept-package-agreements --accept-source-agreements --silent"
            Add-DependencySummary "node: install preview via winget"
            return $true
        }

        Invoke-ActionWithSpinner -Description "Installing Node.js $nodeVer via winget" -Action {
            param($version)
            winget install --exact --id OpenJS.NodeJS.LTS --version $version --accept-package-agreements --accept-source-agreements --silent | Out-Null
        } -ArgumentList $nodeVer
        Update-SessionEnvironment
    } else {
        Add-DependencySummary "node: missing (requires nvm or winget)"
        return $false
    }

    if ((Get-Command node -ErrorAction SilentlyContinue) -and (Get-Command npm -ErrorAction SilentlyContinue)) {
        Add-DependencySummary "node: installed"
        Add-NewlyAvailableCommand -CommandNames @("node", "npm")
        return $true
    }

    Add-DependencySummary "node: install attempted"
    return $false
}

function Ensure-NodeForPnpm {
    if ((Get-Command node -ErrorAction SilentlyContinue) -and (Get-Command npm -ErrorAction SilentlyContinue)) {
        return $true
    }

    $nodeInstalled = Install-NodeIfMissing
    if ($DryRun -and $nodeInstalled) { return $true }
    return ((Get-Command node -ErrorAction SilentlyContinue) -and (Get-Command npm -ErrorAction SilentlyContinue))
}

function Install-PnpmIfMissing {
    if (Resolve-PnpmCommand) {
        Add-DependencySummary "pnpm: present"
        return $true
    }

    if (-not (Confirm-Install "Install pnpm package manager?")) {
        Add-DependencySummary "pnpm: skipped"
        return $false
    }

    if (-not (Ensure-NodeForPnpm)) {
        Add-DependencySummary "pnpm: missing (requires Node.js/npm; try oooconf deps node pnpm)"
        return $false
    }

    $pnpmHome = if ($env:PNPM_HOME) { $env:PNPM_HOME } else { Join-Path $HomeDir ".local/share/pnpm" }
    $env:PNPM_HOME = $pnpmHome

    if (-not (Ensure-Directory -Path $pnpmHome)) {
        Add-DependencySummary "pnpm: install failed"
        return $false
    }

    if (($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ }) -notcontains $pnpmHome) {
        $env:PATH = "$pnpmHome$([IO.Path]::PathSeparator)$env:PATH"
    }

    $pnpmVer = (Get-DepInfo "pnpm").ver
    if (-not $pnpmVer) { $pnpmVer = "10.18.3" }  # fallback only during transition

    if ($DryRun) {
        Write-Output "[dry-run] corepack enable --install-directory $pnpmHome pnpm"
        Write-Output "[dry-run] corepack prepare pnpm@$pnpmVer --activate"
        Add-DependencySummary "pnpm: install preview via corepack"
        return $false
    }

    if (Get-Command corepack -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Output "[dry-run] corepack enable --install-directory $pnpmHome pnpm"
            Write-Output "[dry-run] corepack prepare pnpm@$pnpmVer --activate"
            Add-DependencySummary "pnpm: install preview via corepack"
            return $false
        }

        Invoke-ActionWithSpinner -Description "Installing pnpm@$pnpmVer via corepack" -Action {
            param($homeDir, $version)
            corepack enable --install-directory $homeDir pnpm | Out-Null
            corepack prepare "pnpm@$version" --activate | Out-Null
        } -ArgumentList $pnpmHome, $pnpmVer
    } elseif (Get-Command npm -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Output "[dry-run] npm install --global pnpm@$pnpmVer --prefix $pnpmHome"
            Add-DependencySummary "pnpm: install preview via npm"
            return $false
        }

        Invoke-ActionWithSpinner -Description "Installing pnpm@$pnpmVer via npm" -Action {
            param($homeDir, $version)
            npm install --global "pnpm@$version" --prefix $homeDir | Out-Null
        } -ArgumentList $pnpmHome, $pnpmVer
    } else {
        Add-DependencySummary "pnpm: missing (requires corepack or npm)"
        return $false
    }

    if (Resolve-PnpmCommand) {
        Add-DependencySummary "pnpm: installed"
        Add-NewlyAvailableCommand -CommandNames @("pnpm")
        return $true
    }

    Add-DependencySummary "pnpm: install attempted"
    return $false
}

function Install-PoshGitIfMissing {
    if (Get-Module -ListAvailable -Name posh-git) {
        Add-DependencySummary "posh-git: present"
        return $true
    }

    if (-not (Confirm-Install "Install posh-git from the PowerShell Gallery?")) {
        Add-DependencySummary "posh-git: skipped"
        return $false
    }

    if ($DryRun) {
        Write-Output "[dry-run] Install-Module posh-git -Scope CurrentUser -Force"
        Add-DependencySummary "posh-git: install preview via PowerShell Gallery"
        return $false
    }

    try {
        $nuget = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue
        if (-not $nuget) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
        }

        Invoke-ActionWithSpinner -Description "Installing posh-git via PowerShell Gallery" -Action {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            Install-Module posh-git -Scope CurrentUser -Force -AllowClobber | Out-Null
        }
    } catch {
        Write-Output $_
    }

    if (Get-Module -ListAvailable -Name posh-git) {
        Add-DependencySummary "posh-git: installed via PowerShell Gallery"
        Add-NewlyAvailableCommand -CommandNames @("Add-PoshGitToProfile")
        return $true
    }

    Add-DependencySummary "posh-git: install attempted"
    return $false
}

function Install-PSFzfIfMissing {
    if (Get-Module -ListAvailable -Name PSFzf) {
        Add-DependencySummary "psfzf: present"
        return $true
    }

    if (-not (Confirm-Install "Install PSFzf from the PowerShell Gallery?")) {
        Add-DependencySummary "psfzf: skipped"
        return $false
    }

    if ($DryRun) {
        Write-Output "[dry-run] Install-Module PSFzf -Scope CurrentUser -Force"
        Add-DependencySummary "psfzf: install preview via PowerShell Gallery"
        return $false
    }

    try {
        $nuget = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue
        if (-not $nuget) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
        }

        Invoke-ActionWithSpinner -Description "Installing PSFzf via PowerShell Gallery" -Action {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            Install-Module PSFzf -Scope CurrentUser -Force -AllowClobber | Out-Null
        }
    } catch {
        Write-Output $_
    }

    if (Get-Module -ListAvailable -Name PSFzf) {
        Add-DependencySummary "psfzf: installed via PowerShell Gallery"
        Add-NewlyAvailableCommand -CommandNames @("Invoke-FuzzyHistory")
        return $true
    }

    Add-DependencySummary "psfzf: install attempted"
    return $false
}

function Install-RtkIfMissing {
    if (Test-DependencyStatus -CommandName "rtk" -SummaryName "rtk") { return $true }

    if (-not (Confirm-Install "Install rtk token-optimized AI CLI proxy from the official native executable archive?")) {
        Add-DependencySummary "rtk: skipped"
        return $false
    }

    $rtkInfo = Get-DepInfo "rtk"
    $rtkVer = if ($rtkInfo.ver) { $rtkInfo.ver } else { "0.37.2" }
    $installRoot = Join-Path $ShareHome "tools/rtk/v$rtkVer"
    $archivePath = Join-Path ([System.IO.Path]::GetTempPath()) "rtk-windows-$rtkVer.zip"
    $releaseUrl = "https://github.com/rtk-ai/rtk/releases/download/v$rtkVer/rtk-x86_64-pc-windows-msvc.zip"
    $sourceBinary = Join-Path $installRoot "rtk.exe"
    $targetBinary = Join-Path $LocalBinDir "rtk.exe"

    if ($DryRun) {
        Write-Output "[dry-run] Download $releaseUrl"
        Write-Output "[dry-run] Expand-Archive $archivePath -> $installRoot"
        Write-Output "[dry-run] Copy $sourceBinary -> $targetBinary"
        Add-DependencySummary "rtk: install preview via official archive"
        return $false
    }

    try {
        if (-not (Ensure-Directory -Path $installRoot)) {
            Add-DependencySummary "rtk: install attempted"
            return $false
        }

        if (-not (Test-Path $sourceBinary)) {
            Invoke-WebRequest -Uri $releaseUrl -OutFile $archivePath
            Expand-Archive -Path $archivePath -DestinationPath $installRoot -Force
        }

        Copy-Item -Path $sourceBinary -Destination $targetBinary -Force
    } catch {
        Write-Output $_
        # Fallback to cargo if zip download/extract failed
        $cargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
        if ($cargoCommand) {
            Invoke-ActionWithSpinner -Description "Installing rtk via cargo (fallback)" -Action {
                param($cmd)
                & $cmd install --git https://github.com/rtk-ai/rtk | Out-Null
            } -ArgumentList $cargoCommand
            if (Get-Command rtk -ErrorAction SilentlyContinue) {
                Add-DependencySummary "rtk: installed (via cargo fallback)"
                Add-NewlyAvailableCommand -CommandNames @("rtk")
                return $true
            }
        }
        Add-DependencySummary "rtk: install attempted"
        return $false
    } finally {
        if (Test-Path $archivePath) { Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue }
    }

    if (Get-Command rtk -ErrorAction SilentlyContinue -CommandType Application) {
        Add-DependencySummary "rtk: installed official v$rtkVer"
        Add-NewlyAvailableCommand -CommandNames @("rtk")
        return $true
    }

    if (Test-Path $targetBinary) {
        Add-DependencySummary "rtk: installed official v$rtkVer"
        Add-NewlyAvailableCommand -CommandNames @("rtk")
        return $true
    }

    Add-DependencySummary "rtk: install attempted"
    return $false
}

function Install-NeovimIfMissing {
    if (Test-DependencyStatus -CommandName "nvim" -SummaryName "nvim") { return $true }

    if (-not (Confirm-Install "Install Neovim from the official GitHub release archive?")) {
        Add-DependencySummary "nvim: skipped"
        return $false
    }

    $nvimInfo = Get-DepInfo "nvim"
    $nvimVer = if ($nvimInfo.ver) { $nvimInfo.ver } else { "0.12.1" }
    $arch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq [System.Runtime.InteropServices.Architecture]::Arm64) { "arm64" } else { "x64" }
    $assetName = if ($arch -eq "arm64") { "nvim-win-arm64.zip" } else { "nvim-win64.zip" }
    $extractedDir = if ($arch -eq "arm64") { "nvim-win-arm64" } else { "nvim-win64" }
    $installRoot = Join-Path $ShareHome "tools/neovim/v$nvimVer"
    $archivePath = Join-Path ([System.IO.Path]::GetTempPath()) $assetName
    $releaseUrl = "https://github.com/neovim/neovim/releases/download/v$nvimVer/$assetName"
    $sourceBinary = Join-Path $installRoot "$extractedDir/bin/nvim.exe"
    $targetBinary = Join-Path $LocalBinDir "nvim.exe"

    if ($DryRun) {
        Write-Output "[dry-run] Download $releaseUrl"
        Write-Output "[dry-run] Expand-Archive $archivePath -> $installRoot"
        Write-Output "[dry-run] Copy $sourceBinary -> $targetBinary"
        Add-DependencySummary "nvim: install preview via official GitHub release"
        return $false
    }

    try {
        if (-not (Ensure-Directory -Path $installRoot) -or -not (Ensure-Directory -Path $LocalBinDir)) {
            Add-DependencySummary "nvim: install attempted"
            return $false
        }

        if (-not (Test-Path $sourceBinary)) {
            Invoke-WebRequest -Uri $releaseUrl -OutFile $archivePath
            Expand-Archive -Path $archivePath -DestinationPath $installRoot -Force
        }

        Copy-Item -Path $sourceBinary -Destination $targetBinary -Force
    } catch {
        Write-Output $_
        Add-Failure "Installing Neovim"
    }

    if ((Get-Command nvim -ErrorAction SilentlyContinue -CommandType Application) -or (Test-Path $targetBinary)) {
        Add-DependencySummary "nvim: installed official v$nvimVer"
        Add-NewlyAvailableCommand -CommandNames @("nvim")
        return $true
    }

    Add-DependencySummary "nvim: install attempted"
    if (Test-Path $archivePath) { Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue }
    return $false
}

function Install-TectonicIfMissing {
    if (Test-DependencyStatus -CommandName "tectonic" -SummaryName "tectonic") { return $true }

    if (-not (Confirm-Install "Install Tectonic (modern LaTeX engine) from the official GitHub releases?")) {
        Add-DependencySummary "tectonic: skipped"
        return $false
    }

    $repo = "tectonic-typesetting/tectonic"
    $latest = $null
    try {
        if ($null -ne (Get-Command gh -ErrorAction SilentlyContinue)) {
             $latestJson = gh api repos/$repo/releases/latest | ConvertFrom-Json
             $latest = [pscustomobject]@{ tag_name = $latestJson.tag_name; assets = $latestJson.assets }
        } else {
             $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
        }
    } catch {
        Write-Warning "Failed to fetch latest Tectonic release info from GitHub API: $($_.Exception.Message)"
    }

    if (-not $latest) {
        # Fallback to hardcoded version if API fails
        $version = "0.16.9"
        $tag = "tectonic@0.16.9"
    } else {
        $tag = $latest.tag_name
        $version = $tag -replace '^tectonic@', ''
    }

    $asset = $null
    if ($latest) {
        $asset = $latest.assets | Where-Object { $_.name -match "x86_64-pc-windows-msvc\.zip$" } | Select-Object -First 1
    }

    $downloadUrl = if ($asset) { $asset.browser_download_url } else {
        $encodedTag = [uri]::EscapeDataString($tag)
        "https://github.com/$repo/releases/download/$encodedTag/tectonic-$version-x86_64-pc-windows-msvc.zip"
    }

    $installRoot = Join-Path $ShareHome "tools/tectonic/v$version"
    $archivePath = Join-Path ([System.IO.Path]::GetTempPath()) "tectonic-windows-$version.zip"
    $sourceBinary = Join-Path $installRoot "tectonic.exe"
    $targetBinary = Join-Path $LocalBinDir "tectonic.exe"

    if ($DryRun) {
        Write-Output "[dry-run] Download $downloadUrl"
        Write-Output "[dry-run] Expand-Archive $archivePath -> $installRoot"
        Write-Output "[dry-run] Copy $sourceBinary -> $targetBinary"
        Add-DependencySummary "tectonic: install preview via official GitHub release"
        return $false
    }

    $downloadSuccess = Invoke-ActionWithSpinner -Description "Installing Tectonic v$version via GitHub releases" -Action {
        param($url, $zip, $root, $src, $dst)
        if (-not (Ensure-Directory -Path $root)) { throw "Failed to create directory $root" }
        if (-not (Test-Path $src)) {
            Invoke-WebRequest -Uri $url -OutFile $zip
            Expand-Archive -Path $zip -DestinationPath $root -Force
        }
        Copy-Item -Path $src -Destination $dst -Force
        Update-SessionEnvironment
    } -ArgumentList $downloadUrl, $archivePath, $installRoot, $sourceBinary, $targetBinary

    if ($downloadSuccess -and (Test-AnyCommand -Names @("tectonic"))) {
        Add-DependencySummary "tectonic: installed official v$version"
        Add-NewlyAvailableCommand -CommandNames @("tectonic")
        if (Test-Path $archivePath) { Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue }
        return $true
    }

    # Fallback to cargo if download failed
    $cargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
    if ($cargoCommand) {
        if (Invoke-ActionWithSpinner -Description "Installing tectonic via cargo (fallback)" -Action {
            param($cmd)
            & $cmd install tectonic | Out-Null
        } -ArgumentList $cargoCommand) {
            if (Get-Command tectonic -ErrorAction SilentlyContinue) {
                Add-DependencySummary "tectonic: installed (via cargo fallback)"
                Add-NewlyAvailableCommand -CommandNames @("tectonic")
                if (Test-Path $archivePath) { Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue }
                return $true
            }
        }
    }

    Add-DependencySummary "tectonic: install attempted"
    if (Test-Path $archivePath) { Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue }
    return $false
}

function Install-BitwardenCliIfMissing {
    if (Test-DependencyStatus -CommandName "bw" -SummaryName "bw") { return $true }

    if (-not (Confirm-Install "Install Bitwarden CLI from the official native executable archive?")) {
        Add-DependencySummary "bw: skipped"
        return $false
    }

    $bwInfo = Get-DepInfo "bw"
    $bwVer = if ($bwInfo.ver) { $bwInfo.ver } else { "1.22.1" }
    $installRoot = Join-Path $ShareHome "tools/bitwarden-cli/v$bwVer"
    $archivePath = Join-Path ([System.IO.Path]::GetTempPath()) "bw-windows-$bwVer.zip"
    $releaseUrl = "https://github.com/bitwarden/cli/releases/download/v$bwVer/bw-windows-$bwVer.zip"
    $sourceBinary = Join-Path $installRoot "bw.exe"
    $targetBinary = Join-Path $LocalBinDir "bw.exe"

    if ($DryRun) {
        Write-Output "[dry-run] Download $releaseUrl"
        Write-Output "[dry-run] Expand-Archive $archivePath -> $installRoot"
        Write-Output "[dry-run] Copy $sourceBinary -> $targetBinary"
        Add-DependencySummary "bw: install preview via official archive"
        return $false
    }

    try {
        if (-not (Ensure-Directory -Path $installRoot)) {
            Add-DependencySummary "bw: install attempted"
            return $false
        }

        if (-not (Test-Path $sourceBinary)) {
            Invoke-WebRequest -Uri $releaseUrl -OutFile $archivePath
            Expand-Archive -Path $archivePath -DestinationPath $installRoot -Force
        }

        Copy-Item -Path $sourceBinary -Destination $targetBinary -Force
    } catch {
        Write-Output $_
        Add-Failure "Installing Bitwarden CLI"
    }

    if (Get-Command bw -ErrorAction SilentlyContinue -CommandType Application) {
        Add-DependencySummary "bw: installed official v$bwVer"
        Add-NewlyAvailableCommand -CommandNames @("bw")
        return $true
    }

    if (Test-Path $targetBinary) {
        Add-DependencySummary "bw: installed official v$bwVer"
        Add-NewlyAvailableCommand -CommandNames @("bw")
        return $true
    }

    Add-DependencySummary "bw: install attempted"
    return $false
}

function Install-CargoIfMissing {
    if (Test-DependencyStatus -CommandName "cargo" -SummaryName "cargo") { return $true }

    if (-not (Confirm-Install "Install Rust and cargo via rustup?")) {
        Add-DependencySummary "cargo: skipped"
        return $false
    }

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Output "[dry-run] winget install Rustlang.Rustup"
            Add-DependencySummary "cargo: install preview via winget"
            return $false
        }

        try {
            winget install Rustlang.Rustup --accept-package-agreements --accept-source-agreements
        } catch {
            Write-Output $_
        }

        if (Get-Command cargo -ErrorAction SilentlyContinue) {
            Add-DependencySummary "cargo: installed via winget"
            Add-NewlyAvailableCommand -CommandNames @("cargo", "rustc")
            return $true
        }

        Add-DependencySummary "cargo: install attempted via winget"
        return $false
    }

    Add-DependencySummary "cargo: missing (requires winget)"
    return $false
}

function Install-DuaIfMissing {
    $duaRepoUrl = "https://github.com/byron/dua-cli.git"
    $cargoBinDir = Join-Path $HomeDir ".cargo/bin"
    $cargoExe = Join-Path $cargoBinDir "cargo.exe"
    $duaExe = Join-Path $cargoBinDir "dua.exe"

    if ((Get-Command dua -ErrorAction SilentlyContinue) -or (Test-Path $duaExe)) {
        Add-DependencySummary "dua: present"
        return $true
    }

    if (-not (Confirm-Install "Install dua-cli for disk usage analysis from byron/dua-cli via cargo?")) {
        Add-DependencySummary "dua: skipped"
        return $false
    }

    if (-not (Install-CargoIfMissing)) {
        Add-DependencySummary "dua: missing (cargo unavailable)"
        return $false
    }

    if (($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ }) -notcontains $cargoBinDir) {
        $env:PATH = "$cargoBinDir$([IO.Path]::PathSeparator)$env:PATH"
    }

    $cargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
    if (-not $cargoCommand -and (Test-Path $cargoExe)) {
        $cargoCommand = $cargoExe
    }

    if (-not $cargoCommand) {
        Add-DependencySummary "dua: missing (cargo unavailable)"
        return $false
    }

    if ($DryRun) {
        Write-Output "[dry-run] cargo install --locked --git $duaRepoUrl dua-cli"
        Add-DependencySummary "dua: install preview via cargo"
        return $false
    }

    try {
        & $cargoCommand install --locked --git $duaRepoUrl dua-cli
    } catch {
        Write-Output $_
    }

    if ((Get-Command dua -ErrorAction SilentlyContinue) -or (Test-Path $duaExe)) {
        Add-DependencySummary "dua: installed"
        Add-NewlyAvailableCommand -CommandNames @("dua")
        return $true
    }

    Add-DependencySummary "dua: install attempted"
    return $false
}

function Install-OptionalDependencies {
    if ($SkipDeps) {
        if (Test-VerboseMode) {
            Write-Output "Skipping optional dependency installation (--skip-deps)"
        }
        return
    }
    if (Test-VerboseMode) {
        Write-Output "Dependency check:"
    }
    $specs = @(Get-OptionalDependencySpecs)
    $selectedSpecs = @($specs | Where-Object { Test-OptionalDependencySelected -Key $_.Key })

    $needsChocolatey = $false
    foreach ($spec in $selectedSpecs) {
        if ($spec.Key -eq "choco") {
            $needsChocolatey = $true
            break
        }
        $platformConfig = Get-OptionalDependencyPlatformConfig -Spec $spec
        if ($platformConfig -and $platformConfig.manager -eq "choco") {
            $needsChocolatey = $true
            break
        }
    }
    if ($needsChocolatey) {
        $null = Install-Chocolatey
    }

    foreach ($spec in $specs) {
        $null = Install-OptionalDependencyFromSpec -Spec $spec
    }
}

function Generate-AutogenCompletions {
    $targetDir = Join-Path $RepoRoot "home/.config/ooodnakov/zsh/completions/autogen"
    if ($DryRun) {
        Write-Output "[dry-run] Generating autogen completions in $targetDir"
        return
    }

    Ensure-Directory -Path $targetDir | Out-Null

    if (-not (Test-Path $AutogenCompletionsManifest)) {
        Add-ToolSummary "autogen completions: manifest missing ($AutogenCompletionsManifest)"
        return
    }

    $completionSpecs = Get-Content -Path $AutogenCompletionsManifest -ErrorAction SilentlyContinue
    foreach ($line in $completionSpecs) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.Trim().StartsWith("#")) {
            continue
        }

        $parts = $line -split "\|", 4
        if ($parts.Count -lt 4) {
            continue
        }
        $commandName = $parts[0].Trim()
        $description = $parts[1].Trim()
        $outputFile = Join-Path $targetDir ($parts[2].Trim())
        $commandLine = $parts[3].Trim()

        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            continue
        }

        Invoke-ActionWithSpinner -Description $description -Action {
            param($lineToRun, $targetFile, $workingDirectory)
            Push-Location $workingDirectory
            try {
                $content = @(Invoke-Expression $lineToRun)
                $normalized = [string]::Join("`n", $content) + "`n"
                [System.IO.File]::WriteAllText($targetFile, $normalized, (New-Object System.Text.UTF8Encoding $false))
            } finally {
                Pop-Location
            }
        } -ArgumentList $commandLine, $outputFile, $RepoRoot
    }
}

function Generate-OooconfCompletions {
    if ($DryRun) {
        Write-Output "[dry-run] Generating oooconf command completions"
        return
    }

    if (-not (Test-Path $OooconfCompletionsGenerator)) {
        Add-ToolSummary "oooconf completions: generator missing ($OooconfCompletionsGenerator)"
        return
    }

    Invoke-ActionWithSpinner -Description "Generating oooconf command completions" -Action {
        param($scriptPath)
        $null = Run-Python -ScriptPath $scriptPath -ScriptArgs @()
    } -ArgumentList $OooconfCompletionsGenerator
}

function Add-NewlyAvailableCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CommandNames
    )
    foreach ($cmd in $CommandNames) {
        if ($null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            if ($script:NewlyAvailableCommands -notcontains $cmd) {
                $script:NewlyAvailableCommands.Add($cmd)
            }
            return
        }
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

function Test-DoctorLink {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    if (Test-LinkMatches -Source $Source -Target $Target) {
        Write-UiLine -Role ok -Message "$Target -> $Source"
        return
    }

    Write-UiLine -Role missing -Message "$Target (expected symlink to $Source)"
    $script:Failures.Add("doctor link $Target") | Out-Null
}

function Test-DoctorCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (Test-AnyCommand -Names @($Name)) {
        Write-UiLine -Role ok -Message "command: $Name"
        return
    }

    Write-UiLine -Role missing -Message "command: $Name"
    $script:Failures.Add("doctor command $Name") | Out-Null
}

function Get-MinimalDependencyKeys {
    if ($script:MinimalDependencyKeysCache) {
        return $script:MinimalDependencyKeysCache
    }

    $keys = @()
    try {
        $raw = Run-Python (Join-Path $RepoRoot "scripts/cli/read_optional_deps.py") @("minimal") 2>$null
        if ($raw) {
            $keys = @($raw -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    } catch {
    }

    if ($keys.Count -eq 0) {
        $keys = @((Get-OptionalDepsTomlFallbackData).MinimalKeys)
    }

    $script:MinimalDependencyKeysCache = @($keys | Select-Object -Unique)
    return $script:MinimalDependencyKeysCache
}

function Test-DoctorDependency {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Spec,
        [switch]$Required
    )

    if (-not $Spec -or [string]::IsNullOrWhiteSpace($Spec.Key)) {
        return
    }

    if (Test-OptionalDependencyPresent -Key $Spec.Key) {
        Write-UiLine -Role ok -Message "dependency: $($Spec.Key)"
        return
    }

    if ($Required) {
        Write-UiLine -Role missing -Message "dependency: $($Spec.Key)"
        $script:Failures.Add("doctor dependency $($Spec.Key)") | Out-Null
        return
    }

    Write-UiLine -Role hint -Message "dependency: $($Spec.Key) not installed"
}

function Test-DoctorOptionalCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (Test-AnyCommand -Names @($Name)) {
        Write-UiLine -Role ok -Message "optional command: $Name"
        return
    }

    Write-UiLine -Role hint -Message "command: $Name not installed"
}

function Test-Doctor {
    Write-UiLine -Role info -Message "Running doctor checks..."

    # Read links from manifest via link_manager.py for doctor checks
    $linkOutput = python3 "$RepoRoot/scripts/link_manager.py" --repo-root "$RepoRoot" --format text 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($linkOutput)) {
        $linkOutput -split "`n" | ForEach-Object {
            if ([string]::IsNullOrWhiteSpace($_)) { return }
            $parts = $_ -split '\|'
            if ($parts.Count -lt 3) { return }
            $key = $parts[0]
            $source = $parts[1]
            $target = $parts[2]
            Test-DoctorLink -Source $source -Target $target
        }
    } else {
        # Fallback to hardcoded links for older versions
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/wezterm") -Target (Join-Path $ConfigHome "wezterm")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/yazi") -Target (Join-Path $ConfigHome "yazi")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/lazygit") -Target (Join-Path $ConfigHome "lazygit")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/noctalia") -Target (Join-Path $ConfigHome "noctalia")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/nvim") -Target (Join-Path $ConfigHome "nvim")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov") -Target (Join-Path $ConfigHome "ooodnakov")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ohmyposh/ooodnakov.omp.json") -Target (Join-Path $OhMyPoshDir "ooodnakov.omp.json")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target $PowerShellProfileTarget
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target $ActivePowerShellProfile
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/oooconf.ps1") -Target (Join-Path $LocalBinDir "oooconf.ps1")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/oooconf.cmd") -Target (Join-Path $LocalBinDir "oooconf.cmd")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/o.ps1") -Target (Join-Path $LocalBinDir "o.ps1")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/o.cmd") -Target (Join-Path $LocalBinDir "o.cmd")

        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/komorebi/komorebi.json") -Target (Join-Path $HomeDir "komorebi.json")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/komorebi/komorebi.bar.json") -Target (Join-Path $HomeDir "komorebi.bar.json")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/komorebi/applications.json") -Target (Join-Path $HomeDir "applications.json")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/komorebi/whkdrc") -Target (Join-Path $ConfigHome "whkdrc")

        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.glzr/glazewm") -Target (Join-Path $HomeDir ".glzr/glazewm")
        Test-DoctorLink -Source (Join-Path $RepoRoot "home/.glzr/zebar") -Target (Join-Path $HomeDir ".glzr/zebar")
    }

    Test-DoctorCommand -Name "oooconf"
    Test-DoctorCommand -Name "o"

    $requiredDependencyKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in (Get-MinimalDependencyKeys)) {
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $null = $requiredDependencyKeys.Add($key)
        }
    }
    foreach ($key in @("wezterm", "yazi", "nvim")) {
        $null = $requiredDependencyKeys.Add($key)
    }

    foreach ($spec in @(Get-OptionalDependencySpecs | Sort-Object Key)) {
        Test-DoctorDependency -Spec $spec -Required:$requiredDependencyKeys.Contains($spec.Key)
    }

    foreach ($commandName in @("komorebic", "whkd")) {
        Test-DoctorOptionalCommand -Name $commandName
    }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $userPathParts = @($userPath -split [IO.Path]::PathSeparator | Where-Object { $_ })
    if ($userPathParts -contains $LocalBinDir) {
        Write-UiLine -Role ok -Message "user PATH contains $LocalBinDir"
    } else {
        Write-UiLine -Role missing -Message "user PATH entry: $LocalBinDir"
        $script:Failures.Add("doctor user PATH") | Out-Null
    }

    if ($script:Failures.Count -gt 0) {
        Write-UiSpacer
        Write-UiLine -Role fail -Message "Doctor found $($script:Failures.Count) issue(s). Run 'oooconf install' to try fixing them."
        return
    }

    Write-UiLine -Role ok -Message "Doctor checks passed."
}

function Invoke-Install {
    param(
        [switch]$ContinueProgress
    )

    if (-not $ContinueProgress) {
        Start-StepProgress -Total 6 -Activity "oooconf $Command"
    }
    Step-Progress -Status "Preparing directories"
    foreach ($dir in @($ConfigHome, $DataHome, $CacheHome, $StateHome, $ShareHome, (Join-Path $ShareHome "bin"), $LocalBinDir, $OhMyPoshDir, $PowerShellConfigDir)) {
        if (Ensure-Directory -Path $dir) {
            Add-ToolSummary "ensured directory: $dir"
        }
    }

    Step-Progress -Status "Checking/installing optional dependencies"
    Install-OptionalDependencies

    Step-Progress -Status "Linking managed configuration"
    $linkOutput = python3 "$RepoRoot/scripts/link_manager.py" --repo-root "$RepoRoot" --format text 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($linkOutput)) {
        Write-Output "[warn] link_manager.py failed or returned no output; falling back to hardcoded links"
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/wezterm") -Target (Join-Path $ConfigHome "wezterm")) {
            Add-ToolSummary "wezterm: linked"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/yazi") -Target (Join-Path $ConfigHome "yazi")) {
            Add-ToolSummary "yazi: linked"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/lazygit") -Target (Join-Path $ConfigHome "lazygit")) {
            Add-ToolSummary "lazygit: linked"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/noctalia") -Target (Join-Path $ConfigHome "noctalia")) {
            Add-ToolSummary "noctalia: linked"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/nvim") -Target (Join-Path $ConfigHome "nvim")) {
            Add-ToolSummary "nvim: linked"

            # Sync LazyVim plugins non-interactively
            if (Get-Command nvim -ErrorAction SilentlyContinue) {
                $syncExitCode = Invoke-WithProgress -Description "Syncing LazyVim plugins" -Action {
                    param($stdoutLog, $stderrLog)
                    Start-Process -FilePath "nvim" `
                        -ArgumentList @("--headless", "+Lazy! sync", "+qa") `
                        -NoNewWindow `
                        -RedirectStandardOutput $stdoutLog `
                        -RedirectStandardError $stderrLog `
                        -PassThru
                }

                if ($syncExitCode -eq 0) {
                    Add-ToolSummary "nvim: plugins synced"
                } else {
                    Write-Warning "LazyVim plugin sync exited with code $syncExitCode"
                }
            }
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/ooodnakov") -Target (Join-Path $ConfigHome "ooodnakov")) {
            Add-ToolSummary "ooodnakov config: linked"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/ohmyposh/ooodnakov.omp.json") -Target (Join-Path $OhMyPoshDir "ooodnakov.omp.json")) {
            Add-ToolSummary "oh-my-posh config: linked"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target $PowerShellProfileTarget) {
            Add-ToolSummary "PowerShell XDG profile: linked"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target $ActivePowerShellProfile) {
            Add-ToolSummary "PowerShell active profile: linked"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/oooconf.ps1") -Target (Join-Path $LocalBinDir "oooconf.ps1")) {
            Add-ToolSummary "oooconf.ps1: linked into $LocalBinDir"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/oooconf.cmd") -Target (Join-Path $LocalBinDir "oooconf.cmd")) {
            Add-ToolSummary "oooconf.cmd: linked into $LocalBinDir"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/o.ps1") -Target (Join-Path $LocalBinDir "o.ps1")) {
            Add-ToolSummary "o.ps1: linked into $LocalBinDir"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/o.cmd") -Target (Join-Path $LocalBinDir "o.cmd")) {
            Add-ToolSummary "o.cmd: linked into $LocalBinDir"
        }

        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/komorebi/komorebi.json") -Target (Join-Path $HomeDir "komorebi.json")) {
            Add-ToolSummary "komorebi: linked config"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/komorebi/komorebi.bar.json") -Target (Join-Path $HomeDir "komorebi.bar.json")) {
            Add-ToolSummary "komorebi-bar: linked config"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/komorebi/applications.json") -Target (Join-Path $HomeDir "applications.json")) {
            Add-ToolSummary "komorebi-applications: linked config"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/komorebi/whkdrc") -Target (Join-Path $ConfigHome "whkdrc")) {
            Add-ToolSummary "whkd: linked config"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.glzr/glazewm") -Target (Join-Path $HomeDir ".glzr/glazewm")) {
            Add-ToolSummary "glazewm: linked config directory"
        }
        if (New-Symlink -Source (Join-Path $RepoRoot "home/.glzr/zebar") -Target (Join-Path $HomeDir ".glzr/zebar")) {
            Add-ToolSummary "zebar: linked config directory"
        }
    } else {
        $linkOutput -split "`n" | ForEach-Object {
            if ([string]::IsNullOrWhiteSpace($_)) { return }
            $parts = $_ -split '\|'
            if ($parts.Count -lt 3) { return }
            $key = $parts[0]
            $source = $parts[1]
            $target = $parts[2]
            if (New-Symlink -Source $source -Target $target) {
                Add-ToolSummary "linked: $key"
            }
        }

        # Sync LazyVim plugins non-interactively (nvim post-link hook)
        if (Get-Command nvim -ErrorAction SilentlyContinue) {
            $syncExitCode = Invoke-WithProgress -Description "Syncing LazyVim plugins" -Action {
                param($stdoutLog, $stderrLog)
                Start-Process -FilePath "nvim" `
                    -ArgumentList @("--headless", "+Lazy! sync", "+qa") `
                    -NoNewWindow `
                    -RedirectStandardOutput $stdoutLog `
                    -RedirectStandardError $stderrLog `
                    -PassThru
            }

            if ($syncExitCode -eq 0) {
                Add-ToolSummary "nvim: plugins synced"
            } else {
                Write-Warning "LazyVim plugin sync exited with code $syncExitCode"
            }
        }
    }

    if (Ensure-UserPathContains -PathEntry $LocalBinDir) {
        Add-ToolSummary "user PATH: ensured $LocalBinDir"
    }
    if (Add-SshInclude) {
        Add-ToolSummary "ssh include: ensured"
    }

    Step-Progress -Status "Generating completions and platform integrations"
    Generate-AutogenCompletions
    Generate-OooconfCompletions

    Step-Progress -Status "Writing setup summary"
    Write-Summary
    Write-Output ""
    Write-Output "Bootstrap complete."
    Write-Output "If needed, create local overrides in $ConfigHome/ooodnakov/local."
    Step-Progress -Status "Done"
}

Start-SetupLogging
try {
    $allPresent = $false
    $requestedDependencyKeys = @($DependencyKeys | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    # Handle --minimal flag
    if ($requestedDependencyKeys -contains "--minimal") {
        $minimalKeys = Run-Python (Join-Path $RepoRoot "scripts/cli/read_optional_deps.py") @("minimal")
        $requestedDependencyKeys = @($minimalKeys -split ' ' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        Write-Information "Installing minimal setup: $($requestedDependencyKeys -join ', ')" -InformationAction Continue
    } elseif ($Command -eq "deps" -and $requestedDependencyKeys -contains "--all") {
        $allKeys = @((Get-AllOptionalDependencySpecs).Key | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $requestedDependencyKeys = @($allKeys)
        Write-Information "Installing all optional dependencies: $($requestedDependencyKeys -join ', ')" -InformationAction Continue
    }

    if ($requestedDependencyKeys.Count -gt 0) {
        # Validate against ALL specs (including platform-inapplicable ones)
        $allKeys = @((Get-AllOptionalDependencySpecs).Key | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        foreach ($key in $requestedDependencyKeys) {
            if ($allKeys -notcontains $key) {
                $suggestion = Get-ClosestSuggestion -InputText $key -Candidates $allKeys
                if ($suggestion) {
                    throw "Unknown dependency key: $key`nDid you mean: $suggestion"
                }
                throw "Unknown dependency key: $key"
            }
            # Warn if the dep is not applicable to the current platform
            $spec = Get-AllOptionalDependencySpecs | Where-Object { $_.Key -eq $key }
            if (-not (Test-OptionalDependencyApplicable -Spec $spec)) {
                $platform = Detect-Platform
                Write-Information "Note: $key is not applicable on $platform; skipping." -InformationAction Continue
            }
        }
        $script:SelectedOptionalKeys = @($requestedDependencyKeys)
        $InstallOptionalMode = "always"
    } elseif ($Command -eq "deps") {
        if (-not (Test-Interactive)) {
            throw "oooconf deps needs explicit dependency keys in non-interactive mode."
        }

        $selected = @(Select-OptionalDependenciesWithGum)
        # $null means gum not available, fall back to text prompt
        if ($selected.Count -eq 1 -and $selected[0] -eq $null) {
            $selected = @(Select-OptionalDependenciesWithoutGum)
        }
        if ($selected.Count -eq 1 -and $selected[0] -eq "__all_present__") {
            $allPresent = $true
        }
        # User cancelled (Esc in gum picker, or empty input in text prompt) — exit cleanly
        if (-not $allPresent -and $selected.Count -eq 0) {
            Write-Output "No optional dependencies selected."
            return
        }
        if (-not $allPresent) {
            $script:SelectedOptionalKeys = $selected
            $InstallOptionalMode = "always"
        }
    }

    switch ($Command) {
        "install" {
            Invoke-Install
        }
        "update" {
            Start-StepProgress -Total 7 -Activity "oooconf update"
            Step-Progress -Status "Pulling latest repository changes"
            if ($DryRun) {
                Write-Output "[dry-run] git -C $RepoRoot pull --ff-only"
            } else {
                Invoke-ActionWithSpinner -Description "Pulling repository" -Action {
                    git -C $RepoRoot pull --ff-only
                }
            }
            Invoke-Install -ContinueProgress
        }
        "doctor" {
            if ($DryRun) {
                Write-Output "[dry-run] would run doctor checks"
                return
            }
            Test-Doctor
        }
        "deps" {
            if ($allPresent) {
                Write-Output "Optional dependency install complete."
                break
            }

            Start-StepProgress -Total 4 -Activity "oooconf deps"
            Step-Progress -Status "Preparing dependency install paths"
            foreach ($dir in @($DataHome, $StateHome, $ShareHome, (Join-Path $ShareHome "bin"), $LocalBinDir)) {
                if ($DryRun) {
                    Write-Output "[dry-run] ensure directory $dir"
                } else {
                    Ensure-Directory -Path $dir | Out-Null
                }
            }

            Step-Progress -Status "Installing selected optional dependencies"
            if ($DryRun) {
                Write-Output "[dry-run] install optional dependencies: $($script:SelectedOptionalKeys -join ', ')"
            } else {
                Install-OptionalDependencies
            }
            Step-Progress -Status "Writing dependency summary"
            Write-Summary
            Write-Output ""
            Write-Output "Optional dependency install complete."
            Step-Progress -Status "Done"
        }
        "completions" {
            Start-StepProgress -Total 4 -Activity "oooconf completions"
            Step-Progress -Status "Preparing completion output path"
            $completionsDir = Join-Path $RepoRoot "home/.config/ooodnakov/zsh/completions/autogen"
            if ($DryRun) {
                Write-Output "[dry-run] ensure directory $completionsDir"
            } else {
                Ensure-Directory -Path $completionsDir | Out-Null
            }
            Step-Progress -Status "Generating tracked autogen completions"
            if (-not $DryRun) {
                Generate-AutogenCompletions
            }
            Step-Progress -Status "Generating oooconf command completions"
            if (-not $DryRun) {
                Generate-OooconfCompletions
            }
            Write-Output ""
            Write-Output "Completion generation complete."
            Step-Progress -Status "Done"
        }
        "minimal" {
            if ($DryRun) {
                Write-Output "[dry-run] would run minimal-setup.sh"
                return
            }
            & (Join-Path $RepoRoot "scripts/setup/minimal-setup.ps1")
        }
        "link" {
            if ($DryRun) {
                Write-Output "[dry-run] would link:"
                python3 "$RepoRoot/scripts/link_manager.py" --repo-root "$RepoRoot" --format text 2>$null | ForEach-Object {
                    $parts = $_ -split '\|'
                    if ($parts.Count -ge 3) {
                        Write-Output "[dry-run]   $($parts[2]) -> $($parts[1])"
                    }
                }
                return
            }
            python3 "$RepoRoot/scripts/link_manager.py" --repo-root "$RepoRoot" --format text 2>$null | ForEach-Object {
                $parts = $_ -split '\|'
                if ($parts.Count -ge 3) {
                    $source = $parts[1]
                    $target = $parts[2]
                    New-Symlink -Source $source -Target $target | Out-Null
                }
            }
        }
    }
} finally {
    if ($script:LogFile) {
        Write-Output "Log file: $script:LogFile"
    }
    Stop-SetupLogging
}

if ($script:Failures.Count -gt 0) {
    exit 1
}
