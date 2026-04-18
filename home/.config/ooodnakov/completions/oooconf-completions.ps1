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
        'version',
        'check',
        'preview',
        'upgrade',
        'help'
    )

    $OooconfGlobalOptions = @(
        '-C', '--repo-root', '-h', '--help', '-n', '--dry-run',
        '--yes-optional', '-V', '--version', '--print-repo-root'
    )

    $OooconfSecretsSubcommands = @(
        'login',
        'unlock',
        'sync',
        'doctor',
        'list',
        'ls',
        'status',
        'logout',
        'add',
        'remove',
        'rm',
        'del'
    )

    $OooconfShellSubcommands = @('status', 'forgit-aliases', 'typo-handling', 'psfzf-tab', 'psfzf-git', 'auto-uv-env')
    $OooconfForgitAliasModes = @('plain', 'forgit', 'status')
    $OooconfTypoHandlingModes = @('silent', 'suggest', 'help', 'status')
    $OooconfPsfzfModes = @('enabled', 'disabled', 'status')
    $ShellValues = @('zsh', 'pwsh', 'bash', 'fish')

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
        'uv',
        'bw',
        'node',
        'npm',
        'pnpm',
        'autoconf',
        'fc-cache',
        'cargo',
        'dua',
        'nvim',
        'k',
        'python3',
        'lazygit',
        'rtk',
        'fastfetch'
    )

    # Simple AST parsing to find the command and subcommands
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

    # Find the main oooconf command position (it might be oooconf/o, .ps1/.cmd variants, or a path)
    $commandIndex = -1
    for ($i = 0; $i -lt $tokens.Length; $i++) {
        if ($tokens[$i] -match '(^|[\\/])(oooconf|o)(\.ps1|\.cmd)?$') {
            $commandIndex = $i
            break
        }
    }

    if ($commandIndex -eq -1) { return @() }

    # Find the first subcommand after oooconf that isn't a global option
    $subcommand = $null
    $subcommandIndex = -1
    for ($i = $commandIndex + 1; $i -lt $tokens.Length; $i++) {
        $t = $tokens[$i]
        if ($t -in $OooconfCommands) {
            $subcommand = $t
            $subcommandIndex = $i
            break
        }
    }

    $completions = @()

    if ($null -eq $subcommand) {
        # Complete subcommands and global options
        $completions = $OooconfCommands + $OooconfGlobalOptions
    }
    elseif ($subcommand -eq 'secrets') {
        # Secrets sub-subcommands
        $secSub = $null
        for ($i = $subcommandIndex + 1; $i -lt $tokens.Length; $i++) {
            if ($tokens[$i] -in $OooconfSecretsSubcommands) {
                $secSub = $tokens[$i]
                break
            }
        }

        if ($null -eq $secSub) {
            $completions = $OooconfSecretsSubcommands + @('--dry-run', '--resolved', '--shell')
        } else {
            # Sub-subcommand options
            if ($tokens[-1] -eq '--shell') {
                $completions = $ShellValues
            } else {
                switch ($secSub) {
                    'unlock' { $completions = @('--shell', '--raw') }
                    'sync'   { $completions = @('--dry-run', '--force', '--template', '--backend') }
                    'list'   { $completions = @('--resolved', '--template', '--backend') }
                    'ls'     { $completions = @('--resolved', '--template', '--backend') }
                    'login'  { $completions = @('--server', '--method', '--client-id', '--client-secret') }
                    default  { $completions = @('--template') }
                }
            }
        }
    }
    elseif ($subcommand -eq 'shell') {
        $shellSub = $null
        for ($i = $subcommandIndex + 1; $i -lt $tokens.Length; $i++) {
            if ($tokens[$i] -in $OooconfShellSubcommands) {
                $shellSub = $tokens[$i]
                break
            }
        }
        if ($null -eq $shellSub) {
            $completions = $OooconfShellSubcommands
        } else {
            switch ($shellSub) {
                'forgit-aliases' { $completions = $OooconfForgitAliasModes }
                'typo-handling'  { $completions = $OooconfTypoHandlingModes }
                'psfzf-tab'      { $completions = $OooconfPsfzfModes }
                'psfzf-git'      { $completions = $OooconfPsfzfModes }
                'auto-uv-env'    { $completions = @('enabled', 'quiet', 'status') }
            }
        }
    }
    elseif ($subcommand -in @('install', 'deps', 'update', 'upgrade')) {
        $completions = @('--dry-run', '--yes-optional') + $OooconfDepsKeys
    }
    elseif ($subcommand -eq 'agents') {
        $completions = @('detect', 'sync', 'doctor', 'update', '--json', '--check', '--strict-config-paths')
    }
    elseif ($subcommand -eq 'update-pins') {
        $completions = @('--apply')
    }
    elseif ($subcommand -eq 'completions') {
        $completions = @('--dry-run')
    }

    return $completions | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# Register for all possible names
@('oooconf', 'oooconf.ps1', 'oooconf.cmd', 'o', 'o.ps1', 'o.cmd') | ForEach-Object {
    Register-ArgumentCompleter -Native -CommandName $_ -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        Get-OooconfCompletions -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
    }
}
