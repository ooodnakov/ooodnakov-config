# Dot-sourced by scripts/setup/ooodnakov.ps1; do not execute directly.

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
