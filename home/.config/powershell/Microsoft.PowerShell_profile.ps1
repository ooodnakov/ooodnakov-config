$ConfigRoot = Join-Path $HOME ".config/ooodnakov"
$PromptConfig = Join-Path $HOME ".config/ohmyposh/ooodnakov.omp.json"
$SharedEnv = Join-Path $ConfigRoot "env/common.ps1"
$LocalEnv = Join-Path $ConfigRoot "local/env.ps1"

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config $PromptConfig | Invoke-Expression
}

if (Test-Path $SharedEnv) {
    . $SharedEnv
}

if (Test-Path $LocalEnv) {
    . $LocalEnv
}

Set-Alias ll Get-ChildItem

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
