$env:EDITOR = if ($env:EDITOR) { $env:EDITOR } else { "nvim" }
$env:VISUAL = if ($env:VISUAL) { $env:VISUAL } else { $env:EDITOR }
$env:PAGER = if ($env:PAGER) { $env:PAGER } else { "less" }
$env:OOODNAKOV_CONFIG_HOME = if ($env:OOODNAKOV_CONFIG_HOME) { $env:OOODNAKOV_CONFIG_HOME } else { Join-Path $HOME ".config/ooodnakov" }
$env:OOODNAKOV_SHARE_HOME = if ($env:OOODNAKOV_SHARE_HOME) { $env:OOODNAKOV_SHARE_HOME } else { Join-Path $HOME ".local/share/ooodnakov-config" }
$env:OOODNAKOV_STATE_HOME = if ($env:OOODNAKOV_STATE_HOME) { $env:OOODNAKOV_STATE_HOME } else { Join-Path $HOME ".local/state/ooodnakov-config" }
$env:OOODNAKOV_CACHE_HOME = if ($env:OOODNAKOV_CACHE_HOME) { $env:OOODNAKOV_CACHE_HOME } else { Join-Path $HOME ".cache/ooodnakov-config" }

function Add-PathEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathEntry
    )

    if (-not (Test-Path $PathEntry)) {
        return
    }

    $pathParts = @($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ })
    if ($pathParts -notcontains $PathEntry) {
        $env:PATH = "$PathEntry$([IO.Path]::PathSeparator)$env:PATH"
    }
}

$localBin = Join-Path $HOME ".local/bin"
$cargoBin = Join-Path $HOME ".cargo/bin"
$shareBin = Join-Path $env:OOODNAKOV_SHARE_HOME "bin"
$npmBin = Join-Path $HOME ".npm/bin"

Add-PathEntry -PathEntry $localBin
Add-PathEntry -PathEntry $cargoBin
Add-PathEntry -PathEntry $shareBin
Add-PathEntry -PathEntry $npmBin

$pnpmHome = if ($env:PNPM_HOME) { $env:PNPM_HOME } else { Join-Path $HOME ".local/share/pnpm" }
$env:PNPM_HOME = $pnpmHome
Add-PathEntry -PathEntry $pnpmHome

if (Get-Command uv -ErrorAction SilentlyContinue) {
    (& uv generate-shell-completion powershell) | Out-String | Invoke-Expression
}

if (Get-Command rustup -ErrorAction SilentlyContinue) {
    (& rustup completions powershell) | Out-String | Invoke-Expression
}

if (Get-Command gum -ErrorAction SilentlyContinue) {
    (& gum completion powershell) | Out-String | Invoke-Expression
}

if (Get-Command bw -ErrorAction SilentlyContinue) {
    (& bw completion --shell powershell) | Out-String | Invoke-Expression
}

if (Get-Command glow -ErrorAction SilentlyContinue) {
    (& glow completion powershell) | Out-String | Invoke-Expression
}

if (Get-Command fd -ErrorAction SilentlyContinue) {
    (& fd --gen-completions powershell) | Out-String | Invoke-Expression
}

if (Get-Command direnv -ErrorAction SilentlyContinue) {
    (& direnv hook pwsh) | Out-String | Invoke-Expression
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    (& zoxide init pwsh) | Out-String | Invoke-Expression
}

$oooconfCompletions = Join-Path $env:OOODNAKOV_CONFIG_HOME "completions/oooconf-completions.ps1"
if (Test-Path $oooconfCompletions) {
    . $oooconfCompletions
}

# Load pnpm completions
$PnpmCompletions = Join-Path $env:OOODNAKOV_CONFIG_HOME "completions/pnpm-completions.ps1"
if (Test-Path $PnpmCompletions) {
    . $PnpmCompletions
}

$markerInit = Join-Path $env:OOODNAKOV_SHARE_HOME "marker/marker.ps1"
if (Test-Path $markerInit) {
    . $markerInit
}
