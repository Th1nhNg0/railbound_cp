<#
.SYNOPSIS
Runs full native-Windows benchmarks for CP-SAT and Chuffed.

.EXAMPLE
.\scripts\run_full_benchmark.ps1
#>
[CmdletBinding()]
param(
    [int]$TimeLimitMilliseconds = 300000,
    [int]$CpSatThreads = 8,
    [string]$OutputDirectory = "benchmark_results"
)

$ErrorActionPreference = "Stop"
$scriptDirectory = Split-Path -Parent $PSCommandPath

Write-Host "=== MiniZinc version ===" -ForegroundColor Cyan
& (Get-Command minizinc -ErrorAction Stop).Source --version

Write-Host "`n=== Starting CP-SAT benchmark ($CpSatThreads threads) ===" -ForegroundColor Cyan
& (Join-Path $scriptDirectory "run_benchmarks.ps1") `
    -OutputDirectory $OutputDirectory `
    -MiniZincArguments "--solver cp-sat --time-limit $TimeLimitMilliseconds --statistics -p $CpSatThreads"

Write-Host "`n=== Starting Chuffed benchmark ===" -ForegroundColor Cyan
& (Join-Path $scriptDirectory "run_benchmarks.ps1") `
    -OutputDirectory $OutputDirectory `
    -MiniZincArguments "--solver chuffed --time-limit $TimeLimitMilliseconds --statistics"

Write-Host "`n=== All benchmarks complete ===" -ForegroundColor Green
