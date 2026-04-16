# PowerShell argument completions for oooconf
# This file is automatically loaded by the managed PowerShell profile via common.ps1

$OooconfCommands = @(
    'bootstrap',
    'install',
    'deps',
    'update',
    'upgrade',
    'doctor',
    'check',
    'dry-run',
    'preview',
    'delete',
    'remove',
    'lock',
    'update-pins',
    'agents',
    'shell',
    'secrets',
    'help',
    'version'
)

$OooconfGlobalOptions = @(
    '-C',
    '--repo-root',
    '-h',
    '--help',
    '-n',
    '--dry-run',
    '--yes-optional',
    '-V',
    '--version',
    '--print-repo-root'
)

$OooconfSecretsSubcommands = @(
    'sync',
    'doctor',
    'list',
    'ls',
    'status',
    'login',
    'unlock',
    'logout',
    'add',
    'remove',
    'rm',
    'del'
)

$OooconfShellSubcommands = @(
    'forgit-aliases',
    'typo-handling'
)

$OooconfForgitAliasModes = @(
    'plain',
    'forgit',
    'status'
)

$OooconfTypoHandlingModes = @(
    'silent',
    'suggest',
    'help',
    'status'
)

$ShellValues = @('zsh', 'pwsh', 'bash', 'fish')

function Get-OooconfCompleter {
    param(
        [string]$WordToComplete,
        [string[]]$Tokens
    )

    # Find command position
    $commandIndex = -1
    for ($i = 1; $i -lt $Tokens.Length; $i++) {
        if ($Tokens[$i] -in $OooconfCommands) {
            $commandIndex = $i
            break
        }
    }

    # If no command yet, complete commands and global options
    if ($commandIndex -eq -1) {
        $completions = @()
        $completions += $OooconfCommands | Where-Object { $_ -like "$WordToComplete*" }
        $completions += $OooconfGlobalOptions | Where-Object { $_ -like "$WordToComplete*" }

        return $completions | Sort-Object -Unique
    }

    $command = $Tokens[$commandIndex]

    # Secrets subcommands
    if ($command -eq 'secrets') {
        $subcommandIndex = -1
        for ($i = $commandIndex + 1; $i -lt $Tokens.Length; $i++) {
            if ($Tokens[$i] -in $OooconfSecretsSubcommands) {
                $subcommandIndex = $i
                break
            }
        }

        if ($subcommandIndex -eq -1) {
            $completions = @()
            $completions += $OooconfSecretsSubcommands | Where-Object { $_ -like "$WordToComplete*" }
            $completions += @('--dry-run', '--resolved', '--shell') | Where-Object { $_ -like "$WordToComplete*" }
            return $completions | Sort-Object -Unique
        }

        $subcommand = $Tokens[$subcommandIndex]

        # Complete --shell values
        if ($WordToComplete -like '--shell*' -or $Tokens[-1] -eq '--shell') {
            return $ShellValues | Where-Object { $_ -like "$WordToComplete*" }
        }

        # Command-specific options
        $options = @()
        if ($subcommand -eq 'unlock') {
            $options += '--shell'
            $options += '--raw'
        }
        if ($subcommand -eq 'sync') {
            $options += '--dry-run'
            $options += '--force'
            $options += '--template'
            $options += '--backend'
        }
        if ($subcommand -in @('list', 'ls')) {
            $options += '--resolved'
            $options += '--template'
            $options += '--backend'
        }
        if ($subcommand -in @('doctor', 'status', 'add', 'remove', 'rm', 'del')) {
            $options += '--template'
        }
        if ($subcommand -eq 'doctor') {
            $options += '--backend'
        }
        if ($subcommand -eq 'login') {
            $options += '--server'
        }

        return $options | Where-Object { $_ -like "$WordToComplete*" }
    }

    if ($command -eq 'shell') {
        $subcommandIndex = -1
        for ($i = $commandIndex + 1; $i -lt $Tokens.Length; $i++) {
            if ($Tokens[$i] -in $OooconfShellSubcommands) {
                $subcommandIndex = $i
                break
            }
        }

        if ($subcommandIndex -eq -1) {
            return $OooconfShellSubcommands | Where-Object { $_ -like "$WordToComplete*" }
        }

        $subcommand = $Tokens[$subcommandIndex]
        if ($subcommand -eq 'forgit-aliases') {
            return $OooconfForgitAliasModes | Where-Object { $_ -like "$WordToComplete*" }
        }
        if ($subcommand -eq 'typo-handling') {
            return $OooconfTypoHandlingModes | Where-Object { $_ -like "$WordToComplete*" }
        }
    }

    # update-pins options
    if ($command -eq 'update-pins') {
        return @('--apply') | Where-Object { $_ -like "$WordToComplete*" }
    }

    if ($command -eq 'agents') {
        return @('detect', 'sync', 'doctor', '--json', '--check', '--strict-config-paths') | Where-Object { $_ -like "$WordToComplete*" }
    }

    # install, deps, update global options
    if ($command -in @('install', 'deps', 'update', 'upgrade')) {
        return @('--dry-run', '--yes-optional') | Where-Object { $_ -like "$WordToComplete*" }
    }

    if ($command -in @('doctor', 'check', 'dry-run', 'preview', 'bootstrap', 'delete', 'remove', 'version')) {
        return @()
    }

    return @()
}

Register-ArgumentCompleter -CommandName oooconf -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $tokens = @($commandAst.ToString().TrimEnd() -split '\s+' | Where-Object { $_ -ne '' })

    $completions = Get-OooconfCompleter -WordToComplete $wordToComplete -Tokens $tokens

    return $completions | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(
            $_,
            $_,
            [System.Management.Automation.CompletionResultType]::ParameterValue,
            $_
        )
    }
}

# Register completions for .ps1 and .cmd wrappers
@('oooconf.ps1', 'oooconf.cmd') | ForEach-Object {
    Register-ArgumentCompleter -CommandName $_ -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        $tokens = @($commandAst.ToString().TrimEnd() -split '\s+' | Where-Object { $_ -ne '' })

        # Replace the .ps1/.cmd command with oooconf for completion purposes
        if ($tokens.Count -gt 0) {
            $tokens[0] = 'oooconf'
        }

        $completions = Get-OooconfCompleter -WordToComplete $wordToComplete -Tokens $tokens

        return $completions | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                $_,
                $_,
                [System.Management.Automation.CompletionResultType]::ParameterValue,
                $_
            )
        }
    }
}
