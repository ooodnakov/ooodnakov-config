param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments = @()
)

$ErrorActionPreference = "Stop"

$RepoRoot = if ($env:OOODNAKOV_REPO_ROOT) {
    $env:OOODNAKOV_REPO_ROOT
} else {
    (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}
$SetupScript = Join-Path $PSScriptRoot "setup.ps1"
$DeleteScript = Join-Path $PSScriptRoot "delete.ps1"
$GenerateLockScript = Join-Path $PSScriptRoot "generate_dependency_lock.py"
$UpdatePinsScript = Join-Path $PSScriptRoot "update_pins.py"
$RenderSecretsScript = Join-Path $PSScriptRoot "render_secrets.py"
$AgentsToolScript = Join-Path $PSScriptRoot "agents_tool.py"
$CommandsFile = Join-Path $PSScriptRoot "oooconf-commands.txt"

function Get-KnownCommands {
    $fallback = @("install", "deps", "update", "doctor", "dry-run", "delete", "remove", "lock", "update-pins", "completions", "agents", "secrets", "shell", "version", "check", "preview", "upgrade")
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

$KnownShellSubcommands = @("status", "forgit-aliases", "typo-handling", "psfzf-tab", "psfzf-git", "auto-uv-env")
$KnownShellForgitModes = @("plain", "forgit", "status")
$KnownShellTypoModes = @("silent", "suggest", "help", "status")
$KnownShellPsfzfModes = @("enabled", "disabled", "status")
$KnownShellAutoUvModes = @("enabled", "quiet", "status")
$LocalOverridesStart = "# --- LOCAL OVERRIDES START ---"
$LocalOverridesEnd = "# --- LOCAL OVERRIDES END ---"
$ForgitAliasVar = "OOODNAKOV_FORGIT_ALIAS_MODE"
$TypoHandlingVar = "OOODNAKOV_TYPO_HANDLING_MODE"
$PsfzfTabVar = "OOODNAKOV_PSFZF_TAB"
$PsfzfGitVar = "OOODNAKOV_PSFZF_GIT"
$AutoUvEnvVar = "AUTO_UV_ENV_QUIET"
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
    Section = "$([char]27)[38;5;111m"
    Ok = "$([char]27)[38;5;78m"
    Warn = "$([char]27)[38;5;221m"
    Fail = "$([char]27)[38;5;203m"
    Info = "$([char]27)[38;5;117m"
    Muted = "$([char]27)[38;5;245m"
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

function Get-UiCommandIcon {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (Test-UiNerdFont) {
        switch ($Name) {
            "install" { return [char]::ConvertFromUtf32(0xF05E0) }
            "deps" { return [char]::ConvertFromUtf32(0xF03D6) }
            "update" { return [char]::ConvertFromUtf32(0xF06B0) }
            "doctor" { return [char]::ConvertFromUtf32(0xF04D9) }
            "dry-run" { return [char]::ConvertFromUtf32(0xF0709) }
            "version" { return [char]::ConvertFromUtf32(0xF0386) }
            "lock" { return [char]::ConvertFromUtf32(0xF033E) }
            "update-pins" { return [char]::ConvertFromUtf32(0xF1962) }
            "completions" { return [char]::ConvertFromUtf32(0xF0A6B) }
            "shell" { return [char]::ConvertFromUtf32(0xF1183) }
            "secrets" { return [char]::ConvertFromUtf32(0xF082E) }
            "agents" { return [char]::ConvertFromUtf32(0xF0B79) }
            default { return [char]::ConvertFromUtf32(0xF060D) }
        }
    }
    switch ($Name) {
        "install" { return "[inst]" }
        "deps" { return "[deps]" }
        "update" { return "[up]" }
        "doctor" { return "[doc]" }
        "dry-run" { return "[dry]" }
        "version" { return "[ver]" }
        "lock" { return "[lock]" }
        "update-pins" { return "[pins]" }
        "completions" { return "[comp]" }
        "shell" { return "[sh]" }
        "secrets" { return "[sec]" }
        "agents" { return "[agt]" }
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
    $color = switch ($Role) {
        "section" { $UiAnsi.Section }
        "ok" { $UiAnsi.Ok }
        "warn" { $UiAnsi.Warn }
        "fail" { $UiAnsi.Fail }
        "info" { $UiAnsi.Info }
        "hint" { $UiAnsi.Muted }
        "muted" { $UiAnsi.Muted }
        default { $UiAnsi.Muted }
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
            '^(Examples:|Environment overrides:|Subcommands:|Forgit alias modes:|Typo handling modes:|PSFzf options:)$' {
                Write-Output (Format-UiText -Text $line -Role "info")
                continue
            }
            '^\s{2}(oooconf|OOODNAKOV_)' {
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

function Show-ShellStatus {
    Write-UiLine -Role info -Message "forgit-aliases: $(Get-ForgitAliasMode)"
    Write-UiLine -Role info -Message "typo-handling: $(Get-TypoHandlingMode)"
    Write-UiLine -Role info -Message "psfzf-tab: $(Get-PsfzfTabMode)"
    Write-UiLine -Role info -Message "psfzf-git: $(Get-PsfzfGitMode)"
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

$AgentsToolScript = Join-Path $PSScriptRoot "agents_tool.py"

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
    Write-UiSection "oooconf"
    Write-Output "Usage: oooconf [global options] <command> [command options]"
    Write-Output ""
    Write-Output (Format-UiText -Text "oooconf - reproducible cross-platform dotfiles manager" -Role "section")
    Write-Output (Format-UiText -Text "Global options:" -Role "info")
    Write-Output @"
  -C, --repo-root PATH  run against a specific repo checkout
  -h, --help            show this help
  -n, --dry-run         add --dry-run to install or update
      --yes-optional    auto-accept optional dependency installs
  -V, --version         show CLI version information
      --print-repo-root print the resolved repo root and exit
"@
    Write-Output ""
    Write-Output (Format-UiText -Text "Commands:" -Role "info")
    Write-Output ("  " + (Format-UiText -Text "Setup:" -Role "hint"))
    Write-UiCommandRow -CommandName "install" -Description "apply managed config and optional dependency installs"
    Write-UiCommandRow -CommandName "deps" -Description "install optional dependencies only"
    Write-UiCommandRow -CommandName "update" -Description "pull repo with --ff-only, then re-run install"
    Write-Output ("  " + (Format-UiText -Text "Inspect & Validate:" -Role "hint"))
    Write-UiCommandRow -CommandName "doctor" -Description "validate managed symlinks and required commands"
    Write-UiCommandRow -CommandName "dry-run" -Description "preview install flow without mutating filesystem"
    Write-UiCommandRow -CommandName "version" -Description "print CLI version and repo root"
    Write-Output ("  " + (Format-UiText -Text "Manage State:" -Role "hint"))
    Write-UiCommandRow -CommandName "delete" -Description "remove managed links and restore latest backups"
    Write-UiCommandRow -CommandName "remove" -Description "remove managed links only (no backup restore)"
    Write-UiCommandRow -CommandName "lock" -Description "regenerate dependency lock artifacts from pinned refs"
    Write-UiCommandRow -CommandName "update-pins" -Description "compare/update pinned refs and refresh lock artifacts"
    Write-UiCommandRow -CommandName "completions" -Description "regenerate tracked shell completions (autogen + oooconf)"
    Write-UiCommandRow -CommandName "agents" -Description "detect/sync/doctor/update AGENTS.md and agent CLI workflows"
    Write-Output ("  " + (Format-UiText -Text "Shell / Secrets:" -Role "hint"))
    Write-UiCommandRow -CommandName "shell" -Description "manage local shell preferences such as forgit aliases"
    Write-UiCommandRow -CommandName "secrets" -Description "sync or validate local secret env files"
    Write-Output @"
Aliases:
  check -> doctor
  preview -> dry-run
  upgrade -> update
Note:
  bootstrap is Unix-only in this wrapper.
  On Windows, run `scripts/setup.ps1 install` for initial setup.
Getting help:
  oooconf --help                     show this message
  oooconf help <command>             show command-specific help
  oooconf help secrets               show secrets subcommand help
Common workflows:
  # Initial setup on Windows:
  ./scripts/setup.ps1 install
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
        "deps" {
            Write-UiHelpBlock @"
Usage: oooconf deps [--dry-run] [dependency-key...]

Install optional dependencies only. Without dependency keys, an interactive
picker is shown (using gum if available).

All dependency metadata (including versions, URLs, and install methods) lives exclusively in scripts/optional-deps.toml.

  oooconf deps                         # interactive picker (when gum available)
  oooconf deps key1 key2                # specific tools (see optional-deps.toml for keys)
  oooconf deps --dry-run               # preview only
"@
        }
        "update" {
            Write-Output "See README.md for oooconf update usage"
        }
        "doctor" {
            Write-UiHelpBlock @"
Usage: oooconf doctor

Validate managed symlinks and required commands.
Checks that all managed config links point to valid targets and that
key tools (git, zsh, wezterm, nvim, etc.) are available on PATH.
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
        "delete" {
            Write-UiHelpBlock @"
Usage: oooconf delete

Remove managed links and restore the latest backups when available.
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
Reads pinned versions from scripts/setup.ps1 (or setup.sh) and writes
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
Usage: oooconf agents <detect|sync|doctor|update> [options]

Manage shared AGENTS.md instructions and validate configured agent tooling.
Subcommands:
  detect [--json]                detect configured agent CLIs on PATH
  sync [--check]                 append/update shared AGENTS.md managed block
  doctor [--strict-config-paths] verify AGENTS.md managed block and default agent config paths
  update [--check]               update installed agent CLIs (pnpm-based tools use pnpm)
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

  oooconf version                      # show version and repo path
"@
        }
        "shell" {
            Write-UiHelpBlock @"
Usage: oooconf shell status
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
Auto UV environment options:
  enabled   show activation/deactivation messages for Python venvs
  quiet     suppress activation/deactivation messages
  status    show the currently configured mode
Examples:
  oooconf shell status
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
        & $SetupScript $SetupCommand -DryRun @RemainingArgs
        return
    }

    & $SetupScript $SetupCommand @RemainingArgs
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
    "agents" {
        Assert-NoDryRun -CommandName "agents"
        if ($remaining.Count -eq 0 -or $remaining[0] -in @("-h", "--help", "help")) {
            Show-CommandUsage "agents"
            exit 0
        }
        Require-PythonRuntime
        Run-Python -ScriptPath $AgentsToolScript -ScriptArgs (@("--repo-root", $RepoRoot) + $remaining)
    }
    default {
        $suggestion = Get-CommandSuggestion -InputCommand $command
        Write-UnknownCommandMessage -Message "Unknown command: $command" -Suggestion $suggestion
        throw "Unknown command: $command"
    }
}

exit $LASTEXITCODE
