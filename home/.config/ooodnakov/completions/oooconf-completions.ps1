# PowerShell argument completions for oooconf
# This file is automatically loaded by the managed PowerShell profile via common.ps1

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
    'status',
    'login',
    'unlock',
    'logout'
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
        }
        if ($subcommand -eq 'sync') {
            $options += '--dry-run'
        }
        if ($subcommand -eq 'list') {
            $options += '--resolved'
        }

        return $options | Where-Object { $_ -like "$WordToComplete*" }
    }

    # update-pins options
    if ($command -eq 'update-pins') {
        return @('--apply') | Where-Object { $_ -like "$WordToComplete*" }
    }

    # install, deps, update global options
    if ($command -in @('install', 'deps', 'update')) {
        return @('--dry-run', '--yes-optional') | Where-Object { $_ -like "$WordToComplete*" }
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
