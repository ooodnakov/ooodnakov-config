<#
.SYNOPSIS
PowerShell smoke tests for the central optional-deps.toml catalog.

Run with: pwsh -NoProfile -File tests/test_powershell.ps1
#>

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$ErrorActionPreference = "Stop"

$OptionalDepsScript = Join-Path $RepoRoot "scripts/cli/read_optional_deps.py"
$SetupScript = Join-Path $RepoRoot "scripts/setup/setup.ps1"

Write-Host "=== PowerShell Test Suite for ooodnakov-config ===" -ForegroundColor Cyan
Write-Host "Testing central optional-deps.toml as sole source of truth..." -ForegroundColor Cyan

$TestPassed = 0
$TestFailed = 0

function Assert-True($Condition, $Message) {
    if ($Condition) {
        Write-Host "  [PASS] $Message" -ForegroundColor Green
        $script:TestPassed++
    } else {
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
        $script:TestFailed++
    }
}

function Get-PythonCommand {
    $python = Get-Command python3 -ErrorAction SilentlyContinue
    if ($python) {
        return $python.Source
    }

    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        return $python.Source
    }

    throw "python3 or python is required for tests/test_powershell.ps1"
}

function Invoke-OptionalDeps {
    param([string[]]$ScriptArgs)

    $python = Get-PythonCommand
    $output = & $python $OptionalDepsScript @ScriptArgs
    if ($LASTEXITCODE -ne 0) {
        throw "read_optional_deps.py failed: $($ScriptArgs -join ' ')"
    }
    return $output
}

# Keep nested setup.ps1 dry-runs from trying to write to the user's uv cache.
$env:UV_CACHE_DIR = Join-Path ([System.IO.Path]::GetTempPath()) "oooconf-uv-cache-test"
$env:OOODNAKOV_LOG_ROOT = Join-Path ([System.IO.Path]::GetTempPath()) "oooconf-logs-test"
$env:OOODNAKOV_INTERACTIVE = "never"

Write-Host "`n1. Testing managed tool and dependency metadata..."
$managedTools = Invoke-OptionalDeps @("managed-tools") | ConvertFrom-Json
Assert-True ($managedTools."oh-my-zsh".ref.Length -eq 40) "managed-tools returns valid git ref for oh-my-zsh"

$deps = Invoke-OptionalDeps @("json") | ConvertFrom-Json
$rtkInfo = $deps | Where-Object { $_.key -eq "rtk" } | Select-Object -First 1
Assert-True ($null -ne $rtkInfo) "catalog includes rtk"
Assert-True ($rtkInfo.ver -eq "0.37.2") "catalog returns current rtk version"
Assert-True ($rtkInfo.url -like "*rtk-ai/rtk*") "catalog returns URL for rtk"

Write-Host "`n2. Testing catalog command output..."
$catalog = Invoke-OptionalDeps @("catalog")
Assert-True ($catalog -like "*rtk|rtk|*") "catalog output contains rtk"

Write-Host "`n3. Testing setup.ps1 dependency dry-run path..."
$dryRunOutput = & pwsh -NoProfile -File $SetupScript deps -DryRun rtk 2>&1
Assert-True ($LASTEXITCODE -eq 0) "setup.ps1 deps -DryRun rtk exits successfully"
Assert-True (($dryRunOutput -join "`n") -match "dry-run|Optional dependency install complete") "setup.ps1 dry-run emits expected output"

Write-Host "`n4. Verifying current script paths exist..."
Assert-True (Test-Path (Join-Path $RepoRoot "scripts/setup/setup.ps1")) "setup.ps1 exists under scripts/setup"
Assert-True (Test-Path (Join-Path $RepoRoot "scripts/setup/ooodnakov.ps1")) "ooodnakov.ps1 exists under scripts/setup"
Assert-True (Test-Path (Join-Path $RepoRoot "scripts/cli/read_optional_deps.py")) "read_optional_deps.py exists under scripts/cli"

Write-Host "`n5. Verifying no scattered dependency lists remain outside TOML..."
$filesToCheck = @(
    "scripts/setup/setup.ps1",
    "scripts/setup/ooodnakov.ps1",
    "scripts/setup/ooodnakov.sh",
    "scripts/setup/lib",
    "README.md",
    "docs/dependency-decisions.md",
    "docs/troubleshooting.md"
)
$badPatterns = @("bat delta", "rg fd", "gum fzf", "wezterm oh-my-posh", "bat, delta, glow")
$foundBad = $false
foreach ($file in $filesToCheck) {
    $path = Join-Path $RepoRoot $file
    $paths = if (Test-Path $path -PathType Container) {
        Get-ChildItem -Path $path -File -Recurse -Include *.ps1,*.psm1,*.sh
    } else {
        Get-Item -Path $path
    }
    foreach ($candidate in $paths) {
        $content = Get-Content $candidate.FullName -Raw
        foreach ($pattern in $badPatterns) {
            if ($content -match [regex]::Escape($pattern)) {
                Write-Host "  Found old list in $($candidate.FullName)" -ForegroundColor Yellow
                $foundBad = $true
            }
        }
    }
}
Assert-True (-not $foundBad) "No hard-coded dependency lists found outside optional-deps.toml"

Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $TestPassed" -ForegroundColor Green
Write-Host "Failed: $TestFailed" -ForegroundColor $(if ($TestFailed -eq 0) { "Green" } else { "Red" })

if ($TestFailed -eq 0) {
    Write-Host "All PowerShell tests passed. Central TOML is the only source of truth." -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests failed. Check output above." -ForegroundColor Red
    exit 1
}
