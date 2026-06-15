if (Test-Path "$HOME\.x-cmd.root\local\data\pwsh\_index.ps1") { Set-ExecutionPolicy Bypass -Scope Process; . "$HOME\.x-cmd.root\local\data\pwsh\_index.ps1" };  # boot up x-cmd.
$ConfigRoot = Join-Path $HOME ".config/ooodnakov"
$DefaultPromptConfig = Join-Path $HOME ".config/ohmyposh/ooodnakov.omp.json"
$PromptConfig = if ($env:OOOCONF_OMP_CONFIG -and (Test-Path $env:OOOCONF_OMP_CONFIG)) { $env:OOOCONF_OMP_CONFIG } else { $DefaultPromptConfig }
$SharedEnv = Join-Path $ConfigRoot "env/common.ps1"
$LocalEnv = Join-Path $ConfigRoot "local/env.ps1"
$LocalBin = Join-Path $HOME ".local/bin"

# Configure fzf to use a popup-style window to prevent screen shifting
# We use a smaller height and no border to minimize displacement of multi-line prompts.
$env:FZF_DEFAULT_OPTS = "--height 40% --inline-info --clear"

if (Test-Path $LocalBin) {
    $pathParts = @($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ })
    if ($pathParts -notcontains $LocalBin) {
        $env:PATH = "$LocalBin$([IO.Path]::PathSeparator)$env:PATH"
    }
}

$CacheDir = Join-Path $ConfigRoot "cache"
if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Path $CacheDir -ErrorAction SilentlyContinue }

function Test-InteractiveConsoleHost {
    return (
        -not [Console]::IsInputRedirected -and
        -not [Console]::IsOutputRedirected -and
        $Host.Name -eq 'ConsoleHost'
    )
}

# ---[ PLUGINS & CONFIG ]---

# Optimized Oh My Posh initialization
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    $ompCache = Join-Path $CacheDir "oh-my-posh.ps1"
    if (-not (Test-Path $ompCache) -or (Get-Item $PromptConfig).LastWriteTime -gt (Get-Item $ompCache).LastWriteTime) {
        oh-my-posh init pwsh --config $PromptConfig --print > $ompCache
    }
    . $ompCache
}

# Optimized zoxide initialization
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    $zoxideCache = Join-Path $CacheDir "zoxide.ps1"
    if (-not (Test-Path $zoxideCache)) {
        zoxide init powershell > $zoxideCache
    }
    . $zoxideCache
}

# Ensure Update-Venv runs on every prompt (handles cd, z, zi, etc.)
# We do this AFTER oh-my-posh and zoxide have potentially wrapped the prompt
$oldPrompt = $function:prompt
function global:prompt {
    Update-Venv
    if ($oldPrompt) { & $oldPrompt }
    else { "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) " }
}

if (Test-Path $SharedEnv) {
    . $SharedEnv
}

if (Test-Path $LocalEnv) {
    . $LocalEnv
}

if ($null -ne (Get-Module -ListAvailable -Name posh-git)) {
    Import-Module posh-git -ErrorAction SilentlyContinue
}

if ($null -ne (Get-Module -ListAvailable -Name PSFzf)) {
    Import-Module PSFzf -ErrorAction SilentlyContinue
}

if ($null -ne (Get-Module -ListAvailable -Name PSReadLine)) {
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd

    # Prediction rendering fails in redirected/non-VT hosts (for example RTK-wrapped commands).
    if (Test-InteractiveConsoleHost) {
        try {
            Set-PSReadLineOption -PredictionSource HistoryAndPlugin
            Set-PSReadLineOption -PredictionViewStyle InlineView
        } catch {
            # Skip predictive suggestions when the current host cannot render them.
        }
    }

    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key "Ctrl+Spacebar" -Function MenuComplete

    Set-PSReadLineKeyHandler -Chord Alt+b -Function BackwardWord
    Set-PSReadLineKeyHandler -Chord Alt+f -Function ForwardWord

    Set-Alias oooconf oooconf.ps1 -ErrorAction SilentlyContinue

    if ($null -ne (Get-Command Set-PsFzfOption -ErrorAction SilentlyContinue)) {
        $psFzfArgs = @{
            PSReadlineChordProvider       = 'Ctrl+t'
            PSReadlineChordReverseHistory = 'Ctrl+r'
            TabExpansion                  = ($env:OOODNAKOV_PSFZF_TAB -ne 'disabled')
            GitKeyBindings                = ($env:OOODNAKOV_PSFZF_GIT -ne 'disabled')
            TabCompletionPreviewWindow    = 'hidden'
        }

        if ($null -ne (Get-Command fd -ErrorAction SilentlyContinue)) {
            $psFzfArgs.EnableFd = $true
        }

        Set-PsFzfOption @psFzfArgs

        # Explicitly bind both Ctrl+r and UpArrow to the PSFzf handler
        if (Get-Command Invoke-FzfPsReadlineHandlerHistory -ErrorAction SilentlyContinue) {
            Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -ScriptBlock { Invoke-FzfPsReadlineHandlerHistory }
            Set-PSReadLineKeyHandler -Key UpArrow -ScriptBlock { Invoke-FzfPsReadlineHandlerHistory }
        } else {
            Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
        }

        Set-PSReadLineKeyHandler -Key Tab -ScriptBlock { Invoke-FzfTabCompletion }
    }
}

Set-Alias ll Get-ChildItem

function gst {
    git status @args
}

function gc {
    git commit -v @args
}

function gp {
    git push @args
}

function gl {
    git pull @args
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
        if (-not $name.EndsWith(".exe") -and (Get-Command "$name.exe" -ErrorAction SilentlyContinue)) {
            return $true
        }
    }

    return $false
}

function Invoke-ForgitOrGit {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ForgitNames,
        [Parameter(Mandatory = $true)]
        [scriptblock]$GitFallback
    )

    foreach ($name in $ForgitNames) {
        if (Get-Command $name -ErrorAction SilentlyContinue) {
            & $name @args
            return
        }
    }

    & $GitFallback
}

$forgitMode = $env:OOODNAKOV_FORGIT_ALIAS_MODE ?? "plain"

if ($forgitMode -eq "forgit") {
    function gd {
        Invoke-ForgitOrGit -ForgitNames @("forgit_diff") -GitFallback { git diff @args }
    }

    function gco {
        Invoke-ForgitOrGit -ForgitNames @("forgit_checkout") -GitFallback { git checkout @args }
    }

    function glo {
        Invoke-ForgitOrGit -ForgitNames @("forgit_log", "forgit") -GitFallback { git log --oneline --graph --decorate --all @args }
    }
} else {
    function gd {
        git diff @args
    }

    function gco {
        git checkout @args
    }

    function glo {
        git log --oneline --graph --decorate --all @args
    }
}

function Test-Command {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-EzaOrGetChildItem {
    param(
        [string[]]$EzaArguments = @(),
        [string[]]$Path = @()
    )

    if (Test-Command "eza") {
        eza @EzaArguments @Path
        return
    }

    Get-ChildItem -Force
}

function l {
    param([string[]]$Path)
    Invoke-EzaOrGetChildItem -EzaArguments @("-la", "--git", "--colour-scale", "all", "-g", "--smart-group", "--icons", "always") -Path $Path
}

function a {
    param([string[]]$Path)
    Invoke-EzaOrGetChildItem -EzaArguments @("-la", "--git", "--colour-scale", "all", "-g", "--smart-group", "--icons", "always") -Path $Path
}

function aa {
    param([string[]]$Path)
    Invoke-EzaOrGetChildItem -EzaArguments @("-la", "--git", "--colour-scale", "all", "-g", "--smart-group", "--icons", "always", "-s", "modified", "-r") -Path $Path
}

function e {
    exit
}

function myip {
    if (Test-Command "curl") {
        curl "https://wtfismyip.com/text"
        return
    }

    Invoke-RestMethod -Uri "https://wtfismyip.com/text"
}

function we {
    if (Test-Command "curl") {
        curl "https://wttr.in/"
        return
    }

    Invoke-RestMethod -Uri "https://wttr.in/"
}

function cheat {
    param(
        [Parameter(Position = 0)]
        [string]$Topic,
        [Parameter(Position = 1)]
        [string]$Subject,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Query = @()
    )

    if (-not $Topic) {
        Write-Error "Usage: cheat <topic> [subject] [query terms...]"
        return
    }

    $queryTail = if ($Query.Count -gt 0) { "+" + (($Query | Where-Object { $_ }) -join "+") } else { "" }
    $path = if ($Subject) { "$Topic/$Subject$queryTail" } else { $Topic }

    Invoke-RestMethod -Uri "https://cheat.sh/$path"
}

function ipgeo {
    param(
        [Parameter(Position = 0)]
        [string]$IpAddress
    )

    $ip = if ($IpAddress) { $IpAddress } else { (myip).ToString().Trim() }
    Invoke-RestMethod -Uri "http://api.db-ip.com/v2/free/$ip"
}

# Automatic Python Virtual Environment Activation (Port of auto-uv-env features)
function Get-OoodnakovAutoUvEnvMode {
    if ($env:OOODNAKOV_AUTO_UV_ENV_MODE -in @("disabled", "existing", "enabled", "quiet")) {
        return $env:OOODNAKOV_AUTO_UV_ENV_MODE
    }

    if ($env:AUTO_UV_ENV_QUIET -eq "1") {
        return "quiet"
    }

    return "existing"
}

function Test-OoodnakovAutoUvEnvQuiet {
    return (Get-OoodnakovAutoUvEnvMode) -eq "quiet"
}

function Clear-OoodnakovManagedVenv {
    param(
        [bool]$ShowMessage = $true
    )

    $wasUv = $global:__last_venv_was_uv
    if ($global:__managed_venv -and $env:VIRTUAL_ENV -eq $global:__managed_venv) {
        if (Get-Command deactivate -ErrorAction SilentlyContinue) {
            deactivate
        } else {
            Remove-Item Env:VIRTUAL_ENV -ErrorAction SilentlyContinue
        }

        if ($ShowMessage -and -not (Test-OoodnakovAutoUvEnvQuiet) -and (Test-InteractiveConsoleHost)) {
            $msg = if ($wasUv) { "⬇️  Deactivated UV environment" } else { "⬇️  Deactivated environment" }
            Write-Host $msg -ForegroundColor Gray
        }
    }

    $global:__managed_venv = $null
    $global:__last_venv_was_uv = $false
}

function Update-Venv {
    $mode = Get-OoodnakovAutoUvEnvMode

    if ($mode -eq "disabled") {
        Clear-OoodnakovManagedVenv -ShowMessage:$false
        return
    }

    # 1. Manual Override Protection: If user activated something manually, don't touch it
    if ($env:VIRTUAL_ENV -and $global:__managed_venv -and $env:VIRTUAL_ENV -ne $global:__managed_venv) {
        return
    }

    if ($global:__managed_venv -and $env:VIRTUAL_ENV -eq $global:__managed_venv -and -not (Test-Path -LiteralPath $global:__managed_venv)) {
        Clear-OoodnakovManagedVenv
    }

    $current = Get-Item .
    $projectRoot = $null
    $ignoreFound = $false

    # 2. Recursive Search with .auto-uv-env-ignore support
    while ($current) {
        if (Test-Path (Join-Path $current.FullName ".auto-uv-env-ignore")) {
            $ignoreFound = $true
            break
        }
        if (Test-Path (Join-Path $current.FullName "pyproject.toml")) {
            $projectRoot = $current.FullName
            break
        }
        $current = $current.Parent
    }

    if ($projectRoot -and -not $ignoreFound) {
        $venvPath = Join-Path $projectRoot ".venv"
        $venvFullName = if (Test-Path -LiteralPath $venvPath) { (Get-Item -LiteralPath $venvPath -Force).FullName } else { $null }

        if ($global:__managed_venv -and $env:VIRTUAL_ENV -eq $global:__managed_venv -and (-not $venvFullName -or $global:__managed_venv -ne $venvFullName)) {
            Clear-OoodnakovManagedVenv
        }

        # 3. Auto-Creation: enabled and quiet modes create missing .venv directories using uv.
        # Existing mode is default: activate only when the project already has .venv.
        if (-not $venvFullName) {
            if ($mode -eq "existing") {
                return
            }

            if (Get-Command uv -ErrorAction SilentlyContinue) {
                if (-not (Test-OoodnakovAutoUvEnvQuiet) -and (Test-InteractiveConsoleHost)) {
                    Write-Host "🔨 No .venv found. Creating one with uv..." -ForegroundColor Gray
                }
                & uv venv --quiet
                $venvFullName = (Get-Item -LiteralPath $venvPath -Force).FullName
            } else {
                return
            }
        }

        if ($env:VIRTUAL_ENV -ne $venvFullName) {
            # Detect if it's a UV project for the message
            $isUv = $false
            $content = Get-Content (Join-Path $projectRoot "pyproject.toml") -Raw -ErrorAction SilentlyContinue
            if ($content -and ($content -match "\[tool\.uv\]")) { $isUv = $true }

            # Robust version detection
            $version = "Unknown"
            $cfg = Join-Path $venvFullName "pyvenv.cfg"
            if (Test-Path $cfg) {
                $cfgContent = Get-Content $cfg -ErrorAction SilentlyContinue
                $vLine = $cfgContent | Where-Object { $_ -match "^version(_info)?\s*=" } | Select-Object -First 1
                if ($vLine -and ($vLine -match "=\s*([\d\.]+)")) { $version = $matches[1] }
            }

            if ($version -eq "Unknown") {
                foreach ($relativePython in @("Scripts\python.exe", "bin/python")) {
                    $pyExe = Join-Path $venvFullName $relativePython
                    if (Test-Path -LiteralPath $pyExe) {
                        $vInfo = & $pyExe --version 2>&1
                        if ($vInfo -match "([\d\.]+)") { $version = $matches[1] }
                        break
                    }
                }
            }

            $activateScript = Join-Path $venvFullName "Scripts\Activate.ps1"
            if (-not (Test-Path -LiteralPath $activateScript)) {
                $activateScript = Join-Path $venvFullName "bin/Activate.ps1"
            }
            if (-not (Test-Path -LiteralPath $activateScript)) {
                return
            }

            . $activateScript
            $global:__managed_venv = $env:VIRTUAL_ENV
            $global:__last_venv_was_uv = $isUv

            if (-not (Test-OoodnakovAutoUvEnvQuiet) -and (Test-InteractiveConsoleHost)) {
                if ($isUv) { Write-Host "🚀 UV environment activated (Python $version)" -ForegroundColor Cyan }
                else { Write-Host "🚀 Environment activated (Python $version)" -ForegroundColor Green }
            }
        }
    } elseif ($global:__managed_venv -and $env:VIRTUAL_ENV -eq $global:__managed_venv) {
        # 4. Managed Deactivation: Only deactivate if we were the ones who activated it
        Clear-OoodnakovManagedVenv
    }
}

# Attach to Set-Location
function Set-Location-With-Venv {
    # If no arguments provided, default to HOME like standard cd
    if ($args.Count -eq 0) {
        Microsoft.PowerShell.Management\Set-Location $HOME
    } else {
        Microsoft.PowerShell.Management\Set-Location @args
    }
    Update-Venv
}

Set-Alias cd Set-Location-With-Venv -Option AllScope -Force
Set-Alias sl Set-Location-With-Venv -Option AllScope -Force

# Initial check
Update-Venv
