param(
    [Parameter(Position = 0)]
    [ValidateSet("install", "update", "doctor", "dry-run", "lock", "update-pins")]
    [string]$Command = "install",
    [switch]$Apply
)

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$SetupScript = Join-Path $PSScriptRoot "setup.ps1"
$GenerateLockScript = Join-Path $PSScriptRoot "generate-dependency-lock.py"
$UpdatePinsScript = Join-Path $PSScriptRoot "update-pins.py"

switch ($Command) {
    "install" { & $SetupScript install }
    "update" { & $SetupScript update }
    "doctor" { & $SetupScript doctor }
    "dry-run" { & $SetupScript install -DryRun }
    "lock" {
        if (Get-Command python3 -ErrorAction SilentlyContinue) {
            & python3 $GenerateLockScript
        } else {
            throw "python3 is required to generate dependency lock artifacts."
        }
    }
    "update-pins" {
        if (Get-Command python3 -ErrorAction SilentlyContinue) {
            if ($Apply) {
                & python3 $UpdatePinsScript --apply
            } else {
                & python3 $UpdatePinsScript
            }
        } else {
            throw "python3 is required for update-pins."
        }
    }
}
