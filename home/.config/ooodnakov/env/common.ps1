$env:EDITOR = if ($env:EDITOR) { $env:EDITOR } else { "nvim" }
$env:VISUAL = if ($env:VISUAL) { $env:VISUAL } else { $env:EDITOR }
$env:PAGER = if ($env:PAGER) { $env:PAGER } else { "less" }
$env:XDG_CONFIG_HOME = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME ".config" }
$env:XDG_DATA_HOME = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path $HOME ".local/share" }
$env:XDG_STATE_HOME = if ($env:XDG_STATE_HOME) { $env:XDG_STATE_HOME } else { Join-Path $HOME ".local/state" }
$env:XDG_CACHE_HOME = if ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME } else { Join-Path $HOME ".cache" }
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

function Get-DirenvConfigRoot {
    if ($env:XDG_CONFIG_HOME) {
        return Join-Path $env:XDG_CONFIG_HOME "direnv"
    }
    if ($IsWindows -and $env:APPDATA) {
        return Join-Path $env:APPDATA "direnv"
    }
    return Join-Path $HOME ".config/direnv"
}

function Invoke-CompletionScript {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Generator
    )

    try {
        $scriptText = (& $Generator 2>$null) | Out-String
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($scriptText)) {
            Invoke-Expression $scriptText
        }
    } catch {
        # Keep shell startup usable when a tool does not support PowerShell completions.
    }
}

if (Get-Command uv -ErrorAction SilentlyContinue) {
    Invoke-CompletionScript { uv generate-shell-completion powershell }
}

if (Get-Command rustup -ErrorAction SilentlyContinue) {
    Invoke-CompletionScript { rustup completions powershell }
}

if (Get-Command gum -ErrorAction SilentlyContinue) {
    Invoke-CompletionScript { gum completion powershell }
}

if (Get-Command bw -ErrorAction SilentlyContinue) {
    Invoke-CompletionScript { bw completion --shell powershell }
}

if (Get-Command glow -ErrorAction SilentlyContinue) {
    Invoke-CompletionScript { glow completion powershell }
}

if (Get-Command fd -ErrorAction SilentlyContinue) {
    Invoke-CompletionScript { fd --gen-completions powershell }
}

if (Get-Command direnv -ErrorAction SilentlyContinue) {
    $gitBash = "C:\Program Files\Git\bin\bash.exe"
    if (Test-Path $gitBash) {
        $env:DIRENV_BASH = $gitBash
    }

    # Normalize common Windows env var names to all-caps for direnv compatibility.
    # This prevents direnv from constantly trying to "fix" the case (e.g., Path -> PATH)
    # which can be noisy and sometimes disrupts other shell hooks on Windows.
    $varsToNormalize = @("Path", "ComSpec", "SystemRoot", "windir", "ProgramFiles", "CommonProgramFiles", "SystemDrive", "TEMP", "TMP", "HOME")
    foreach ($v in $varsToNormalize) {
        $envVar = Get-ChildItem "env:/$v" -ErrorAction SilentlyContinue
        if ($null -ne $envVar) {
            $u = $v.ToUpperInvariant()
            if ($envVar.Name -cne $u) {
                $val = $envVar.Value
                Remove-Item "env:/$($envVar.Name)"
                Set-Content "env:/$u" $val
            }
        }
    }

    $direnvConfigRoot = Get-DirenvConfigRoot
    if (-not (Test-Path -LiteralPath $direnvConfigRoot)) {
        New-Item -ItemType Directory -Path $direnvConfigRoot -Force | Out-Null
    }
    Invoke-CompletionScript { direnv hook pwsh }
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-CompletionScript { zoxide init powershell }
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
