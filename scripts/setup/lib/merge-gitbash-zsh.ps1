param(
    [Parameter(Mandatory = $true)]
    [string]$StagingRoot,
    [Parameter(Mandatory = $true)]
    [string]$GitRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-NotReparsePoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing reparse point during Git Bash zsh merge: '$Path'."
    }
}

function Copy-PlainDirectoryContents {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDir,
        [Parameter(Mandatory = $true)]
        [string]$TargetDir
    )

    Assert-NotReparsePoint -Path $SourceDir
    if (Test-Path -LiteralPath $TargetDir) {
        if (-not (Test-Path -LiteralPath $TargetDir -PathType Container)) {
            throw "Target path is not a directory: '$TargetDir'."
        }
        Assert-NotReparsePoint -Path $TargetDir
    } else {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }

    foreach ($entry in (Get-ChildItem -LiteralPath $SourceDir -Force)) {
        if ($null -eq $entry) { continue }
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing reparse point during Git Bash zsh merge: '$($entry.FullName)'."
        }

        $destination = Join-Path $TargetDir $entry.Name
        if ($entry.PSIsContainer) {
            Copy-PlainDirectoryContents -SourceDir $entry.FullName -TargetDir $destination
        } else {
            if (Test-Path -LiteralPath $destination) {
                if (Test-Path -LiteralPath $destination -PathType Container) {
                    throw "Cannot overwrite directory with file: '$destination'."
                }
                Assert-NotReparsePoint -Path $destination
            }
            Copy-Item -LiteralPath $entry.FullName -Destination $destination -Force
        }
    }
}

if (-not (Test-Path -LiteralPath $StagingRoot -PathType Container)) {
    throw "Staging directory does not exist: '$StagingRoot'."
}
if (-not (Test-Path -LiteralPath $GitRoot -PathType Container)) {
    throw "Git for Windows directory does not exist: '$GitRoot'."
}

Assert-NotReparsePoint -Path $StagingRoot
Assert-NotReparsePoint -Path $GitRoot

$mergeTopDirs = @("usr", "etc")

# Validate the entire staged tree upfront before modifying GitRoot.
foreach ($top in $mergeTopDirs) {
    $sourceTop = Join-Path $StagingRoot $top
    if (-not (Test-Path -LiteralPath $sourceTop)) { continue }
    if (-not (Test-Path -LiteralPath $sourceTop -PathType Container)) {
        throw "Staged entry is not a directory: '$sourceTop'."
    }
    Assert-NotReparsePoint -Path $sourceTop

    foreach ($child in (Get-ChildItem -LiteralPath $sourceTop -Recurse -Force)) {
        if ($null -eq $child) { continue }
        if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing reparse point during Git Bash zsh merge: '$($child.FullName)'."
        }
    }

    $targetTop = Join-Path $GitRoot $top
    if (Test-Path -LiteralPath $targetTop) {
        if (-not (Test-Path -LiteralPath $targetTop -PathType Container)) {
            throw "Target entry is not a directory: '$targetTop'."
        }
        Assert-NotReparsePoint -Path $targetTop
    }
}

foreach ($top in $mergeTopDirs) {
    $sourceTop = Join-Path $StagingRoot $top
    if (-not (Test-Path -LiteralPath $sourceTop)) { continue }
    $targetTop = Join-Path $GitRoot $top
    Copy-PlainDirectoryContents -SourceDir $sourceTop -TargetDir $targetTop
}
