$ScriptPath = $PSCommandPath
$ScriptItem = Get-Item -LiteralPath $ScriptPath -ErrorAction SilentlyContinue
if ($ScriptItem -and $ScriptItem.LinkType -eq "SymbolicLink" -and $ScriptItem.Target) {
    $ScriptPath = $ScriptItem.Target
}

$OooconfWrapper = Join-Path (Split-Path -Parent $ScriptPath) "oooconf.ps1"
if (-not (Test-Path $OooconfWrapper)) {
    throw "Unable to locate oooconf wrapper at $OooconfWrapper"
}

& $OooconfWrapper @args
exit $LASTEXITCODE
