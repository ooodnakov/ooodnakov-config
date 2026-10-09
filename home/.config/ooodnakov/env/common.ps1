$env:EDITOR = if ($env:EDITOR) { $env:EDITOR } else { "nvim" }
$env:VISUAL = if ($env:VISUAL) { $env:VISUAL } else { $env:EDITOR }
$env:PAGER = if ($env:PAGER) { $env:PAGER } else { "less" }
# Unix-only: SUDO_EDITOR + snvim alias live in common.sh
$env:XDG_CONFIG_HOME = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME ".config" }
$env:XDG_DATA_HOME = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path $HOME ".local/share" }
$env:XDG_STATE_HOME = if ($env:XDG_STATE_HOME) { $env:XDG_STATE_HOME } else { Join-Path $HOME ".local/state" }
$env:XDG_CACHE_HOME = if ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME } else { Join-Path $HOME ".cache" }
$env:OOODNAKOV_CONFIG_HOME = if ($env:OOODNAKOV_CONFIG_HOME) { $env:OOODNAKOV_CONFIG_HOME } else { Join-Path $HOME ".config/ooodnakov" }
$env:OOODNAKOV_SHARE_HOME = if ($env:OOODNAKOV_SHARE_HOME) { $env:OOODNAKOV_SHARE_HOME } else { Join-Path $HOME ".local/share/ooodnakov-config" }
$env:OOODNAKOV_STATE_HOME = if ($env:OOODNAKOV_STATE_HOME) { $env:OOODNAKOV_STATE_HOME } else { Join-Path $HOME ".local/state/ooodnakov-config" }
$env:OOODNAKOV_CACHE_HOME = if ($env:OOODNAKOV_CACHE_HOME) { $env:OOODNAKOV_CACHE_HOME } else { Join-Path $HOME ".cache/ooodnakov-config" }
$env:YAZI_CONFIG_HOME = if ($env:YAZI_CONFIG_HOME) { $env:YAZI_CONFIG_HOME } else { Join-Path $HOME ".config/yazi" }
$ENV:PILENS_DATA_DIR = Join-Path $HOME ".pi-lens" "data"
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
$bunBin = Join-Path $HOME ".bun/bin"
$buncacheBin = Join-Path $HOME ".cache/.bun/bin"

Add-PathEntry -PathEntry $localBin
Add-PathEntry -PathEntry $cargoBin
Add-PathEntry -PathEntry $shareBin
Add-PathEntry -PathEntry $npmBin
Add-PathEntry -PathEntry $bunBin
Add-PathEntry -PathEntry $buncacheBin

foreach ($brewBin in @("/opt/homebrew/bin", "/usr/local/bin", "/home/linuxbrew/.linuxbrew/bin")) {
    if (Test-Path (Join-Path $brewBin "brew")) {
        Add-PathEntry -PathEntry $brewBin
        break
    }
}

$pnpmHome = if ($env:PNPM_HOME) { $env:PNPM_HOME } else { Join-Path $HOME ".local/share/pnpm" }
$env:PNPM_HOME = $pnpmHome
Add-PathEntry -PathEntry $pnpmHome
Add-PathEntry -PathEntry (Join-Path $pnpmHome "bin")

# fnm (Fast Node Manager) — match its installer location on Windows.
if (Get-Command fnm -ErrorAction SilentlyContinue) {
    $fnmDir = if ($env:FNM_DIR) { $env:FNM_DIR } else { Join-Path $HOME ".local/share/fnm" }
    $env:FNM_DIR = $fnmDir
    $fnmMultishell = Join-Path $env:LOCALAPPDATA "fnm_multishells"
    if (-not (Test-Path $fnmMultishell)) {
        New-Item -ItemType Directory -Path $fnmMultishell -Force | Out-Null
    }
    $env:FNM_MULTISHELL_PATH = $fnmMultishell
    $env:FNM_NODE_VERSION_BEFORE_INSTALL = ""
    Add-PathEntry -PathEntry (Join-Path $HOME ".local/share/fnm/node-versions" "installation")
    try {
        Invoke-Expression (& fnm env --use-on-cd --shell powershell)
    } catch {
        # Keep shell startup usable when fnm env fails (e.g. no installed Node yet).
    }
}

if (-not (Get-Command o -ErrorAction SilentlyContinue) -and (Get-Command oooconf -ErrorAction SilentlyContinue)) {
    function global:o {
        oooconf @args
    }
}

function Get-DirenvConfigRoot {
    if ($env:XDG_CONFIG_HOME) {
        return Join-Path $env:XDG_CONFIG_HOME "direnv"
    }
    if ($IsWindows -and $env:APPDATA) {
        return Join-Path $env:APPDATA "direnv"
    }
    return Join-Path $HOME ".config/direnv"
}

function Invoke-CachedCompletionScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Tool,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Generator
    )

    $toolCommand = Get-Command $Tool -ErrorAction SilentlyContinue
    if (-not $toolCommand) {
        return
    }

    $cacheFile = Join-Path $env:OOODNAKOV_CACHE_HOME "completions/$Name.ps1"
    $cacheStale = -not (Test-Path -LiteralPath $cacheFile)
    if (-not $cacheStale) {
        $toolItem = Get-Item -LiteralPath $toolCommand.Source -ErrorAction SilentlyContinue
        $cacheItem = Get-Item -LiteralPath $cacheFile
        $cacheStale = $null -ne $toolItem -and $toolItem.LastWriteTime -gt $cacheItem.LastWriteTime
    }

    if ($cacheStale) {
        try {
            $scriptText = (& $Generator 2>$null) | Out-String
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($scriptText)) {
                New-Item -ItemType Directory -Path (Split-Path -Parent $cacheFile) -Force | Out-Null
                Set-Content -LiteralPath $cacheFile -Value $scriptText -NoNewline
            }
        } catch {
            # Keep shell startup usable when a tool does not support PowerShell completions.
        }
    }

    if (Test-Path -LiteralPath $cacheFile) {
        . $cacheFile
    }
}

Invoke-CachedCompletionScript -Name uv -Tool uv -Generator { uv generate-shell-completion powershell }

Invoke-CachedCompletionScript -Name rustup -Tool rustup -Generator { rustup completions powershell }

Invoke-CachedCompletionScript -Name glow -Tool glow -Generator { glow completion powershell }

Invoke-CachedCompletionScript -Name fd -Tool fd -Generator { fd --gen-completions powershell }

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
    Invoke-CachedCompletionScript -Name direnv-hook -Tool direnv -Generator { direnv hook pwsh }
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
