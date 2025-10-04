#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Runs MiniZinc benchmarks for Railbound puzzles across all levels.

.DESCRIPTION
    This script runs the Railbound solver on all puzzle files and collects
    detailed statistics including solve time, nodes explored, failures, etc.

.PARAMETER Solver
    MiniZinc solver to use (default: chuffed)

.PARAMETER TimeLimit
    MiniZinc time limit in milliseconds (default: 60000)

.PARAMETER Levels
    Comma-separated list of levels to run (default: all)

.PARAMETER OutputDir
    Directory to save benchmark results (default: benchmark_results)

.EXAMPLE
    .\run_benchmarks.ps1
    .\run_benchmarks.ps1 -Solver gecode -TimeLimit 30000
    .\run_benchmarks.ps1 -Levels "1,2,3"
#>

param(
    [string]$Solver = "cp-sat",
    [int]$TimeLimit = 300000,
    [string]$Levels = "",
    [string]$OutputDir = "benchmark_results",
    [string]$ModelFile = "main.mzn",
    [int]$Parallel = 8
)

# Ensure output directory exists
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvFile = Join-Path $OutputDir "benchmark_${Solver}_${timestamp}.csv"
$summaryFile = Join-Path $OutputDir "summary_${Solver}_${timestamp}.txt"

# Get all data directories
$dataDir = "data"
if (-not (Test-Path $dataDir)) {
    Write-Error "Data directory not found: $dataDir"
    exit 1
}

$levelDirs = Get-ChildItem $dataDir -Directory | Sort-Object { [int]$_.Name }

# Filter levels if specified
if ($Levels) {
    $levelList = $Levels -split ',' | ForEach-Object { $_.Trim() }
    $levelDirs = $levelDirs | Where-Object { $levelList -contains $_.Name }
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Railbound Benchmark Suite" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Model      : $ModelFile"
Write-Host "Solver     : $Solver"
Write-Host "Time Limit : $TimeLimit ms"
Write-Host "Levels     : $($levelDirs.Name -join ', ')"
Write-Host "Output CSV : $csvFile"
Write-Host "Summary    : $summaryFile"
    Write-Host "Command    : minizinc --solver $Solver --time-limit $TimeLimit --statistics <Model> <Data>" -ForegroundColor DarkCyan
Write-Host "============================================================`n" -ForegroundColor Cyan

$csvHeader = "timestamp,level,puzzle,status,duration_ms,solver,time_ms,failures,nodes,propagations,restarts,variables,intVars,boolVars,propagators,peakDepth,nSolutions,objective,objectiveBound,paths,flatBoolVars,flatIntVars,flatBoolConstraints,flatIntConstraints,evaluatedReifiedConstraints,evaluatedHalfReifiedConstraints,eliminatedImplications,method,flatTime"
$csvHeader | Out-File -FilePath $csvFile -Encoding UTF8

# Track overall statistics
$totalPuzzles = 0
$successCount = 0
$unsatCount = 0
$timeoutCount = 0
$errorCount = 0
$totalTime = 0
$totalNodes = 0
$totalFailures = 0

# Process each level
foreach ($levelDir in $levelDirs) {
    $level = $levelDir.Name
    $puzzleFiles = Get-ChildItem (Join-Path $dataDir $level) -Filter "*.dzn" | Sort-Object Name
    
    Write-Host "`n[Level $level] Found $($puzzleFiles.Count) puzzles" -ForegroundColor Yellow
    Write-Host ("=" * 80)
    
    $levelSuccess = 0
    $levelTimeout = 0
    $levelError = 0
    
    foreach ($puzzleFile in $puzzleFiles) {
        $puzzleName = [System.IO.Path]::GetFileNameWithoutExtension($puzzleFile.Name)
        $totalPuzzles++
        
        Write-Host "[${totalPuzzles}] $level/$puzzleName ... " -NoNewline
        
        # Run MiniZinc
        $startTime = Get-Date
        try {
            if ($Solver -eq "cp-sat") {
                # OR-Tools CP-SAT specific parameters for parallel search
                $output = & minizinc --solver $Solver --time-limit $TimeLimit --statistics -p $Parallel $ModelFile $puzzleFile.FullName 2>&1 | Out-String
            } else {
                $output = & minizinc --solver $Solver --time-limit $TimeLimit --statistics $ModelFile $puzzleFile.FullName 2>&1 | Out-String
            }
            $exitCode = $LASTEXITCODE
        } catch {
            $output = $_.Exception.Message
            $exitCode = -1
        }
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalMilliseconds
        
        # Determine status
        $status = "UNKNOWN"
        if ($output -match "=====UNSATISFIABLE=====") {
            $status = "UNSAT"
            $unsatCount++
            Write-Host "UNSAT" -ForegroundColor Magenta -NoNewline
        } elseif ($output -match "Time limit exceeded|time limit") {
            $status = "TIMEOUT"
            $timeoutCount++
            Write-Host "TIMEOUT" -ForegroundColor Yellow -NoNewline
        } elseif ($exitCode -eq 0 -and $output -match "=====") {
            $status = "SUCCESS"
            $successCount++
            $levelSuccess++
            Write-Host "SUCCESS" -ForegroundColor Green -NoNewline
        } else {
            $status = "ERROR"
            $errorCount++
            $levelError++
            Write-Host "ERROR" -ForegroundColor Red -NoNewline
        }
        # Extract statistics using regex
        function Extract-Stat {
            param($pattern, $default = "N/A")
            if ($output -match $pattern) {
                return $matches[1]
            }
            return $default
        }
        
        $time = Extract-Stat "%%%mzn-stat: time=([0-9.]+)" "N/A"
        $failures = Extract-Stat "%%%mzn-stat: failures=([0-9]+)" "0"
        $nodes = Extract-Stat "%%%mzn-stat: nodes=([0-9]+)" "0"
        $propagations = Extract-Stat "%%%mzn-stat: propagations=([0-9]+)" "0"
        $restarts = Extract-Stat "%%%mzn-stat: restarts=([0-9]+)" "0"
        $variables = Extract-Stat "%%%mzn-stat: variables=([0-9]+)" "0"
        $intVars = Extract-Stat "%%%mzn-stat: intVars=([0-9]+)" "0"
        $boolVars = Extract-Stat "%%%mzn-stat: boolVariables=([0-9]+)" "0"
        $propagators = Extract-Stat "%%%mzn-stat: propagators=([0-9]+)" "0"
        $peakDepth = Extract-Stat "%%%mzn-stat: peakDepth=([0-9]+)" "0"
        $nSolutions = Extract-Stat "%%%mzn-stat: nSolutions=([0-9]+)" "0"
        $objective = Extract-Stat "%%%mzn-stat: objective=([0-9.-]+)" "N/A"
        $objectiveBound = Extract-Stat "%%%mzn-stat: objectiveBound=([0-9.-]+)" "N/A"
        $paths = Extract-Stat "%%%mzn-stat: paths=([0-9]+)" "0"
        $flatBoolVars = Extract-Stat "%%%mzn-stat: flatBoolVars=([0-9]+)" "0"
        $flatIntVars = Extract-Stat "%%%mzn-stat: flatIntVars=([0-9]+)" "0"
        $flatBoolConstraints = Extract-Stat "%%%mzn-stat: flatBoolConstraints=([0-9]+)" "0"
        $flatIntConstraints = Extract-Stat "%%%mzn-stat: flatIntConstraints=([0-9]+)" "0"
        $evaluatedReifiedConstraints = Extract-Stat "%%%mzn-stat: evaluatedReifiedConstraints=([0-9]+)" "0"
        $evaluatedHalfReifiedConstraints = Extract-Stat "%%%mzn-stat: evaluatedHalfReifiedConstraints=([0-9]+)" "0"
        $eliminatedImplications = Extract-Stat "%%%mzn-stat: eliminatedImplications=([0-9]+)" "0"
        $method = Extract-Stat '%%%mzn-stat: method="([^"]+)"' "N/A"
        $flatTime = Extract-Stat "%%%mzn-stat: flatTime=([0-9.]+)" "N/A"
        
        # Update totals
        if ($time -ne "N/A") {
            $totalTime += [double]$time
        }
        if ($nodes -ne "N/A" -and $nodes -ne "0") {
            $totalNodes += [long]$nodes
        }
        if ($failures -ne "N/A" -and $failures -ne "0") {
            $totalFailures += [long]$failures
        }
        
        # Write to CSV (exclude exitCode and command)
        $rowTs = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
        $csvValues = @(
            $rowTs,
            $level,
            $puzzleName,
            $status,
            [math]::Round($duration,0),
            $Solver,
            $time,
            $failures,
            $nodes,
            $propagations,
            $restarts,
            $variables,
            $intVars,
            $boolVars,
            $propagators,
            $peakDepth,
            $nSolutions,
            $objective,
            $objectiveBound,
            $paths,
            $flatBoolVars,
            $flatIntVars,
            $flatBoolConstraints,
            $flatIntConstraints,
            $evaluatedReifiedConstraints,
            $evaluatedHalfReifiedConstraints,
            $eliminatedImplications,
            $method,
            $flatTime
        )
        $csvLine = $csvValues -join ','
        $csvLine | Out-File -FilePath $csvFile -Append -Encoding UTF8
        
        # Display key stats
        Write-Host " (${time}s, ${nodes} nodes, ${failures} fails)" -ForegroundColor Gray
    }
    
    Write-Host "`nLevel ${level}: $levelSuccess/$($puzzleFiles.Count) solved" -ForegroundColor Cyan
}

# Generate summary
$summaryText = @"
============================================================
Railbound Benchmark Summary
============================================================
Timestamp  : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Solver     : $Solver
Time Limit : $TimeLimit ms
Model      : $ModelFile

RESULTS
------------------------------------------------------------
Total Puzzles  : $totalPuzzles
Success        : $successCount ($([math]::Round(100.0 * $successCount / $totalPuzzles, 1))%)
UNSAT          : $unsatCount
Timeout        : $timeoutCount
Error          : $errorCount

STATISTICS
------------------------------------------------------------
Total Time     : $([math]::Round($totalTime, 2)) seconds
Avg Time       : $(if ($successCount -gt 0) { [math]::Round($totalTime / $successCount, 3) } else { "N/A" }) seconds (successful puzzles)
Total Nodes    : $totalNodes
Avg Nodes      : $(if ($successCount -gt 0) { [math]::Round($totalNodes / $successCount, 0) } else { "N/A" }) (successful puzzles)
Total Failures : $totalFailures
Avg Failures   : $(if ($successCount -gt 0) { [math]::Round($totalFailures / $successCount, 0) } else { "N/A" }) (successful puzzles)

DETAILS
------------------------------------------------------------
Results saved to: $csvFile
Logs saved to   : $(Join-Path $OutputDir "logs")
============================================================
"@

$summaryText | Out-File -FilePath $summaryFile -Encoding UTF8

Write-Host "`n$summaryText" -ForegroundColor Cyan

Write-Host "`nBenchmark complete! Results saved to:" -ForegroundColor Green
Write-Host "  CSV:     $csvFile" -ForegroundColor White
Write-Host "  Summary: $summaryFile" -ForegroundColor White
