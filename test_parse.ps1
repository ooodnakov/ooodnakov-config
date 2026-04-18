$null = $errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path "scripts/setup.ps1"),
  [ref]$null,
  [ref]$errors
) | Out-Null
if ($errors.Count -gt 0) {
  $errors | ForEach-Object { Write-Error $_.Message }
  throw "PowerShell parse failed"
}
Write-Host "[ok] Parsed scripts/setup.ps1"
