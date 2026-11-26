# herdr-task is an extensionless Python script, which Windows cannot execute
# directly. Run it with Python, from wherever this wrapper (or its link) lives.
$ScriptPath = $PSCommandPath
$ScriptItem = Get-Item -LiteralPath $ScriptPath -ErrorAction SilentlyContinue
if ($ScriptItem -and $ScriptItem.LinkType -eq "SymbolicLink" -and $ScriptItem.Target) {
    $ScriptPath = $ScriptItem.Target
}

$CliScript = Join-Path (Split-Path -Parent $ScriptPath) "herdr-task"
if (-not (Test-Path -LiteralPath $CliScript)) {
    throw "Unable to locate herdr-task next to $ScriptPath"
}

$Python = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $Python) {
    $Python = Get-Command python3 -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}
if (-not $Python) {
    throw "herdr-task needs Python 3.8+ on PATH"
}

$global:LASTEXITCODE = $null
& $Python.Source $CliScript @args
exit $LASTEXITCODE
