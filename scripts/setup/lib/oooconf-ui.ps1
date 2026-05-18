# Dot-sourced by scripts/setup/ooodnakov.ps1; do not execute directly.

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
        "missing" { $palette.Fail }
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
            '^(Examples:|Environment overrides:|Subcommands:|Global options:|Mode values:|Aliases:|Note:|Getting help:|Common workflows:|Repo root:|UI controls:|Themes:|Forgit alias modes:|Typo handling modes:|PSFzf options:|Prompt options:|Auto UV environment options:)$' {
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

function Get-UiThemePalette {
    $theme = "$(Get-OooconfTheme):$(Get-OooconfColorMode)"
    switch ($theme) {
        "catppuccin:dark" {
            return @{
                Section = "$([char]27)[38;5;111m"
                Ok = "$([char]27)[38;5;150m"
                Warn = "$([char]27)[38;5;223m"
                Fail = "$([char]27)[38;5;203m"
                Info = "$([char]27)[38;5;117m"
                Muted = "$([char]27)[38;5;145m"
            }
        }
        "gruvbox:dark" {
            return @{
                Section = "$([char]27)[38;5;214m"
                Ok = "$([char]27)[38;5;142m"
                Warn = "$([char]27)[38;5;214m"
                Fail = "$([char]27)[38;5;167m"
                Info = "$([char]27)[38;5;109m"
                Muted = "$([char]27)[38;5;248m"
            }
        }
        "nord:dark" {
            return @{
                Section = "$([char]27)[38;5;110m"
                Ok = "$([char]27)[38;5;108m"
                Warn = "$([char]27)[38;5;180m"
                Fail = "$([char]27)[38;5;174m"
                Info = "$([char]27)[38;5;110m"
                Muted = "$([char]27)[38;5;146m"
            }
        }
        "tokyonight:dark" {
            return @{
                Section = "$([char]27)[38;5;111m"
                Ok = "$([char]27)[38;5;114m"
                Warn = "$([char]27)[38;5;221m"
                Fail = "$([char]27)[38;5;203m"
                Info = "$([char]27)[38;5;117m"
                Muted = "$([char]27)[38;5;146m"
            }
        }
        "noctalia:dark" {
            return @{
                Section = "$([char]27)[38;5;141m"
                Ok = "$([char]27)[38;5;110m"
                Warn = "$([char]27)[38;5;180m"
                Fail = "$([char]27)[38;5;174m"
                Info = "$([char]27)[38;5;117m"
                Muted = "$([char]27)[38;5;146m"
            }
        }
        { $_ -in @("default:light", "catppuccin:light", "noctalia:light", "tokyonight:light") } {
            return @{
                Section = "$([char]27)[38;5;25m"
                Ok = "$([char]27)[38;5;64m"
                Warn = "$([char]27)[38;5;130m"
                Fail = "$([char]27)[38;5;124m"
                Info = "$([char]27)[38;5;25m"
                Muted = "$([char]27)[38;5;59m"
            }
        }
        "gruvbox:light" {
            return @{
                Section = "$([char]27)[38;5;94m"
                Ok = "$([char]27)[38;5;64m"
                Warn = "$([char]27)[38;5;130m"
                Fail = "$([char]27)[38;5;124m"
                Info = "$([char]27)[38;5;24m"
                Muted = "$([char]27)[38;5;59m"
            }
        }
        "nord:light" {
            return @{
                Section = "$([char]27)[38;5;24m"
                Ok = "$([char]27)[38;5;31m"
                Warn = "$([char]27)[38;5;131m"
                Fail = "$([char]27)[38;5;131m"
                Info = "$([char]27)[38;5;25m"
                Muted = "$([char]27)[38;5;59m"
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
