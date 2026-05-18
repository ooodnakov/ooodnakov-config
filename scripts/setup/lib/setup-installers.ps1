# Dot-sourced by scripts/setup/setup.ps1; do not execute directly.

function Get-ManagedTool {
    param([string]$Name, [string]$Field = "ref")
    $json = Run-Python (Join-Path $RepoRoot "scripts/cli/read_optional_deps.py") @("managed-tools") | ConvertFrom-Json
    if ($json.PSObject.Properties.Name -contains $Name) {
        $json.$Name.$Field
    } else {
        ""
    }
}

function Get-DepInfo {
    param([string]$Key)
    # Returns hashtable with ver, url, bin, check, etc.
    $json = Run-Python (Join-Path $RepoRoot "scripts/cli/read_optional_deps.py") @("json") | ConvertFrom-Json
    $dep = $json | Where-Object { $_.key -eq $Key } | Select-Object -First 1
    if ($dep) { $dep } else { @{} }
}

function Install-Fonts {
    Step-Progress -Status "Installing bundled fonts"
    $fontDir = Join-Path $RepoRoot "fonts/meslo"
    if (-not (Test-Path $fontDir)) {
        Write-Warning "Font directory not found at $fontDir"
        return
    }

    $shellApp = New-Object -ComObject Shell.Application
    $fontsFolder = $shellApp.Namespace(0x14) # CSIDL_FONTS

    $fonts = Get-ChildItem -Path $fontDir -Filter "*.ttf"
    foreach ($font in $fonts) {
        $targetPath = Join-Path $env:SystemRoot "Fonts\$($font.Name)"
        if (-not (Test-Path $targetPath)) {
            Write-Output "Installing font: $($font.Name)"
            $fontsFolder.CopyHere($font.FullName, 0x10)
        } else {
            Write-Verbose "Font already installed: $($font.Name)"
        }
    }
}

$script:DependencySummary = [System.Collections.Generic.List[string]]::new()
$script:NewlyAvailableCommands = [System.Collections.Generic.List[string]]::new()
$script:ToolSummary = [System.Collections.Generic.List[string]]::new()
$script:Failures = [System.Collections.Generic.List[string]]::new()
$script:LogFile = $null
$script:LatestLogFile = $null
$script:TranscriptStarted = $false
$script:StepTotal = 0
$script:StepCurrent = 0
$script:StepActivity = ""
$ValidSetupCommands = @("install", "update", "doctor", "deps", "completions", "minimal", "link")

# Run a Python script, preferring `uv run` when available.
function Run-Python {
    param([string]$ScriptPath, [string[]]$ScriptArgs)
    $pyprojectPath = Join-Path $RepoRoot "pyproject.toml"
    if ((Get-Command uv -ErrorAction SilentlyContinue) -and (Test-Path $pyprojectPath)) {
        $prevErrorAction = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = & uv run $ScriptPath @ScriptArgs 2>$null
            return $output
        } finally {
            $ErrorActionPreference = $prevErrorAction
        }
    } else {
        $pyCmd = Get-PythonCommand
        if ($pyCmd) {
            & $pyCmd $ScriptPath @ScriptArgs
        } else {
            Write-Error "Python not found. Install Python 3.8+ or add it to your PATH."
            exit 1
        }
    }
}


function Get-PythonCommand {
    foreach ($candidate in @("python3", "python", "py")) {
        if (Get-Command $candidate -ErrorAction SilentlyContinue) { return $candidate }
    }
    return $null
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
        if ($IsWindows -and -not $name.EndsWith(".exe")) {
            if (Get-Command "$name.exe" -ErrorAction SilentlyContinue) {
                return $true
            }
        }
    }

    return $false
}

function Test-DependencyStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,
        [Parameter(Mandatory = $true)]
        [string]$SummaryName,
        [switch]$IsModule
    )

    if (-not $DryRun -and (Test-VerboseMode)) {
        if (Test-Interactive) {
            Write-Host "[-] Checking $SummaryName..." -NoNewline
        }
    }

    $isPresent = $false
    if ($IsModule) {
        $isPresent = [bool](Get-Module -ListAvailable -Name $CommandName -ErrorAction SilentlyContinue)
    } else {
        $isPresent = (Test-AnyCommand -Names @($CommandName))
    }

    if ($isPresent) {
        if (-not $DryRun) {
            if (Test-Interactive -and (Test-VerboseMode)) {
                Write-Host "`r[ok] $SummaryName is present.             "
            } else {
                Write-Output "[ok] $SummaryName is present."
            }
        }
        Add-DependencySummary "${SummaryName}: present"
        return $true
    }

    if (-not $DryRun -and (Test-Interactive) -and (Test-VerboseMode)) {
        Write-Host "`r" -NoNewline
    }
    return $false
}

function Install-Chocolatey {
    if (Test-DependencyStatus -CommandName "choco" -SummaryName "choco") { return $true }

    if (-not (Confirm-Install "Install Chocolatey for optional Windows CLI packages?")) {
        Add-DependencySummary "choco: skipped"
        return $false
    }

    if ($DryRun) {
        Write-UiLine -Role hint -Message "[dry-run] Install Chocolatey"
        Add-DependencySummary "choco: install preview"
        return $false
    }

    try {
        Write-UiLine -Role info -Message "Installing Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-RestMethod -Uri "https://community.chocolatey.org/install.ps1" | Invoke-Expression
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Add-DependencySummary "choco: installed"
            Add-NewlyAvailableCommand -CommandNames @("choco")
            return $true
        }
    } catch {
        Write-Output $_
        Add-Failure "Installing Chocolatey"
    }

    Add-DependencySummary "choco: install attempted"
    return $false
}

function Add-HomebrewToSessionPath {
    $brewBins = @(
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/home/linuxbrew/.linuxbrew/bin"
    )

    foreach ($binDir in $brewBins) {
        $brewPath = Join-Path $binDir "brew"
        if (Test-Path $brewPath) {
            $pathParts = @($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ })
            if ($pathParts -notcontains $binDir) {
                $env:PATH = "$binDir$([IO.Path]::PathSeparator)$env:PATH"
            }
            return $true
        }
    }

    return $false
}

function Install-HomebrewIfMissing {
    if (Test-DependencyStatus -CommandName "brew" -SummaryName "brew") { return $true }

    $platform = Detect-Platform
    if ($platform -notin @("macos", "linux")) {
        Add-DependencySummary "brew: skipped (macOS/Linux only)"
        return $false
    }

    if (-not (Confirm-Install "Install Homebrew package manager with the official install script?")) {
        Add-DependencySummary "brew: skipped"
        return $false
    }

    if (-not (Get-Command curl -ErrorAction SilentlyContinue)) {
        Add-DependencySummary "brew: missing (curl unavailable)"
        return $false
    }

    if (-not (Test-Path "/bin/bash")) {
        Add-DependencySummary "brew: missing (/bin/bash unavailable)"
        return $false
    }

    $res = Invoke-ActionWithSpinner -Description "Installing Homebrew" -Action {
        & env NONINTERACTIVE=1 /bin/bash -c '$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)'
    }

    if ($DryRun) {
        Add-DependencySummary "brew: install preview"
        return $true
    }

    $null = Add-HomebrewToSessionPath

    if ($res -and (Get-Command brew -ErrorAction SilentlyContinue)) {
        Add-DependencySummary "brew: installed"
        Add-NewlyAvailableCommand -CommandNames @("brew")
        return $true
    }

    Add-DependencySummary "brew: install attempted"
    return $false
}

function Install-PackageIfMissing {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CommandNames,
        [string]$WingetId,
        [string]$ChocoId,
        [string]$CargoGitUrl,
        [string]$ScoopPackage,
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [string]$SummaryName
    )

    if (Test-DependencyStatus -CommandName $CommandNames[0] -SummaryName $SummaryName) { return $true }

    if ($WingetId -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        if (Confirm-Install "Install $Description with winget?") {
            if ($DryRun) {
                Write-Output "[dry-run] winget install --exact --id $WingetId"
                Add-DependencySummary "${SummaryName}: install preview via winget"
                return $false
            }

            Invoke-ActionWithSpinner -Description "Installing $Description via winget" -Action {
                param($wid)
                winget install --exact --id $wid --accept-package-agreements --accept-source-agreements --silent | Out-Null
            } -ArgumentList $WingetId

            Update-SessionEnvironment

            if (Test-AnyCommand -Names $CommandNames) {
                Add-DependencySummary "${SummaryName}: installed via winget"
                Add-NewlyAvailableCommand -CommandNames $CommandNames
                return $true
            }

            Add-DependencySummary "${SummaryName}: install attempted via winget"
            return $false
        }

        Add-DependencySummary "${SummaryName}: skipped"
        return $false
    }

    if ($ChocoId -and (Get-Command choco -ErrorAction SilentlyContinue)) {
        if (Confirm-Install "Install $Description with Chocolatey?") {
            if ($DryRun) {
                Write-Output "[dry-run] choco install $ChocoId -y"
                Add-DependencySummary "${SummaryName}: install preview via choco"
                return $false
            }

            Invoke-ActionWithSpinner -Description "Installing $Description via choco" -Action {
                param($cid)
                choco install $cid -y | Out-Null
            } -ArgumentList $ChocoId

            Update-SessionEnvironment

            if (Test-AnyCommand -Names $CommandNames) {
                Add-DependencySummary "${SummaryName}: installed via choco"
                Add-NewlyAvailableCommand -CommandNames $CommandNames
                return $true
            }

            Add-DependencySummary "${SummaryName}: install attempted via choco"
            return $false
        }

        Add-DependencySummary "${SummaryName}: skipped"
        return $false
    }

    if ($ScoopPackage -and (Get-Command scoop -ErrorAction SilentlyContinue)) {
        if (Confirm-Install "Install $Description with Scoop?") {
            if ($DryRun) {
                Write-Output "[dry-run] scoop install $ScoopPackage"
                Add-DependencySummary "${SummaryName}: install preview via scoop"
                return $false
            }

            Invoke-ActionWithSpinner -Description "Installing $Description via scoop" -Action {
                param($pkg)
                scoop install $pkg | Out-Null
            } -ArgumentList $ScoopPackage

            Update-SessionEnvironment

            if (Test-AnyCommand -Names $CommandNames) {
                Add-DependencySummary "${SummaryName}: installed via scoop"
                Add-NewlyAvailableCommand -CommandNames $CommandNames
                return $true
            }

            Add-DependencySummary "${SummaryName}: install attempted via scoop"
            return $false
        }

        Add-DependencySummary "${SummaryName}: skipped"
        return $false
    }

    if ($CargoGitUrl) {
        if (-not (Install-CargoIfMissing)) {
            Add-DependencySummary "${SummaryName}: missing (cargo unavailable)"
            return $false
        }

        if (Confirm-Install "Install $Description via cargo?") {
            $cargoBinDir = Join-Path $HomeDir ".cargo/bin"
            $cargoExe = Join-Path $cargoBinDir "cargo.exe"
            if (($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ }) -notcontains $cargoBinDir) {
                $env:PATH = "$cargoBinDir$([IO.Path]::PathSeparator)$env:PATH"
            }

            $cargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
            if (-not $cargoCommand -and (Test-Path $cargoExe)) {
                $cargoCommand = $cargoExe
            }

            if (-not $cargoCommand) {
                Add-DependencySummary "${SummaryName}: missing (cargo unavailable)"
                return $false
            }

            if ($DryRun) {
                if ($CargoGitUrl -match "^https?://" -or $CargoGitUrl -match "^git@") {
                    Write-Output "[dry-run] cargo install --locked --git $CargoGitUrl"
                } else {
                    Write-Output "[dry-run] cargo install $CargoGitUrl"
                }
                Add-DependencySummary "${SummaryName}: install preview via cargo"
                return $false
            }

            Invoke-ActionWithSpinner -Description "Installing $Description via cargo" -Action {
                param($url, $cmd)
                if ($url -match "^https?://" -or $url -match "^git@") {
                    & $cmd install --locked --git $url | Out-Null
                } else {
                    & $cmd install $url | Out-Null
                }
            } -ArgumentList $CargoGitUrl, $cargoCommand

            $installedPath = Join-Path $cargoBinDir "$($CommandNames[0]).exe"
            if ((Test-AnyCommand -Names $CommandNames) -or (Test-Path $installedPath)) {
                Add-DependencySummary "${SummaryName}: installed via cargo"
                Add-NewlyAvailableCommand -CommandNames $CommandNames
                return $true
            }

            Add-DependencySummary "${SummaryName}: install attempted via cargo"
            return $false
        }

        Add-DependencySummary "${SummaryName}: skipped"
        return $false
    }

    Add-DependencySummary "${SummaryName}: missing (no supported package manager)"
    return $false
}

function Get-OptionalConfigValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Config -is [hashtable]) {
        if ($Config.ContainsKey($Name)) { return [string]$Config[$Name] }
        return ""
    }

    if ($Config.PSObject.Properties.Name -contains $Name) {
        return [string]$Config.$Name
    }

    return ""
}

function Get-GitHubReleaseArch {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    if ($arch -eq [System.Runtime.InteropServices.Architecture]::X64) { return "x86_64" }
    if ($arch -eq [System.Runtime.InteropServices.Architecture]::Arm64) { return "aarch64" }
    if ($arch -eq [System.Runtime.InteropServices.Architecture]::X86) { return "i686" }
    return ""
}

function Expand-GitHubReleaseTemplate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Template,
        [Parameter(Mandatory = $true)]
        [string]$Version,
        [Parameter(Mandatory = $true)]
        [string]$System,
        [Parameter(Mandatory = $true)]
        [string]$Arch
    )

    return $Template.Replace('${ver}', $Version).Replace('${system}', $System).Replace('${arch}', $Arch)
}

function Install-GitHubReleaseDependencyIfMissing {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Spec,
        [Parameter(Mandatory = $true)]
        [object]$PlatformConfig,
        [Parameter(Mandatory = $true)]
        [string[]]$CommandNames,
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [string]$SummaryName
    )

    if (Test-DependencyStatus -CommandName $CommandNames[0] -SummaryName $SummaryName) { return $true }

    $repo = Get-OptionalConfigValue -Config $PlatformConfig -Name "package"
    $version = if ($Spec.Ver) { [string]$Spec.Ver } else { "" }
    $assetTemplate = Get-OptionalConfigValue -Config $PlatformConfig -Name "asset"
    $urlTemplate = Get-OptionalConfigValue -Config $PlatformConfig -Name "url"
    if ([string]::IsNullOrWhiteSpace($version) -or [string]::IsNullOrWhiteSpace($repo) -or ([string]::IsNullOrWhiteSpace($assetTemplate) -and [string]::IsNullOrWhiteSpace($urlTemplate))) {
        Add-DependencySummary "${SummaryName}: missing (github-release metadata incomplete)"
        return $false
    }

    $system = Detect-Platform
    $arch = Get-GitHubReleaseArch
    if ([string]::IsNullOrWhiteSpace($arch)) {
        Add-DependencySummary "${SummaryName}: unsupported architecture"
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($assetTemplate)) {
        $assetTemplate = Split-Path -Leaf $urlTemplate
    }

    $assetName = Expand-GitHubReleaseTemplate -Template $assetTemplate -Version $version -System $system -Arch $arch
    $releaseUrl = if ([string]::IsNullOrWhiteSpace($urlTemplate)) {
        "https://github.com/$repo/releases/download/v$version/$assetName"
    } else {
        Expand-GitHubReleaseTemplate -Template $urlTemplate -Version $version -System $system -Arch $arch
    }

    if (-not (Confirm-Install "Install $Description from the GitHub release archive?")) {
        Add-DependencySummary "${SummaryName}: skipped"
        return $false
    }

    $binaryName = if ($Spec.Bin) { [string]$Spec.Bin } else { $CommandNames[0] }
    $binaryFile = if ($IsWindows -and -not $binaryName.EndsWith(".exe")) { "$binaryName.exe" } else { $binaryName }
    $installRoot = Join-Path $ShareHome "tools/$SummaryName/v$version"
    $archivePath = Join-Path ([System.IO.Path]::GetTempPath()) $assetName
    $targetBinary = Join-Path $LocalBinDir $binaryFile

    if ($DryRun) {
        Write-Output "[dry-run] Download $releaseUrl"
        Write-Output "[dry-run] Extract $archivePath -> $installRoot"
        Write-Output "[dry-run] Copy $binaryFile -> $targetBinary"
        Add-DependencySummary "${SummaryName}: install preview via GitHub release"
        return $false
    }

    try {
        if (-not (Ensure-Directory -Path $installRoot) -or -not (Ensure-Directory -Path $LocalBinDir)) {
            Add-DependencySummary "${SummaryName}: install attempted"
            return $false
        }

        Invoke-WebRequest -Uri $releaseUrl -OutFile $archivePath
        if ($assetName.EndsWith(".zip")) {
            Expand-Archive -Path $archivePath -DestinationPath $installRoot -Force
        } else {
            tar -xf $archivePath -C $installRoot
        }

        $sourceBinary = Get-ChildItem -Path $installRoot -Recurse -File -Filter $binaryFile | Select-Object -First 1
        if (-not $sourceBinary) {
            Add-DependencySummary "${SummaryName}: install attempted"
            return $false
        }

        Copy-Item -Path $sourceBinary.FullName -Destination $targetBinary -Force
        Update-SessionEnvironment
    } catch {
        Write-Output $_
        Add-Failure "Installing $Description"
    } finally {
        if (Test-Path $archivePath) { Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue }
    }

    if ((Test-AnyCommand -Names $CommandNames) -or (Test-Path $targetBinary)) {
        Add-DependencySummary "${SummaryName}: installed official v$version"
        Add-NewlyAvailableCommand -CommandNames $CommandNames
        return $true
    }

    Add-DependencySummary "${SummaryName}: install attempted"
    return $false
}

function Resolve-PnpmCommand {
    $cmd = Get-Command pnpm -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $pnpmHome = if ($env:PNPM_HOME) { $env:PNPM_HOME } else { Join-Path $HomeDir ".local/share/pnpm" }
    $candidates = @(
        (Join-Path $pnpmHome "pnpm.cmd"),
        (Join-Path $pnpmHome "pnpm.ps1"),
        (Join-Path $pnpmHome "pnpm"),
        (Join-Path $pnpmHome "bin/pnpm.cmd"),
        (Join-Path $pnpmHome "bin/pnpm.ps1"),
        (Join-Path $pnpmHome "bin/pnpm")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    return ""
}

function Install-NodeIfMissing {
    if ((Get-Command node -ErrorAction SilentlyContinue) -and (Get-Command npm -ErrorAction SilentlyContinue)) {
        Add-DependencySummary "node: present"
        return $true
    }

    $nodeVer = (Get-DepInfo "node").ver
    if (-not $nodeVer) { $nodeVer = "24.15.0" }

    if (-not (Confirm-Install "Install Node.js $nodeVer with bundled npm?")) {
        Add-DependencySummary "node: skipped"
        return $false
    }

    $nvmCommand = Get-Command nvm -ErrorAction SilentlyContinue
    if ($nvmCommand) {
        if ($DryRun) {
            Write-Output "[dry-run] nvm install $nodeVer"
            Write-Output "[dry-run] nvm use $nodeVer"
            Add-DependencySummary "node: install preview via nvm"
            return $true
        }

        Invoke-ActionWithSpinner -Description "Installing Node.js $nodeVer via nvm" -Action {
            param($version)
            nvm install $version | Out-Null
            nvm use $version | Out-Null
        } -ArgumentList $nodeVer
        Update-SessionEnvironment
    } elseif ($IsWindows -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        if ($DryRun) {
            Write-Output "[dry-run] winget install --exact --id OpenJS.NodeJS.LTS --version $nodeVer --accept-package-agreements --accept-source-agreements --silent"
            Add-DependencySummary "node: install preview via winget"
            return $true
        }

        Invoke-ActionWithSpinner -Description "Installing Node.js $nodeVer via winget" -Action {
            param($version)
            winget install --exact --id OpenJS.NodeJS.LTS --version $version --accept-package-agreements --accept-source-agreements --silent | Out-Null
        } -ArgumentList $nodeVer
        Update-SessionEnvironment
    } else {
        Add-DependencySummary "node: missing (requires nvm or winget)"
        return $false
    }

    if ((Get-Command node -ErrorAction SilentlyContinue) -and (Get-Command npm -ErrorAction SilentlyContinue)) {
        Add-DependencySummary "node: installed"
        Add-NewlyAvailableCommand -CommandNames @("node", "npm")
        return $true
    }

    Add-DependencySummary "node: install attempted"
    return $false
}

function Ensure-NodeForPnpm {
    if ((Get-Command node -ErrorAction SilentlyContinue) -and (Get-Command npm -ErrorAction SilentlyContinue)) {
        return $true
    }

    $nodeInstalled = Install-NodeIfMissing
    if ($DryRun -and $nodeInstalled) { return $true }
    return ((Get-Command node -ErrorAction SilentlyContinue) -and (Get-Command npm -ErrorAction SilentlyContinue))
}

function Install-PnpmIfMissing {
    if (Resolve-PnpmCommand) {
        Add-DependencySummary "pnpm: present"
        return $true
    }

    if (-not (Confirm-Install "Install pnpm package manager?")) {
        Add-DependencySummary "pnpm: skipped"
        return $false
    }

    if (-not (Ensure-NodeForPnpm)) {
        Add-DependencySummary "pnpm: missing (requires Node.js/npm; try oooconf deps node pnpm)"
        return $false
    }

    $pnpmHome = if ($env:PNPM_HOME) { $env:PNPM_HOME } else { Join-Path $HomeDir ".local/share/pnpm" }
    $env:PNPM_HOME = $pnpmHome

    if (-not (Ensure-Directory -Path $pnpmHome)) {
        Add-DependencySummary "pnpm: install failed"
        return $false
    }

    if (($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ }) -notcontains $pnpmHome) {
        $env:PATH = "$pnpmHome$([IO.Path]::PathSeparator)$env:PATH"
    }

    $pnpmVer = (Get-DepInfo "pnpm").ver
    if (-not $pnpmVer) { $pnpmVer = "10.18.3" }  # fallback only during transition

    if ($DryRun) {
        Write-Output "[dry-run] corepack enable --install-directory $pnpmHome pnpm"
        Write-Output "[dry-run] corepack prepare pnpm@$pnpmVer --activate"
        Add-DependencySummary "pnpm: install preview via corepack"
        return $false
    }

    if (Get-Command corepack -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Output "[dry-run] corepack enable --install-directory $pnpmHome pnpm"
            Write-Output "[dry-run] corepack prepare pnpm@$pnpmVer --activate"
            Add-DependencySummary "pnpm: install preview via corepack"
            return $false
        }

        Invoke-ActionWithSpinner -Description "Installing pnpm@$pnpmVer via corepack" -Action {
            param($homeDir, $version)
            corepack enable --install-directory $homeDir pnpm | Out-Null
            corepack prepare "pnpm@$version" --activate | Out-Null
        } -ArgumentList $pnpmHome, $pnpmVer
    } elseif (Get-Command npm -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Output "[dry-run] npm install --global pnpm@$pnpmVer --prefix $pnpmHome"
            Add-DependencySummary "pnpm: install preview via npm"
            return $false
        }

        Invoke-ActionWithSpinner -Description "Installing pnpm@$pnpmVer via npm" -Action {
            param($homeDir, $version)
            npm install --global "pnpm@$version" --prefix $homeDir | Out-Null
        } -ArgumentList $pnpmHome, $pnpmVer
    } else {
        Add-DependencySummary "pnpm: missing (requires corepack or npm)"
        return $false
    }

    if (Resolve-PnpmCommand) {
        Add-DependencySummary "pnpm: installed"
        Add-NewlyAvailableCommand -CommandNames @("pnpm")
        return $true
    }

    Add-DependencySummary "pnpm: install attempted"
    return $false
}

function Install-PoshGitIfMissing {
    if (Get-Module -ListAvailable -Name posh-git) {
        Add-DependencySummary "posh-git: present"
        return $true
    }

    if (-not (Confirm-Install "Install posh-git from the PowerShell Gallery?")) {
        Add-DependencySummary "posh-git: skipped"
        return $false
    }

    if ($DryRun) {
        Write-Output "[dry-run] Install-Module posh-git -Scope CurrentUser -Force"
        Add-DependencySummary "posh-git: install preview via PowerShell Gallery"
        return $false
    }

    try {
        $nuget = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue
        if (-not $nuget) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
        }

        Invoke-ActionWithSpinner -Description "Installing posh-git via PowerShell Gallery" -Action {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            Install-Module posh-git -Scope CurrentUser -Force -AllowClobber | Out-Null
        }
    } catch {
        Write-Output $_
    }

    if (Get-Module -ListAvailable -Name posh-git) {
        Add-DependencySummary "posh-git: installed via PowerShell Gallery"
        Add-NewlyAvailableCommand -CommandNames @("Add-PoshGitToProfile")
        return $true
    }

    Add-DependencySummary "posh-git: install attempted"
    return $false
}

function Install-PSFzfIfMissing {
    if (Get-Module -ListAvailable -Name PSFzf) {
        Add-DependencySummary "psfzf: present"
        return $true
    }

    if (-not (Confirm-Install "Install PSFzf from the PowerShell Gallery?")) {
        Add-DependencySummary "psfzf: skipped"
        return $false
    }

    if ($DryRun) {
        Write-Output "[dry-run] Install-Module PSFzf -Scope CurrentUser -Force"
        Add-DependencySummary "psfzf: install preview via PowerShell Gallery"
        return $false
    }

    try {
        $nuget = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue
        if (-not $nuget) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
        }

        Invoke-ActionWithSpinner -Description "Installing PSFzf via PowerShell Gallery" -Action {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            Install-Module PSFzf -Scope CurrentUser -Force -AllowClobber | Out-Null
        }
    } catch {
        Write-Output $_
    }

    if (Get-Module -ListAvailable -Name PSFzf) {
        Add-DependencySummary "psfzf: installed via PowerShell Gallery"
        Add-NewlyAvailableCommand -CommandNames @("Invoke-FuzzyHistory")
        return $true
    }

    Add-DependencySummary "psfzf: install attempted"
    return $false
}

function Install-RtkIfMissing {
    if (Test-DependencyStatus -CommandName "rtk" -SummaryName "rtk") { return $true }

    if (-not (Confirm-Install "Install rtk token-optimized AI CLI proxy from the official native executable archive?")) {
        Add-DependencySummary "rtk: skipped"
        return $false
    }

    $rtkInfo = Get-DepInfo "rtk"
    $rtkVer = if ($rtkInfo.ver) { $rtkInfo.ver } else { "0.37.2" }
    $installRoot = Join-Path $ShareHome "tools/rtk/v$rtkVer"
    $archivePath = Join-Path ([System.IO.Path]::GetTempPath()) "rtk-windows-$rtkVer.zip"
    $releaseUrl = "https://github.com/rtk-ai/rtk/releases/download/v$rtkVer/rtk-x86_64-pc-windows-msvc.zip"
    $sourceBinary = Join-Path $installRoot "rtk.exe"
    $targetBinary = Join-Path $LocalBinDir "rtk.exe"

    if ($DryRun) {
        Write-Output "[dry-run] Download $releaseUrl"
        Write-Output "[dry-run] Expand-Archive $archivePath -> $installRoot"
        Write-Output "[dry-run] Copy $sourceBinary -> $targetBinary"
        Add-DependencySummary "rtk: install preview via official archive"
        return $false
    }

    try {
        if (-not (Ensure-Directory -Path $installRoot)) {
            Add-DependencySummary "rtk: install attempted"
            return $false
        }

        if (-not (Test-Path $sourceBinary)) {
            Invoke-WebRequest -Uri $releaseUrl -OutFile $archivePath
            Expand-Archive -Path $archivePath -DestinationPath $installRoot -Force
        }

        Copy-Item -Path $sourceBinary -Destination $targetBinary -Force
    } catch {
        Write-Output $_
        # Fallback to cargo if zip download/extract failed
        $cargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
        if ($cargoCommand) {
            Invoke-ActionWithSpinner -Description "Installing rtk via cargo (fallback)" -Action {
                param($cmd)
                & $cmd install --git https://github.com/rtk-ai/rtk | Out-Null
            } -ArgumentList $cargoCommand
            if (Get-Command rtk -ErrorAction SilentlyContinue) {
                Add-DependencySummary "rtk: installed (via cargo fallback)"
                Add-NewlyAvailableCommand -CommandNames @("rtk")
                return $true
            }
        }
        Add-DependencySummary "rtk: install attempted"
        return $false
    } finally {
        if (Test-Path $archivePath) { Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue }
    }

    if (Get-Command rtk -ErrorAction SilentlyContinue -CommandType Application) {
        Add-DependencySummary "rtk: installed official v$rtkVer"
        Add-NewlyAvailableCommand -CommandNames @("rtk")
        return $true
    }

    if (Test-Path $targetBinary) {
        Add-DependencySummary "rtk: installed official v$rtkVer"
        Add-NewlyAvailableCommand -CommandNames @("rtk")
        return $true
    }

    Add-DependencySummary "rtk: install attempted"
    return $false
}

function Install-NeovimIfMissing {
    if (Test-DependencyStatus -CommandName "nvim" -SummaryName "nvim") { return $true }

    if (-not (Confirm-Install "Install Neovim from the official GitHub release archive?")) {
        Add-DependencySummary "nvim: skipped"
        return $false
    }

    $nvimInfo = Get-DepInfo "nvim"
    $nvimVer = if ($nvimInfo.ver) { $nvimInfo.ver } else { "0.12.1" }
    $arch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq [System.Runtime.InteropServices.Architecture]::Arm64) { "arm64" } else { "x64" }
    $assetName = if ($arch -eq "arm64") { "nvim-win-arm64.zip" } else { "nvim-win64.zip" }
    $extractedDir = if ($arch -eq "arm64") { "nvim-win-arm64" } else { "nvim-win64" }
    $installRoot = Join-Path $ShareHome "tools/neovim/v$nvimVer"
    $archivePath = Join-Path ([System.IO.Path]::GetTempPath()) $assetName
    $releaseUrl = "https://github.com/neovim/neovim/releases/download/v$nvimVer/$assetName"
    $sourceBinary = Join-Path $installRoot "$extractedDir/bin/nvim.exe"
    $targetBinary = Join-Path $LocalBinDir "nvim.exe"

    if ($DryRun) {
        Write-Output "[dry-run] Download $releaseUrl"
        Write-Output "[dry-run] Expand-Archive $archivePath -> $installRoot"
        Write-Output "[dry-run] Copy $sourceBinary -> $targetBinary"
        Add-DependencySummary "nvim: install preview via official GitHub release"
        return $false
    }

    try {
        if (-not (Ensure-Directory -Path $installRoot) -or -not (Ensure-Directory -Path $LocalBinDir)) {
            Add-DependencySummary "nvim: install attempted"
            return $false
        }

        if (-not (Test-Path $sourceBinary)) {
            Invoke-WebRequest -Uri $releaseUrl -OutFile $archivePath
            Expand-Archive -Path $archivePath -DestinationPath $installRoot -Force
        }

        Copy-Item -Path $sourceBinary -Destination $targetBinary -Force
    } catch {
        Write-Output $_
        Add-Failure "Installing Neovim"
    }

    if ((Get-Command nvim -ErrorAction SilentlyContinue -CommandType Application) -or (Test-Path $targetBinary)) {
        Add-DependencySummary "nvim: installed official v$nvimVer"
        Add-NewlyAvailableCommand -CommandNames @("nvim")
        return $true
    }

    Add-DependencySummary "nvim: install attempted"
    if (Test-Path $archivePath) { Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue }
    return $false
}

function Install-TectonicIfMissing {
    if (Test-DependencyStatus -CommandName "tectonic" -SummaryName "tectonic") { return $true }

    if (-not (Confirm-Install "Install Tectonic (modern LaTeX engine) from the official GitHub releases?")) {
        Add-DependencySummary "tectonic: skipped"
        return $false
    }

    $repo = "tectonic-typesetting/tectonic"
    $latest = $null
    try {
        if ($null -ne (Get-Command gh -ErrorAction SilentlyContinue)) {
             $latestJson = gh api repos/$repo/releases/latest | ConvertFrom-Json
             $latest = [pscustomobject]@{ tag_name = $latestJson.tag_name; assets = $latestJson.assets }
        } else {
             $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
        }
    } catch {
        Write-Warning "Failed to fetch latest Tectonic release info from GitHub API: $($_.Exception.Message)"
    }

    if (-not $latest) {
        # Fallback to hardcoded version if API fails
        $version = "0.16.9"
        $tag = "tectonic@0.16.9"
    } else {
        $tag = $latest.tag_name
        $version = $tag -replace '^tectonic@', ''
    }

    $asset = $null
    if ($latest) {
        $asset = $latest.assets | Where-Object { $_.name -match "x86_64-pc-windows-msvc\.zip$" } | Select-Object -First 1
    }

    $downloadUrl = if ($asset) { $asset.browser_download_url } else {
        $encodedTag = [uri]::EscapeDataString($tag)
        "https://github.com/$repo/releases/download/$encodedTag/tectonic-$version-x86_64-pc-windows-msvc.zip"
    }

    $installRoot = Join-Path $ShareHome "tools/tectonic/v$version"
    $archivePath = Join-Path ([System.IO.Path]::GetTempPath()) "tectonic-windows-$version.zip"
    $sourceBinary = Join-Path $installRoot "tectonic.exe"
    $targetBinary = Join-Path $LocalBinDir "tectonic.exe"

    if ($DryRun) {
        Write-Output "[dry-run] Download $downloadUrl"
        Write-Output "[dry-run] Expand-Archive $archivePath -> $installRoot"
        Write-Output "[dry-run] Copy $sourceBinary -> $targetBinary"
        Add-DependencySummary "tectonic: install preview via official GitHub release"
        return $false
    }

    $downloadSuccess = Invoke-ActionWithSpinner -Description "Installing Tectonic v$version via GitHub releases" -Action {
        param($url, $zip, $root, $src, $dst)
        if (-not (Ensure-Directory -Path $root)) { throw "Failed to create directory $root" }
        if (-not (Test-Path $src)) {
            Invoke-WebRequest -Uri $url -OutFile $zip
            Expand-Archive -Path $zip -DestinationPath $root -Force
        }
        Copy-Item -Path $src -Destination $dst -Force
        Update-SessionEnvironment
    } -ArgumentList $downloadUrl, $archivePath, $installRoot, $sourceBinary, $targetBinary

    if ($downloadSuccess -and (Test-AnyCommand -Names @("tectonic"))) {
        Add-DependencySummary "tectonic: installed official v$version"
        Add-NewlyAvailableCommand -CommandNames @("tectonic")
        if (Test-Path $archivePath) { Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue }
        return $true
    }

    # Fallback to cargo if download failed
    $cargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
    if ($cargoCommand) {
        if (Invoke-ActionWithSpinner -Description "Installing tectonic via cargo (fallback)" -Action {
            param($cmd)
            & $cmd install tectonic | Out-Null
        } -ArgumentList $cargoCommand) {
            if (Get-Command tectonic -ErrorAction SilentlyContinue) {
                Add-DependencySummary "tectonic: installed (via cargo fallback)"
                Add-NewlyAvailableCommand -CommandNames @("tectonic")
                if (Test-Path $archivePath) { Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue }
                return $true
            }
        }
    }

    Add-DependencySummary "tectonic: install attempted"
    if (Test-Path $archivePath) { Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue }
    return $false
}

function Install-BitwardenCliIfMissing {
    if (Test-DependencyStatus -CommandName "bw" -SummaryName "bw") { return $true }

    if (-not (Confirm-Install "Install Bitwarden CLI from the official native executable archive?")) {
        Add-DependencySummary "bw: skipped"
        return $false
    }

    $bwInfo = Get-DepInfo "bw"
    $bwVer = if ($bwInfo.ver) { $bwInfo.ver } else { "1.22.1" }
    $installRoot = Join-Path $ShareHome "tools/bitwarden-cli/v$bwVer"
    $archivePath = Join-Path ([System.IO.Path]::GetTempPath()) "bw-windows-$bwVer.zip"
    $releaseUrl = "https://github.com/bitwarden/cli/releases/download/v$bwVer/bw-windows-$bwVer.zip"
    $sourceBinary = Join-Path $installRoot "bw.exe"
    $targetBinary = Join-Path $LocalBinDir "bw.exe"

    if ($DryRun) {
        Write-Output "[dry-run] Download $releaseUrl"
        Write-Output "[dry-run] Expand-Archive $archivePath -> $installRoot"
        Write-Output "[dry-run] Copy $sourceBinary -> $targetBinary"
        Add-DependencySummary "bw: install preview via official archive"
        return $false
    }

    try {
        if (-not (Ensure-Directory -Path $installRoot)) {
            Add-DependencySummary "bw: install attempted"
            return $false
        }

        if (-not (Test-Path $sourceBinary)) {
            Invoke-WebRequest -Uri $releaseUrl -OutFile $archivePath
            Expand-Archive -Path $archivePath -DestinationPath $installRoot -Force
        }

        Copy-Item -Path $sourceBinary -Destination $targetBinary -Force
    } catch {
        Write-Output $_
        Add-Failure "Installing Bitwarden CLI"
    }

    if (Get-Command bw -ErrorAction SilentlyContinue -CommandType Application) {
        Add-DependencySummary "bw: installed official v$bwVer"
        Add-NewlyAvailableCommand -CommandNames @("bw")
        return $true
    }

    if (Test-Path $targetBinary) {
        Add-DependencySummary "bw: installed official v$bwVer"
        Add-NewlyAvailableCommand -CommandNames @("bw")
        return $true
    }

    Add-DependencySummary "bw: install attempted"
    return $false
}

function Install-CargoIfMissing {
    if (Test-DependencyStatus -CommandName "cargo" -SummaryName "cargo") { return $true }

    if (-not (Confirm-Install "Install Rust and cargo via rustup?")) {
        Add-DependencySummary "cargo: skipped"
        return $false
    }

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Output "[dry-run] winget install Rustlang.Rustup"
            Add-DependencySummary "cargo: install preview via winget"
            return $false
        }

        try {
            winget install Rustlang.Rustup --accept-package-agreements --accept-source-agreements
        } catch {
            Write-Output $_
        }

        if (Get-Command cargo -ErrorAction SilentlyContinue) {
            Add-DependencySummary "cargo: installed via winget"
            Add-NewlyAvailableCommand -CommandNames @("cargo", "rustc")
            return $true
        }

        Add-DependencySummary "cargo: install attempted via winget"
        return $false
    }

    Add-DependencySummary "cargo: missing (requires winget)"
    return $false
}

function Install-DuaIfMissing {
    $duaRepoUrl = "https://github.com/byron/dua-cli.git"
    $cargoBinDir = Join-Path $HomeDir ".cargo/bin"
    $cargoExe = Join-Path $cargoBinDir "cargo.exe"
    $duaExe = Join-Path $cargoBinDir "dua.exe"

    if ((Get-Command dua -ErrorAction SilentlyContinue) -or (Test-Path $duaExe)) {
        Add-DependencySummary "dua: present"
        return $true
    }

    if (-not (Confirm-Install "Install dua-cli for disk usage analysis from byron/dua-cli via cargo?")) {
        Add-DependencySummary "dua: skipped"
        return $false
    }

    if (-not (Install-CargoIfMissing)) {
        Add-DependencySummary "dua: missing (cargo unavailable)"
        return $false
    }

    if (($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ }) -notcontains $cargoBinDir) {
        $env:PATH = "$cargoBinDir$([IO.Path]::PathSeparator)$env:PATH"
    }

    $cargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
    if (-not $cargoCommand -and (Test-Path $cargoExe)) {
        $cargoCommand = $cargoExe
    }

    if (-not $cargoCommand) {
        Add-DependencySummary "dua: missing (cargo unavailable)"
        return $false
    }

    if ($DryRun) {
        Write-Output "[dry-run] cargo install --locked --git $duaRepoUrl dua-cli"
        Add-DependencySummary "dua: install preview via cargo"
        return $false
    }

    try {
        & $cargoCommand install --locked --git $duaRepoUrl dua-cli
    } catch {
        Write-Output $_
    }

    if ((Get-Command dua -ErrorAction SilentlyContinue) -or (Test-Path $duaExe)) {
        Add-DependencySummary "dua: installed"
        Add-NewlyAvailableCommand -CommandNames @("dua")
        return $true
    }

    Add-DependencySummary "dua: install attempted"
    return $false
}

function Install-OptionalDependencies {
    if ($SkipDeps) {
        if (Test-VerboseMode) {
            Write-Output "Skipping optional dependency installation (--skip-deps)"
        }
        return
    }
    if (Test-VerboseMode) {
        Write-Output "Dependency check:"
    }
    $specs = @(Get-OptionalDependencySpecs)
    $selectedSpecs = @($specs | Where-Object { Test-OptionalDependencySelected -Key $_.Key })

    $needsChocolatey = $false
    foreach ($spec in $selectedSpecs) {
        if ($spec.Key -eq "choco") {
            $needsChocolatey = $true
            break
        }
        $platformConfig = Get-OptionalDependencyPlatformConfig -Spec $spec
        if ($platformConfig -and $platformConfig.manager -eq "choco") {
            $needsChocolatey = $true
            break
        }
    }
    if ($needsChocolatey) {
        $null = Install-Chocolatey
    }

    foreach ($spec in $specs) {
        $null = Install-OptionalDependencyFromSpec -Spec $spec
    }
}

