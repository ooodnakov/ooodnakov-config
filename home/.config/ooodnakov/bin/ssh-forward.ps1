# ssh-forward.ps1 - PowerShell port of the zsh ssh-forward helper.
#
# Mirrors the interface from home/.config/zsh/.zshrc.d/10-shell.zsh:
#   ssh-forward [-r] [<host>] [<local-port>] [<remote-port>]
#   ssh-forward-ls [-a|--all]
#
# Differences from the zsh version: Windows OpenSSH does not implement
# master-mode control sockets (-M / -S / -O exit), so each tunnel is
# tracked via its PID in a small JSON sidecar under $env:TEMP. Closing a
# tunnel stops the process and removes the sidecar.
#
# Interactive bits (host picker, tunnel picker) shell out to `fzf` when
# available and we're on an interactive console host; otherwise they fall
# back to Read-Host / plain text.

$script:SshForwardStateDir = Join-Path $env:TEMP 'ooodnakov-ssh-forward'
if (-not (Test-Path -LiteralPath $script:SshForwardStateDir)) {
    New-Item -ItemType Directory -Path $script:SshForwardStateDir -Force | Out-Null
}

$script:SshForwardRecentPath = Join-Path $script:SshForwardStateDir 'recent.json'

function Get-SshForwardSocketPath {
    param(
        [Parameter(Mandatory = $true)][string]$Hostname,
        [Parameter(Mandatory = $true)][int]$Port,
        [switch]$Reverse
    )

    $tag = if ($Reverse) { 'ssh-fwd-r' } else { 'ssh-fwd' }
    return Join-Path $script:SshForwardStateDir ($tag + '-' + $Hostname + '-' + $Port + '.json')
}

function Test-SshForwardTunnelAlive {
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    return [bool]$proc
}

function Write-SshForwardState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$State
    )

    $State | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-SshForwardState {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $obj = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return @{
            Host        = [string]$obj.Host
            LocalPort   = [int]$obj.LocalPort
            RemotePort  = [int]$obj.RemotePort
            Reverse     = [bool]$obj.Reverse
            ProcessId   = [int]$obj.ProcessId
            User        = if ($obj.PSObject.Properties['User']) { [string]$obj.User } else { '' }
        }
    } catch {
        return $null
    }
}

function Remove-SshForwardState {
    param([Parameter(Mandatory = $true)][string]$Path)

    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Stop-SshForwardTunnel {
    param([Parameter(Mandatory = $true)][string]$StatePath)

    $state = Read-SshForwardState -Path $StatePath
    if (-not $state) {
        Remove-SshForwardState -Path $StatePath
        return $true
    }

    $alive = $false
    try {
        $proc = Get-Process -Id $state.ProcessId -ErrorAction SilentlyContinue
        if ($proc) {
            Stop-Process -Id $state.ProcessId -Force -ErrorAction SilentlyContinue
            $alive = $true
        }
    } catch {
        $alive = $false
    }

    Remove-SshForwardState -Path $StatePath
    return $alive
}

# Parse `Host ...` blocks out of OpenSSH client config files. Returns an
# array of objects with Alias, HostName, User. Wildcards ('*') are skipped.
function Get-SshForwardHostList {
    $ooodnakovRoot = if ($ConfigRoot) { $ConfigRoot } else { (Join-Path $HOME '.config/ooodnakov') }
    $configFiles = @(
        (Join-Path $HOME '.ssh/config')
        (Join-Path $ooodnakovRoot 'ssh/config')
    )

    $entries = @()
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($path in $configFiles) {
        if (-not (Test-Path -LiteralPath $path)) { continue }

        $currentAlias = $null
        $currentHost = $null
        $currentUser = $null

        foreach ($line in (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
            $trimmed = $line.Trim() -replace '\s+#.*$', ''
            if (-not $trimmed) { continue }
            if ($trimmed -match '^(?i)Host\s+(.+)$') {
                if ($currentAlias -and $currentAlias -notmatch '\*') {
                    if ($seen.Add($currentAlias)) {
                        $entries += [pscustomobject]@{
                            Alias   = $currentAlias
                            HostName = if ($currentHost) { $currentHost } else { $currentAlias }
                            User    = if ($currentUser) { $currentUser } else { '' }
                        }
                    }
                }
                $currentAlias = ($matches[1].Trim() -split '\s+')[0]
                $currentHost = $null
                $currentUser = $null
            } elseif ($currentAlias) {
                if ($trimmed -match '^(?i)HostName\s+(.+)$') { $currentHost = $matches[1].Trim() }
                elseif ($trimmed -match '^(?i)User\s+(.+)$') { $currentUser = $matches[1].Trim() }
            }
        }

        if ($currentAlias -and $currentAlias -notmatch '\*') {
            if ($seen.Add($currentAlias)) {
                $entries += [pscustomobject]@{
                    Alias   = $currentAlias
                    HostName = if ($currentHost) { $currentHost } else { $currentAlias }
                    User    = if ($currentUser) { $currentUser } else { '' }
                }
            }
        }
    }

    return $entries
}

function Get-SshForwardRecentPort {
    param([Parameter(Mandatory = $true)][string]$Hostname)

    if (-not (Test-Path -LiteralPath $script:SshForwardRecentPath)) { return $null }
    try {
        $obj = Get-Content -LiteralPath $script:SshForwardRecentPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($obj.PSObject.Properties[$Hostname]) { return [int]$obj.$Hostname }
    } catch { }
    return $null
}

function Set-SshForwardRecentPort {
    param(
        [Parameter(Mandatory = $true)][string]$Hostname,
        [Parameter(Mandatory = $true)][int]$Port
    )

    $table = [ordered]@{}
    if (Test-Path -LiteralPath $script:SshForwardRecentPath) {
        try {
            $existing = Get-Content -LiteralPath $script:SshForwardRecentPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            foreach ($prop in $existing.PSObject.Properties) {
                $table[$prop.Name] = [int]$prop.Value
            }
        } catch { }
    }
    $table[$Hostname] = $Port
    $table | ConvertTo-Json | Set-Content -LiteralPath $script:SshForwardRecentPath -Encoding UTF8
}

function Show-SshForwardHostPicker {
    $hosts = Get-SshForwardHostList
    if (-not $hosts) {
        Write-Error 'ssh-forward: no SSH config hosts found in ~/.ssh/config or ~/.config/ooodnakov/ssh/config.'
        return $null
    }

    $lines = $hosts | ForEach-Object {
        $userLabel = if ($_.User) { "$($_.User)@" } else { '' }
        '{0,-20}  {1}{2}' -f $_.Alias, $userLabel, $_.HostName
    }
    $input = ($lines -join "`n") + "`n"

    $choice = $null
    try {
        $choice = $input | fzf --prompt 'host > ' --height 40% --reverse --ansi --no-multi --header 'Pick a host alias (Enter selects)' --with-nth=1
    } catch {
        Write-Error "ssh-forward: fzf failed: $($_.Exception.Message)"
        return $null
    }
    if (-not $choice) { return $null }

    $alias = ($choice -split '\s+')[0].Trim()
    return $hosts | Where-Object { $_.Alias -eq $alias } | Select-Object -First 1
}

function Read-SshForwardPort {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][int]$Default
    )

    $suffix = if ($Default) { " [$Default]" } else { '' }
    $answer = Read-Host "${Prompt}${suffix}"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    if ($answer -notmatch '^\d+$' -or ([int]$answer -lt 1 -or [int]$answer -gt 65535)) {
        Write-Error "ssh-forward: invalid port '$answer'."
        return $null
    }
    return [int]$answer
}

function ssh-forward {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Argument1,
        [Parameter(Position = 1)]
        [string]$Argument2,
        [Parameter(Position = 2)]
        [string]$Argument3,
        [switch]$Reverse
    )

    # Accept the zsh-style `-r` flag for parity.
    if ($Argument1 -eq '-r') {
        $Reverse = $true
        $hostname = $Argument2
        $port1 = $Argument3
        $port2 = if ($args.Count -ge 4) { $args[3] } else { $null }
    } else {
        $hostname = $Argument1
        $port1 = $Argument2
        $port2 = $Argument3
    }

    $sshUserResolved = ''
    $sshHostArg = $null
    $userAtHost = $null

    # Interactive picker when host is missing.
    if ([string]::IsNullOrWhiteSpace($hostname)) {
        if (-not (Test-InteractiveConsoleHost)) {
            Write-Host 'Usage:'
            Write-Host '  Local (default):  ssh-forward <host> <local-port> [remote-port]'
            Write-Host '  Reverse:          ssh-forward -r <host> <remote-port> [local-port]'
            return 1
        }
        if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
            Write-Error 'ssh-forward: fzf is required for the interactive host picker.'
            return 1
        }

        $picked = Show-SshForwardHostPicker
        if (-not $picked) { return 1 }
        $hostname = $picked.Alias
        $userAtHost = if ($picked.User) { "$($picked.User)@$($picked.HostName)" } else { $picked.HostName }
        $sshHostArg = if ($picked.User) { "$($picked.User)@$($picked.HostName)" } else { $picked.HostName }
        $sshUserResolved = $picked.User

        $defaultPort = Get-SshForwardRecentPort -Hostname $hostname
        if (-not $defaultPort) { $defaultPort = 8080 }

        $pickedPort = Read-SshForwardPort -Prompt 'local port' -Default $defaultPort
        if ($null -eq $pickedPort) { return 1 }

        $localPort = $pickedPort
        $remotePort = Read-SshForwardPort -Prompt 'remote port' -Default $pickedPort
        if ($null -eq $remotePort) { return 1 }
    } else {
        # Direct invocation path.
        if ([string]::IsNullOrWhiteSpace($port1)) {
            Write-Error 'ssh-forward: missing port.'
            return 1
        }
        if (-not ($port1 -match '^\d+$') -or ([int]$port1 -lt 1 -or [int]$port1 -gt 65535)) {
            Write-Error "ssh-forward: invalid port '$port1'. Use a number between 1 and 65535."
            return 1
        }
        $resolvedPort2 = if ([string]::IsNullOrWhiteSpace($port2)) { [int]$port1 } else {
            if (-not ($port2 -match '^\d+$') -or ([int]$port2 -lt 1 -or [int]$port2 -gt 65535)) {
                Write-Error "ssh-forward: invalid port '$port2'. Use a number between 1 and 65535."
                return 1
            }
            [int]$port2
        }

        $localPort = if ($Reverse) { $resolvedPort2 } else { [int]$port1 }
        $remotePort = if ($Reverse) { [int]$port1 } else { $resolvedPort2 }

        $sshHostArg = $hostname
        $userAtHost = $hostname
    }

    if (-not (Test-Command 'ssh')) {
        Write-Error 'ssh: command not found. Install OpenSSH for Windows or add it to PATH.'
        return 1
    }

    $statePath = Get-SshForwardSocketPath -Hostname $hostname -Port $localPort -Reverse:$Reverse
    if (Test-Path -LiteralPath $statePath) {
        $existing = Read-SshForwardState -Path $statePath
        if ($existing -and (Test-SshForwardTunnelAlive -ProcessId $existing.ProcessId)) {
            Write-Error "ssh-forward: tunnel for ${hostname}:${localPort} is already running (PID $($existing.ProcessId)). Use ssh-forward-ls to manage it."
            return 1
        }
        Remove-SshForwardState -Path $statePath
    }

    if ($Reverse) {
        Write-Host "Forwarding remote port ${remotePort} to local http://localhost:${localPort} on ${userAtHost}..."
        $forwardSpec = "${remotePort}:localhost:${localPort}"
        $sshArgs = @('-N', '-R', $forwardSpec, $sshHostArg)
    } else {
        Write-Host "Forwarding local localhost:${localPort} to remote port ${remotePort} on ${userAtHost}..."
        $forwardSpec = "${localPort}:localhost:${remotePort}"
        $sshArgs = @('-N', '-L', $forwardSpec, $sshHostArg)
    }

    try {
        $proc = Start-Process -FilePath 'ssh' -ArgumentList $sshArgs -PassThru -WindowStyle Hidden
    } catch {
        Write-Error "ssh-forward: failed to launch ssh: $($_.Exception.Message)"
        return 1
    }

    if (-not $proc) {
        Write-Error 'ssh-forward: failed to launch ssh (no process returned).'
        return 1
    }

    Start-Sleep -Milliseconds 250
    if (-not (Test-SshForwardTunnelAlive -ProcessId $proc.Id)) {
        Write-Host '✘ Failed to establish tunnel (ssh exited immediately).'
        return 1
    }

    $state = @{
        Host        = $hostname
        LocalPort   = $localPort
        RemotePort  = $remotePort
        Reverse     = [bool]$Reverse
        ProcessId   = $proc.Id
        User        = $sshUserResolved
    }
    Write-SshForwardState -Path $statePath -State $state
    Set-SshForwardRecentPort -Hostname $hostname -Port $localPort

    Write-Host "✔ Tunnel established in background (PID $($proc.Id))."
    return 0
}

function ssh-forward-ls {
    [CmdletBinding()]
    param(
        [Alias('a')][switch]$All
    )

    $stateFiles = Get-ChildItem -LiteralPath $script:SshForwardStateDir -Filter 'ssh-fwd*.json' -ErrorAction SilentlyContinue
    if (-not $stateFiles) {
        Write-Host 'No active ssh-forward tunnels found.'
        return 0
    }

    $live = @()
    foreach ($file in $stateFiles) {
        $state = Read-SshForwardState -Path $file.FullName
        if (-not $state) {
            Remove-SshForwardState -Path $file.FullName
            continue
        }
        if (-not (Test-SshForwardTunnelAlive -ProcessId $state.ProcessId)) {
            Remove-SshForwardState -Path $file.FullName
            continue
        }
        $live += [pscustomobject]@{
            Path       = $file.FullName
            Host       = $state.Host
            LocalPort  = $state.LocalPort
            RemotePort = $state.RemotePort
            Reverse    = $state.Reverse
            ProcessId  = $state.ProcessId
            User       = $state.User
        }
    }

    if ($live.Count -eq 0) {
        Write-Host 'No active ssh-forward tunnels found.'
        return 0
    }

    $closeAll = [bool]$All
    $chosenPaths = @()

    if ($closeAll) {
        $chosenPaths = $live | ForEach-Object { $_.Path }
    } elseif ((Test-InteractiveConsoleHost) -and (Get-Command fzf -ErrorAction SilentlyContinue)) {
        $lines = $live | ForEach-Object {
            $kind = if ($_.Reverse) { 'R' } else { 'L' }
            $userAt = if ($_.User) { "$($_.User)@" } else { '' }
            '{0,-3} {1,-20} {2}->{3}  PID {4}  ({5}{6})' -f $kind, $_.Host, $_.LocalPort, $_.RemotePort, $_.ProcessId, $userAt, $_.Host
        }
        $input = ($lines -join "`n") + "`n"
        $selections = @()
        try {
            $selections = @($input | fzf --multi --prompt 'tunnel > ' --height 40% --reverse --ansi --header 'TAB to mark, ENTER to close' --with-nth=1,2,3)
        } catch {
            Write-Error "ssh-forward-ls: fzf failed: $($_.Exception.Message)"
            return 1
        }

        foreach ($line in $selections) {
            if (-not $line) { continue }
            $kind = ($line -split '\s+')[0]
            $hostAlias = ($line -split '\s+')[1]
            foreach ($t in $live) {
                $k = if ($t.Reverse) { 'R' } else { 'L' }
                if ($k -eq $kind -and $t.Host -eq $hostAlias) {
                    $chosenPaths += $t.Path
                    break
                }
            }
        }
    } else {
        # Plain-text fallback.
        Write-Host 'Active Tunnels:'
        Write-Host '----------------------------------------'
        foreach ($t in $live) {
            $kind = if ($t.Reverse) { 'R' } else { 'L' }
            Write-Host ("{0,-4} Host: {1,-20} local:{2,-6} remote:{3,-6} PID:{4}" -f $kind, $t.Host, $t.LocalPort, $t.RemotePort, $t.ProcessId)
        }
        Write-Host '----------------------------------------'

        if (-not (Test-InteractiveConsoleHost)) { return 0 }

        $answer = Read-Host "Stop a tunnel? (Enter host name, 'all', or 'no')"
        if ([string]::IsNullOrWhiteSpace($answer) -or $answer -eq 'no') { return 0 }
        if ($answer -eq 'all') {
            $chosenPaths = $live | ForEach-Object { $_.Path }
        } else {
            foreach ($t in $live) {
                if ($t.Host -eq $answer) { $chosenPaths += $t.Path }
            }
            if (-not $chosenPaths) {
                Write-Host "No tunnel found for host '$answer'."
                return 0
            }
        }
    }

    $closed = 0
    foreach ($p in ($chosenPaths | Select-Object -Unique)) {
        $state = Read-SshForwardState -Path $p
        [void](Stop-SshForwardTunnel -StatePath $p)
        if ($state) { Write-Host "Closed tunnel for $($state.Host)." }
        $closed++
    }

    if ($closed -eq 0) {
        Write-Host 'No tunnels closed.'
    } elseif ($closeAll) {
        Write-Host "All tunnels closed ($closed)."
    }
    return 0
}