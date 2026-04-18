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
            $deletion = $dist[$i - 1, $j] + 1
            $insertion = $dist[$i, $j - 1] + 1
            $substitution = $dist[$i - 1, $j - 1] + $cost
            $dist[$i, $j] = [Math]::Min([Math]::Min($deletion, $insertion), $substitution)
        }
    }

    return $dist[$rows - 1, $cols - 1]
}

Get-EditDistance -Left "test" -Right "tset"
