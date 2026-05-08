# PowerShell argument completions for oooconf
# This file is automatically loaded by the managed PowerShell profile via common.ps1

function Get-OooconfCompletions {
    param($wordToComplete, $commandAst, $cursorPosition)

    $OooconfCommands = @(
        'bootstrap',
        'install',
        'deps',
        'update',
        'doctor',
        'dry-run',
        'delete',
        'remove',
        'lock',
        'update-pins',
        'completions',
        'agents',
        'secrets',
        'shell',
        'color',
        'version',
        'check',
        'preview',
        'upgrade',
        'komorebi',
        'wm',
        'help'
    )

    $OooconfGlobalOptions = @(
        '-C',
        '--repo-root',
        '--print-repo-root',
        '-h',
        '--help',
        '-n',
        '--dry-run',
        '--yes-optional',
        '-V',
        '--version'
    )

    $OooconfDepsKeys = @(
        'wget',
        'git',
        'wezterm',
        'oh-my-posh',
        'posh-git',
        'psfzf',
        'choco',
        'gsudo',
        'rg',
        'fd',
        'zsh',
        'direnv',
        'fzf',
        'bat',
        'delta',
        'glow',
        'gum',
        'zoxide',
        'q',
        'eza',
        'yazi',
        'ffmpeg',
        'jq',
        'p7zip',
        'poppler',
        'fc-cache',
        'cargo',
        'dua',
        'nvim',
        'tree-sitter',
        'k',
        'python3',
        'lazygit',
        'lazydocker',
        'impala',
        'bluetui',
        'uv',
        'bw',
        'pnpm',
        'rtk',
        'imagemagick',
        'ghostscript',
        'luarocks',
        'tectonic',
        'mermaid-cli',
        'zig',
        'neovim-node',
        'neovim-python',
        'fastfetch',
        'btop',
        'cava',
        'blackhole-2ch',
        'glazewm',
        'zebar',
        'overline-zebar'
    )

    $OooconfAliases =
    @{
        'check' = @('doctor')
        'preview' = @('dry-run')
        'upgrade' = @('update')
    }

    $OooconfCommandOptions =
    @{
        'agents' = @()
        'bootstrap' = @()
        'check' = @()
        'color' = @()
        'completions' = @('--dry-run')
        'delete' = @()
        'deps' = @('--dry-run', '--yes-optional', '-h', '--help')
        'doctor' = @()
        'dry-run' = @()
        'help' = @()
        'install' = @('--dry-run', '--yes-optional', '-h', '--help')
        'lock' = @()
        'minimal' = @()
        'preview' = @()
        'remove' = @()
        'secrets' = @()
        'shell' = @()
        'update' = @('--dry-run', '--yes-optional', '-h', '--help')
        'update-pins' = @('--apply')
        'upgrade' = @()
        'version' = @()
        'wm' = @()
    }

    $OooconfCommandSubcommands =
    @{
        'agents' = @('detect', 'sync', 'doctor', 'mcp', 'status', 'rtk', 'provider', 'update', 'install', 'install-scripts-build', 'skills')
        'bootstrap' = @()
        'check' = @()
        'color' = @()
        'completions' = @()
        'delete' = @()
        'deps' = @()
        'doctor' = @()
        'dry-run' = @()
        'help' = @()
        'install' = @()
        'lock' = @()
        'minimal' = @()
        'preview' = @()
        'remove' = @()
        'secrets' = @('login', 'unlock', 'sync', 'doctor', 'list', 'ls', 'status', 'logout', 'add', 'remove', 'rm', 'del')
        'shell' = @('status', 'forgit-aliases', 'typo-handling', 'psfzf-tab', 'psfzf-git', 'auto-uv-env')
        'update' = @()
        'update-pins' = @()
        'upgrade' = @()
        'version' = @()
        'wm' = @('status', 'set', 'start', 'stop', 'reload', 'bar', 'komorebi')
    }

    $OooconfCommandValues =
    @{
        'agents' = @()
        'bootstrap' = @()
        'check' = @()
        'color' = @('status', 'list', 'default', 'catppuccin', 'gruvbox', 'nord', 'tokyonight', 'noctalia')
        'completions' = @()
        'delete' = @()
        'deps' = @()
        'doctor' = @()
        'dry-run' = @()
        'help' = @()
        'install' = @()
        'lock' = @()
        'minimal' = @()
        'preview' = @()
        'remove' = @()
        'secrets' = @()
        'shell' = @()
        'update' = @()
        'update-pins' = @()
        'upgrade' = @()
        'version' = @()
        'wm' = @('komorebi', 'glazewm')
    }

    $OooconfSubcommandOptions =
    @{
        'agents:detect' = @('--repo-root', '--config', '--json')
        'agents:doctor' = @('--repo-root', '--config', '--strict-config-paths')
        'agents:install' = @('--repo-root', '--config', '--check')
        'agents:sync' = @('--repo-root', '--config', '--check', '--global', '--materialize-secrets')
        'agents:update' = @('--repo-root', '--config', '--check')
        'secrets:add' = @('--template')
        'secrets:del' = @('--template')
        'secrets:doctor' = @('--backend', '--template')
        'secrets:list' = @('--template', '--resolved', '--backend')
        'secrets:login' = @('--server', '--method', '--client-id', '--client-secret')
        'secrets:ls' = @('--template', '--resolved', '--backend')
        'secrets:remove' = @('--template')
        'secrets:rm' = @('--template')
        'secrets:status' = @('--template')
        'secrets:sync' = @('--backend', '--template', '--dry-run', '--force')
        'secrets:unlock' = @('--shell', '--raw')
    }

    $OooconfSubcommandValues =
    @{
        'shell:auto-uv-env' = @('enabled', 'quiet', 'status')
        'shell:forgit-aliases' = @('plain', 'forgit', 'status')
        'shell:psfzf-git' = @('enabled', 'disabled', 'status')
        'shell:psfzf-tab' = @('enabled', 'disabled', 'status')
        'shell:typo-handling' = @('silent', 'suggest', 'help', 'status')
    }

    $OooconfSubsubcommands =
    @{
        'agents:mcp' = @('sync', 'status', 'add')
        'agents:provider' = @('sync')
        'agents:rtk' = @('init')
        'agents:skills' = @('sync', 'view', 'add')
    }

    $OooconfSubsubcommandOptions =
    @{
        'agents:mcp:add' = @('--name', '--json', '--multi', '--preview', '--sync-now', '--check')
        'agents:mcp:status' = @()
        'agents:mcp:sync' = @('--check')
        'agents:provider:sync' = @('--check', '--materialize-secrets', '--region')
        'agents:rtk:init' = @('--check')
        'agents:skills:add' = @('--agent', '--sync-now', '--check')
        'agents:skills:sync' = @('--check')
        'agents:skills:view' = @('--check', '--json')
    }

    $OooconfOptionValues =
    @{
        'agents:--region' = @('global', 'china')
        'secrets:--backend' = @('bw')
        'secrets:--method' = @('auto', 'password', 'apikey')
        'secrets:--shell' = @('sh', 'zsh', 'bash', 'pwsh', 'fish')
    }

    $elements = $commandAst.CommandElements
    $tokens = @()
    for ($i = 0; $i -lt $elements.Count; $i++) {
        $element = $elements[$i]
        if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $val = $element.Value
            if ($val -eq $wordToComplete -and $i -eq ($elements.Count - 1)) { break }
            $tokens += $val
        }
    }

    $commandIndex = -1
    for ($i = 0; $i -lt $tokens.Length; $i++) {
        if ($tokens[$i] -match '(^|[\\/])(oooconf|o)(\.ps1|\.cmd)?$') {
            $commandIndex = $i
            break
        }
    }
    if ($commandIndex -eq -1) { return @() }

    $commandName = $null
    $commandPos = -1
    for ($i = $commandIndex + 1; $i -lt $tokens.Length; $i++) {
        $token = $tokens[$i]
        if ($token -in $OooconfCommands) { $commandName = $token; $commandPos = $i; break }
    }

    $completions = @()
    if ($null -eq $commandName) {
        $completions = $OooconfCommands + $OooconfGlobalOptions
    } else {
        if ($OooconfAliases.ContainsKey($commandName)) { $commandName = $OooconfAliases[$commandName][0] }
        $commandOpts = if ($OooconfCommandOptions.ContainsKey($commandName)) { $OooconfCommandOptions[$commandName] } else { @() }
        $subcommands = if ($OooconfCommandSubcommands.ContainsKey($commandName)) { $OooconfCommandSubcommands[$commandName] } else { @() }
        $commandValues = if ($OooconfCommandValues.ContainsKey($commandName)) { $OooconfCommandValues[$commandName] } else { @() }

        $subcommandName = $null
        for ($i = $commandPos + 1; $i -lt $tokens.Length; $i++) {
            if ($tokens[$i] -in $subcommands) { $subcommandName = $tokens[$i]; break }
        }

        if ($null -eq $subcommandName) {
            $completions = $commandOpts + $subcommands + $commandValues
            if ($commandName -in @('install', 'deps', 'update')) { $completions += $OooconfDepsKeys }
        } else {
            $lastToken = if ($tokens.Length -gt 0) { $tokens[-1] } else { '' }
            $valueKey = "${commandName}:$lastToken"
            if ($OooconfOptionValues.ContainsKey($valueKey)) {
                $completions = $OooconfOptionValues[$valueKey]
            } else {
                $optKey = "${commandName}:$subcommandName"
                $subsubKey = "${commandName}:$subcommandName"
                $subsubCommands = if ($OooconfSubsubcommands.ContainsKey($subsubKey)) { $OooconfSubsubcommands[$subsubKey] } else { @() }
                $subsubcommandName = $null
                for ($j = $commandPos + 2; $j -lt $tokens.Length; $j++) {
                    if ($tokens[$j] -in $subsubCommands) { $subsubcommandName = $tokens[$j]; break }
                }

                if ($null -eq $subsubcommandName) {
                    if ($OooconfSubcommandOptions.ContainsKey($optKey)) { $completions += $OooconfSubcommandOptions[$optKey] }
                    if ($OooconfSubcommandValues.ContainsKey($optKey)) { $completions += $OooconfSubcommandValues[$optKey] }
                    $completions += $subsubCommands
                } else {
                    $subsubOptKey = "${commandName}:${subcommandName}:$subsubcommandName"
                    if ($OooconfSubsubcommandOptions.ContainsKey($subsubOptKey)) { $completions += $OooconfSubsubcommandOptions[$subsubOptKey] }
                }
            }
        }
    }

    return $completions | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

@('oooconf', 'oooconf.ps1', 'oooconf.cmd', 'o', 'o.ps1', 'o.cmd') | ForEach-Object {
    Register-ArgumentCompleter -Native -CommandName $_ -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        Get-OooconfCompletions -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
    }
}
