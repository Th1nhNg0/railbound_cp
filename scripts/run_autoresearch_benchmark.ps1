[CmdletBinding()]
param(
    [ValidateRange(1, 20)]
    [int]$Repeats = 3,
    [ValidateRange(1, 64)]
    [int]$Threads = 8,
    [ValidateRange(1000, 3600000)]
    [int]$TimeLimitMilliseconds = 300000,
    [string]$MiniZincPath = ""
)

$ErrorActionPreference = "Stop"
$scriptDirectory = Split-Path -Parent $PSCommandPath
$projectRoot = Split-Path -Parent $scriptDirectory
$modelPath = Join-Path $projectRoot "main.mzn"
$referencePath = Join-Path $projectRoot "docs/benchmark_results/cp-sat.csv"

if ([string]::IsNullOrWhiteSpace($MiniZincPath)) {
    $MiniZincPath = (Get-Command minizinc -ErrorAction Stop).Source
}

$puzzles = @(
    @{ Name = "1-10";  Path = "data/1/1-10.dzn" },
    @{ Name = "2-5";   Path = "data/2/2-5.dzn" },
    @{ Name = "3-7";   Path = "data/3/3-7.dzn" },
    @{ Name = "3-11";  Path = "data/3/3-11.dzn" },
    @{ Name = "4-8";   Path = "data/4/4-8.dzn" },
    @{ Name = "5-3B";  Path = "data/5/5-3B.dzn" },
    @{ Name = "6-6A";  Path = "data/6/6-6A.dzn" },
    @{ Name = "7-4";   Path = "data/7/7-4.dzn" },
    @{ Name = "8-2";   Path = "data/8/8-2.dzn" },
    @{ Name = "8-2A";  Path = "data/8/8-2A.dzn" }
)

$referenceRows = Import-Csv -LiteralPath $referencePath
$referenceTimes = @{}
foreach ($puzzle in $puzzles) {
    $row = $referenceRows | Where-Object puzzle -eq $puzzle.Name | Select-Object -First 1
    if ($null -eq $row -or $row.status -ne "SUCCESS") {
        throw "Missing successful reference result for $($puzzle.Name)"
    }
    $referenceTimes[$puzzle.Name] = [double]::Parse(
        $row.solveTime,
        [Globalization.CultureInfo]::InvariantCulture
    )
}

function Get-Median {
    param([double[]]$Values)
    $sorted = @($Values | Sort-Object)
    $middle = [int][math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) {
        return $sorted[$middle]
    }
    return ($sorted[$middle - 1] + $sorted[$middle]) / 2.0
}

$measurements = @{}
foreach ($puzzle in $puzzles) {
    $measurements[$puzzle.Name] = [Collections.Generic.List[double]]::new()
}

for ($repeat = 1; $repeat -le $Repeats; $repeat++) {
    Write-Host "Repeat $repeat/$Repeats"
    foreach ($puzzle in $puzzles) {
        $dataPath = Join-Path $projectRoot $puzzle.Path
        $arguments = @(
            "--solver", "cp-sat",
            "--time-limit", $TimeLimitMilliseconds,
            "--statistics",
            "-p", $Threads,
            $modelPath,
            $dataPath
        )
        $output = (& $MiniZincPath @arguments 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0 -or $output -notmatch "==========") {
            throw "Puzzle $($puzzle.Name) failed on repeat $repeat`n$output"
        }
        $match = [regex]::Match($output, "%%%mzn-stat: solveTime=([^`r`n]+)")
        if (-not $match.Success) {
            throw "Puzzle $($puzzle.Name) did not report solveTime"
        }
        $solveTime = [double]::Parse(
            $match.Groups[1].Value.Trim(),
            [Globalization.CultureInfo]::InvariantCulture
        )
        $measurements[$puzzle.Name].Add($solveTime)
        Write-Host ("  {0,-6} {1,10:N4}s" -f $puzzle.Name, $solveTime)
    }
}

$logSpeedupSum = 0.0
$rows = foreach ($puzzle in $puzzles) {
    $median = Get-Median -Values $measurements[$puzzle.Name].ToArray()
    $reference = $referenceTimes[$puzzle.Name]
    $speedup = $reference / $median
    $logSpeedupSum += [math]::Log($speedup)
    [pscustomobject]@{
        Puzzle   = $puzzle.Name
        Reference = $reference
        Median   = $median
        Speedup  = $speedup
    }
}

$score = [math]::Exp($logSpeedupSum / $puzzles.Count)
$rows | Format-Table -AutoSize
Write-Output ("AUTORESEARCH_SCORE={0:R}" -f $score)
