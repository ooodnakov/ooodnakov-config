# Pregenerate the PowerShell tool-completion cache used by the managed profile.
#
# The zsh completions are generated at setup time by
# generate_tool_completions.py. This is the PowerShell equivalent: it loads the
# shared environment, which registers/generates the same tool completions into
# OOODNAKOV_CACHE_HOME\completions, then exits. Shell startup then only loads
# the cached files; if a cache is missing it is still generated on demand.

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$env:OOODNAKOV_CACHE_HOME = if ($env:OOODNAKOV_CACHE_HOME) {
    $env:OOODNAKOV_CACHE_HOME
} else {
    Join-Path $HOME ".cache/ooodnakov-config"
}

# Force a fresh generation: Invoke-CachedCompletionScript only writes when a
# file is missing, and this run is the setup-time equivalent of the zsh
# generator.
$completionDir = Join-Path $env:OOODNAKOV_CACHE_HOME "completions"
Remove-Item -LiteralPath $completionDir -Recurse -Force -ErrorAction SilentlyContinue

. (Join-Path $RepoRoot "home/.config/ooodnakov/env/common.ps1")
if (Test-Path -LiteralPath $completionDir) {
    Write-Output "PowerShell completions: $completionDir"
} else {
    Write-Output "PowerShell completions: no supported tools found"
}
