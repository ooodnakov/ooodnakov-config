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
if (-not $env:YAZI_FILE_ONE) {
    $programFiles = if ($env:ProgramFiles) { $env:ProgramFiles } else { "C:\Program Files" }
    $yaziFileOne = Join-Path $programFiles "Git\usr\bin\file.exe"
    if (Test-Path $yaziFileOne) { $env:YAZI_FILE_ONE = $yaziFileOne }
}
$ENV:PILENS_DATA_DIR = Join-Path $HOME ".pi-lens" "data"
$script:__oooconfPathParts = $null
$script:__oooconfPathValue = $null
function Add-PathEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathEntry
    )

    if (-not (Test-Path $PathEntry)) {
        return
    }

    # Splitting PATH for every entry costs more than the membership test, so
    # keep a case-insensitive set of the current entries and rebuild it only
    # when PATH changed underneath us.
    if ($null -eq $script:__oooconfPathParts -or $script:__oooconfPathValue -cne $env:PATH) {
        $script:__oooconfPathParts = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($part in ($env:PATH -split [IO.Path]::PathSeparator)) {
            if ($part) { [void]$script:__oooconfPathParts.Add($part) }
        }
        $script:__oooconfPathValue = $env:PATH
    }

    if ($script:__oooconfPathParts.Add($PathEntry)) {
        $env:PATH = "$PathEntry$([IO.Path]::PathSeparator)$env:PATH"
        $script:__oooconfPathValue = $env:PATH
    }
}

$localBin = Join-Path $HOME ".local/bin"
$cargoBin = Join-Path $HOME ".cargo/bin"
$shareBin = Join-Path $env:OOODNAKOV_SHARE_HOME "bin"
# npm globals stay independent of whichever Node.js runtime is active (pnpm
# runtime, a version manager such as fnm, or a system package); pnpm globals
# keep their own bin dir through PNPM_HOME below.
$env:NPM_CONFIG_PREFIX = if ($env:NPM_CONFIG_PREFIX) { $env:NPM_CONFIG_PREFIX } else { Join-Path $HOME ".npm-global" }
$npmBin = Join-Path $env:NPM_CONFIG_PREFIX "bin"
# Add-PathEntry skips missing directories; create the prefix so the first
# `npm install -g` is immediately runnable in the same session.
if (-not (Test-Path $npmBin)) {
    New-Item -ItemType Directory -Path $npmBin -Force | Out-Null
}
$bunBin = Join-Path $HOME ".bun/bin"
$buncacheBin = Join-Path $HOME ".cache/.bun/bin"

Add-PathEntry -PathEntry $localBin
Add-PathEntry -PathEntry $cargoBin
Add-PathEntry -PathEntry $shareBin
Add-PathEntry -PathEntry $npmBin
Add-PathEntry -PathEntry $bunBin
Add-PathEntry -PathEntry $buncacheBin

# Homebrew lives outside Windows; the three Test-Path calls are pure overhead there.
if (-not $IsWindows) {
    foreach ($brewBin in @("/opt/homebrew/bin", "/usr/local/bin", "/home/linuxbrew/.linuxbrew/bin")) {
        if (Test-Path (Join-Path $brewBin "brew")) {
            Add-PathEntry -PathEntry $brewBin
            break
        }
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

# A generated completion script registers its completer while being dot-sourced,
# so a large file (uv's is ~750 KB) costs ~100 ms of parsing on every startup.
# Register a stub instead and capture/execute the real completer on the first
# Tab press; the stub then forwards to the exact same scriptblock.
function Register-LazyNativeCompletion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $lazyCompletion = @{ Path = $Path; Script = $null; Loaded = $false; Names = $null }
    Register-ArgumentCompleter -Native -CommandName $CommandName -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)

        if (-not $lazyCompletion.Loaded) {
            $lazyCompletion.Loaded = $true
            $global:__oooconfLazyCapture = $null
            $global:__oooconfLazyNames = [System.Collections.Generic.List[string]]::new()
            # Shadow the registration so the generated file hands over its
            # scriptblock instead of registering a second completer.
            function global:Register-ArgumentCompleter {
                param(
                    [switch]$Native,
                    [string[]]$CommandName,
                    [scriptblock]$ScriptBlock
                )
                $global:__oooconfLazyCapture = $ScriptBlock
                if ($CommandName) { $global:__oooconfLazyNames.AddRange($CommandName) }
            }
            try {
                . $lazyCompletion.Path
            } finally {
                Remove-Item function:\Register-ArgumentCompleter -ErrorAction SilentlyContinue
            }
            $lazyCompletion.Names = $global:__oooconfLazyNames
            $lazyCompletion.Script = $global:__oooconfLazyCapture
            $global:__oooconfLazyCapture = $null
            $global:__oooconfLazyNames = $null

            # Unexpected generated format (not a single completer for this
            # command): fall back to letting the script register itself.
            if ($null -eq $lazyCompletion.Script -or $lazyCompletion.Names.Count -ne 1 -or $lazyCompletion.Names[0] -ne $CommandName) {
                $lazyCompletion.Script = $null
                . $lazyCompletion.Path
            }
        }

        if ($lazyCompletion.Script) {
            & $lazyCompletion.Script $wordToComplete $commandAst $cursorPosition
        }
    }.GetNewClosure()
}

function Invoke-CachedCompletionScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Tool,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Generator,
        [switch]$Lazy
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

    if (-not (Test-Path -LiteralPath $cacheFile)) {
        return
    }

    if ($Lazy) {
        Register-LazyNativeCompletion -CommandName $Name -Path $cacheFile
    } else {
        . $cacheFile
    }
}

# uv's completion file is by far the largest generated script; load it on demand.
Invoke-CachedCompletionScript -Name uv -Tool uv -Lazy -Generator { uv generate-shell-completion powershell }

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
    # One dictionary beats a Get-ChildItem env:/ lookup per name (each one
    # crosses the provider layer).
    $envNames = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in [Environment]::GetEnvironmentVariables().Keys) {
        $envNames[[string]$name] = [string]$name
    }
    foreach ($v in $varsToNormalize) {
        $actualName = $null
        if (-not $envNames.TryGetValue($v, [ref]$actualName)) {
            continue
        }
        $u = $v.ToUpperInvariant()
        if ($actualName -cne $u) {
            $val = [Environment]::GetEnvironmentVariable($actualName)
            [Environment]::SetEnvironmentVariable($actualName, $null)
            [Environment]::SetEnvironmentVariable($u, $val)
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
