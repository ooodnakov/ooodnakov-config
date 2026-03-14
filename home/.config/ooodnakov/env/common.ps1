$env:EDITOR = if ($env:EDITOR) { $env:EDITOR } else { "nvim" }
$env:VISUAL = if ($env:VISUAL) { $env:VISUAL } else { $env:EDITOR }
$env:PAGER = if ($env:PAGER) { $env:PAGER } else { "less" }

$localBin = Join-Path $HOME ".local/bin"
if (Test-Path $localBin) {
    $env:PATH = "$localBin$([IO.Path]::PathSeparator)$env:PATH"
}

$cargoBin = Join-Path $HOME ".cargo/bin"
if (Test-Path $cargoBin) {
    $env:PATH = "$cargoBin$([IO.Path]::PathSeparator)$env:PATH"
}

$npmBin = Join-Path $HOME ".npm/bin"
if (Test-Path $npmBin) {
    $env:PATH = "$npmBin$([IO.Path]::PathSeparator)$env:PATH"
}

$pnpmHome = if ($env:PNPM_HOME) { $env:PNPM_HOME } else { Join-Path $HOME ".local/share/pnpm" }
$env:PNPM_HOME = $pnpmHome
if (Test-Path $pnpmHome) {
    $env:PATH = "$pnpmHome$([IO.Path]::PathSeparator)$env:PATH"
}
