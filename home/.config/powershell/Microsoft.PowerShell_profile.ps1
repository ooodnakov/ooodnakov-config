$ConfigRoot = Join-Path $HOME ".config/ooodnakov"
$PromptConfig = Join-Path $HOME ".config/ohmyposh/ooodnakov.omp.json"
$SharedEnv = Join-Path $ConfigRoot "env/common.ps1"
$LocalEnv = Join-Path $ConfigRoot "local/env.ps1"

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config $PromptConfig | Invoke-Expression
}

if (Test-Path $SharedEnv) {
    . $SharedEnv
}

if (Test-Path $LocalEnv) {
    . $LocalEnv
}

Set-Alias ll Get-ChildItem
