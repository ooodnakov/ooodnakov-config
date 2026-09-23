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
    Invoke-EzaOrGetChildItem -EzaArguments @("-la", "--git", "--color-scale", "all", "-g", "--smart-group", "--icons", "always") -Path $Path
}

function a {
    param([string[]]$Path)
    Invoke-EzaOrGetChildItem -EzaArguments @("-la", "--git", "--color-scale", "all", "-g", "--smart-group", "--icons", "always") -Path $Path
}

function aa {
    param([string[]]$Path)
    Invoke-EzaOrGetChildItem -EzaArguments @("-la", "--git", "--color-scale", "all", "-g", "--smart-group", "--icons", "always", "-s", "modified", "-r") -Path $Path
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

# Import the Chocolatey Profile that contains the necessary code to enable
# tab-completions to function for `choco`.
# Be aware that if you are missing these lines from your profile, tab completion
# for `choco` will not function.
# See https://ch0.co/tab-completion for details.
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path($ChocolateyProfile)) {
  Import-Module "$ChocolateyProfile"
}

# DO NOT MODIFY -- coreutils -- 60b36fc6-2d59-49df-be51-28dd2f4c3c9a
# vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
# Inlining the template into the profile shaves off ~10ms (25%).
$script:__COREUTILS__ = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('arch','b2sum','base32','base64','basename','basenc','cat','cksum','comm','cp','csplit','cut','date','df','dirname','du','echo','env','expr','factor','false','find','fmt','fold','grep','head','hostname','join','la','link','ln','ls','md5sum','mkdir','mktemp','mv','nl','nproc','numfmt','od','paste','pathchk','pr','printenv','printf','ptx','pwd','readlink','realpath','rm','rmdir','seq','sha1sum','sha224sum','sha256sum','sha384sum','sha512sum','shuf','sleep','sort','split','stat','sum','tac','tail','tee','test','touch','tr','true','truncate','tsort','unexpand','uniq','unlink','uptime','wc','xargs','yes'),
    [System.StringComparer]::OrdinalIgnoreCase
)

$script:__COREUTILS_FAST_SKIP__ = [regex]::new(
    '\b(?:' + ($script:__COREUTILS__ -join '|') + ')\b',
    [System.Text.RegularExpressions.RegexOptions]::Compiled -bor `
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)

# Casting the scriptblock to Func<Ast,bool> once and reusing it avoids the
# per-FindAll scriptblock-to-delegate wrapping overhead (~1.7x faster).
$script:__COREUTILS_CMD_PREDICATE__ = [System.Func[System.Management.Automation.Language.Ast, bool]] {
    param($n) $n -is [System.Management.Automation.Language.CommandAst]
}

$script:__COREUTILS_ARG_SPECIAL__ = [char[]] @("'", '"', '`', '$')

# Wrap arguments into quotes. By being a function we can properly handle $variables.
# As per MSVCRT, any `\` before `"` must be doubled to escape them.
function global:__coreutils_q {
    param($s)
    '"' + (([string]$s) -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

# PowerShell tokenizes `*"a"*` as [BareWord] instead of the expected [DoubleQuoted, BareWord, DoubleQuoted].
# To work around that we use... regex. Group 1 = 'single', 2 = "double", 3 = `escape, 4 = bare run.
$script:__COREUTILS_ARG_RX__ = [regex]::new(
    "'((?:[^']|'')*)'|""((?:[^""``]|""""|``.)*)""|``(.)|([^'""``]+)",
    [System.Text.RegularExpressions.RegexOptions]::Compiled
)
$script:__COREUTILS_ARG_EVAL__ = [System.Text.RegularExpressions.MatchEvaluator] {
    param($m)
    if ($m.Groups[1].Success) {
        # Single-quoted: literal. PS '' -> ', then MSVCRT-quote.
        $body = $m.Groups[1].Value.Replace("''", "'")
        if ($body -match '^(.*?)(\\+)$') {
            return '"' + ($matches[1] -replace '(\\*)"', '$1$1\"') + '"' + $matches[2]
        }
        return '"' + ($body -replace '(\\*)"', '$1$1\"') + '"'
    }
    if ($m.Groups[2].Success) {
        # Double-quoted: collapse PS quote-escapes to raw " / ', let ExpandString
        # resolve `n / `t / $var, then MSVCRT-quote.
        $body = $m.Groups[2].Value.
        Replace('`"', '"').
        Replace("``'", "'").
        Replace('""', '"')
        $body = $ExecutionContext.InvokeCommand.ExpandString($body)
        if ($body -match '^(.*?)(\\+)$') {
            return '"' + ($matches[1] -replace '(\\*)"', '$1$1\"') + '"' + $matches[2]
        }
        return '"' + ($body -replace '(\\*)"', '$1$1\"') + '"'
    }
    if ($m.Groups[3].Success) {
        # Backtick-escaped char outside a string: " -> \"; everything else
        # becomes a one-char quoted region so glob metas stay literal.
        $c = $m.Groups[3].Value
        if ($c -eq '"') {
            return '\"'
        }
        return '"' + $c + '"'
    }
    # Bare run: passed through unquoted so coreutils can glob it; expand $vars.
    return $ExecutionContext.InvokeCommand.ExpandString($m.Groups[4].Value)
}

# 0: not tested, 1: coreutils not installed, 2: coreutils installed.
$script:__COREUTILS_CMD_DIR_TEST__ = 0

# PSConsoleHostReadLine override that rewrites coreutils command names to their
# .cmd equivalents after PSReadLine returns (history keeps the original).
#
# Why .cmd over .exe: PSNativeCommandArgumentPassing = 'Windows' results in a behavior
# where passing bare quotes to CreateProcess() is impossible. This prevents us from
# passing "*" as "*" to coreutils and instead will be given as a bare *.
# This causes it to treat it as a glob pattern. "*.cmd" files however are automatically
# treated as PSNativeCommandArgumentPassing = 'Legacy', which preserves quotes.
# It is the only possible workaround and the only way coreutils can work at all.
function PSConsoleHostReadLine {
    [System.Diagnostics.DebuggerHidden()]
    param()

    $lastRunStatus = $?
    Microsoft.PowerShell.Core\Set-StrictMode -Off
    $line = [Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($host.Runspace, $ExecutionContext, $lastRunStatus)

    # If the line contains no coreutils name, we don't need to parse the AST at all.
    if (-not $script:__COREUTILS_FAST_SKIP__.IsMatch($line)) {
        return $line
    }

    # Roamed/synced profiles can load this snippet on machines where coreutils is not installed.
    # Test for the existence of the command directory once and remember the result.
    if ($script:__COREUTILS_CMD_DIR_TEST__ -eq 0) {
        $script:__COREUTILS_CMD_DIR_TEST__ = 1
        if (Test-Path -LiteralPath 'C:\Program Files\coreutils\cmd\' -PathType Container -ErrorAction Ignore) {
            $script:__COREUTILS_CMD_DIR_TEST__ = 2
        }
    }
    if ($script:__COREUTILS_CMD_DIR_TEST__ -ne 2) {
        return $line
    }

    $ast = [System.Management.Automation.Language.Parser]::ParseInput($line, [ref]$null, [ref]$null)
    $commands = $ast.FindAll($script:__COREUTILS_CMD_PREDICATE__, $true)

    # Process right-to-left so earlier offsets stay valid after each splice.
    # In-place reverse beats Sort-Object for the typical 1-command line.
    if ($commands.Count -gt 1) {
        $commands = [System.Collections.Generic.List[object]]::new($commands)
        $commands.Reverse()
    }

    foreach ($cmd in $commands) {
        $name = $cmd.GetCommandName()
        if (!$name) {
            continue
        }

        $baseName = $name
        if ($name.EndsWith('.exe') -or $name.EndsWith('.cmd')) {
            $baseName = $name.Substring(0, $name.Length - 4)
        }
        if (!$script:__COREUTILS__.Contains($baseName)) {
            continue
        }

        # ls/la get colour + listing flags injected; la also rewrites to ls.
        $cmdElement = $cmd.CommandElements[0]
        $start = $cmdElement.Extent.StartOffset
        $end = $cmdElement.Extent.EndOffset
        $replacement = "& 'C:\Program Files\coreutils\cmd\"

        switch ($baseName) {
            'la' { $replacement += "ls.cmd' --color=auto -AFhl" }
            'ls' { $replacement += "ls.cmd' --color=auto" }
            default { $replacement += "$baseName.cmd'" }
        }

        # Walk command elements, merging adjacent ones whose extents touch
        # (e.g. `'a'*` parses as [SingleQuoted, BareWord] but is one shell word).
        # The inverse case `*'a'*` parses as a single BareWord whose text
        # contains the embedded quotes, which is why AST-only analysis
        # isn't enough and we still need to re-tokenize the source span.
        $argsStart = $end
        $argsEnd = $cmd.Extent.EndOffset
        $rewrittenArgs = ''
        $elements = $cmd.CommandElements
        $count = $elements.Count
        $i = 1
        while ($i -lt $count) {
            $first = $elements[$i]
            $wordStart = $first.Extent.StartOffset
            $wordEnd = $first.Extent.EndOffset
            $merged = $false
            while ($i + 1 -lt $count -and $elements[$i + 1].Extent.StartOffset -eq $wordEnd) {
                $i++
                $wordEnd = $elements[$i].Extent.EndOffset
                $merged = $true
            }
            $source = $line.Substring($wordStart, $wordEnd - $wordStart)
            $rewrittenArgs += $line.Substring($argsStart, $wordStart - $argsStart)
            $argsStart = $wordEnd
            # IndexOfAny beats running the regex per arg.
            if ($source.IndexOfAny($script:__COREUTILS_ARG_SPECIAL__) -lt 0) {
                $rewrittenArgs += $source
                $i++
                continue
            }
            # A single un-merged PS expression that needs $var resolution
            # (bare $var, "...$var...", $x.Member, $($expr), etc.).
            # Defer evaluation to runtime so the value reaches coreutils as a literal arg.
            # This matches POSIX behaviour where variable expansions don't result in globbing.
            if (-not $merged -and
                ($first -is [System.Management.Automation.Language.VariableExpressionAst] -or
                $first -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -or
                $first -is [System.Management.Automation.Language.MemberExpressionAst])) {
                $rewrittenArgs += '(__coreutils_q ' + $source + ')'
                $i++
                continue
            }
            # Slow path: re-tokenise and re-emit as MSVCRT-style quoting,
            # then wrap in PS single quotes so PS hands the body verbatim.
            $windowsQuoted = $script:__COREUTILS_ARG_RX__.Replace($source, $script:__COREUTILS_ARG_EVAL__)
            $rewrittenArgs += "'" + $windowsQuoted.Replace("'", "''") + "'"
            $i++
        }
        $rewrittenArgs += $line.Substring($argsStart, $argsEnd - $argsStart)

        $line = $line.Substring(0, $start) + $replacement + $rewrittenArgs + $line.Substring($argsEnd)
    }

    return $line
}
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# DO NOT MODIFY -- coreutils -- 60b36fc6-2d59-49df-be51-28dd2f4c3c9a
