param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments = @()
)

$ErrorActionPreference = "Stop"
if ($null -eq $IsWindows) { $IsWindows = $true }

$RepoRoot = if ($env:OOODNAKOV_REPO_ROOT) {
    $env:OOODNAKOV_REPO_ROOT
} else {
    (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
}
$SetupScript = Join-Path $RepoRoot "scripts/setup/setup.ps1"
$DeleteScript = Join-Path $RepoRoot "scripts/setup/delete.ps1"
$GenerateLockScript = Join-Path $RepoRoot "scripts/generate/generate_dependency_lock.py"
$UpdatePinsScript = Join-Path $RepoRoot "scripts/update/update_pins.py"
$RenderSecretsScript = Join-Path $RepoRoot "scripts/generate/render_secrets.py"
$AgentsToolScript = Join-Path $RepoRoot "scripts/cli/agents_tool.py"
$SyncColorThemeScript = Join-Path $RepoRoot "scripts/lib/sync_color_theme.py"
$CommandsFile = Join-Path $RepoRoot "scripts/cli/oooconf-commands.txt"

function Get-KnownCommands {
    $fallback = @("install", "deps", "update", "doctor", "dry-run", "delete", "remove", "lock", "update-pins", "completions", "agents", "secrets", "shell", "color", "version", "check", "preview", "upgrade")
    if (-not (Test-Path $CommandsFile)) {
        return $fallback
    }

    $commands = @(
        Get-Content -Path $CommandsFile -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith("#") }
    )
    $commands = @($commands | Where-Object { $_ -ne "bootstrap" })
    if ($commands.Count -eq 0) {
        return $fallback
    }
    return $commands
}

$KnownCommands = Get-KnownCommands

$KnownShellSubcommands = @("status", "prompt", "prompt-style", "forgit-aliases", "typo-handling", "psfzf-tab", "psfzf-git", "auto-uv-env")
$KnownShellForgitModes = @("plain", "forgit", "status")
$KnownShellTypoModes = @("silent", "suggest", "help", "status")
$KnownShellPsfzfModes = @("enabled", "disabled", "status")
$KnownShellAutoUvModes = @("enabled", "quiet", "status")
$KnownShellPromptModes = @("p10k", "ohmyposh", "status")
$KnownShellPromptStyleModes = @("verbose", "concise", "status")
$KnownColorThemes = @("default", "catppuccin", "gruvbox", "nord", "tokyonight", "noctalia")
$KnownWmSubcommands = @("status", "set", "start", "stop", "reload", "bar", "komorebi")
$KnownWmOptions = @("komorebi", "glazewm")
$KnownBarSubcommands = @("set", "zebar-config", "stop", "start", "reload")
$KnownBarTypes = @("zebar", "yabs")
$LocalOverridesStart = "# --- LOCAL OVERRIDES START ---"
$LocalOverridesEnd = "# --- LOCAL OVERRIDES END ---"
$ForgitAliasVar = "OOODNAKOV_FORGIT_ALIAS_MODE"
$TypoHandlingVar = "OOODNAKOV_TYPO_HANDLING_MODE"
$PsfzfTabVar = "OOODNAKOV_PSFZF_TAB"
$PsfzfGitVar = "OOODNAKOV_PSFZF_GIT"
$AutoUvEnvVar = "AUTO_UV_ENV_QUIET"
$OooconfThemeVar = "OOOCONF_THEME"
$OooconfOmpConfigVar = "OOOCONF_OMP_CONFIG"
$OooconfZshPromptVar = "OOOCONF_ZSH_PROMPT"
$OooconfPromptStyleVar = "OOOCONF_PROMPT_STYLE"
$UiAscii = @{
    section = "=="
    ok = "[ok]"
    warn = "[warn]"
    fail = "[fail]"
    info = "[info]"
    hint = "->"
}
$UiNerd = @{
    section = 0x25B8
    ok = 0x2713
    warn = 0x26A0
    fail = 0x2717
    info = 0x2139
    hint = 0x2192
}
$UiAnsi = @{
    Reset = "$([char]27)[0m"
    Bold = "$([char]27)[1m"
    Section = ""
    Ok = ""
    Warn = ""
    Fail = ""
    Info = ""
    Muted = ""
}

# Run a Python script, preferring `uv run` when available.
function Run-Python {
    param([string]$ScriptPath, [string[]]$ScriptArgs)
    $pyprojectPath = Join-Path $RepoRoot "pyproject.toml"
    if ((Get-Command uv -ErrorAction SilentlyContinue) -and (Test-Path $pyprojectPath)) {
        & uv run $ScriptPath @ScriptArgs
    } else {
        & python3 $ScriptPath @ScriptArgs
    }
}

function Resolve-GlazeWmCommand {
    $candidates = @("glazewm", "glazewm.exe")
    foreach ($candidate in $candidates) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) {
            return $command
        }
    }

    return $null
}

function Resolve-ZebarCommand {
    $candidates = @("zebar", "zebar.exe")
    foreach ($candidate in $candidates) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) {
            return $command
        }
    }

    return $null
}

function Restart-ZebarForGlazeWm {
    $zebarCommand = Resolve-ZebarCommand
    if (-not $zebarCommand) {
        Write-UiLine -Role warn -Message "Zebar is not installed. Run 'oooconf deps zebar' first."
        return
    }

    Stop-Process -Name "zebar" -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 2000
    & $zebarCommand.Source startup *> $null
}

function Get-ZebarConfigRoot {
    return Join-Path $RepoRoot "home/.glzr/zebar"
}

function Get-ZebarSettingsPath {
    return Join-Path (Get-ZebarConfigRoot) "settings.json"
}

function Get-ZebarExternalRoot {
    return Join-Path $HOME ".glzr/zebar-external"
}

function Normalize-ZebarConfigName {
    param([string]$Value)

    return ([string]$Value -replace "[^a-zA-Z0-9]+", "").ToLowerInvariant()
}

function Get-ZebarWidgetPacks {
    $configRoot = Get-ZebarConfigRoot
    if (-not (Test-Path $configRoot)) {
        return @()
    }

    $packs = @()
    $directories = Get-ChildItem -Path $configRoot -Directory -Force | Where-Object { $_.Name -notmatch "^\." }
    foreach ($directory in $directories) {
        $zpackPath = Join-Path $directory.FullName "zpack.json"
        if (-not (Test-Path $zpackPath)) {
            continue
        }

        try {
            $zpack = Get-Content -Path $zpackPath -Raw | ConvertFrom-Json
        } catch {
            Write-UiLine -Role warn -Message "Skipping invalid Zebar pack at $($directory.Name)."
            continue
        }

        $widgets = @($zpack.widgets)
        if ($widgets.Count -eq 0) {
            continue
        }

        $selectedWidget = $widgets | Where-Object { $_.name -eq $zpack.name } | Select-Object -First 1
        if (-not $selectedWidget) {
            $selectedWidget = $widgets | Where-Object { $_.name -eq "main" } | Select-Object -First 1
        }
        if (-not $selectedWidget) {
            $selectedWidget = $widgets | Select-Object -First 1
        }

        $presets = @($selectedWidget.presets)
        $selectedPreset = $presets | Where-Object { $_.name -eq "default" } | Select-Object -First 1
        if (-not $selectedPreset) {
            $selectedPreset = $presets | Select-Object -First 1
        }

        $packName = if ($zpack.name) { [string]$zpack.name } else { $directory.Name }
        $widgetName = [string]$selectedWidget.name
        $presetName = if ($selectedPreset) { [string]$selectedPreset.name } else { "" }

        $packs += [pscustomobject]@{
            Id = $directory.Name
            PackName = $packName
            WidgetName = $widgetName
            PresetName = $presetName
            Path = $directory.FullName
            MatchKeys = @(
                (Normalize-ZebarConfigName $directory.Name),
                (Normalize-ZebarConfigName $packName),
                (Normalize-ZebarConfigName $widgetName)
            ) | Select-Object -Unique
        }
    }

    return @($packs)
}

function Get-ZebarActiveConfig {
    $settingsPath = Get-ZebarSettingsPath
    if (-not (Test-Path $settingsPath)) {
        return $null
    }

    try {
        $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
    } catch {
        Write-UiLine -Role warn -Message "Could not parse Zebar settings.json."
        return $null
    }

    $startupConfigs = @($settings.startupConfigs)
    if ($startupConfigs.Count -eq 0) {
        return $null
    }

    return $startupConfigs[0]
}

function Set-ZebarActiveConfig {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Pack
    )

    $settingsPath = Get-ZebarSettingsPath
    if (-not (Test-Path $settingsPath)) {
        throw "Zebar settings.json was not found at $settingsPath."
    }

    $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
    $settings.startupConfigs = @(
        [pscustomobject]@{
            pack = $Pack.PackName
            widget = $Pack.WidgetName
            preset = $Pack.PresetName
        }
    )
    ($settings | ConvertTo-Json -Depth 10) | Set-Content -Path $settingsPath
}

function Restart-ZebarIfRunning {
    $hasGlazeWm = [bool](Get-Process glazewm -ErrorAction SilentlyContinue)
    $hasZebar = [bool](Get-Process zebar -ErrorAction SilentlyContinue)
    if (-not ($hasGlazeWm -or $hasZebar)) {
        return
    }

    Restart-ZebarForGlazeWm
}

function Add-GitExcludeEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $excludePath = Join-Path $RepoRoot ".git/info/exclude"
    $existing = if (Test-Path $excludePath) { Get-Content -Path $excludePath -ErrorAction SilentlyContinue } else { @() }
    if ($existing -contains $RelativePath) {
        return
    }

    Add-Content -Path $excludePath -Value $RelativePath
}

function Resolve-ZebarInstallTarget {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $knownTargets = @{
        "overlinezebar" = @{
            RepoUrl = "https://github.com/mushfikurr/overline-zebar.git"
            DirectoryName = "overline-zebar"
            BuildCommand = "pnpm --filter ""@overline-zebar/*"" build"
        }
    }

    $normalized = Normalize-ZebarConfigName $Value
    if ($knownTargets.ContainsKey($normalized)) {
        return [pscustomobject]$knownTargets[$normalized]
    }

    if ($Value -match "^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$") {
        $directoryName = ($Value -split "/")[-1]
        return [pscustomobject]@{
            RepoUrl = "https://github.com/$Value.git"
            DirectoryName = $directoryName
            BuildCommand = "pnpm build"
        }
    }

    if ($Value -match "^(https://|git@)") {
        $directoryName = [System.IO.Path]::GetFileNameWithoutExtension($Value.TrimEnd('/'))
        return [pscustomobject]@{
            RepoUrl = $Value
            DirectoryName = $directoryName
            BuildCommand = "pnpm build"
        }
    }

    return $null
}

function Install-ZebarConfigPack {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    $resolved = Resolve-ZebarInstallTarget -Value $Target
    if (-not $resolved) {
        Write-UiLine -Role fail -Message "Unknown Zebar pack source: $Target"
        Write-UiLine -Role hint -Message "Use a known name like overline-zebar or a GitHub repo like owner/repo."
        return $false
    }

    $externalRoot = Get-ZebarExternalRoot
    $externalPath = Join-Path $externalRoot $resolved.DirectoryName
    $linkPath = Join-Path (Get-ZebarConfigRoot) $resolved.DirectoryName
    New-Item -ItemType Directory -Path $externalRoot -Force | Out-Null

    if (Test-Path (Join-Path $externalPath ".git")) {
        Write-UiLine -Role info -Message "Updating Zebar pack $($resolved.DirectoryName)..."
        & git -C $externalPath pull --ff-only
    } else {
        Write-UiLine -Role info -Message "Cloning Zebar pack $($resolved.DirectoryName)..."
        & git clone $resolved.RepoUrl $externalPath
    }
    if ($LASTEXITCODE -ne 0) {
        Write-UiLine -Role fail -Message "Failed to fetch Zebar pack from $($resolved.RepoUrl)."
        return $false
    }

    if (Test-Path (Join-Path $externalPath "package.json")) {
        Write-UiLine -Role info -Message "Installing dependencies for $($resolved.DirectoryName)..."
        & pnpm install --dir $externalPath
        if ($LASTEXITCODE -ne 0) {
            Write-UiLine -Role fail -Message "pnpm install failed for $($resolved.DirectoryName)."
            return $false
        }

        Write-UiLine -Role info -Message "Building $($resolved.DirectoryName)..."
        & pwsh -NoProfile -Command "Set-Location -LiteralPath '$externalPath'; $($resolved.BuildCommand)"
        if ($LASTEXITCODE -ne 0) {
            Write-UiLine -Role fail -Message "Build failed for $($resolved.DirectoryName)."
            return $false
        }
    }

    if (Test-Path $linkPath) {
        $item = Get-Item -Path $linkPath -Force
        if ($item.LinkType -and $item.Target -contains $externalPath) {
            Add-GitExcludeEntry -RelativePath ("home/.glzr/zebar/{0}" -f $resolved.DirectoryName)
            return $true
        }

        Write-UiLine -Role fail -Message "Path already exists and is not the expected external pack link: $linkPath"
        return $false
    }

    New-Item -ItemType SymbolicLink -Path $linkPath -Target $externalPath | Out-Null
    Add-GitExcludeEntry -RelativePath ("home/.glzr/zebar/{0}" -f $resolved.DirectoryName)
    return $true
}

function Invoke-ZebarConfigCommand {
    param(
        [string[]]$ZebarArgs
    )

    $action = if ($ZebarArgs.Count -gt 0) { $ZebarArgs[0] } else { "status" }
    $packs = @(Get-ZebarWidgetPacks)

    switch ($action) {
        "status" {
            $active = Get-ZebarActiveConfig
            if (-not $active) {
                Write-UiLine -Role warn -Message "No active Zebar startup config is set."
                return
            }

            $activeName = if ($active.pack) { $active.pack } else { "<unknown>" }
            Write-UiLine -Role info -Message "Active Zebar config: $(Format-UiText -Text $activeName -Role ok -Bold)"
            if ($active.widget) {
                Write-UiLine -Role info -Message "Widget: $($active.widget)"
            }
            if ($active.preset) {
                Write-UiLine -Role info -Message "Preset: $($active.preset)"
            }
            return
        }
        "list" {
            if ($packs.Count -eq 0) {
                Write-UiLine -Role warn -Message "No Zebar widget packs were found in home/.glzr/zebar."
                return
            }

            $active = Get-ZebarActiveConfig
            foreach ($pack in $packs) {
                $marker = if ($active -and $active.pack -eq $pack.PackName) { "*" } else { "-" }
                Write-UiLine -Role info -Message "$marker $($pack.Id) (pack=$($pack.PackName), widget=$($pack.WidgetName), preset=$($pack.PresetName))"
            }
            return
        }
        "set" {
            $target = if ($ZebarArgs.Count -gt 1) { $ZebarArgs[1] } else { "" }
            if (-not $target) {
                Write-UiLine -Role fail -Message "Missing Zebar config name."
                Write-UiLine -Role hint -Message "Usage: oooconf wm zebar-config set <name>"
                return
            }

            $normalizedTarget = Normalize-ZebarConfigName $target
            $pack = $packs | Where-Object { $_.MatchKeys -contains $normalizedTarget } | Select-Object -First 1
            if (-not $pack) {
                Write-UiLine -Role fail -Message "Unknown Zebar config: $target"
                if ($packs.Count -gt 0) {
                    Write-UiLine -Role hint -Message "Available configs: $($packs.Id -join ', ')"
                }
                return
            }

            Set-ZebarActiveConfig -Pack $pack
            Restart-ZebarIfRunning
            Write-UiLine -Role ok -Message "Zebar config set to $($pack.Id)."
            return
        }
        "install" {
            $target = if ($ZebarArgs.Count -gt 1) { $ZebarArgs[1] } else { "" }
            if (-not $target) {
                Write-UiLine -Role fail -Message "Missing Zebar pack source."
                Write-UiLine -Role hint -Message "Usage: oooconf wm zebar-config install <name|owner/repo|git-url>"
                return
            }

            if (-not (Install-ZebarConfigPack -Target $target)) {
                return
            }

            $packs = @(Get-ZebarWidgetPacks)
            $normalizedTarget = Normalize-ZebarConfigName $target
            $pack = $packs | Where-Object { $_.MatchKeys -contains $normalizedTarget } | Select-Object -First 1
            if ($pack) {
                Set-ZebarActiveConfig -Pack $pack
                Restart-ZebarIfRunning
                Write-UiLine -Role ok -Message "Installed and activated Zebar config $($pack.Id)."
            } else {
                Write-UiLine -Role ok -Message "Installed Zebar pack from $target."
                Write-UiLine -Role hint -Message "Run 'oooconf wm zebar-config list' to confirm the available pack name."
            }
            return
        }
        default {
            Write-UiLine -Role fail -Message "Unknown zebar-config action: $action"
            Write-UiLine -Role hint -Message "Use: status, list, set <name>, or install <source>"
            return
        }
    }
}

function Test-UiInteractive {
    try {
        return -not [Console]::IsOutputRedirected
    } catch {
        return $false
    }
}

function Test-UiColor {
    if (${env:NO_COLOR}) { return $false }
    if (${env:OOOCONF_COLOR} -in @("0", "false", "never")) { return $false }
    if (${env:OOOCONF_COLOR} -in @("1", "true", "always") -or ${env:FORCE_COLOR}) { return $true }
    return Test-UiInteractive
}

function Test-UiNerdFont {
    if (${env:OOOCONF_ASCII} -eq "1") { return $false }
    if (-not (Test-UiInteractive)) { return $false }
    return (($OutputEncoding.WebName -match "utf") -or ([Console]::OutputEncoding.WebName -match "utf"))
}

function Get-UiIcon {
    param([string]$Name)
    if (Test-UiNerdFont) {
        $codepoint = $UiNerd[$Name]
        if ($codepoint) { return [char]::ConvertFromUtf32($codepoint) }
    }
    return $UiAscii[$Name]
}

$script:OooconfThemePaletteCache = $null

function Get-UiCommandIcon {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (Test-UiNerdFont) {
        switch ($Name) {
            "bootstrap" { return [char]::ConvertFromUtf32(0xF0320) }
            "install" { return [char]::ConvertFromUtf32(0xF05E0) }
            "deps" { return [char]::ConvertFromUtf32(0xF03D6) }
            "update" { return [char]::ConvertFromUtf32(0xF06B0) }
            "doctor" { return [char]::ConvertFromUtf32(0xF04D9) }
            "dry-run" { return [char]::ConvertFromUtf32(0xF0709) }
            "version" { return [char]::ConvertFromUtf32(0xF0386) }
            "delete" { return [char]::ConvertFromUtf32(0xF0A7A) }
            "remove" { return [char]::ConvertFromUtf32(0xF1238) }
            "lock" { return [char]::ConvertFromUtf32(0xF033E) }
            "update-pins" { return [char]::ConvertFromUtf32(0xF1962) }
            "completions" { return [char]::ConvertFromUtf32(0xF0A6B) }
            "link" { return [char]::ConvertFromUtf32(0xF0337) }
            "shell" { return [char]::ConvertFromUtf32(0xF1183) }
            "color" { return [char]::ConvertFromUtf32(0xF03D8) }
            "secrets" { return [char]::ConvertFromUtf32(0xF082E) }
            "agents" { return [char]::ConvertFromUtf32(0xF0B79) }
            "komorebi" { return [char]::ConvertFromUtf32(0xF0319) }
            "check" { return [char]::ConvertFromUtf32(0xF04D9) }
            "preview" { return [char]::ConvertFromUtf32(0xF0709) }
            "upgrade" { return [char]::ConvertFromUtf32(0xF06B0) }
            "wm" { return [char]::ConvertFromUtf32(0xF030F) }
            default { return [char]::ConvertFromUtf32(0xF060D) }
        }
    }
    switch ($Name) {
        "bootstrap" { return "[boot]" }
        "install" { return "[inst]" }
        "deps" { return "[deps]" }
        "update" { return "[up]" }
        "doctor" { return "[doc]" }
        "dry-run" { return "[dry]" }
        "version" { return "[ver]" }
        "delete" { return "[del]" }
        "remove" { return "[rm]" }
        "lock" { return "[lock]" }
        "update-pins" { return "[pins]" }
        "completions" { return "[comp]" }
        "link" { return "[link]" }
        "shell" { return "[sh]" }
        "color" { return "[clr]" }
        "secrets" { return "[sec]" }
        "agents" { return "[agt]" }
        "komorebi" { return "[kom]" }
        "check" { return "[doc]" }
        "preview" { return "[dry]" }
        "upgrade" { return "[up]" }
        "wm" { return "[wm]" }
        default { return "[cmd]" }
    }
}

function Format-UiText {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Role,
        [switch]$Bold
    )
    if (-not (Test-UiColor)) { return $Text }
    $palette = if ($null -ne $script:OooconfThemePaletteCache) { $script:OooconfThemePaletteCache } else { $script:OooconfThemePaletteCache = Get-UiThemePalette }
    $color = switch ($Role) {
        "section" { $palette.Section }
        "ok" { $palette.Ok }
        "warn" { $palette.Warn }
        "fail" { $palette.Fail }
        "info" { $palette.Info }
        "hint" { $palette.Muted }
        "muted" { $palette.Muted }
        default { $palette.Muted }
    }
    $prefix = if ($Bold) { "$($UiAnsi.Bold)$color" } else { $color }
    return "$prefix$Text$($UiAnsi.Reset)"
}

function Write-UiLine {
    param(
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $icon = Format-UiText -Text (Get-UiIcon $Role) -Role $Role -Bold
    Write-Output "$icon $Message"
}

function Write-UiSection {
    param([Parameter(Mandatory = $true)][string]$Title)
    $icon = Format-UiText -Text (Get-UiIcon "section") -Role "section" -Bold
    $heading = Format-UiText -Text $Title -Role "section" -Bold
    $ruleChar = if (Test-UiNerdFont) { [string][char]0x2500 } else { "-" }
    $rule = Format-UiText -Text ($ruleChar * ($Title.Length + 3)) -Role "muted"
    Write-Output "$icon $heading"
    Write-Output $rule
}

function Write-UiBannerLine {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    $padding = [Math]::Max(0, $Width - $Text.Length)
    $leftPadding = [Math]::Floor($padding / 2)
    $rightPadding = $padding - $leftPadding
    $line = $Left + (" " * $leftPadding) + $Text + (" " * $rightPadding) + $Right
    Write-Output (Format-UiText -Text $line -Role "section" -Bold)
}

function Write-UiBanner {
    $width = 58
    $horizontal = "-"
    $topLeft = "+"
    $topRight = "+"
    $bottomLeft = "+"
    $bottomRight = "+"
    $left = "|"
    $right = "|"
    $platformLine = "Linux / Windows / macOS"

    if (Test-UiNerdFont) {
        $horizontal = [string][char]0x2500
        $topLeft = [string][char]0x250C
        $topRight = [string][char]0x2510
        $bottomLeft = [string][char]0x2514
        $bottomRight = [string][char]0x2518
        $left = [string][char]0x2502
        $right = [string][char]0x2502
        $platformLine = "Linux • Windows • macOS"
    }

    Write-Output (Format-UiText -Text ($topLeft + ($horizontal * $width) + $topRight) -Role "section" -Bold)
    Write-UiBannerLine -Text "oooconf" -Width $width -Left $left -Right $right
    Write-UiBannerLine -Text "reproducible dotfiles manager" -Width $width -Left $left -Right $right
    Write-UiBannerLine -Text $platformLine -Width $width -Left $left -Right $right
    Write-Output (Format-UiText -Text ($bottomLeft + ($horizontal * $width) + $bottomRight) -Role "section" -Bold)
}

function Write-UiSeparator {
    $ruleChar = if (Test-UiNerdFont) { [string][char]0x2500 } else { "-" }
    Write-Output (Format-UiText -Text ($ruleChar * 54) -Role "muted")
}

function Write-UiSpacer {
    Write-Output ""
}

function Write-UiSectionFancy {
    param(
        [Parameter(Mandatory = $true)][string]$IconName,
        [Parameter(Mandatory = $true)][string]$Title
    )
    $icon = Format-UiText -Text (Get-UiCommandIcon $IconName) -Role "hint"
    $heading = Format-UiText -Text $Title -Role "section" -Bold
    $ruleChar = if (Test-UiNerdFont) { [string][char]0x2500 } else { "-" }
    $rule = Format-UiText -Text ($ruleChar * ($Title.Length + 6)) -Role "muted"
    Write-Output "  $icon  $heading"
    Write-Output "  $rule"
}

function Write-UiCommandRow {
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)][string]$Description
    )
    $paddedIcon = (Get-UiCommandIcon $CommandName).PadRight(6)
    $iconText = Format-UiText -Text $paddedIcon -Role "hint"
    $paddedCommand = $CommandName.PadRight(16)
    $commandText = Format-UiText -Text $paddedCommand -Role "info"
    $descriptionText = Format-UiText -Text $Description -Role "muted"
    Write-Output ("    " + $iconText + " " + $commandText + " " + $descriptionText)
}

function Write-UiHelpBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Text
    )

    foreach ($line in ($Text -split "`r?`n")) {
        switch -Regex ($line) {
            '^Usage:' {
                Write-Output (Format-UiText -Text $line -Role "section")
                continue
            }
            '^(Examples:|Environment overrides:|Subcommands:|Global options:|Mode values:|Aliases:|Getting help:|Common workflows:|Repo root:|UI controls:|Themes:|Forgit alias modes:|Typo handling modes:|PSFzf options:|Prompt options:|Auto UV environment options:)$' {
                Write-Output (Format-UiText -Text $line -Role "info")
                continue
            }
            '^\s+(oooconf|OOODNAKOV_|OOOCONF_|\$env:OOOCONF_|\./scripts/)' {
                Write-Output (Format-UiText -Text $line -Role "hint")
                continue
            }
            default {
                Write-Output $line
            }
        }
    }
}

function Get-ShellConfigHome {
    $baseConfigHome = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME ".config" }
    return Join-Path $baseConfigHome "ooodnakov"
}

function Get-LocalEnvZshPath {
    return Join-Path (Get-ShellConfigHome) "local/env.zsh"
}

function Get-LocalEnvPs1Path {
    return Join-Path (Get-ShellConfigHome) "local/env.ps1"
}

function Ensure-LocalOverrideFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        @(
            $LocalOverridesStart
            "# Add machine-specific env vars here. This section is preserved across syncs."
            $LocalOverridesEnd
        ) | Set-Content -LiteralPath $Path
        return
    }

    $content = Get-Content -LiteralPath $Path
    if ($content -notcontains $LocalOverridesStart) {
        Add-Content -LiteralPath $Path -Value ""
        Add-Content -LiteralPath $Path -Value $LocalOverridesStart
        Add-Content -LiteralPath $Path -Value "# Add machine-specific env vars here. This section is preserved across syncs."
        Add-Content -LiteralPath $Path -Value $LocalOverridesEnd
    }
}

function Set-LocalOverrideLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$VariableName,
        [Parameter(Mandatory = $true)]
        [string]$ReplacementLine
    )

    Ensure-LocalOverrideFile -Path $Path
    $lines = Get-Content -LiteralPath $Path
    $result = New-Object System.Collections.Generic.List[string]
    $inBlock = $false
    $inserted = $false

    foreach ($line in $lines) {
        if ($line -eq $LocalOverridesStart) {
            $inBlock = $true
            $result.Add($line)
            continue
        }

        if ($line -eq $LocalOverridesEnd) {
            if ($inBlock -and -not $inserted) {
                $result.Add($ReplacementLine)
                $inserted = $true
            }
            $inBlock = $false
            $result.Add($line)
            continue
        }

        if ($inBlock -and ($line -match ("^export " + [regex]::Escape($VariableName) + "=") -or $line -match ('^\$env:' + [regex]::Escape($VariableName) + ' = '))) {
            if (-not $inserted) {
                $result.Add($ReplacementLine)
                $inserted = $true
            }
            continue
        }

        $result.Add($line)
    }

    if (-not $inserted) {
        if ($result.Count -gt 0 -and $result[$result.Count - 1] -ne "") {
            $result.Add("")
        }
        $result.Add($LocalOverridesStart)
        $result.Add($ReplacementLine)
        $result.Add($LocalOverridesEnd)
    }

    Set-Content -LiteralPath $Path -Value $result
}

function Get-ZshPromptMode {
    if ($env:OOOCONF_ZSH_PROMPT) {
        return $env:OOOCONF_ZSH_PROMPT
    }

    $envPath = Get-LocalEnvZshPath
    if (Test-Path -LiteralPath $envPath) {
        foreach ($line in Get-Content -LiteralPath $envPath) {
            if ($line -match "^export $([regex]::Escape($OooconfZshPromptVar))=""([^""]+)""$") {
                return $Matches[1]
            }
        }
    }
    return "p10k"
}

function Get-PromptStyleMode {
    if ($env:OOOCONF_PROMPT_STYLE) {
        return $env:OOOCONF_PROMPT_STYLE
    }

    $envZshPath = Get-LocalEnvZshPath
    if (Test-Path -LiteralPath $envZshPath) {
        foreach ($line in Get-Content -LiteralPath $envZshPath) {
            if ($line -match ('^export ' + [regex]::Escape($OooconfPromptStyleVar) + '="([^"]+)"$')) {
                return $Matches[1]
            }
        }
    }

    $envPs1Path = Get-LocalEnvPs1Path
    if (Test-Path -LiteralPath $envPs1Path) {
        foreach ($line in Get-Content -LiteralPath $envPs1Path) {
            if ($line -match ('^\$env:' + [regex]::Escape($OooconfPromptStyleVar) + " = '([^']+)'$")) {
                return $Matches[1]
            }
        }
    }

    return "verbose"
}

function Get-ForgitAliasMode {
    $envPath = Get-LocalEnvZshPath
    if (Test-Path -LiteralPath $envPath) {
        foreach ($line in Get-Content -LiteralPath $envPath) {
            if ($line -match "^export $([regex]::Escape($ForgitAliasVar))=""([^""]+)""$") {
                return $Matches[1]
            }
        }
    }

    return "plain"
}

function Get-TypoHandlingMode {
    if ($env:OOODNAKOV_TYPO_HANDLING_MODE) {
        return $env:OOODNAKOV_TYPO_HANDLING_MODE
    }

    $envPath = Get-LocalEnvZshPath
    if (Test-Path -LiteralPath $envPath) {
        foreach ($line in Get-Content -LiteralPath $envPath) {
            if ($line -match "^export $([regex]::Escape($TypoHandlingVar))=""([^""]+)""$") {
                return $Matches[1]
            }
        }
    }

    return "help"
}

function Get-PsfzfTabMode {
    $envPath = Get-LocalEnvPs1Path
    if (Test-Path -LiteralPath $envPath) {
        foreach ($line in Get-Content -LiteralPath $envPath) {
            if ($line -match ('^\$env:' + [regex]::Escape($PsfzfTabVar) + " = '([^']+)'$")) {
                return $Matches[1]
            }
        }
    }
    return "enabled"
}

function Get-PsfzfGitMode {
    $envPath = Get-LocalEnvPs1Path
    if (Test-Path -LiteralPath $envPath) {
        foreach ($line in Get-Content -LiteralPath $envPath) {
            if ($line -match ('^\$env:' + [regex]::Escape($PsfzfGitVar) + " = '([^']+)'$")) {
                return $Matches[1]
            }
        }
    }
    return "enabled"
}

function Get-AutoUvEnvMode {
    $envPath = Get-LocalEnvPs1Path
    if (Test-Path -LiteralPath $envPath) {
        foreach ($line in Get-Content -LiteralPath $envPath) {
            if ($line -match ('^\$env:' + [regex]::Escape($AutoUvEnvVar) + " = 1$")) {
                return "quiet"
            }
        }
    }
    return "enabled"
}

function Get-OooconfTheme {
    if ($env:OOOCONF_THEME) {
        return $env:OOOCONF_THEME
    }

    $envPath = Get-LocalEnvZshPath
    if (Test-Path -LiteralPath $envPath) {
        foreach ($line in Get-Content -LiteralPath $envPath) {
            if ($line -match "^export $([regex]::Escape($OooconfThemeVar))=""([^""]+)""$") {
                return $Matches[1]
            }
        }
    }
    $repoTheme = Get-RepoColorTheme
    if ($repoTheme) {
        return $repoTheme
    }
    return "default"
}

function Get-RepoColorTheme {
    $weztermMain = Join-Path $RepoRoot "home/.config/wezterm/wezterm.lua"
    if (Test-Path -LiteralPath $weztermMain) {
        $raw = Get-Content -LiteralPath $weztermMain -Raw
        if ($raw -match "Noctalia") {
            return "noctalia"
        }
    }

    $weztermGeneral = Join-Path $RepoRoot "home/.config/wezterm/config/general.lua"
    if (Test-Path -LiteralPath $weztermGeneral) {
        $raw = Get-Content -LiteralPath $weztermGeneral -Raw
        if ($raw -match "(?i)catppuccin") {
            return "catppuccin"
        }
    }

    $nvimColors = Join-Path $RepoRoot "home/.config/nvim/lua/plugins/colorscheme.lua"
    if (Test-Path -LiteralPath $nvimColors) {
        $raw = Get-Content -LiteralPath $nvimColors -Raw
        if ($raw -match "(?i)catppuccin") {
            return "catppuccin"
        }
    }

    return $null
}

function Get-UiThemePalette {
    $theme = Get-OooconfTheme
    switch ($theme) {
        "catppuccin" {
            return @{
                Section = "$([char]27)[38;5;111m"
                Ok = "$([char]27)[38;5;150m"
                Warn = "$([char]27)[38;5;223m"
                Fail = "$([char]27)[38;5;203m"
                Info = "$([char]27)[38;5;117m"
                Muted = "$([char]27)[38;5;145m"
            }
        }
        "gruvbox" {
            return @{
                Section = "$([char]27)[38;5;214m"
                Ok = "$([char]27)[38;5;142m"
                Warn = "$([char]27)[38;5;214m"
                Fail = "$([char]27)[38;5;167m"
                Info = "$([char]27)[38;5;109m"
                Muted = "$([char]27)[38;5;248m"
            }
        }
        "nord" {
            return @{
                Section = "$([char]27)[38;5;110m"
                Ok = "$([char]27)[38;5;108m"
                Warn = "$([char]27)[38;5;180m"
                Fail = "$([char]27)[38;5;174m"
                Info = "$([char]27)[38;5;110m"
                Muted = "$([char]27)[38;5;146m"
            }
        }
        "tokyonight" {
            return @{
                Section = "$([char]27)[38;5;111m"
                Ok = "$([char]27)[38;5;114m"
                Warn = "$([char]27)[38;5;221m"
                Fail = "$([char]27)[38;5;203m"
                Info = "$([char]27)[38;5;117m"
                Muted = "$([char]27)[38;5;146m"
            }
        }
        "noctalia" {
            return @{
                Section = "$([char]27)[38;5;141m"
                Ok = "$([char]27)[38;5;110m"
                Warn = "$([char]27)[38;5;180m"
                Fail = "$([char]27)[38;5;174m"
                Info = "$([char]27)[38;5;117m"
                Muted = "$([char]27)[38;5;146m"
            }
        }
        default {
            return @{
                Section = "$([char]27)[38;5;111m"
                Ok = "$([char]27)[38;5;78m"
                Warn = "$([char]27)[38;5;221m"
                Fail = "$([char]27)[38;5;203m"
                Info = "$([char]27)[38;5;117m"
                Muted = "$([char]27)[38;5;245m"
            }
        }
    }
}

function Set-ZshPromptMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    if ($Mode -notin @("p10k", "ohmyposh")) {
        throw "Invalid zsh prompt mode: $Mode`nExpected one of: p10k, ohmyposh"
    }

    $envZsh = Get-LocalEnvZshPath
    Set-LocalOverrideLine -Path $envZsh -VariableName $OooconfZshPromptVar -ReplacementLine "export $OooconfZshPromptVar=""$Mode"""

    Write-UiLine -Role ok -Message "zsh prompt set to $Mode"
    Write-UiLine -Role info -Message "zsh: $envZsh"
    Write-UiLine -Role hint -Message "Open a new zsh session or run: exec zsh"
}

function Set-PromptStyleMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    if ($Mode -notin @("verbose", "concise")) {
        throw "Invalid prompt style: $Mode`nExpected one of: verbose, concise"
    }

    $envZsh = Get-LocalEnvZshPath
    $envPs1 = Get-LocalEnvPs1Path
    Set-LocalOverrideLine -Path $envZsh -VariableName $OooconfPromptStyleVar -ReplacementLine "export $OooconfPromptStyleVar=""$Mode"""
    Set-LocalOverrideLine -Path $envPs1 -VariableName $OooconfPromptStyleVar -ReplacementLine "`$env:$OooconfPromptStyleVar = '$Mode'"

    Write-UiLine -Role ok -Message "prompt style set to $Mode"
    Write-UiLine -Role info -Message "zsh: $envZsh"
    Write-UiLine -Role info -Message "pwsh: $envPs1"
    Write-UiLine -Role hint -Message "Open a new shell session to apply the change."
}

function Set-AutoUvEnvMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    if ($Mode -notin @("enabled", "quiet")) {
        throw "Invalid auto-uv-env mode: $Mode`nExpected one of: enabled, quiet"
    }

    $envZsh = Get-LocalEnvZshPath
    $envPs1 = Get-LocalEnvPs1Path

    $zshVal = if ($Mode -eq "quiet") { "1" } else { "0" }
    $ps1Val = if ($Mode -eq "quiet") { "1" } else { "0" }

    Set-LocalOverrideLine -Path $envZsh -VariableName $AutoUvEnvVar -ReplacementLine "export $AutoUvEnvVar=""$zshVal"""
    Set-LocalOverrideLine -Path $envPs1 -VariableName $AutoUvEnvVar -ReplacementLine "`$env:$AutoUvEnvVar = $ps1Val"

    Write-UiLine -Role ok -Message "auto-uv-env mode set to $Mode"
    Write-UiLine -Role info -Message "zsh: $envZsh"
    Write-UiLine -Role info -Message "pwsh: $envPs1"
    Write-UiLine -Role hint -Message "Open a new shell session to apply the change."
}

function Set-OooconfTheme {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Theme
    )

    if ($Theme -notin $KnownColorThemes) {
        throw "Invalid theme: $Theme`nExpected one of: $($KnownColorThemes -join ', ')"
    }

    $envZsh = Get-LocalEnvZshPath
    $envPs1 = Get-LocalEnvPs1Path
    $ompConfigPath = Join-Path (Get-ShellConfigHome) "local/ohmyposh/$Theme.omp.json"
    Set-LocalOverrideLine -Path $envZsh -VariableName $OooconfThemeVar -ReplacementLine "export $OooconfThemeVar=""$Theme"""
    Set-LocalOverrideLine -Path $envPs1 -VariableName $OooconfThemeVar -ReplacementLine "`$env:$OooconfThemeVar = '$Theme'"
    Set-LocalOverrideLine -Path $envZsh -VariableName $OooconfOmpConfigVar -ReplacementLine "export $OooconfOmpConfigVar=""$ompConfigPath"""
    Set-LocalOverrideLine -Path $envPs1 -VariableName $OooconfOmpConfigVar -ReplacementLine "`$env:$OooconfOmpConfigVar = '$ompConfigPath'"

    Write-UiLine -Role ok -Message "oooconf theme set to $Theme"
    Write-UiLine -Role info -Message "zsh: $envZsh"
    Write-UiLine -Role info -Message "pwsh: $envPs1"
    Run-Python -ScriptPath $SyncColorThemeScript -ScriptArgs @("apply", "--theme", $Theme)
    Write-UiLine -Role hint -Message "Open a new shell session to apply the theme globally."
}

function Set-ForgitAliasMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    if ($Mode -notin @("plain", "forgit")) {
        throw "Invalid forgit alias mode: $Mode`nExpected one of: plain, forgit"
    }

    $envZsh = Get-LocalEnvZshPath
    $envPs1 = Get-LocalEnvPs1Path

    Set-LocalOverrideLine -Path $envZsh -VariableName $ForgitAliasVar -ReplacementLine "export $ForgitAliasVar=""$Mode"""
    Set-LocalOverrideLine -Path $envPs1 -VariableName $ForgitAliasVar -ReplacementLine "`$env:$ForgitAliasVar = '$Mode'"

    Write-UiLine -Role ok -Message "forgit alias mode set to $Mode"
    Write-UiLine -Role info -Message "zsh: $envZsh"
    Write-UiLine -Role info -Message "pwsh: $envPs1"
    Write-UiLine -Role hint -Message "Open a new shell session to apply the change."
}

function Set-TypoHandlingMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    if ($Mode -notin @("silent", "suggest", "help")) {
        throw "Invalid typo handling mode: $Mode`nExpected one of: silent, suggest, help"
    }

    $envZsh = Get-LocalEnvZshPath
    $envPs1 = Get-LocalEnvPs1Path

    Set-LocalOverrideLine -Path $envZsh -VariableName $TypoHandlingVar -ReplacementLine "export $TypoHandlingVar=""$Mode"""
    Set-LocalOverrideLine -Path $envPs1 -VariableName $TypoHandlingVar -ReplacementLine "`$env:$TypoHandlingVar = '$Mode'"

    Write-UiLine -Role ok -Message "typo handling mode set to $Mode"
    Write-UiLine -Role info -Message "zsh: $envZsh"
    Write-UiLine -Role info -Message "pwsh: $envPs1"
    Write-UiLine -Role hint -Message "Open a new shell session to apply the change."
}

function Set-PsfzfTabMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    if ($Mode -notin @("enabled", "disabled")) {
        throw "Invalid psfzf-tab mode: $Mode`nExpected one of: enabled, disabled"
    }

    $envPs1 = Get-LocalEnvPs1Path
    Set-LocalOverrideLine -Path $envPs1 -VariableName $PsfzfTabVar -ReplacementLine "`$env:$PsfzfTabVar = '$Mode'"

    Write-UiLine -Role ok -Message "psfzf-tab mode set to $Mode"
    Write-UiLine -Role info -Message "pwsh: $envPs1"
    Write-UiLine -Role hint -Message "Open a new shell session to apply the change."
}

function Set-PsfzfGitMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    if ($Mode -notin @("enabled", "disabled")) {
        throw "Invalid psfzf-git mode: $Mode`nExpected one of: enabled, disabled"
    }

    $envPs1 = Get-LocalEnvPs1Path
    Set-LocalOverrideLine -Path $envPs1 -VariableName $PsfzfGitVar -ReplacementLine "`$env:$PsfzfGitVar = '$Mode'"

    Write-UiLine -Role ok -Message "psfzf-git mode set to $Mode"
    Write-UiLine -Role info -Message "pwsh: $envPs1"
    Write-UiLine -Role hint -Message "Open a new shell session to apply the change."
}

function Invoke-WmCommand {
    param(
        [string[]]$WmArgs
    )

    $subcommand = if ($WmArgs.Count -gt 0) { $WmArgs[0] } else { "" }

    switch ($subcommand) {
        "" { Show-CommandUsage "wm"; return }
        "help" { Show-CommandUsage "wm"; return }
        "-h" { Show-CommandUsage "wm"; return }
        "--help" { Show-CommandUsage "wm"; return }
        "zebar-config" {
            $remainingArgs = if ($WmArgs.Count -gt 1) { $WmArgs[1..($WmArgs.Count - 1)] } else { @() }
            Invoke-ZebarConfigCommand -ZebarArgs $remainingArgs
            return
        }
        "status" {
            $active = "none"
            if (Get-Process komorebi -ErrorAction SilentlyContinue) { $active = "komorebi" }
            elseif (Get-Process glazewm -ErrorAction SilentlyContinue) { $active = "glazewm" }

            Write-UiLine -Role info -Message "Active Window Manager: $(Format-UiText -Text $active -Role ok -Bold)"
            return
        }
        "set" {
            $choice = if ($WmArgs.Count -gt 1) { $WmArgs[1] } else { "" }
            if ($choice -notin $KnownWmOptions) {
                Write-UiLine -Role fail -Message "Invalid WM choice: $choice"
                Write-UiLine -Role hint -Message "Available options: $($KnownWmOptions -join ', ')"
                return
            }

            Write-UiLine -Role info -Message "Switching to $choice..."
            # Stop everything first
            & "$PSScriptRoot/ooodnakov.ps1" wm stop
            Start-Sleep -Milliseconds 500

            if ($choice -eq "komorebi") {
                Write-UiLine -Role info -Message "Starting Komorebi..."
                $barType = Get-DefaultBarType
                $startArgs = @("start", "--whkd")
                if ($barType -eq "zebar") { $startArgs += "--bar" }
                komorebic @startArgs 2>$null
                Start-Sleep -Milliseconds 500
                Write-UiLine -Role ok -Message "Komorebi started."
                return
            } elseif ($choice -eq "glazewm") {
                $glazeWmCommand = Resolve-GlazeWmCommand
                if (-not $glazeWmCommand) {
                    Write-UiLine -Role warn -Message "GlazeWM is not installed. Run 'oooconf deps glazewm' first."
                    return
                }
                Write-UiLine -Role info -Message "Starting GlazeWM and Zebar..."
                Start-Process -FilePath $glazeWmCommand.Source -WindowStyle Hidden
                Restart-ZebarForGlazeWm
                Write-UiLine -Role ok -Message "GlazeWM stack started."
            }
            return
        }
        "start" {
            if (Get-Process glazewm -ErrorAction SilentlyContinue) { Write-UiLine -Role info -Message "GlazeWM is already running." }
            elseif (Get-Process komorebi -ErrorAction SilentlyContinue) { Write-UiLine -Role info -Message "Komorebi is already running." }
            else {
                Write-UiLine -Role info -Message "Starting Komorebi..."
                komorebic start --whkd 2>$null
                Start-Sleep -Milliseconds 500
                Write-UiLine -Role ok -Message "Komorebi started."
            }
            return
        }
        "stop" {
            Write-UiLine -Role info -Message "Stopping all Window Managers..."
            # Stop Komorebi
            try {
                if (Get-Process komorebi -ErrorAction SilentlyContinue) {
                    Write-UiLine -Role info -Message "Stopping Komorebi stack..."
                    komorebic stop --bar 2>$null
                }
            } catch {
                Write-UiLine -Role warn -Message "Komorebic stop failed, forcing processes to close."
            }
            Stop-Process -Name "komorebi", "whkd", "komorebi-bar" -ErrorAction SilentlyContinue

            # Stop GlazeWM
            Stop-Process -Name "glazewm" -ErrorAction SilentlyContinue
            Write-UiLine -Role ok -Message "WM stack stopped."
            return
        }
        "reload" {
            if (Get-Process komorebi -ErrorAction SilentlyContinue) {
                Write-UiLine -Role info -Message "Reloading Komorebi..."
                komorebic reload-configuration
                return
            }
            elseif (Get-Process glazewm -ErrorAction SilentlyContinue) {
                $glazeWmCommand = Resolve-GlazeWmCommand
                if (-not $glazeWmCommand) {
                    Write-UiLine -Role warn -Message "GlazeWM executable was not found on PATH."
                    return
                }
                Write-UiLine -Role info -Message "Reloading GlazeWM..."
                Stop-Process -Name "glazewm" -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
                Start-Process -FilePath $glazeWmCommand.Source -WindowStyle Hidden
                Restart-ZebarForGlazeWm
                Write-UiLine -Role ok -Message "GlazeWM reloaded."
            } else {
                Write-UiLine -Role warn -Message "No active WM found to reload."
            }
            return
        }
        "komorebi" {
            $remainingArgs = if ($WmArgs.Count -gt 1) { $WmArgs[1..($WmArgs.Count - 1)] } else { @() }
            $barMode = $false
            $subcommand = ""
            foreach ($arg in $remainingArgs) {
                if ($arg -eq "--bar") { $barMode = $true }
                elseif ($arg -in @("reload", "start", "stop")) { $subcommand = $arg }
            }
            if (-not $subcommand) {
                Write-UiLine -Role fail -Message "Missing komorebi subcommand (reload, start, stop)"
                return
            }
            if ($barMode) {
                Write-UiLine -Role info -Message "Komorebi $subcommand with bar..."
                komorebic stop --bar 2>$null
                Stop-Process -Name "komorebi", "whkd", "komorebi-bar" -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 300
                if ($subcommand -in @("start", "reload")) {
                    Start-Process komorebic -ArgumentList "start", "--whkd", "--bar" -WindowStyle Hidden
                }
            } else {
                Write-UiLine -Role info -Message "Komorebi $subcommand (no bar)..."
                komorebic stop 2>$null
                Stop-Process -Name "komorebi", "whkd" -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 300
                if ($subcommand -in @("start", "reload")) {
                    Start-Process komorebic -ArgumentList "start", "--whkd" -WindowStyle Hidden
                }
            }
            Write-UiLine -Role ok -Message "Komorebi $subcommand complete."
            return
        }
        "bar" {
            $remainingArgs = if ($WmArgs.Count -gt 1) { $WmArgs[1..($WmArgs.Count - 1)] } else { @() }
            Invoke-BarCommand -BarArgs $remainingArgs
            return
        }
        default {
            $suggestion = Get-SuggestionFromList -InputValue $subcommand -Candidates $KnownWmSubcommands
            Write-UnknownCommandMessage -Message "Unknown wm subcommand: $subcommand" -Suggestion $suggestion -Scope wm
            throw "Unknown wm subcommand: $subcommand"
        }
    }
}

function Invoke-BarCommand {
    param([string[]]$BarArgs)
    $action = if ($BarArgs.Count -gt 0) { $BarArgs[0] } else { "" }
    $remainingArgs = if ($BarArgs.Count -gt 1) { $BarArgs[1..($BarArgs.Count - 1)] } else { @() }
    switch ($action) {
        "-h" { $action = "help" }
        "--help" { $action = "help" }
        "" {
            Write-UiHelpBlock @"
Usage: oooconf wm bar set <type>
       oooconf wm bar zebar-config status
       oooconf wm bar zebar-config list
       oooconf wm bar zebar-config set <name>

Set or inspect the default bar type (zebar/yabs) used when activating a WM.
Bar type determines which bar loads on wm start:
  zebar  - loads komorebi-bar with zebar provider (default)
  yabs   - future replacement bar (not implemented yet)

Subcommands:
  set           set or show default bar type
  zebar-config  manage zebar configs (status, list, set)
Examples:
  oooconf wm bar set              # show current bar type
  oooconf wm bar set zebar        # set to zebar
  oooconf wm bar set yabs         # set to yabs (future)
  oooconf wm bar zebar-config list
"@
            return
        }
        "set" {
            Invoke-BarSetCommand $remainingArgs
            return
        }
        "zebar-config" { Invoke-ZebarConfigCommand -ZebarArgs $remainingArgs; return }
        "stop" {
            Stop-Process -Name "komorebi-bar" -ErrorAction SilentlyContinue
            Stop-Process -Name "zebar" -ErrorAction SilentlyContinue
            Write-UiLine -Role ok -Message "Bar stopped."
            return
        }
        "start" {
            $zebarCommand = Get-Command zebar -ErrorAction SilentlyContinue
            if (-not $zebarCommand) {
                Write-UiLine -Role warn -Message "Zebar is not installed. Run 'oooconf deps zebar' first."
                return
            }
            & $zebarCommand.Source startup *> $null
            Write-UiLine -Role ok -Message "Bar started."
            return
        }
        "reload" {
            Stop-Process -Name "komorebi-bar" -ErrorAction SilentlyContinue
            Stop-Process -Name "zebar" -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
            $zebarCommand = Get-Command zebar -ErrorAction SilentlyContinue
            if ($zebarCommand) {
                & $zebarCommand.Source startup *> $null
            }
            Write-UiLine -Role ok -Message "Bar reloaded."
            return
        }
        "help" {
            Write-UiHelpBlock @"
Usage: oooconf wm bar set <type>
       oooconf wm bar zebar-config status
       oooconf wm bar zebar-config list
       oooconf wm bar zebar-config set <name>

Subcommands:
  set           set or show default bar type
  zebar-config  manage zebar configs (status, list, set)
  stop          stop zebar and komorebi-bar (keep komorebi running)
  start         start zebar with configured settings
  reload        restart zebar (stop then start)
  help          show this help
"@
            return
        }
        default {
            $suggestion = Get-SuggestionFromList -InputValue $action -Candidates $KnownBarSubcommands
            Write-UnknownCommandMessage -Message "Unknown bar subcommand: $action" -Suggestion $suggestion -Scope "wm bar"
            throw "Unknown bar subcommand: $action"
        }
    }
}

function Get-DefaultBarType {
    $configPath = Get-ZebarConfigRoot
    $settingsPath = Join-Path $configPath "config.yaml"
    if (-not (Test-Path $settingsPath)) {
        return "zebar"  # default
    }
    $content = Get-Content -Path $settingsPath -Raw
    if ($content -match 'default_bar_type:\s*(\S+)') {
        return $matches[1]
    }
    return "zebar"  # default
}

function Set-DefaultBarType {
    param([string]$Type)
    if ($Type -notin $KnownBarTypes) {
        Write-UiLine -Role fail -Message "Unknown bar type: $Type. Available: $($KnownBarTypes -join ', ')"
        return $false
    }
    $configPath = Get-ZebarConfigRoot
    $settingsPath = Join-Path $configPath "config.yaml"
    if (-not (Test-Path $settingsPath)) {
        Write-UiLine -Role fail -Message "Zebar config.yaml not found at $settingsPath."
        return $false
    }
    $content = Get-Content -Path $settingsPath -Raw
    if ($content -match 'default_bar_type:\s*\S+') {
        $content = $content -replace 'default_bar_type:\s*\S+', "default_bar_type: $Type"
    } else {
        $content = $content -replace '(?m)^(window:)', ("default_bar_type: $Type`n`$1")
    }
    Set-Content -Path $settingsPath -Value $content
    return $true
}

function Invoke-BarSetCommand {
    if ($Args.Count -eq 0 -or $Args[0] -notin $KnownBarTypes) {
        $current = Get-DefaultBarType
        Write-UiLine -Role info -Message "Current default bar type: $current"
        Write-UiLine -Role hint -Message "Usage: wm bar set <type>  (available: $($KnownBarTypes -join ', '))"
        return
    }
    $type = $Args[0]
    $result = Set-DefaultBarType -Type $type
    if ($result) {
        Write-UiLine -Role ok -Message "Default bar type set to $type."
    }
}

function Show-ShellStatus {
    Write-UiLine -Role info -Message "forgit-aliases: $(Get-ForgitAliasMode)"
    Write-UiLine -Role info -Message "typo-handling: $(Get-TypoHandlingMode)"
    Write-UiLine -Role info -Message "psfzf-tab: $(Get-PsfzfTabMode)"
    Write-UiLine -Role info -Message "psfzf-git: $(Get-PsfzfGitMode)"
    Write-UiLine -Role info -Message "prompt: $(Get-ZshPromptMode)"
    Write-UiLine -Role info -Message "prompt-style: $(Get-PromptStyleMode)"
    Write-UiLine -Role info -Message "auto-uv-env: $(Get-AutoUvEnvMode)"
}

function Write-UnknownCommandMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Suggestion,
        [string]$Scope = "main"
    )

    $mode = Get-TypoHandlingMode
    switch ($mode) {
        "silent" {
            return
        }
        "suggest" {
            if ($Suggestion) {
                Write-UiLine -Role hint -Message "Did you mean: $Suggestion"
            } else {
                Write-UiLine -Role fail -Message $Message
            }
            return
        }
        default {
            Write-UiLine -Role fail -Message $Message
            if ($Suggestion) {
                Write-UiLine -Role hint -Message "Did you mean: $Suggestion"
            }
            if ($Scope -eq "shell") {
                Show-CommandUsage "shell"
            } else {
                Show-Usage
            }
            return
        }
    }
}

function Invoke-ShellCommand {
    param(
        [string[]]$ShellArgs
    )

    $subcommand = if ($ShellArgs.Count -gt 0) { $ShellArgs[0] } else { "" }

    switch ($subcommand) {
        "" { Show-CommandUsage "shell"; return }
        "help" { Show-CommandUsage "shell"; return }
        "-h" { Show-CommandUsage "shell"; return }
        "--help" { Show-CommandUsage "shell"; return }
        "status" { Show-ShellStatus; return }

        "prompt" {
            $mode = if ($ShellArgs.Count -gt 1) { $ShellArgs[1] } else { "status" }
            switch ($mode) {
                "status" { Write-Output (Get-ZshPromptMode) }
                "p10k" { Set-ZshPromptMode -Mode $mode }
                "ohmyposh" { Set-ZshPromptMode -Mode $mode }
                default {
                    $suggestion = Get-SuggestionFromList -InputValue $mode -Candidates $KnownShellPromptModes
                    Write-UnknownCommandMessage -Message "Unknown shell option: $mode" -Suggestion $suggestion -Scope shell
                    throw "Unknown shell option: $mode`nExpected one of: p10k, ohmyposh, status"
                }
            }
            return
        }
        "prompt-style" {
            $mode = if ($ShellArgs.Count -gt 1) { $ShellArgs[1] } else { "status" }
            switch ($mode) {
                "status" { Write-Output (Get-PromptStyleMode) }
                "verbose" { Set-PromptStyleMode -Mode $mode }
                "concise" { Set-PromptStyleMode -Mode $mode }
                default {
                    $suggestion = Get-SuggestionFromList -InputValue $mode -Candidates $KnownShellPromptStyleModes
                    Write-UnknownCommandMessage -Message "Unknown shell option: $mode" -Suggestion $suggestion -Scope shell
                    throw "Unknown shell option: $mode`nExpected one of: verbose, concise, status"
                }
            }
            return
        }
        "forgit-aliases" {
            $mode = if ($ShellArgs.Count -gt 1) { $ShellArgs[1] } else { "status" }
            switch ($mode) {
                "status" { Write-Output (Get-ForgitAliasMode) }
                "plain" { Set-ForgitAliasMode -Mode $mode }
                "forgit" { Set-ForgitAliasMode -Mode $mode }
                default {
                    $suggestion = Get-SuggestionFromList -InputValue $mode -Candidates $KnownShellForgitModes
                    Write-UnknownCommandMessage -Message "Unknown shell option: $mode" -Suggestion $suggestion -Scope shell
                    throw "Unknown shell option: $mode`nExpected one of: plain, forgit, status"
                }
            }
            return
        }
        "typo-handling" {
            $mode = if ($ShellArgs.Count -gt 1) { $ShellArgs[1] } else { "status" }
            switch ($mode) {
                "status" { Write-Output (Get-TypoHandlingMode) }
                "silent" { Set-TypoHandlingMode -Mode $mode }
                "suggest" { Set-TypoHandlingMode -Mode $mode }
                "help" { Set-TypoHandlingMode -Mode $mode }
                default {
                    $suggestion = Get-SuggestionFromList -InputValue $mode -Candidates $KnownShellTypoModes
                    Write-UnknownCommandMessage -Message "Unknown shell option: $mode" -Suggestion $suggestion -Scope shell
                    throw "Unknown shell option: $mode`nExpected one of: silent, suggest, help, status"
                }
            }
            return
        }
        "psfzf-tab" {
            $mode = if ($ShellArgs.Count -gt 1) { $ShellArgs[1] } else { "status" }
            switch ($mode) {
                "status" { Write-Output (Get-PsfzfTabMode) }
                "enabled" { Set-PsfzfTabMode -Mode $mode }
                "disabled" { Set-PsfzfTabMode -Mode $mode }
                default {
                    $suggestion = Get-SuggestionFromList -InputValue $mode -Candidates $KnownShellPsfzfModes
                    Write-UnknownCommandMessage -Message "Unknown shell option: $mode" -Suggestion $suggestion -Scope shell
                    throw "Unknown shell option: $mode`nExpected one of: enabled, disabled, status"
                }
            }
            return
        }
        "psfzf-git" {
            $mode = if ($ShellArgs.Count -gt 1) { $ShellArgs[1] } else { "status" }
            switch ($mode) {
                "status" { Write-Output (Get-PsfzfGitMode) }
                "enabled" { Set-PsfzfGitMode -Mode $mode }
                "disabled" { Set-PsfzfGitMode -Mode $mode }
                default {
                    $suggestion = Get-SuggestionFromList -InputValue $mode -Candidates $KnownShellPsfzfModes
                    Write-UnknownCommandMessage -Message "Unknown shell option: $mode" -Suggestion $suggestion -Scope shell
                    throw "Unknown shell option: $mode`nExpected one of: enabled, disabled, status"
                }
            }
            return
        }
        "auto-uv-env" {
            $mode = if ($ShellArgs.Count -gt 1) { $ShellArgs[1] } else { "status" }
            switch ($mode) {
                "status" { Write-Output (Get-AutoUvEnvMode) }
                "enabled" { Set-AutoUvEnvMode -Mode $mode }
                "quiet" { Set-AutoUvEnvMode -Mode $mode }
                default {
                    $suggestion = Get-SuggestionFromList -InputValue $mode -Candidates $KnownShellAutoUvModes
                    Write-UnknownCommandMessage -Message "Unknown shell option: $mode" -Suggestion $suggestion -Scope shell
                    throw "Unknown shell option: $mode`nExpected one of: enabled, quiet, status"
                }
            }
            return
        }
        default {
            $suggestion = Get-SuggestionFromList -InputValue $subcommand -Candidates $KnownShellSubcommands
            Write-UnknownCommandMessage -Message "Unknown shell subcommand: $subcommand" -Suggestion $suggestion -Scope shell
            throw "Unknown shell subcommand: $subcommand"
        }
    }
}

function Invoke-ColorCommand {
    param(
        [string[]]$ColorArgs
    )

    $action = if ($ColorArgs.Count -gt 0) { $ColorArgs[0] } else { "status" }
    switch ($action) {
        "status" {
            Write-Output (Get-OooconfTheme)
            Run-Python -ScriptPath $SyncColorThemeScript -ScriptArgs @("status")
        }
        "list" { $KnownColorThemes | ForEach-Object { Write-Output $_ } }
        "help" { Show-CommandUsage "color" }
        "-h" { Show-CommandUsage "color" }
        "--help" { Show-CommandUsage "color" }
        default { Set-OooconfTheme -Theme $action }
    }
}

function Resolve-CommandAlias {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    switch ($CommandName) {
        "check" { return "doctor" }
        "preview" { return "dry-run" }
        "upgrade" { return "update" }
        default { return $CommandName }
    }
}

function Get-EditDistance {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Left,
        [Parameter(Mandatory = $true)]
        [string]$Right
    )

    $Left = [string]$Left
    $Right = [string]$Right

    $rightLength = $Right.Length
    $previous = New-Object int[] ($rightLength + 1)
    for ($j = 0; $j -le $rightLength; $j++) {
        $previous[$j] = $j
    }

    for ($i = 1; $i -le $Left.Length; $i++) {
        $current = New-Object int[] ($rightLength + 1)
        $current[0] = $i
        $leftChar = $Left.Substring($i - 1, 1)

        for ($j = 1; $j -le $rightLength; $j++) {
            $rightChar = $Right.Substring($j - 1, 1)
            $cost = if ($leftChar -ceq $rightChar) { 0 } else { 1 }
            $deletion = $previous[$j] + 1
            $insertion = $current[($j - 1)] + 1
            $substitution = $previous[($j - 1)] + $cost
            $current[$j] = [Math]::Min([Math]::Min($deletion, $insertion), $substitution)
        }

        $previous = $current
    }

    return $previous[$rightLength]
}

function Get-CommandSuggestion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputCommand
    )

    $bestCommand = $null
    $bestDistance = [int]::MaxValue

    foreach ($candidate in @($KnownCommands | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        $candidateText = [string]$candidate
        $distance = Get-EditDistance -Left $InputCommand -Right $candidateText
        if ($distance -lt $bestDistance) {
            $bestDistance = $distance
            $bestCommand = $candidateText
        }
    }

    $threshold = if ($InputCommand.Length -le 4) { 2 } else { 3 }
    if ($bestDistance -le $threshold) {
        return $bestCommand
    }

    return $null
}

function Get-SuggestionFromList {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputValue,
        [Parameter(Mandatory = $true)]
        [string[]]$Candidates
    )

    $bestMatch = $null
    $bestDistance = [int]::MaxValue

    foreach ($candidate in @($Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        $candidateText = [string]$candidate
        $distance = Get-EditDistance -Left $InputValue -Right $candidateText
        if ($distance -lt $bestDistance) {
            $bestDistance = $distance
            $bestMatch = $candidateText
        }
    }

    $threshold = if ($InputValue.Length -le 4) { 2 } else { 3 }
    if ($bestDistance -le $threshold) {
        return $bestMatch
    }

    return $null
}

$AgentsToolScript = Join-Path $RepoRoot "scripts/cli/agents_tool.py"

function Get-Version {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        try {
            $version = git -C $RepoRoot describe --always --dirty --tags 2>$null
            if ($LASTEXITCODE -eq 0 -and $version) {
                return $version.Trim()
            }
        } catch {
        }

        try {
            $version = git -C $RepoRoot rev-parse --short HEAD 2>$null
            if ($LASTEXITCODE -eq 0 -and $version) {
                return $version.Trim()
            }
        } catch {
        }
    }

    return "unknown"
}

function Show-Usage {
    Write-UiBanner
    Write-UiSpacer
    Write-Output (Format-UiText -Text "Usage: oooconf [global options] <command> [command options]" -Role "section" -Bold)
    Write-Output (Format-UiText -Text "A reproducible cross-platform dotfiles manager with setup, health checks, secrets, and shell tooling." -Role "muted")

    Write-UiSpacer
    Write-UiSeparator
    Write-UiSectionFancy -IconName "version" -Title "Global options"
    Write-Output @"
  -C, --repo-root PATH  run against a specific repo checkout
  -h, --help            show this help
  -n, --dry-run         add --dry-run to install or update
      --yes-optional    auto-accept optional dependency installs
      --skip-deps       skip dependency installation
  -V, --version         show CLI version information
      --print-repo-root print the resolved repo root and exit
"@

    Write-UiSpacer
    Write-UiSeparator
    Write-UiSectionFancy -IconName "install" -Title "Setup"
    Write-UiCommandRow -CommandName "install" -Description "apply managed config and optional dependency installs"
    Write-UiCommandRow -CommandName "deps" -Description "install optional dependencies only"
    Write-UiCommandRow -CommandName "update" -Description "pull repo with --ff-only, then re-run install"

    Write-UiSpacer
    Write-UiSectionFancy -IconName "doctor" -Title "Inspect & Validate"
    Write-UiCommandRow -CommandName "doctor" -Description "validate managed symlinks and required commands"
    Write-UiCommandRow -CommandName "dry-run" -Description "preview install flow without mutating filesystem"
    Write-UiCommandRow -CommandName "version" -Description "print CLI version and repo root"

    Write-UiSpacer
    Write-UiSectionFancy -IconName "lock" -Title "Manage State"
    Write-UiCommandRow -CommandName "delete" -Description "remove managed links and restore latest backups"
    Write-UiCommandRow -CommandName "remove" -Description "remove managed links only (no backup restore)"
    Write-UiCommandRow -CommandName "lock" -Description "regenerate dependency lock artifacts from pinned refs"
    Write-UiCommandRow -CommandName "update-pins" -Description "compare/update pinned refs and refresh lock artifacts"
    Write-UiCommandRow -CommandName "completions" -Description "regenerate tracked shell completions (autogen + oooconf)"
    Write-UiCommandRow -CommandName "link" -Description "inspect or manage links from the symlink manifest"

    Write-UiSpacer
    Write-UiSectionFancy -IconName "shell" -Title "Shell / Secrets / Agents"
    Write-UiCommandRow -CommandName "shell" -Description "manage local shell preferences such as forgit aliases"
    Write-UiCommandRow -CommandName "color" -Description "set a unified oooconf CLI color theme"
    Write-UiCommandRow -CommandName "secrets" -Description "sync or validate local secret env files"
    Write-UiCommandRow -CommandName "agents" -Description "detect/sync/doctor/update AGENTS.md and agent CLI workflows"
    Write-UiCommandRow -CommandName "wm" -Description "switch between or manage window managers (komorebi/glazewm)"

    Write-UiSpacer
    Write-UiSeparator
    Write-UiHelpBlock @"
Aliases:
  check -> doctor
  preview -> dry-run
  upgrade -> update
Note:
  bootstrap is Unix-only in this wrapper.
  On Windows, run ``scripts/setup/setup.ps1 install`` for initial setup.
Getting help:
  oooconf --help                     show this message
  oooconf help <command>             show command-specific help
  oooconf help secrets               show secrets subcommand help
UI controls:
  `$env:OOOCONF_COLOR='always'       override color output
  `$env:OOOCONF_ASCII='1'            force ASCII icons and borders
  `$env:OOOCONF_THEME='<theme>'      set the CLI color theme for this run
Common workflows:
  # Initial setup on Windows:
  ./scripts/setup/setup.ps1 install
  # Preview what install would do:
  oooconf dry-run
  # Apply config and install dependencies:
  oooconf install
  oooconf deps
"@
}

function Show-CommandUsage {
    param($command)
    switch ($command) {
        "install" {
            Write-UiHelpBlock @"
Usage: oooconf install [--dry-run] [--yes-optional] [--skip-deps]

Apply managed config and optional dependency installation.
Creates symlinks from tracked config in home/ to their target locations,
backing up any replaced files. Optionally installs dependencies when
allowed.
Examples:
  oooconf install                      # interactive dependency prompts
  oooconf install --yes-optional       # auto-accept all optional installs
  oooconf install --skip-deps          # apply config without dependency installs
  oooconf install --dry-run            # preview without making changes
"@
        }
        "deps" {
            Write-UiHelpBlock @"
Usage: oooconf deps [--dry-run] [--all] [dependency-key...]

Install optional dependencies only. Without dependency keys, an interactive
picker is shown (using gum if available).

All dependency metadata (including versions, URLs, and install methods) lives exclusively in scripts/optional-deps.toml.
Examples:
  oooconf deps                         # interactive picker (when gum available)
  oooconf deps key1 key2               # install specific dependency keys
  oooconf deps --dry-run               # preview only
  oooconf deps --all                   # install all dependency keys
"@
        }
        "update" {
            Write-UiHelpBlock @"
Usage: oooconf update [--dry-run] [--yes-optional]

Pull the repo with --ff-only, then re-run the install flow.
Use this to update your config to the latest tracked state. It performs
a fast-forward pull only, failing if local changes would prevent it.
Examples:
  oooconf update                       # pull and reinstall
  oooconf update --yes-optional        # also install missing dependencies
  oooconf update --dry-run             # preview pull and install
"@
        }
        "doctor" {
            Write-UiHelpBlock @"
Usage: oooconf doctor

Validate managed symlinks and required commands.
Checks that all managed config links point to valid targets and that
key tools (git, zsh, wezterm, yazi, nvim, etc.) are available on PATH.
Examples:
  oooconf doctor                       # run all checks
"@
        }
        "dry-run" {
            Write-UiHelpBlock @"
Usage: oooconf dry-run

Preview the install flow without mutating the filesystem.
Shows what links would be created, what files would be backed up, and
what dependencies would be installed, without making any changes.
Examples:
  oooconf dry-run                      # preview install
  oooconf --yes-optional dry-run       # preview with dependency installs
"@
        }
        "link" {
            Write-UiHelpBlock @"
Usage: oooconf link [--dry-run]

Create or update symlinks from tracked config in home/ to their target
locations, backing up any replaced files. Reads from links.toml manifest
with auto-discovery for home/.config, home/.local, and home/.glzr.
Examples:
  oooconf link                       # create/update all manifest links
  oooconf link --dry-run            # preview without making changes
"@
        }
        "delete" {
            Write-UiHelpBlock @"
Usage: oooconf delete

Remove managed links and restore the latest backups when available.
Use this to undo the managed config and return to your previous state.
Backup files are stored in ~/.local/state/ooodnakov-config/backups/.
Examples:
  oooconf delete                       # restore from backups
"@
        }
        "remove" {
            Write-UiHelpBlock @"
Usage: oooconf remove

Remove managed links without restoring backups.
Use this when you want to cleanly remove the managed config without
putting previous files back in place.
Examples:
  oooconf remove                       # clean removal
"@
        }
        "lock" {
            Write-UiHelpBlock @"
Usage: oooconf lock

Regenerate dependency lock artifacts from pinned refs in setup scripts.
Reads pinned versions from scripts/setup/setup.ps1 (or setup.sh) and writes
the resolved lock file to deps.lock.json.
Examples:
  oooconf lock                         # regenerate lock artifact
"@
        }
        "update-pins" {
            Write-UiHelpBlock @"
Usage: oooconf update-pins [--apply]

Compare pinned git refs to upstream HEAD and refresh lock artifacts.
Without --apply, only reports differences. With --apply, updates the
pinned refs in setup scripts and regenerates lock artifacts.
Examples:
  oooconf update-pins                  # check for pin drift
  oooconf update-pins --apply          # update pins and regenerate lock
"@
        }
        "completions" {
            Write-UiHelpBlock @"
Usage: oooconf completions [--dry-run]

Regenerate tracked shell completion files:
  - autogen zsh completions under home/.config/ooodnakov/zsh/completions/autogen
  - oooconf command completions for zsh and PowerShell
This does not install dependencies; it only rebuilds completion files.
Examples:
  oooconf completions                  # rebuild tracked completion files
  oooconf completions --dry-run        # preview generation actions
"@
        }
        "agents" {
            Write-UiHelpBlock @"

Usage: oooconf agents <detect|sync|doctor|install|provider|update|mcp|rtk|skills> [options]

Manage shared AGENTS.md instructions and validate configured agent tooling.
Subcommands:
  detect [--json]                detect configured agent CLIs on PATH
  sync [--check] [--materialize-secrets]
                                  append/update shared AGENTS.md managed block
  doctor [--strict-config-paths] verify AGENTS.md managed block and default agent config paths
  install [<agent> ...] [--all|--missing] [--check]
                                  install missing, selected, or all configured agent CLIs
  update [--check]               update installed agent CLIs (pnpm-based tools use pnpm)
  provider sync minimax [--check] [--region global|china] [--materialize-secrets]
                                  configure MiniMax-M2.7 backends for Claude Code, OpenCode, and Codex CLI
  mcp sync|status                synchronize or inspect managed MCP servers
  rtk init [--check]             initialize RTK hooks for detected agents
  mcp add [--name N] [--json J] [--multi] [--preview] [--sync-now]
                                  add one MCP JSON server entry to shared config
  skills sync [--check]          sync configured skill specs across agents
  skills view [--check] [--json] list global shared skills catalog via pnpm dlx
  skills add <source> [--agent gemini] [--sync-now]
                                  add one shared skill source
Examples:
  oooconf agents detect                 # list available agent CLIs
  oooconf agents sync --check           # verify AGENTS.md managed sections
  oooconf agents install --check        # preview missing agent CLI installs
  oooconf agents install codex gemini   # install selected agent CLIs
  oooconf agents mcp status             # show managed MCP server status
  oooconf agents provider sync minimax   # configure MiniMax-M2.7 provider backends
  oooconf agents skills view --json     # show shared skills catalog as JSON
"@
        }
        "secrets" {
            Write-UiHelpBlock @"
Usage: oooconf secrets <sync|doctor|list|status|login|unlock|logout|add|remove> [options]

Render or validate local secret env files from the tracked template.
Examples:
  oooconf secrets                      # show current sync/session status
  oooconf secrets login                # choose login method interactively
  oooconf secrets login --method apikey
  oooconf secrets unlock               # prompt for password and save session
  oooconf secrets unlock 'your-password'
  oooconf secrets unlock --shell pwsh | Invoke-Expression
  oooconf secrets sync
  oooconf secrets sync --dry-run
  oooconf secrets ls                   # alias for list
  oooconf secrets list
  oooconf secrets list --resolved
  oooconf secrets status
  oooconf secrets doctor
  oooconf secrets logout
  oooconf secrets add GITHUB_TOKEN bw://item/abc123/password
  oooconf secrets add SOME_URL https://example.com
  oooconf secrets rm GITHUB_TOKEN      # alias for remove
  oooconf secrets remove GITHUB_TOKEN
Environment overrides:
  OOODNAKOV_SECRETS_BACKEND
  OOODNAKOV_BW_SERVER
"@
        }
        "version" {
            Write-UiHelpBlock @"
Usage: oooconf version

Print the CLI version (git describe or commit SHA) and resolved repo root.
Examples:
  oooconf version                      # show version and repo path
"@
        }
        "shell" {
            Write-UiHelpBlock @"
Usage: oooconf shell status
       oooconf shell prompt [p10k|ohmyposh|status]
       oooconf shell prompt-style [verbose|concise|status]
       oooconf shell forgit-aliases [plain|forgit|status]
       oooconf shell typo-handling [silent|suggest|help|status]
       oooconf shell psfzf-tab [enabled|disabled|status]
       oooconf shell psfzf-git [enabled|disabled|status]
       oooconf shell auto-uv-env [enabled|quiet|status]

Manage local shell preferences that live in the preserved LOCAL OVERRIDES block.
Forgit alias modes:
  plain   keep plain git aliases like gd/gco and define glo as git log
  forgit  enable upstream forgit aliases like glo/gd/gco
  status  show the currently configured mode
Typo handling modes:
  silent   exit 1 without printing anything for wrong commands
  suggest  print only the closest suggestion when available
  help     print the unknown command, suggestion, and full help
PSFzf options:
  psfzf-tab  enable or disable fzf-based tab completion in PowerShell
  psfzf-git  enable or disable fzf-based git keybindings in PowerShell
  status     show the currently configured mode
Prompt options:
  prompt        switch only the zsh prompt engine between Powerlevel10k and Oh My Posh
  prompt-style  switch all managed prompts between verbose and concise layouts
  status        show the currently configured mode
Auto UV environment options:
  enabled   show activation/deactivation messages for Python venvs
  quiet     suppress activation/deactivation messages
  status    show the currently configured mode
Examples:
  oooconf shell status
  oooconf shell prompt status
  oooconf shell prompt ohmyposh
  oooconf shell prompt p10k
  oooconf shell prompt-style concise
  oooconf shell forgit-aliases status
  oooconf shell forgit-aliases plain
  oooconf shell forgit-aliases forgit
  oooconf shell typo-handling status
  oooconf shell typo-handling suggest
  oooconf shell typo-handling silent
  oooconf shell psfzf-tab enabled
  oooconf shell psfzf-tab disabled
  oooconf shell psfzf-git status
  oooconf shell auto-uv-env quiet
"@
        }
        "color" {
            Write-UiHelpBlock @"
Usage: oooconf color [status|list|<theme>]

Set or inspect the oooconf CLI color theme.
Themes:
  default, catppuccin, gruvbox, nord, tokyonight, noctalia
This also syncs theme-friendly overrides for yazi, wezterm local override, komorebi/komorebi.bar, sketchybar colors, zebar css vars, and themed oh-my-posh config.
Status output also reports detected nvim and oh-my-posh theme config state.
Examples:
  oooconf color status                 # print current theme and synced config state
  oooconf color list                   # list available themes
  oooconf color catppuccin             # switch to Catppuccin colors
  oooconf color noctalia               # switch to Noctalia colors
"@
        }
        "wm" {
            Write-UiHelpBlock @"
Usage: oooconf wm status
       oooconf wm set [komorebi|glazewm]
       oooconf wm start
       oooconf wm stop
       oooconf wm reload
       oooconf wm bar set zebar <name>
       oooconf wm bar zebar-config status
       oooconf wm bar zebar-config list
       oooconf wm bar zebar-config set <name>
       oooconf wm komorebi reload
       oooconf wm komorebi start [--bar]
       oooconf wm komorebi stop [--bar]

Switch between or manage window managers.
Subcommands:
  status         shows the currently running window manager
  set            stops the current WM and starts the specified one
  start          starts the default WM (komorebi)
  stop           stops any running WM stack
  reload         reloads the configuration of the active WM
  bar            manage bar and zebar (set, zebar-config)
  komorebi       manage komorebi (reload, start, stop) with optional --bar
Examples:
  oooconf wm status
  oooconf wm set glazewm
  oooconf wm reload
  oooconf wm bar set zebar overline-zebar-komorebi
  oooconf wm bar zebar-config list
  oooconf wm bar zebar-config set overline-zebar-komorebi
  oooconf wm komorebi start --bar
  oooconf wm komorebi stop --bar
"@
        }
        "wm bar" {
            Write-UiHelpBlock @"
Usage: oooconf wm bar set <type>
       oooconf wm bar zebar-config status
       oooconf wm bar zebar-config list
       oooconf wm bar zebar-config set <name>
       oooconf wm bar stop
       oooconf wm bar start
       oooconf wm bar reload
       oooconf wm bar help

Subcommands:
  set           set or show default bar type
  zebar-config  manage zebar configs (status, list, set)
  stop          stop zebar and komorebi-bar (keep komorebi running)
  start         start zebar with configured settings
  reload        restart zebar (stop then start)
  help          show this help
Examples:
  oooconf wm bar set              # show current bar type
  oooconf wm bar set zebar        # set to zebar
  oooconf wm bar zebar-config list
  oooconf wm bar zebar-config set overline-zebar-komorebi
  oooconf wm bar stop
  oooconf wm bar start
  oooconf wm bar reload
"@
        }
        "" { Show-Usage }
        "help" { Show-Usage }
        "-h" { Show-Usage }
        "--help" { Show-Usage }
        default {
            $suggestion = Get-CommandSuggestion -InputCommand $CommandName
            Write-UnknownCommandMessage -Message "Unknown command: $CommandName" -Suggestion $suggestion
            throw "Unknown command: $CommandName"
        }
    }
}

function Require-PythonRuntime {
    $pyprojectPath = Join-Path $RepoRoot "pyproject.toml"
    if ((Get-Command uv -ErrorAction SilentlyContinue) -and (Test-Path $pyprojectPath)) {
        return
    }

    if (Get-Command python3 -ErrorAction SilentlyContinue) {
        return
    }

    throw "python3 or uv is required."
}

$dryRunRequested = $false
$yesOptionalRequested = $false
$skipDepsRequested = $false
$command = $null
$remaining = [System.Collections.Generic.List[string]]::new()

for ($i = 0; $i -lt $Arguments.Count; $i++) {
    $arg = $Arguments[$i]
    switch ($arg) {
        "-C" {
            if ($i + 1 -ge $Arguments.Count) {
                throw "Missing value for $arg"
            }
            $RepoRoot = $Arguments[$i + 1]
            $i++
        }
        "--repo-root" {
            if ($i + 1 -ge $Arguments.Count) {
                throw "Missing value for $arg"
            }
            $RepoRoot = $Arguments[$i + 1]
            $i++
        }
        "--print-repo-root" {
            Write-UiLine -Role info -Message $RepoRoot
            exit 0
        }
        "-V" {
            Write-UiLine -Role info -Message "oooconf $(Get-Version)"
            Write-UiLine -Role info -Message $RepoRoot
            exit 0
        }
        "--version" {
            Write-UiLine -Role info -Message "oooconf $(Get-Version)"
            Write-UiLine -Role info -Message $RepoRoot
            exit 0
        }
        "-h" {
            if ($i + 1 -lt $Arguments.Count -and -not $Arguments[$i + 1].StartsWith("-")) {
                Show-CommandUsage (Resolve-CommandAlias -CommandName $Arguments[$i + 1])
            } else {
                Show-Usage
            }
            exit 0
        }
        "--help" {
            if ($i + 1 -lt $Arguments.Count -and -not $Arguments[$i + 1].StartsWith("-")) {
                Show-CommandUsage (Resolve-CommandAlias -CommandName $Arguments[$i + 1])
            } else {
                Show-Usage
            }
            exit 0
        }
        "-n" {
            $dryRunRequested = $true
        }
        "--dry-run" {
            $dryRunRequested = $true
        }
        "--yes-optional" {
            $yesOptionalRequested = $true
        }
        "--skip-deps" {
            $skipDepsRequested = $true
        }
        "help" {
            if ($i + 1 -lt $Arguments.Count) {
                Show-CommandUsage (Resolve-CommandAlias -CommandName $Arguments[$i + 1])
            } else {
                Show-Usage
            }
            exit 0
        }
        "version" {
            Write-UiLine -Role info -Message "oooconf $(Get-Version)"
            Write-UiLine -Role info -Message $RepoRoot
            exit 0
        }
        default {
            $command = Resolve-CommandAlias -CommandName $arg
            for ($j = $i + 1; $j -lt $Arguments.Count; $j++) {
                $remaining.Add($Arguments[$j])
            }
            break
        }
    }

    if ($command) {
        break
    }
}

if (-not $command) {
    if ($dryRunRequested) {
        $command = "install"
    } else {
        Show-Usage
        exit 0
    }
}

function Test-ShouldNormalizeGlobalFlags {
    param([Parameter(Mandatory = $true)][string]$CommandName)
    return $CommandName -in @("bootstrap", "install", "deps", "update", "doctor", "completions", "dry-run", "delete", "remove", "lock", "update-pins", "agents")
}

if (Test-ShouldNormalizeGlobalFlags -CommandName $command) {
    $normalizedRemaining = @()
    foreach ($arg in $remaining) {
        switch ($arg) {
            "-n" { $dryRunRequested = $true }
            "--dry-run" { $dryRunRequested = $true }
            "--yes-optional" { $yesOptionalRequested = $true }
            "--skip-deps" { $skipDepsRequested = $true }
            default { $normalizedRemaining += $arg }
        }
    }
    $remaining = $normalizedRemaining
}

$env:OOODNAKOV_REPO_ROOT = $RepoRoot
if ($yesOptionalRequested) {
    $env:OOODNAKOV_INSTALL_OPTIONAL = "always"
}

function Invoke-SetupCommand {
    param(
        [Parameter(Mandatory = $true)][string]$SetupCommand,
        [switch]$SupportsDryRun,
        [string[]]$RemainingArgs = @()
    )

    if ($dryRunRequested) {
        if (-not $SupportsDryRun) {
            throw "--dry-run is not supported for $SetupCommand"
        }
        & $SetupScript $SetupCommand -DryRun -SkipDeps:$skipDepsRequested @RemainingArgs
        if ($LASTEXITCODE -ne 0) {
            throw "setup $SetupCommand failed with exit code $LASTEXITCODE"
        }
        return
    }

    & $SetupScript $SetupCommand -SkipDeps:$skipDepsRequested @RemainingArgs
    if ($LASTEXITCODE -ne 0) {
        throw "setup $SetupCommand failed with exit code $LASTEXITCODE"
    }
}

function Assert-NoDryRun {
    param([Parameter(Mandatory = $true)][string]$CommandName)
    if ($dryRunRequested) {
        throw "--dry-run is not supported for $CommandName"
    }
}

function Invoke-DeleteCommand {
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)][string]$DeleteMode,
        [string[]]$RemainingArgs = @()
    )
    Assert-NoDryRun -CommandName $CommandName
    $env:OOODNAKOV_REPO_ROOT = $RepoRoot
    & $DeleteScript $DeleteMode @RemainingArgs
}

switch ($command) {
    "install" {
        Invoke-SetupCommand -SetupCommand "install" -SupportsDryRun -RemainingArgs $remaining
    }
    "deps" {
        Invoke-SetupCommand -SetupCommand "deps" -SupportsDryRun -RemainingArgs $remaining
    }
    "update" {
        Invoke-SetupCommand -SetupCommand "update" -SupportsDryRun -RemainingArgs $remaining
    }
    "delete" {
        Invoke-DeleteCommand -CommandName "delete" -DeleteMode "restore" -RemainingArgs $remaining
    }
    "remove" {
        Invoke-DeleteCommand -CommandName "remove" -DeleteMode "remove" -RemainingArgs $remaining
    }
    "doctor" {
        Invoke-SetupCommand -SetupCommand "doctor" -RemainingArgs $remaining
    }
    "dry-run" {
        if ($dryRunRequested) {
            throw "Use either dry-run or --dry-run, not both"
        }
        & $SetupScript install -DryRun @remaining
    }
    "lock" {
        Assert-NoDryRun -CommandName "lock"
        Run-Python -ScriptPath $GenerateLockScript -ScriptArgs $remaining
    }
    "update-pins" {
        Assert-NoDryRun -CommandName "update-pins"
        Run-Python -ScriptPath $UpdatePinsScript -ScriptArgs $remaining
    }
    "completions" {
        Invoke-SetupCommand -SetupCommand "completions" -SupportsDryRun -RemainingArgs $remaining
    }
    "secrets" {
        Run-Python -ScriptPath $RenderSecretsScript -ScriptArgs (@("--repo-root", $RepoRoot) + $remaining)
    }
    "shell" {
        Invoke-ShellCommand -ShellArgs $remaining
    }
    "color" {
        Invoke-ColorCommand -ColorArgs $remaining
    }
    "agents" {
        Assert-NoDryRun -CommandName "agents"
        if ($remaining.Count -eq 0 -or $remaining[0] -in @("-h", "--help", "help")) {
            Show-CommandUsage "agents"
            exit 0
        }
        Require-PythonRuntime
        Run-Python -ScriptPath $AgentsToolScript -ScriptArgs (@("--repo-root", $RepoRoot) + $remaining)
    }
    "wm" {
        if ($remaining.Count -ge 2 -and $remaining[0] -eq "bar" -and $remaining[1] -in @("-h", "--help")) {
            Show-CommandUsage "wm bar"
            exit 0
        }
        if ($remaining.Count -ge 1 -and $remaining[0] -in @("-h", "--help")) {
            Show-CommandUsage "wm"
            exit 0
        }
        Invoke-WmCommand -WmArgs $remaining
    }
    "link" {
        if ($remaining.Count -gt 0 -and $remaining[0] -in @("-h", "--help", "help")) {
            Run-Python -ScriptPath (Join-Path $RepoRoot "scripts/link_manager.py") -ScriptArgs @("--help")
        } else {
            Run-Python -ScriptPath (Join-Path $RepoRoot "scripts/link_manager.py") -ScriptArgs $remaining
        }
    }
    default {
        $suggestion = Get-CommandSuggestion -InputCommand $command
        Write-UnknownCommandMessage -Message "Unknown command: $command" -Suggestion $suggestion
        throw "Unknown command: $command"
    }
}

exit $LASTEXITCODE
