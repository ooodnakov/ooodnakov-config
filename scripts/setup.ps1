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
$ValidSetupCommands = @("install", "update", "doctor", "deps")

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
        default { return $Host.Name -ne "ServerRemoteHost" }
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

function Get-OptionalDependencySpecs {
    if ($script:OptionalDependencySpecsCache) {
        return $script:OptionalDependencySpecsCache
    }

    $pythonScript = Join-Path $PSScriptRoot "read-optional-deps.py"
    $json = $null
    try {
        $json = & python3 $pythonScript json 2>$null
    } catch {
    }

    if (-not $json) {
        # Fallback: hardcoded specs when Python is unavailable
        return @(
            [pscustomobject]@{ Key = "git"; DisplayName = "git"; Description = "Git version control" }
            [pscustomobject]@{ Key = "wezterm"; DisplayName = "wezterm"; Description = "WezTerm terminal" }
            [pscustomobject]@{ Key = "nvim"; DisplayName = "nvim"; Description = "Neovim" }
            [pscustomobject]@{ Key = "oh-my-posh"; DisplayName = "oh-my-posh"; Description = "Oh My Posh prompt" }
            [pscustomobject]@{ Key = "node"; DisplayName = "node"; Description = "Node.js LTS" }
            [pscustomobject]@{ Key = "choco"; DisplayName = "choco"; Description = "Chocolatey" }
            [pscustomobject]@{ Key = "gsudo"; DisplayName = "gsudo"; Description = "gsudo elevation helper" }
            [pscustomobject]@{ Key = "rg"; DisplayName = "rg"; Description = "ripgrep search tool" }
            [pscustomobject]@{ Key = "fd"; DisplayName = "fd"; Description = "fd find alternative" }
            [pscustomobject]@{ Key = "direnv"; DisplayName = "direnv"; Description = "direnv shell integration" }
            [pscustomobject]@{ Key = "fzf"; DisplayName = "fzf"; Description = "fzf shell integration" }
            [pscustomobject]@{ Key = "bat"; DisplayName = "bat"; Description = "cat alternative with syntax highlighting" }
            [pscustomobject]@{ Key = "delta"; DisplayName = "delta"; Description = "Git diff pager with syntax highlighting" }
            [pscustomobject]@{ Key = "glow"; DisplayName = "glow"; Description = "terminal Markdown reader" }
            [pscustomobject]@{ Key = "gum"; DisplayName = "gum"; Description = "interactive terminal UI toolkit" }
            [pscustomobject]@{ Key = "q"; DisplayName = "q"; Description = "q text-as-data CLI" }
            [pscustomobject]@{ Key = "eza"; DisplayName = "eza"; Description = "modern ls aliases" }
            [pscustomobject]@{ Key = "uv"; DisplayName = "uv"; Description = "Python package manager" }
            [pscustomobject]@{ Key = "python3"; DisplayName = "python3"; Description = "Python 3 runtime" }
            [pscustomobject]@{ Key = "bw"; DisplayName = "bw"; Description = "Bitwarden CLI" }
            [pscustomobject]@{ Key = "pnpm"; DisplayName = "pnpm"; Description = "pnpm package manager" }
            [pscustomobject]@{ Key = "wget"; DisplayName = "wget"; Description = "download helper" }
            [pscustomobject]@{ Key = "zsh"; DisplayName = "zsh"; Description = "default shell support" }
            [pscustomobject]@{ Key = "autoconf"; DisplayName = "autoconf"; Description = "build ezsh native components" }
            [pscustomobject]@{ Key = "fc-cache"; DisplayName = "fc-cache"; Description = "refresh font caches" }
            [pscustomobject]@{ Key = "cargo"; DisplayName = "cargo"; Description = "Rust package manager" }
            [pscustomobject]@{ Key = "dua"; DisplayName = "dua"; Description = "disk usage analysis" }
            [pscustomobject]@{ Key = "k"; DisplayName = "k"; Description = "standalone k command" }
        )
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
    return $specs
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

function Test-OptionalDependencyPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    switch ($Key) {
        "git" { return [bool](Get-Command git -ErrorAction SilentlyContinue) }
        "wezterm" { return [bool](Get-Command wezterm -ErrorAction SilentlyContinue) }
        "nvim" { return [bool](Get-Command nvim -ErrorAction SilentlyContinue) }
        "oh-my-posh" { return [bool](Get-Command oh-my-posh -ErrorAction SilentlyContinue) }
        "node" { return [bool](Get-Command node -ErrorAction SilentlyContinue) }
        "choco" { return [bool](Get-Command choco -ErrorAction SilentlyContinue) }
        "gsudo" { return [bool](Get-Command gsudo -ErrorAction SilentlyContinue) }
        "rg" { return [bool](Get-Command rg -ErrorAction SilentlyContinue) }
        "fd" { return [bool](Get-Command fd -ErrorAction SilentlyContinue) }
        "direnv" { return [bool](Get-Command direnv -ErrorAction SilentlyContinue) }
        "fzf" { return [bool](Get-Command fzf -ErrorAction SilentlyContinue) }
        "bat" { return [bool](Get-Command bat -ErrorAction SilentlyContinue) }
        "delta" { return [bool](Get-Command delta -ErrorAction SilentlyContinue) }
        "glow" { return [bool](Get-Command glow -ErrorAction SilentlyContinue) }
        "gum" { return [bool](Get-Command gum -ErrorAction SilentlyContinue) }
        "q" { return [bool](Get-Command q -ErrorAction SilentlyContinue) }
        "eza" { return [bool](Get-Command eza -ErrorAction SilentlyContinue) }
        "uv" { return [bool](Get-Command uv -ErrorAction SilentlyContinue) }
        "python3" { return [bool](Get-Command python -ErrorAction SilentlyContinue) -or [bool](Get-Command python3 -ErrorAction SilentlyContinue) }
        "bw" { return [bool](Get-Command bw -ErrorAction SilentlyContinue) }
        "pnpm" { return [bool](Get-Command pnpm -ErrorAction SilentlyContinue) }
        default { return $false }
    }
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
    $available = @(Get-OptionalDependencySpecs | Where-Object { -not (Test-OptionalDependencyPresent -Key $_.Key) })

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
        if (Test-OptionalDependencyPresent -Key $spec.Key) {
            continue
        }
        "$($spec.Key)`t$($spec.DisplayName)`t$($spec.Description)"
    }

    if (-not $options) {
        Write-Output "All optional dependencies are already present."
        return @("__all_present__")
    }

    $selection = $options | & gum choose --no-limit --height 20 --header "Select optional dependencies to install. Use arrows to move, x to toggle, enter to continue."
    if (-not $selection) {
        return @()
    }

    return @($selection | ForEach-Object { ($_ -split "`t")[0] })
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

    Write-Output "Logging to $script:LogFile"
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
        Write-Output "linked $Target"
        return $true
    }

    return (Invoke-Action -Description "Link $Target" -Action {
        New-Item -ItemType SymbolicLink -Path $Target -Target $Source -Force | Out-Null
        Write-Output "linked $Target"
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
    }

    return $false
}

function Install-Chocolatey {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Add-DependencySummary "choco: present"
        return $true
    }

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

    if (Test-AnyCommand -Names $CommandNames) {
        Add-DependencySummary "${SummaryName}: present"
        return $true
    }

    if ($WingetId -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        if (Confirm-Install "Install $Description with winget?") {
            if ($DryRun) {
                Write-Output "[dry-run] winget install --exact --id $WingetId"
                Add-DependencySummary "${SummaryName}: install preview via winget"
                return $false
            }

            try {
                winget install --exact --id $WingetId --accept-package-agreements --accept-source-agreements
            } catch {
                Write-Output $_
            }

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

            try {
                choco install $ChocoId -y
            } catch {
                Write-Output $_
            }

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
    if (Get-Command pnpm -ErrorAction SilentlyContinue) {
        Add-DependencySummary "pnpm: present"
        return $true
    }

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

        try {
            & corepack enable --install-directory $pnpmHome pnpm
            & corepack prepare "pnpm@$PnpmVersion" --activate
        } catch {
            Write-Output $_
        }
    } elseif (Get-Command npm -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Output "[dry-run] npm install --global pnpm@$PnpmVersion --prefix $pnpmHome"
            Add-DependencySummary "pnpm: install preview via npm"
            return $false
        }

        try {
            & npm install --global "pnpm@$PnpmVersion" --prefix $pnpmHome
        } catch {
            Write-Output $_
        }
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

function Install-BitwardenCliIfMissing {
    if (Get-Command bw -ErrorAction SilentlyContinue) {
        Add-DependencySummary "bw: present"
        return $true
    }

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

function Install-OptionalDependencies {
    Write-Output "Dependency check:"

    $null = Invoke-SelectedOptionalDependency -Key "git" -Action { Install-PackageIfMissing -CommandNames @("git") -WingetId "Git.Git" -Description "Git" -SummaryName "git" }
    $null = Invoke-SelectedOptionalDependency -Key "wezterm" -Action { Install-PackageIfMissing -CommandNames @("wezterm") -WingetId "wez.wezterm" -Description "WezTerm" -SummaryName "wezterm" }
    $null = Invoke-SelectedOptionalDependency -Key "nvim" -Action { Install-PackageIfMissing -CommandNames @("nvim") -WingetId "Neovim.Neovim" -Description "Neovim" -SummaryName "nvim" }
    $null = Invoke-SelectedOptionalDependency -Key "oh-my-posh" -Action { Install-PackageIfMissing -CommandNames @("oh-my-posh") -WingetId "JanDeDobbeleer.OhMyPosh" -Description "oh-my-posh" -SummaryName "oh-my-posh" }
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
    $null = Invoke-SelectedOptionalDependency -Key "q" -Action { Install-PackageIfMissing -CommandNames @("q") -ChocoId "q" -Description "q" -SummaryName "q" }
    $null = Invoke-SelectedOptionalDependency -Key "eza" -Action { Install-PackageIfMissing -CommandNames @("eza") -ChocoId "eza" -Description "eza" -SummaryName "eza" }
    $null = Invoke-SelectedOptionalDependency -Key "uv" -Action { Install-PackageIfMissing -CommandNames @("uv") -ChocoId "uv" -Description "uv" -SummaryName "uv" }
    $null = Invoke-SelectedOptionalDependency -Key "python3" -Action { Install-PackageIfMissing -CommandNames @("python3", "python") -ChocoId "python" -Description "Python 3" -SummaryName "python3" }
    $null = Invoke-SelectedOptionalDependency -Key "bw" -Action { Install-BitwardenCliIfMissing }
    $null = Invoke-SelectedOptionalDependency -Key "pnpm" -Action { Install-PnpmIfMissing }
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
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/nvim") -Target (Join-Path $ConfigHome "nvim")
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov") -Target (Join-Path $ConfigHome "ooodnakov")
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ohmyposh/ooodnakov.omp.json") -Target (Join-Path $OhMyPoshDir "ooodnakov.omp.json")
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target $PowerShellProfileTarget
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/powershell/Microsoft.PowerShell_profile.ps1") -Target $ActivePowerShellProfile
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/oooconf.ps1") -Target (Join-Path $LocalBinDir "oooconf.ps1")
    Test-DoctorLink -Source (Join-Path $RepoRoot "home/.config/ooodnakov/bin/oooconf.cmd") -Target (Join-Path $LocalBinDir "oooconf.cmd")

    Test-DoctorCommand -Name "git"
    Test-DoctorCommand -Name "wezterm"
    Test-DoctorCommand -Name "nvim"
    Test-DoctorCommand -Name "oh-my-posh"
    Test-DoctorCommand -Name "oooconf"

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
    foreach ($dir in @($ConfigHome, $DataHome, $CacheHome, $StateHome, $ShareHome, (Join-Path $ShareHome "bin"), $LocalBinDir, $OhMyPoshDir, $PowerShellConfigDir)) {
        if (Ensure-Directory -Path $dir) {
            Add-ToolSummary "ensured directory: $dir"
        }
    }

    Install-OptionalDependencies

    if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/wezterm") -Target (Join-Path $ConfigHome "wezterm")) {
        Add-ToolSummary "wezterm: linked"
    }
    if (New-Symlink -Source (Join-Path $RepoRoot "home/.config/nvim") -Target (Join-Path $ConfigHome "nvim")) {
        Add-ToolSummary "nvim: linked"
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

    if (Ensure-UserPathContains -PathEntry $LocalBinDir) {
        Add-ToolSummary "user PATH: ensured $LocalBinDir"
    }
    if (Add-SshInclude) {
        Add-ToolSummary "ssh include: ensured"
    }

    Write-Summary
    Write-Output ""
    Write-Output "Bootstrap complete."
    Write-Output "If needed, create local overrides in $ConfigHome/ooodnakov/local."
}

Start-SetupLogging
try {
    $allPresent = $false

    if ($DependencyKeys.Count -gt 0) {
        $validKeys = @((Get-OptionalDependencySpecs).Key)
        foreach ($key in $DependencyKeys) {
            if ($validKeys -notcontains $key) {
                $suggestion = Get-ClosestSuggestion -InputText $key -Candidates $validKeys
                if ($suggestion) {
                    throw "Unknown dependency key: $key`nDid you mean: $suggestion"
                }
                throw "Unknown dependency key: $key"
            }
        }
        $script:SelectedOptionalKeys = @($DependencyKeys)
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
        if (-not $allPresent -and $selected.Count -eq 0) {
            throw "No optional dependencies selected."
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
            if ($DryRun) {
                Write-Output "[dry-run] git -C $RepoRoot pull --ff-only"
            } else {
                git -C $RepoRoot pull --ff-only
            }
            Invoke-Install
        }
        "doctor" {
            Test-Doctor
        }
        "deps" {
            if ($allPresent) {
                Write-Output "Optional dependency install complete."
                break
            }

            foreach ($dir in @($DataHome, $StateHome, $ShareHome, (Join-Path $ShareHome "bin"), $LocalBinDir)) {
                Ensure-Directory -Path $dir | Out-Null
            }

            Install-OptionalDependencies
            Write-Summary
            Write-Output ""
            Write-Output "Optional dependency install complete."
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
