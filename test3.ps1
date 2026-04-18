function Get-EditDistance {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Left,
        [Parameter(Mandatory = $true)]
        [string]$Right
    )

    $rows = $Left.Length + 1
    $cols = $Right.Length + 1
    $dist = New-Object 'int[,]' $rows, $cols

    for ($i = 0; $i -lt $rows; $i++) {
        $dist[$i, 0] = $i
    }
    for ($j = 0; $j -lt $cols; $j++) {
        $dist[0, $j] = $j
    }

    for ($i = 1; $i -lt $rows; $i++) {
        for ($j = 1; $j -lt $cols; $j++) {
            $cost = if ($Left[$i - 1] -ceq $Right[$j - 1]) { 0 } else { 1 }
            $prevRow = $i - 1
            $prevCol = $j - 1
            $deletion = $dist[$prevRow, $j] + 1
            $insertion = $dist[$i, $prevCol] + 1
            $substitution = $dist[$prevRow, $prevCol] + $cost
            $dist[$i, $j] = [Math]::Min([Math]::Min($deletion, $insertion), $substitution)
        }
    }

    $lastRow = $rows - 1
    $lastCol = $cols - 1
    return $dist[$lastRow, $lastCol]
}

function Get-ClosestSuggestion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputText,
        [Parameter(Mandatory = $true)]
        [string[]]$Candidates
    )

    $bestCandidate = $null
    $bestDistance = [int]::MaxValue

    foreach ($candidate in $Candidates) {
        $distance = Get-EditDistance -Left $InputText -Right $candidate
        if ($distance -lt $bestDistance) {
            $bestDistance = $distance
            $bestCandidate = $candidate
        }
    }

    $threshold = if ($InputText.Length -le 4) { 2 } else { 3 }
    if ($bestDistance -le $threshold) {
        return $bestCandidate
    }

    return $null
}

Get-ClosestSuggestion -InputText "a" -Candidates @("a")
