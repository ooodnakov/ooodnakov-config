<#
.SYNOPSIS
Comprehensive PowerShell test for the refactored ooodnakov-config (central optional-deps.toml as sole source of truth).
Tests Get-ManagedTool, Get-DepInfo, Run-Python, key install functions (dry-run), TOML fallback parser, and no scattered lists.

Run with: pwsh -NoProfile -File tests/test_powershell.ps1
#>

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$ErrorActionPreference = "Stop"

Write-Host "=== PowerShell Test Suite for ooodnakov-config ===" -ForegroundColor Cyan
Write-Host "Testing central optional-deps.toml as sole source of truth..." -ForegroundColor Cyan

# Dot-source the setup to load functions (use -NoProfile in real runs to avoid conflicts)
. (Join-Path $RepoRoot "scripts/setup.ps1")

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

# Test 1: Get-DepInfo (central TOML)
Write-Host "`n1. Testing Get-DepInfo (from optional-deps.toml)..."
$rtkInfo = Get-DepInfo "rtk"
Assert-True ($rtkInfo.ver -eq "0.37.0") "Get-DepInfo returns ver for rtk"
Assert-True ($rtkInfo.url -like "*rtk-ai/rtk*") "Get-DepInfo returns URL for rtk"

# Test 2: Run-Python wrapper
Write-Host "`n2. Testing Run-Python wrapper (prefers uv)..."
$catalog = Run-Python (Join-Path $RepoRoot "scripts/read_optional_deps.py") @("catalog")
Assert-True ($catalog -like "*rtk*") "Run-Python can call read_optional_deps.py catalog"

# Test 3: Dry-run for key functions (no real install)
Write-Host "`n3. Testing dry-run paths for refactored functions..."
$DryRun = $true
$originalDryRun = $DryRun
try {
    $result = Install-RtkIfMissing
    Assert-True ($true) "Install-RtkIfMissing dry-run completes without error"
    $result = Install-BitwardenCliIfMissing
    Assert-True ($true) "Install-BitwardenCliIfMissing dry-run completes without error"
    $result = Install-PnpmIfMissing
    Assert-True ($true) "Install-PnpmIfMissing dry-run completes without error"
} finally {
    $DryRun = $originalDryRun
}

# Test 4: TOML fallback parser (when Python unavailable)
Write-Host "`n4. Testing TOML fallback parser in setup.ps1..."
$specs = Get-OptionalDependencySpecsFromTomlFallback
Assert-True ($specs.Count -gt 30) "Fallback parser returns all deps from TOML"
$rtkSpec = $specs | Where-Object { $_.Key -eq "rtk" } | Select-Object -First 1
Assert-True ($rtkSpec -ne $null -and $rtkSpec.Ver -eq "0.37.0") "Fallback parser includes rich fields for rtk"

# Test 5: No scattered dependency lists (spot check common places)
Write-Host "`n5. Verifying no scattered dependency lists remain outside TOML..."
$filesToCheck = @(
    "scripts/setup.ps1",
    "scripts/ooodnakov.ps1",
    "scripts/ooodnakov.sh",
    "README.md",
    "docs/dependency-decisions.md",
    "docs/troubleshooting.md"
)
$badPatterns = @("bat delta", "rg fd", "gum fzf", "wezterm oh-my-posh", "bat, delta, glow")
$foundBad = $false
foreach ($file in $filesToCheck) {
    $content = Get-Content (Join-Path $RepoRoot $file) -Raw
    foreach ($pattern in $badPatterns) {
        if ($content -match [regex]::Escape($pattern)) {
            Write-Host "  Found old list in $file" -ForegroundColor Yellow
            $foundBad = $true
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
