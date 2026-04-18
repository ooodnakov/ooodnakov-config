param(
    [string]$Command = "",
    [switch]$DryRun,
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$DependencyKeys = @()
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
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
$PnpmVersion = "10.18.3"
$BwVersion = "1.22.1"

$script:DependencySummary = [System.Collections.Generic.List[string]]::new()
$script:ToolSummary = [System.Collections.Generic.List[string]]::new()
$script:Failures = [System.Collections.Generic.List[string]]::new()
$script:LogFile = $null
$script:LatestLogFile = $null
$script:TranscriptStarted = $false
$script:StepTotal = 0
$script:StepCurrent = 0
$script:StepActivity = ""
$ValidSetupCommands = @("install", "update", "doctor", "deps")

# Run a Python script, preferring `uv run` when available.
function Run-Python {
    param([string]$ScriptPath, [string[]]$ScriptArgs)
    $pyprojectPath = Join-Path $RepoRoot "pyproject.toml"
    if ((Get-Command uv -ErrorAction SilentlyContinue) -and (Test-Path $pyprojectPath)) {
        & uv run $ScriptPath @ScriptArgs
    } else {
        & python3 $ScriptPath @ScriptArgs
    }
}

function Get-EditDistance {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Left,
        [Parameter(Mandatory = $true)]
        [string]$Right
    )

    $rows = $Left.Length + 1
    $cols = $Right.Length + 1
    $dist = New-Object 'int[,]' $rows, $cols

    for ($i = 0; $i -lt $rows; $i++) {
        $dist[$i, 0] = $i
    }
    for ($j = 0; $j -lt $cols; $j++) {
        $dist[0, $j] = $j
    }

    for ($i = 1; $i -lt $rows; $i++) {
        for ($j = 1; $j -lt $cols; $j++) {
            $cost = if ($Left[$i - 1] -ceq $Right[$j - 1]) { 0 } else { 1 }
            $deletion = $dist[$i - 1, $j] + 1
            $insertion = $dist[$i, $j - 1] + 1
            $substitution = $dist[$i - 1, $j - 1] + $cost
            $dist[$i, $j] = [Math]::Min([Math]::Min($deletion, $insertion), $substitution)
        }
    }

    return $dist[$rows - 1, $cols - 1]
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
        $distance = Get-EditDistance -Left $InputText -Right $candidate
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
    @"
Usage: setup.ps1 [install|update|doctor|deps] [--dry-run] [dependency-key...]

Commands:
  install   apply managed config and dependencies
  update    git pull this repo, then run install flow
  doctor    validate managed links and required tools
  deps      install optional dependencies only

Options:
  --dry-run       print actions without mutating filesystem
  --yes-optional  auto-accept optional dependency installs
  -h, --help      show this help

Environment variables:
  OOODNAKOV_INTERACTIVE    always, never, auto (default: auto)
  OOODNAKOV_INSTALL_OPTIONAL always, prompt (default: prompt)
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
    Write-Output "Step: $Status"

    if (Test-Interactive) {
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

function Get-OptionalDependencySpecs {
    if ($script:OptionalDependencySpecsCache) {
        return $script:OptionalDependencySpecsCache
    }

    $pythonScript = Join-Path $PSScriptRoot "read-optional-deps.py"
    $json = $null
    try {
        $json = Run-Python -ScriptPath $pythonScript -ScriptArgs @("json") 2>$null
    } catch {
    }

    if (-not $json) {
        # Fallback: hardcoded specs when Python is unavailable
        $all_specs = @(
            [pscustomobject]@{ Key = "wget"; DisplayName = "wget"; Description = "download helper"; Linux = @{ manager = "apt"; package = "wget" }; Macos = @{ manager = "brew"; package = "wget" }; Windows = @{ manager = "winget"; winget_id = "GNU.Wget" } }
            [pscustomobject]@{ Key = "git"; DisplayName = "git"; Description = "Git version control"; Linux = @{ manager = "apt"; package = "git" }; Macos = @{ manager = "brew"; package = "git" }; Windows = @{ manager = "winget"; winget_id = "Git.Git" } }
            [pscustomobject]@{ Key = "wezterm"; DisplayName = "wezterm"; Description = "WezTerm terminal"; Linux = @{ manager = "apt" }; Macos = @{ manager = "brew"; package = "wezterm" }; Windows = @{ manager = "winget"; winget_id = "wez.wezterm" } }
            [pscustomobject]@{ Key = "oh-my-posh"; DisplayName = "oh-my-posh"; Description = "Oh My Posh prompt"; Linux = @{ manager = "curl" }; Macos = @{ manager = "brew"; package = "jandedobbeleer/oh-my-posh/oh-my-posh" }; Windows = @{ manager = "winget"; winget_id = "JanDeDobbeleer.OhMyPosh" } }
            [pscustomobject]@{ Key = "posh-git"; DisplayName = "posh-git"; Description = "PowerShell Git completions and shell integration"; Linux = $null; Macos = $null; Windows = @{ manager = "custom" } }
            [pscustomobject]@{ Key = "psfzf"; DisplayName = "PSFzf"; Description = "PowerShell fzf integration for history, files, and tab completion"; Linux = $null; Macos = $null; Windows = @{ manager = "custom" } }
            [pscustomobject]@{ Key = "choco"; DisplayName = "choco"; Description = "Chocolatey"; Linux = $null; Macos = $null; Windows = @{ manager = "custom" } }
            [pscustomobject]@{ Key = "gsudo"; DisplayName = "gsudo"; Description = "gsudo elevation helper"; Linux = $null; Macos = $null; Windows = @{ manager = "choco"; package = "gsudo" } }
            [pscustomobject]@{ Key = "rg"; DisplayName = "rg"; Description = "ripgrep search tool"; Linux = @{ manager = "apt"; package = "ripgrep" }; Macos = @{ manager = "brew"; package = "ripgrep" }; Windows = @{ manager = "choco"; package = "ripgrep" } }
            [pscustomobject]@{ Key = "fd"; DisplayName = "fd"; Description = "fd find alternative"; Linux = @{ manager = "apt"; package = "fd-find" }; Macos = @{ manager = "brew"; package = "fd" }; Windows = @{ manager = "choco"; package = "fd" } }
            [pscustomobject]@{ Key = "zsh"; DisplayName = "zsh"; Description = "default shell support"; Linux = @{ manager = "apt"; package = "zsh" }; Macos = @{ manager = "brew"; package = "zsh" }; Windows = $null }
            [pscustomobject]@{ Key = "direnv"; DisplayName = "direnv"; Description = "direnv shell integration"; Linux = @{ manager = "apt"; package = "direnv" }; Macos = @{ manager = "brew"; package = "direnv" }; Windows = @{ manager = "choco"; package = "direnv" } }
            [pscustomobject]@{ Key = "fzf"; DisplayName = "fzf"; Description = "fzf shell integration"; Linux = @{ manager = "apt"; package = "fzf" }; Macos = @{ manager = "brew"; package = "fzf" }; Windows = @{ manager = "choco"; package = "fzf" } }
            [pscustomobject]@{ Key = "bat"; DisplayName = "bat"; Description = "cat alternative with syntax highlighting"; Linux = @{ manager = "apt"; package = "bat" }; Macos = @{ manager = "brew"; package = "bat" }; Windows = @{ manager = "choco"; package = "bat" } }
            [pscustomobject]@{ Key = "delta"; DisplayName = "delta"; Description = "Git diff pager with syntax highlighting"; Linux = @{ manager = "apt"; package = "git-delta" }; Macos = @{ manager = "brew"; package = "git-delta" }; Windows = @{ manager = "choco"; package = "delta" } }
            [pscustomobject]@{ Key = "glow"; DisplayName = "glow"; Description = "terminal Markdown reader"; Linux = @{ manager = "apt"; package = "glow" }; Macos = @{ manager = "brew"; package = "glow" }; Windows = @{ manager = "choco"; package = "glow" } }
            [pscustomobject]@{ Key = "gum"; DisplayName = "gum"; Description = "interactive terminal UI toolkit"; Linux = @{ manager = "apt"; package = "gum" }; Macos = @{ manager = "brew"; package = "gum" }; Windows = @{ manager = "winget"; winget_id = "charmbracelet.gum" } }
            [pscustomobject]@{ Key = "zoxide"; DisplayName = "zoxide"; Description = "smart directory jumping"; Linux = @{ manager = "apt"; package = "zoxide" }; Macos = @{ manager = "brew"; package = "zoxide" }; Windows = @{ manager = "choco"; package = "zoxide" } }
            [pscustomobject]@{ Key = "q"; DisplayName = "q"; Description = "q text-as-data CLI"; Linux = @{ manager = "apt"; package = "q" }; Macos = @{ manager = "brew"; package = "q" }; Windows = @{ manager = "choco"; package = "q-dns" } }
            [pscustomobject]@{ Key = "eza"; DisplayName = "eza"; Description = "modern ls aliases"; Linux = @{ manager = "apt"; package = "eza" }; Macos = @{ manager = "brew"; package = "eza" }; Windows = @{ manager = "choco"; package = "eza" } }
            [pscustomobject]@{ Key = "yazi"; DisplayName = "yazi"; Description = "terminal file manager"; Linux = @{ manager = "apt"; package = "yazi" }; Macos = @{ manager = "brew"; package = "yazi" }; Windows = @{ manager = "winget"; winget_id = "sxyazi.yazi" } }
            [pscustomobject]@{ Key = "ffmpeg"; DisplayName = "ffmpeg"; Description = "media preview backend for yazi"; Linux = @{ manager = "apt"; package = "ffmpeg" }; Macos = @{ manager = "brew"; package = "ffmpeg" }; Windows = @{ manager = "winget"; winget_id = "Gyan.FFmpeg" } }
            [pscustomobject]@{ Key = "jq"; DisplayName = "jq"; Description = "JSON parsing helper for yazi plugins"; Linux = @{ manager = "apt"; package = "jq" }; Macos = @{ manager = "brew"; package = "jq" }; Windows = @{ manager = "winget"; winget_id = "jqlang.jq" } }
            [pscustomobject]@{ Key = "p7zip"; DisplayName = "p7zip"; Description = "archive preview and extraction for yazi"; Linux = @{ manager = "apt"; package = "p7zip-full" }; Macos = @{ manager = "brew"; package = "p7zip" }; Windows = @{ manager = "winget"; winget_id = "7zip.7zip" } }
            [pscustomobject]@{ Key = "poppler"; DisplayName = "poppler"; Description = "PDF preview support for yazi"; Linux = @{ manager = "apt"; package = "poppler-utils" }; Macos = @{ manager = "brew"; package = "poppler" }; Windows = @{ manager = "winget"; winget_id = "oschwartz10612.Poppler" } }
            [pscustomobject]@{ Key = "uv"; DisplayName = "uv"; Description = "Python package manager"; Linux = @{ manager = "curl" }; Macos = @{ manager = "brew"; package = "uv" }; Windows = @{ manager = "choco"; package = "uv" } }
            [pscustomobject]@{ Key = "bw"; DisplayName = "bw"; Description = "Bitwarden CLI"; Linux = @{ manager = "custom" }; Macos = @{ manager = "brew"; package = "bitwarden-cli" }; Windows = @{ manager = "custom" } }
            [pscustomobject]@{ Key = "node"; DisplayName = "node"; Description = "Node.js LTS"; Linux = @{ manager = "apt"; package = "nodejs" }; Macos = @{ manager = "brew"; package = "node" }; Windows = @{ manager = "winget"; winget_id = "OpenJS.NodeJS.LTS" } }
            [pscustomobject]@{ Key = "npm"; DisplayName = "npm"; Description = "Node package manager"; Linux = @{ manager = "apt"; package = "npm" }; Macos = @{ manager = "brew"; package = "npm" }; Windows = @{ manager = "winget"; winget_id = "OpenJS.NodeJS.LTS" } }
            [pscustomobject]@{ Key = "pnpm"; DisplayName = "pnpm"; Description = "pnpm package manager"; Linux = @{ manager = "custom" }; Macos = @{ manager = "custom" }; Windows = @{ manager = "custom" } }
            [pscustomobject]@{ Key = "cargo"; DisplayName = "cargo"; Description = "Rust package manager"; Linux = @{ manager = "custom" }; Macos = @{ manager = "custom" }; Windows = @{ manager = "custom" } }
            [pscustomobject]@{ Key = "dua"; DisplayName = "dua"; Description = "disk usage analysis"; Linux = @{ manager = "cargo"; package = "dua-cli" }; Macos = @{ manager = "brew"; package = "dua-cli" }; Windows = @{ manager = "cargo"; package = "dua-cli" } }
            [pscustomobject]@{ Key = "nvim"; DisplayName = "nvim"; Description = "Neovim"; Linux = @{ manager = "apt"; package = "neovim" }; Macos = @{ manager = "brew"; package = "neovim" }; Windows = @{ manager = "winget"; winget_id = "Neovim.Neovim" } }
            [pscustomobject]@{ Key = "k"; DisplayName = "k"; Description = "standalone k command"; Linux = @{ manager = "custom" }; Macos = @{ manager = "custom" }; Windows = @{ manager = "custom" } }
            [pscustomobject]@{ Key = "python3"; DisplayName = "python3"; Description = "Python 3 runtime"; Linux = @{ manager = "apt"; package = "python3" }; Macos = @{ manager = "brew"; package = "python" }; Windows = @{ manager = "choco"; package = "python" } }
            [pscustomobject]@{ Key = "lazygit"; DisplayName = "lazygit"; Description = "simple terminal UI for git commands"; Linux = @{ manager = "brew"; package = "lazygit" }; Macos = @{ manager = "brew"; package = "lazygit" }; Windows = @{ manager = "winget"; winget_id = "JesseDuffield.lazygit" } }
        )
        $specs = @($all_specs | ForEach-Object {
            [pscustomobject]@{
                Key         = $_.Key
                DisplayName = $_.DisplayName
                Description = $_.Description
                Linux       = $_.Linux
                Macos       = $_.Macos
                Windows     = $_.Windows
            }
        })
        $script:OptionalDependencySpecsCache = $specs
        return @($specs | Where-Object { Test-OptionalDependencyApplicable -Spec $_ })
    }

    $raw = $json | ConvertFrom-Json
    $specs = @($raw | ForEach-Object {
        [pscustomobject]@{
            Key         = $_.key
            DisplayName = $_.display
            Description = $_.description
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
    $pythonScript = Join-Path $PSScriptRoot "read-optional-deps.py"
    $json = $null
    try {
        $json = Run-Python -ScriptPath $pythonScript -ScriptArgs @("json") 2>$null
    } catch {}
    if ($json) {
        $raw = $json | ConvertFrom-Json
        return @($raw | ForEach-Object {
            [pscustomobject]@{
                Key         = $_.key
                DisplayName = $_.display
                Description = $_.description
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

    switch ($Key) {
        "wget" { return @("wget") }
        "git" { return @("git") }
        "wezterm" { return @("wezterm") }
        "zsh" { return @("zsh") }
        "nvim" { return @("nvim") }
        "oh-my-posh" { return @("oh-my-posh") }
        "posh-git" { return @() }
        "psfzf" { return @() }
        "node" { return @("node") }
        "choco" { return @("choco") }
        "gsudo" { return @("gsudo") }
        "rg" { return @("rg") }
        "fd" { return @("fd") }
        "direnv" { return @("direnv") }
        "fzf" { return @("fzf") }
        "bat" { return @("bat") }
        "delta" { return @("delta") }
        "glow" { return @("glow") }
        "gum" { return @("gum") }
        "zoxide" { return @("zoxide") }
        "q" { return @("q") }
        "eza" { return @("eza") }
        "yazi" { return @("yazi") }
        "ffmpeg" { return @("ffmpeg") }
        "jq" { return @("jq") }
        "p7zip" { return @("7z") }
        "poppler" { return @("pdftotext") }
        "uv" { return @("uv") }
        "python3" { return @("python", "python3") }
        "bw" { return @("bw") }
        "pnpm" { return @("pnpm") }
        "cargo" { return @("cargo") }
        "dua" { return @("dua") }
        "k" { return @("k") }
        "lazygit" { return @("lazygit") }
        default { return @() }
    }
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
    Write-Output "[failed] $Item"
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


function Invoke-ActionWithSpinner {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action,
        [object[]]$ArgumentList = @()
    )

    if ($DryRun) {
        Write-Output "[dry-run] $Description"
        return $true
    }

    if (-not (Test-VerboseMode)) {
        if (Test-Interactive) {
            Write-Host "[-] $Description..."
        } else {
            Write-Output "[-] $Description..."
        }

        $stdoutLog = Join-Path ([System.IO.Path]::GetTempPath()) ("oooconf-{0}.stdout.log" -f ([guid]::NewGuid().ToString("N")))
        $stderrLog = Join-Path ([System.IO.Path]::GetTempPath()) ("oooconf-{0}.stderr.log" -f ([guid]::NewGuid().ToString("N")))

        try {
            & $Action @ArgumentList > $stdoutLog 2> $stderrLog
            if (Test-Interactive) {
                Write-Host "[ok] $Description"
            } else {
                Write-Output "[ok] $Description"
            }
            return $true
        } catch {
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
            Write-Output "`r[ok] $Description"
        }
        return $true
    } else {
        if ($interactive) {
            Write-Host "`r[failed] $Description                        "
        } else {
            Write-Output "`r[failed] $Description"
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
        Write-Output "[dry-run] $Description"
        return $true
    }

    try {
        & $Action
        return $true
    } catch {
        Write-Output $_
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
        Write-Output "[dry-run] $Description"
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
        Write-Output "backed up $Target -> $backupPath"
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
            Write-Output "linked $Target"
        }
        return $true
    }

    return (Invoke-Action -Description "Link $Target" -Action {
        New-Item -ItemType SymbolicLink -Path $Target -Target $Source -Force | Out-Null
        if (Test-VerboseMode) {
            Write-Output "linked $Target"
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
        Write-Output "updated user PATH with $PathEntry"
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
        if (-not $DryRun -and (Test-VerboseMode)) {
            if (Test-Interactive) {
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
        Write-Output "[dry-run] Install Chocolatey"
        Add-DependencySummary "choco: install preview"
        return $false
    }

    try {
        Write-Output "Installing Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-RestMethod -Uri "https://community.chocolatey.org/install.ps1" | Invoke-Expression
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Add-DependencySummary "choco: installed"
            return $true
        }
    } catch {
        Write-Output $_
        Add-Failure "Installing Chocolatey"
    }

    Add-DependencySummary "choco: install attempted"
    return $false
}

function Install-PackageIfMissing {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CommandNames,
        [string]$WingetId,
        [string]$ChocoId,
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

            if (Test-AnyCommand -Names $CommandNames) {
                Add-DependencySummary "${SummaryName}: installed via winget"
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

            if (Test-AnyCommand -Names $CommandNames) {
                Add-DependencySummary "${SummaryName}: installed via choco"
                return $true
            }

            Add-DependencySummary "${SummaryName}: install attempted via choco"
            return $false
        }

        Add-DependencySummary "${SummaryName}: skipped"
        return $false
    }

    Add-DependencySummary "${SummaryName}: missing (no supported package manager)"
    return $false
}

function Install-PnpmIfMissing {
    if (Test-DependencyStatus -CommandName "pnpm" -SummaryName "pnpm") { return $true }

    if (-not (Confirm-Install "Install pnpm package manager?")) {
        Add-DependencySummary "pnpm: skipped"
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

    if (Get-Command corepack -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Output "[dry-run] corepack enable --install-directory $pnpmHome pnpm"
            Write-Output "[dry-run] corepack prepare pnpm@$PnpmVersion --activate"
            Add-DependencySummary "pnpm: install preview via corepack"
            return $false
        }

        Invoke-ActionWithSpinner -Description "Installing pnpm@$PnpmVersion via corepack" -Action {
            param($homeDir, $version)
            corepack enable --install-directory $homeDir pnpm | Out-Null
            corepack prepare "pnpm@$version" --activate | Out-Null
        } -ArgumentList $pnpmHome, $PnpmVersion
    } elseif (Get-Command npm -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Output "[dry-run] npm install --global pnpm@$PnpmVersion --prefix $pnpmHome"
            Add-DependencySummary "pnpm: install preview via npm"
            return $false
        }

        Invoke-ActionWithSpinner -Description "Installing pnpm@$PnpmVersion via npm" -Action {
            param($homeDir, $version)
            npm install --global "pnpm@$version" --prefix $homeDir | Out-Null
        } -ArgumentList $pnpmHome, $PnpmVersion
    } else {
        Add-DependencySummary "pnpm: missing (requires corepack or npm)"
        return $false
    }

    if (Get-Command pnpm -ErrorAction SilentlyContinue) {
        Add-DependencySummary "pnpm: installed"
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
        return $true
    }

    Add-DependencySummary "psfzf: install attempted"
    return $false
}

function Install-BitwardenCliIfMissing {
    if (Test-DependencyStatus -CommandName "bw" -SummaryName "bw") { return $true }

    if (-not (Confirm-Install "Install Bitwarden CLI from the official native executable archive?")) {
        Add-DependencySummary "bw: skipped"
        return $false
    }

    $installRoot = Join-Path $ShareHome "tools/bitwarden-cli/v$BwVersion"
    $archivePath = Join-Path ([System.IO.Path]::GetTempPath()) "bw-windows-$BwVersion.zip"
    $releaseUrl = "https://github.com/bitwarden/cli/releases/download/v$BwVersion/bw-windows-$BwVersion.zip"
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
        Add-DependencySummary "bw: install attempted"
        return $false
    }

    if (Get-Command bw -ErrorAction SilentlyContinue -CommandType Application) {
        Add-DependencySummary "bw: installed official v$BwVersion"
        return $true
    }

    if (Test-Path $targetBinary) {
        Add-DependencySummary "bw: installed official v$BwVersion"
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
        return $true
    }

    Add-DependencySummary "dua: install attempted"
    return $false
}

function Install-OptionalDependencies {
    if (Test-VerboseMode) {
        Write-Output "Dependency check:"
    }

    $null = Invoke-SelectedOptionalDependency -Key "wget" -Action { Install-PackageIfMissing -CommandNames @("wget") -WingetId "GNU.Wget" -Description "wget" -SummaryName "wget" }
    $null = Invoke-SelectedOptionalDependency -Key "git" -Action { Install-PackageIfMissing -CommandNames @("git") -WingetId "Git.Git" -Description "Git" -SummaryName "git" }
    $null = Invoke-SelectedOptionalDependency -Key "wezterm" -Action { Install-PackageIfMissing -CommandNames @("wezterm") -WingetId "wez.wezterm" -Description "WezTerm" -SummaryName "wezterm" }
    $null = Invoke-SelectedOptionalDependency -Key "zsh" -Action { Write-Warning "zsh is not natively supported on Windows; use WSL or a custom build." }
    $null = Invoke-SelectedOptionalDependency -Key "nvim" -Action { Install-PackageIfMissing -CommandNames @("nvim") -WingetId "Neovim.Neovim" -Description "Neovim" -SummaryName "nvim" }
    $null = Invoke-SelectedOptionalDependency -Key "oh-my-posh" -Action { Install-PackageIfMissing -CommandNames @("oh-my-posh") -WingetId "JanDeDobbeleer.OhMyPosh" -Description "oh-my-posh" -SummaryName "oh-my-posh" }
    $null = Invoke-SelectedOptionalDependency -Key "posh-git" -Action { Install-PoshGitIfMissing }
    $null = Invoke-SelectedOptionalDependency -Key "psfzf" -Action { Install-PSFzfIfMissing }
    $null = Invoke-SelectedOptionalDependency -Key "node" -Action { Install-PackageIfMissing -CommandNames @("node") -WingetId "OpenJS.NodeJS.LTS" -Description "Node.js LTS" -SummaryName "node" }

    $needsChocolatey = Test-OptionalDependencySelected -Key "choco"
    if (-not $needsChocolatey) {
        foreach ($key in @("gsudo", "rg", "fd", "direnv", "fzf", "bat", "delta", "glow", "q", "eza", "uv", "python3")) {
            if (Test-OptionalDependencySelected -Key $key) {
                $needsChocolatey = $true
                break
            }
        }
    }
    if ($needsChocolatey) {
        Install-Chocolatey
    }

    $null = Invoke-SelectedOptionalDependency -Key "gsudo" -Action { Install-PackageIfMissing -CommandNames @("gsudo") -ChocoId "gsudo" -Description "gsudo" -SummaryName "gsudo" }
    $null = Invoke-SelectedOptionalDependency -Key "rg" -Action { Install-PackageIfMissing -CommandNames @("rg") -ChocoId "ripgrep" -Description "ripgrep" -SummaryName "rg" }
    $null = Invoke-SelectedOptionalDependency -Key "fd" -Action { Install-PackageIfMissing -CommandNames @("fd") -ChocoId "fd" -Description "fd" -SummaryName "fd" }
    $null = Invoke-SelectedOptionalDependency -Key "direnv" -Action { Install-PackageIfMissing -CommandNames @("direnv") -ChocoId "direnv" -Description "direnv" -SummaryName "direnv" }
    $null = Invoke-SelectedOptionalDependency -Key "fzf" -Action { Install-PackageIfMissing -CommandNames @("fzf") -ChocoId "fzf" -Description "fzf" -SummaryName "fzf" }
    $null = Invoke-SelectedOptionalDependency -Key "bat" -Action { Install-PackageIfMissing -CommandNames @("bat") -ChocoId "bat" -Description "bat" -SummaryName "bat" }
    $null = Invoke-SelectedOptionalDependency -Key "delta" -Action { Install-PackageIfMissing -CommandNames @("delta") -ChocoId "git-delta" -Description "delta" -SummaryName "delta" }
    $null = Invoke-SelectedOptionalDependency -Key "glow" -Action { Install-PackageIfMissing -CommandNames @("glow") -ChocoId "glow" -Description "glow" -SummaryName "glow" }
    $null = Invoke-SelectedOptionalDependency -Key "gum" -Action { Install-PackageIfMissing -CommandNames @("gum") -WingetId "charmbracelet.gum" -Description "gum" -SummaryName "gum" }
    $null = Invoke-SelectedOptionalDependency -Key "zoxide" -Action { Install-PackageIfMissing -CommandNames @("zoxide") -ChocoId "zoxide" -Description "zoxide" -SummaryName "zoxide" }
    $null = Invoke-SelectedOptionalDependency -Key "q" -Action { Install-PackageIfMissing -CommandNames @("q") -ChocoId "q" -Description "q" -SummaryName "q" }
    $null = Invoke-SelectedOptionalDependency -Key "eza" -Action { Install-PackageIfMissing -CommandNames @("eza") -ChocoId "eza" -Description "eza" -SummaryName "eza" }
    $null = Invoke-SelectedOptionalDependency -Key "yazi" -Action { Install-PackageIfMissing -CommandNames @("yazi") -WingetId "sxyazi.yazi" -Description "yazi" -SummaryName "yazi" }
    $null = Invoke-SelectedOptionalDependency -Key "ffmpeg" -Action { Install-PackageIfMissing -CommandNames @("ffmpeg") -WingetId "Gyan.FFmpeg" -Description "ffmpeg" -SummaryName "ffmpeg" }
    $null = Invoke-SelectedOptionalDependency -Key "jq" -Action { Install-PackageIfMissing -CommandNames @("jq") -WingetId "jqlang.jq" -Description "jq" -SummaryName "jq" }
    $null = Invoke-SelectedOptionalDependency -Key "p7zip" -Action { Install-PackageIfMissing -CommandNames @("7z") -WingetId "7zip.7zip" -Description "7-Zip" -SummaryName "p7zip" }
    $null = Invoke-SelectedOptionalDependency -Key "poppler" -Action { Install-PackageIfMissing -CommandNames @("pdftotext") -WingetId "oschwartz10612.Poppler" -Description "poppler-utils" -SummaryName "poppler" }
    $null = Invoke-SelectedOptionalDependency -Key "uv" -Action { Install-PackageIfMissing -CommandNames @("uv") -ChocoId "uv" -Description "uv" -SummaryName "uv" }
    $null = Invoke-SelectedOptionalDependency -Key "python3" -Action { Install-PackageIfMissing -CommandNames @("python3", "python") -ChocoId "python" -Description "Python 3" -SummaryName "python3" }
    $null = Invoke-SelectedOptionalDependency -Key "bw" -Action { Install-BitwardenCliIfMissing }
    $null = Invoke-SelectedOptionalDependency -Key "pnpm" -Action { Install-PnpmIfMissing }
    $null = Invoke-SelectedOptionalDependency -Key "cargo" -Action { Install-CargoIfMissing }
    $null = Invoke-SelectedOptionalDependency -Key "dua" -Action { Install-DuaIfMissing }
    $null = Invoke-SelectedOptionalDependency -Key "k" -Action { Write-Warning "k is not available on Windows." }
    $null = Invoke-SelectedOptionalDependency -Key "lazygit" -Action { Install-PackageIfMissing -CommandNames @("lazygit") -WingetId "JesseDuffield.lazygit" -Description "lazygit" -SummaryName "lazygit" }
}

function Write-Summary {
    Write-Output ""
    Write-Output "Dependency summary:"
    foreach ($item in $script:DependencySummary) {
        Write-Output "  - $item"
    }

    Write-Output "Managed setup:"
    foreach ($item in $script:ToolSummary) {
        Write-Output "  - $item"
    }

    if ($script:Failures.Count -gt 0) {
        Write-Output "Failures:"
        foreach ($item in $script:Failures) {
            Write-Output "  - $item"
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
        Write-Output "[ok] $Target -> $Source"
        return
    }

    Write-Output "[missing] $Target (expected symlink to $Source)"
    $script:Failures.Add("doctor link $Target") | Out-Null
}

function Test-DoctorCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (Get-Command $Name -ErrorAction SilentlyContinue) {
        Write-Output "[ok] command: $Name"
        return
    }

    Write-Output "[missing] command: $Name"
    $script:Failures.Add("doctor command $Name") | Out-Null
}

function Test-Doctor {
    Write-Output "Running doctor checks..."

    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/wezterm") -Target (Join-Path $ConfigHome "wezterm")
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/lazygit") -Target (Join-Path $ConfigHome "lazygit")
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/nvim") -Target (Join-Path $ConfigHome "nvim")
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov") -Target (Join-Path $ConfigHome "ooodnakov")
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ohmyposh/ooodnakov.omp.json") -Target (Join-Path $OhMyPoshDir "ooodnakov.omp.json")
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target $PowerShellProfileTarget
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target $ActivePowerShellProfile
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/oooconf.ps1") -Target (Join-Path $LocalBinDir "oooconf.ps1")
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/oooconf.cmd") -Target (Join-Path $LocalBinDir "oooconf.cmd")
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/o.ps1") -Target (Join-Path $LocalBinDir "o.ps1")
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/o.cmd") -Target (Join-Path $LocalBinDir "o.cmd")

    Test-DoctorCommand -Name "git"
    Test-DoctorCommand -Name "wezterm"
    Test-DoctorCommand -Name "nvim"
    Test-DoctorCommand -Name "oh-my-posh"
    Test-DoctorCommand -Name "oooconf"
    Test-DoctorCommand -Name "o"

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $userPathParts = @($userPath -split [IO.Path]::PathSeparator | Where-Object { $_ })
    if ($userPathParts -contains $LocalBinDir) {
        Write-Output "[ok] user PATH contains $LocalBinDir"
    } else {
        Write-Output "[missing] user PATH entry: $LocalBinDir"
        $script:Failures.Add("doctor user PATH") | Out-Null
    }

    if ($script:Failures.Count -gt 0) {
        throw "Doctor found $($script:Failures.Count) issue(s)."
    }

    Write-Output "Doctor checks passed."
}

function Invoke-Install {
    param(
        [switch]$ContinueProgress
    )

    if (-not $ContinueProgress) {
        Start-StepProgress -Total 5 -Activity "oooconf $Command"
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
    if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/wezterm") -Target (Join-Path $ConfigHome "wezterm")) {
        Add-ToolSummary "wezterm: linked"
    }
    if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/lazygit") -Target (Join-Path $ConfigHome "lazygit")) {
        Add-ToolSummary "lazygit: linked"
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

    if (Ensure-UserPathContains -PathEntry $LocalBinDir) {
        Add-ToolSummary "user PATH: ensured $LocalBinDir"
    }
    if (Add-SshInclude) {
        Add-ToolSummary "ssh include: ensured"
    }

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
            Start-StepProgress -Total 6 -Activity "oooconf update"
            Step-Progress -Status "Pulling latest repository changes"
            if ($DryRun) {
                Write-Output "[dry-run] git -C $RepoRoot pull --ff-only"
            } else {
                git -C $RepoRoot pull --ff-only
            }
            Invoke-Install -ContinueProgress
        }
        "doctor" {
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
                Ensure-Directory -Path $dir | Out-Null
            }

            Step-Progress -Status "Installing selected optional dependencies"
            Install-OptionalDependencies
            Step-Progress -Status "Writing dependency summary"
            Write-Summary
            Write-Output ""
            Write-Output "Optional dependency install complete."
            Step-Progress -Status "Done"
        }
    }
} finally {
    if ($script:LogFile) {
        Write-Output "Log file: $script:LogFile"
    }
    Stop-SetupLogging
}

if ($script:Failures.Count -gt 0 -and $Command -ne "doctor") {
    exit 1
}
