$ConfigRoot = Join-Path $HOME ".config/ooodnakov"
$PromptConfig = Join-Path $HOME ".config/ohmyposh/ooodnakov.omp.json"
$SharedEnv = Join-Path $ConfigRoot "env/common.ps1"
$LocalEnv = Join-Path $ConfigRoot "local/env.ps1"
$LocalBin = Join-Path $HOME ".local/bin"

if (Test-Path $LocalBin) {
    $pathParts = @($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ })
    if ($pathParts -notcontains $LocalBin) {
        $env:PATH = "$LocalBin$([IO.Path]::PathSeparator)$env:PATH"
    }
}

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config $PromptConfig | Invoke-Expression
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
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

if (Get-Module -ListAvailable -Name posh-git) {
    Import-Module posh-git -ErrorAction SilentlyContinue
}

if (Get-Module -ListAvailable -Name PSFzf) {
    Import-Module PSFzf -ErrorAction SilentlyContinue
}

if (Get-Module -ListAvailable -Name PSReadLine) {
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    Set-PSReadLineOption -PredictionViewStyle InlineView
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Chord Alt+b -Function BackwardWord
    Set-PSReadLineKeyHandler -Chord Alt+f -Function ForwardWord

    Set-Alias oooconf oooconf.ps1 -ErrorAction SilentlyContinue

    if (Get-Command Set-PsFzfOption -ErrorAction SilentlyContinue) {
        $psFzfArgs = @{
            PSReadlineChordProvider       = 'Ctrl+t'
            PSReadlineChordReverseHistory = 'Ctrl+r'
            TabExpansion                  = ($env:OOODNAKOV_PSFZF_TAB -ne 'disabled')
            GitKeyBindings                = ($env:OOODNAKOV_PSFZF_GIT -ne 'disabled')
        }

        if (Get-Command fd -ErrorAction SilentlyContinue) {
            $psFzfArgs.EnableFd = $true
        }
        Set-PSReadLineKeyHandler -Key Tab -ScriptBlock { Invoke-FzfTabCompletion }
        Set-PsFzfOption @psFzfArgs
    }
}

Set-Alias ll Get-ChildItem

function gs {
    git status @args
}

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
$forgitAvailable = (Test-AnyCommand -Names @("forgit", "forgit_log", "forgit_diff", "forgit_checkout"))

if ($forgitMode -eq "forgit" -and $forgitAvailable) {
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
        [string[]]$EzaArguments = @()
    )

    if (Test-Command "eza") {
        eza @EzaArguments
        return
    }

    Get-ChildItem -Force
}

function l {
    Invoke-EzaOrGetChildItem -EzaArguments @("-la", "--git", "--colour-scale", "all", "-g", "--smart-group", "--icons", "always")
}

function a {
    Invoke-EzaOrGetChildItem -EzaArguments @("-la", "--git", "--colour-scale", "all", "-g", "--smart-group", "--icons", "always")
}

function aa {
    Invoke-EzaOrGetChildItem -EzaArguments @("-la", "--git", "--colour-scale", "all", "-g", "--smart-group", "--icons", "always", "-s", "modified", "-r")
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

# Automatic Python Virtual Environment Activation
function Update-Venv {
    $current = Get-Item .
    $venvPath = $null

    # Search upwards for .venv\Scripts\Activate.ps1
    while ($current) {
        $check = Join-Path $current.FullName ".venv\Scripts\Activate.ps1"
        if (Test-Path $check) {
            $venvPath = Join-Path $current.FullName ".venv"
            break
        }
        $current = $current.Parent
    }

    if ($venvPath) {
        $venvFullName = (Get-Item $venvPath).FullName
        if ($env:VIRTUAL_ENV -ne $venvFullName) {
            . "$venvFullName\Scripts\Activate.ps1"
        }
    } elseif ($env:VIRTUAL_ENV) {
        # Deactivate if no .venv is found in the current folder hierarchy
        if (Get-Command deactivate -ErrorAction SilentlyContinue) {
            deactivate
        }
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
