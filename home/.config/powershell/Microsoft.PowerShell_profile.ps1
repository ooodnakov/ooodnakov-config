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

if (Test-Path $SharedEnv) {
    . $SharedEnv
}

if (Test-Path $LocalEnv) {
    . $LocalEnv
}

if (Get-Module -ListAvailable -Name posh-git) {
    Import-Module posh-git -ErrorAction SilentlyContinue

    function Set-PoshGitStatus {
        $global:GitStatus = Get-GitStatus
        $env:POSH_GIT_STRING = Write-GitStatus -Status $global:GitStatus
    }

    New-Alias -Name Set-PoshContext -Value Set-PoshGitStatus -Scope Global -Force
}

if (Get-Module -ListAvailable -Name PSFzf) {
    Import-Module PSFzf -ErrorAction SilentlyContinue
}

if (Get-Module -ListAvailable -Name PSReadLine) {
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Chord Alt+b -Function BackwardWord
    Set-PSReadLineKeyHandler -Chord Alt+f -Function ForwardWord

    if (Get-Command Set-PsFzfOption -ErrorAction SilentlyContinue) {
        $psFzfArgs = @{
            PSReadlineChordProvider       = 'Ctrl+t'
            PSReadlineChordReverseHistory = 'Ctrl+r'
            TabExpansion                  = $true
            GitKeyBindings                = $true
        }

        if (Get-Command fd -ErrorAction SilentlyContinue) {
            $psFzfArgs.EnableFd = $true
        }

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
