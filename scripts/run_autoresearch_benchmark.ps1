[CmdletBinding()]
param(
    [ValidateRange(1, 20)]
    [int]$Repeats = 3,
    [ValidateRange(1000, 3600000)]
    [int]$TimeLimitMilliseconds = 30000,
    [string]$MiniZincPath = ""
)

$ErrorActionPreference = "Stop"
$scriptDirectory = Split-Path -Parent $PSCommandPath
$projectRoot = Split-Path -Parent $scriptDirectory

if ([string]::IsNullOrWhiteSpace($MiniZincPath)) {
    $MiniZincPath = (Get-Command minizinc -ErrorAction Stop).Source
}

$puzzles = @(
    @{ Name = "1-10"; Path = "data/1/1-10.dzn"; Model = "basic.mzn" },
    @{ Name = "2-1";  Path = "data/2/2-1.dzn"; Model = "basic.mzn" },
    @{ Name = "3-2";  Path = "data/3/3-2.dzn"; Model = "activations.mzn" },
    @{ Name = "3-8A"; Path = "data/3/3-8A.dzn"; Model = "activations.mzn" },
    @{ Name = "4-1";  Path = "data/4/4-1.dzn"; Model = "activations.mzn" },
    @{ Name = "5-2";  Path = "data/5/5-2.dzn"; Model = "stations.mzn" },
    @{ Name = "6-1";  Path = "data/6/6-1.dzn"; Model = "eswitches.mzn" },
    @{ Name = "7-1";  Path = "data/7/7-1.dzn"; Model = "decoys.mzn" },
    @{ Name = "8-2";  Path = "data/8/8-2.dzn"; Model = "basic.mzn" },
    @{ Name = "9-1";  Path = "data/9/9-1.dzn"; Model = "semaphores.mzn" }
)

$metricNames = @(
    "solveTime", "flatTime", "failures", "propagations",
    "flatBoolVars", "flatIntVars", "flatBoolConstraints",
    "flatIntConstraints", "boolVariables"
)

function Get-Metric {
    param([string]$Output, [string]$Name)

    $match = [regex]::Match($Output, "%%%mzn-stat: $([regex]::Escape($Name))=([^`r`n]+)")
    if (-not $match.Success) {
        throw "Missing metric '$Name'"
    }
    return [double]::Parse(
        $match.Groups[1].Value.Trim(),
        [Globalization.CultureInfo]::InvariantCulture
    )
}

$rows = @()
for ($repeat = 1; $repeat -le $Repeats; $repeat++) {
    foreach ($puzzle in $puzzles) {
        $dataPath = Join-Path $projectRoot $puzzle.Path
        $modelPath = Join-Path (Join-Path $projectRoot "benchmark_models") $puzzle.Model
        $arguments = @(
            "--solver", "chuffed",
            "-O0",
            "-t", $TimeLimitMilliseconds,
            "--statistics",
            $modelPath,
            $dataPath
        )
        $savedErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $output = (& $MiniZincPath @arguments 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $savedErrorActionPreference
        if ($exitCode -ne 0 -or $output -notmatch "%%%mzn-stat: nSolutions=1") {
            throw "Puzzle $($puzzle.Name) failed on repeat $repeat`n$output"
        }

        $row = [ordered]@{ Repeat = $repeat; Puzzle = $puzzle.Name }
        foreach ($metricName in $metricNames) {
            $row[$metricName] = Get-Metric -Output $output -Name $metricName
        }
        $rows += [pscustomobject]$row
    }
}

$summary = foreach ($group in ($rows | Group-Object Puzzle)) {
    $row = [ordered]@{ Puzzle = $group.Name }
    foreach ($metricName in $metricNames) {
        $row[$metricName] = ($group.Group | Measure-Object -Property $metricName -Average).Average
    }
    $row["combinedTime"] = $row.solveTime + $row.flatTime
    [pscustomobject]$row
}

$summary | Sort-Object combinedTime -Descending | Format-Table -AutoSize
$totalMeanSolveTime = ($summary | Measure-Object solveTime -Sum).Sum
$totalMeanFlatTime = ($summary | Measure-Object flatTime -Sum).Sum
$combinedTime = $totalMeanSolveTime + $totalMeanFlatTime

Write-Output ("TOTAL_MEAN_SOLVE_TIME={0:R}" -f $totalMeanSolveTime)
Write-Output ("TOTAL_MEAN_FLAT_TIME={0:R}" -f $totalMeanFlatTime)
Write-Output ("AUTORESEARCH_COMBINED_TIME={0:R}" -f $combinedTime)
