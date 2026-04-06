param(
    [Parameter(Position = 0)]
    [ValidateSet("install", "update", "doctor", "dry-run")]
    [string]$Command = "install"
)

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$SetupScript = Join-Path $PSScriptRoot "setup.ps1"

switch ($Command) {
    "install" { & $SetupScript install }
    "update" { & $SetupScript update }
    "doctor" { & $SetupScript doctor }
    "dry-run" { & $SetupScript install -DryRun }
}
