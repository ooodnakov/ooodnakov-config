$ScriptPath = $PSCommandPath
$ScriptItem = Get-Item -LiteralPath $ScriptPath -ErrorAction SilentlyContinue
if ($ScriptItem -and $ScriptItem.LinkType -eq "SymbolicLink" -and $ScriptItem.Target) {
    $ScriptPath = $ScriptItem.Target
}

$RepoRoot = if ($env:OOODNAKOV_REPO_ROOT) {
    $env:OOODNAKOV_REPO_ROOT
} else {
    Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $ScriptPath))))
}

$CliScript = Join-Path $RepoRoot "scripts/ooodnakov.ps1"

if (-not (Test-Path $CliScript)) {
    throw "Unable to locate PowerShell oooconf entrypoint at $CliScript"
}

& $CliScript @args
exit $LASTEXITCODE
