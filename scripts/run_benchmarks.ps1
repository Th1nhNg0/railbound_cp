<#
.SYNOPSIS
Runs the Railbound MiniZinc benchmark natively on Windows.

.EXAMPLE
.\run_benchmarks.ps1

.EXAMPLE
.\run_benchmarks.ps1 -MiniZincArguments "--solver cp-sat --time-limit 300000 --statistics"
#>
[CmdletBinding()]
param(
    [string]$Levels = "all",
    [string]$OutputDirectory = "benchmark_results",
    [string]$ModelFile = "main.mzn",
    [string]$MiniZincArguments = "--solver chuffed --time-limit 300000 --statistics",
    [string]$MiniZincPath = ""
)

$ErrorActionPreference = "Stop"
$scriptDirectory = Split-Path -Parent $PSCommandPath
$projectRoot = Split-Path -Parent $scriptDirectory
Set-Location -LiteralPath $projectRoot

if ([string]::IsNullOrWhiteSpace($MiniZincPath)) {
    $MiniZincPath = (Get-Command minizinc -ErrorAction Stop).Source
}
if (-not (Test-Path -LiteralPath $MiniZincPath -PathType Leaf)) {
    throw "MiniZinc executable was not found: $MiniZincPath"
}

$modelPath = Join-Path $projectRoot $ModelFile
if (-not (Test-Path -LiteralPath $modelPath -PathType Leaf)) {
    throw "Model file was not found: $modelPath"
}

$dataPath = Join-Path $projectRoot "data"
if (-not (Test-Path -LiteralPath $dataPath -PathType Container)) {
    throw "Data directory was not found: $dataPath"
}

$levelDirectories = Get-ChildItem -LiteralPath $dataPath -Directory | Sort-Object { [int]$_.Name }
if ($Levels -ne "all") {
    $requestedLevels = $Levels -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    $levelDirectories = $levelDirectories | Where-Object { $_.Name -in $requestedLevels }
    if ($levelDirectories.Count -eq 0) {
        throw "None of the requested levels were found: $Levels"
    }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvPath = Join-Path $OutputDirectory "benchmark_$timestamp.csv"
$summaryPath = Join-Path $OutputDirectory "benchmark_$timestamp.summary.txt"

$header = "timestamp,level,puzzle,status,solveTime,failures,propagations,flatBoolVars,flatIntVars,flatBoolConstraints,flatIntConstraints,flatTime,boolVariables"
Set-Content -LiteralPath $csvPath -Value $header -Encoding utf8

function Get-Stat {
    param(
        [string]$Output,
        [string]$Name,
        [string]$Default = "N/A"
    )

    $match = [regex]::Match($Output, "%%%mzn-stat: $([regex]::Escape($Name))=([^`r`n]+)")
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return $Default
}

$miniZincArgs = $MiniZincArguments -split "\s+" | Where-Object { $_ }
$results = @()
$totalPuzzles = 0

Write-Host "Railbound Benchmark Suite" -ForegroundColor Cyan
Write-Host "Model      : $ModelFile"
Write-Host "Arguments  : $MiniZincArguments"
Write-Host "Levels     : $($levelDirectories.Name -join ', ')"
Write-Host "Output CSV : $csvPath"

foreach ($levelDirectory in $levelDirectories) {
    $puzzles = Get-ChildItem -LiteralPath $levelDirectory.FullName -Filter "*.dzn" -File | Sort-Object Name
    Write-Host "`n[Level $($levelDirectory.Name)] Found $($puzzles.Count) puzzles" -ForegroundColor Yellow

    foreach ($puzzle in $puzzles) {
        $totalPuzzles++
        Write-Host "[$totalPuzzles] $($levelDirectory.Name)/$($puzzle.BaseName) ... " -NoNewline
        $startedAt = Get-Date
        $output = (& $MiniZincPath @miniZincArgs $modelPath $puzzle.FullName 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
        $elapsed = ((Get-Date) - $startedAt).TotalSeconds

        if ($output -match "=====UNSATISFIABLE=====") {
            $status = "UNSAT"
            $colour = "Magenta"
        } elseif ($output -match "=====UNKNOWN=====|Time limit exceeded|time limit") {
            $status = "TIMEOUT"
            $colour = "Yellow"
        } elseif ($exitCode -eq 0 -and $output -match "==========") {
            $status = "SUCCESS"
            $colour = "Green"
        } else {
            $status = "ERROR"
            $colour = "Red"
        }

        $result = [pscustomobject]@{
            timestamp           = Get-Date -Format "s"
            level               = $levelDirectory.Name
            puzzle              = $puzzle.BaseName
            status              = $status
            solveTime           = Get-Stat $output "solveTime"
            failures            = Get-Stat $output "failures" "0"
            propagations        = Get-Stat $output "propagations" "0"
            flatBoolVars        = Get-Stat $output "flatBoolVars" "0"
            flatIntVars         = Get-Stat $output "flatIntVars" "0"
            flatBoolConstraints = Get-Stat $output "flatBoolConstraints" "0"
            flatIntConstraints  = Get-Stat $output "flatIntConstraints" "0"
            flatTime            = Get-Stat $output "flatTime"
            boolVariables       = Get-Stat $output "boolVariables" "0"
        }
        $results += $result
        $result | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Add-Content -LiteralPath $csvPath -Encoding utf8
        Write-Host "$status ($($result.solveTime)s, $([math]::Round($elapsed, 2))s wall)" -ForegroundColor $colour
    }
}

$successful = @($results | Where-Object status -eq "SUCCESS")
$solveSeconds = @($successful | ForEach-Object {
    $value = 0.0
    if ([double]::TryParse($_.solveTime, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$value)) { $value }
})
$failureCount = @($successful | ForEach-Object { [int]$_.failures })

$summary = @"
Railbound Benchmark Summary
===========================
Timestamp       : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Arguments       : $MiniZincArguments
Model           : $ModelFile
Total puzzles   : $($results.Count)
Success         : $($successful.Count)
UNSAT           : $(@($results | Where-Object status -eq "UNSAT").Count)
Timeout         : $(@($results | Where-Object status -eq "TIMEOUT").Count)
Error           : $(@($results | Where-Object status -eq "ERROR").Count)
Total solve time: $([math]::Round(($solveSeconds | Measure-Object -Sum).Sum, 3)) seconds
Average solve   : $(if ($solveSeconds.Count) { [math]::Round(($solveSeconds | Measure-Object -Average).Average, 3) } else { "N/A" }) seconds
CSV             : $csvPath
"@
Set-Content -LiteralPath $summaryPath -Value $summary -Encoding utf8
Write-Host "`n$summary" -ForegroundColor Cyan
