# PowerShell script to run MiniZinc on all test files with Chuffed solver
# Usage: .\run_all_tests.ps1

# Configuration
$modelFile = ".\railbound.mzn"
$testDir = ".\test"
$solvers = @("chuffed", "gecode")
$outputDir = ".\results"

# Create output directory if it doesn't exist
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# Get all .dzn files in the test directory
$testFiles = Get-ChildItem -Path $testDir -Filter "*.dzn" | Sort-Object Name

if ($testFiles.Count -eq 0) {
    Write-Host "No test files found in $testDir" -ForegroundColor Red
    exit 1
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Running MiniZinc tests with multiple solvers" -ForegroundColor Cyan
Write-Host "Model: $modelFile" -ForegroundColor Cyan
Write-Host "Solvers: $($solvers -join ', ')" -ForegroundColor Cyan
Write-Host "Test files found: $($testFiles.Count)" -ForegroundColor Cyan
Write-Host "============================================================`n" -ForegroundColor Cyan

$successCount = 0
$failCount = 0
$results = @()

foreach ($testFile in $testFiles) {
    $testName = $testFile.Name
    $testPath = $testFile.FullName
    
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "TEST: $testName" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    
    foreach ($solver in $solvers) {
        $outputFile = Join-Path $outputDir "$($testFile.BaseName)_$($solver)_output.txt"
        
        Write-Host "  Solver: $solver" -ForegroundColor Yellow
        Write-Host "    Command: minizinc --solver $solver --statistics $modelFile $testPath" -ForegroundColor Gray
        
        # Run MiniZinc and capture output
        try {
            $output = & minizinc --solver $solver --statistics $modelFile $testPath 2>&1
            $exitCode = $LASTEXITCODE
            
            # Save output to file
            $output | Out-File -FilePath $outputFile -Encoding utf8
            
            # Check if output contains UNSATISFIABLE
            $outputText = $output | Out-String
            $isUnsatisfiable = $outputText -match "=====UNSATISFIABLE====="
            
            # Extract solving time from statistics (already in seconds)
            $duration = 0
            if ($outputText -match "%%%mzn-stat: solveTime=(\d+\.?\d*)") {
                $duration = [math]::Round([double]$matches[1], 3)
            } elseif ($outputText -match "%%%mzn-stat: time=(\d+\.?\d*)") {
                $duration = [math]::Round([double]$matches[1], 3)
            }
            
            # Extract additional statistics
            $nodes = if ($outputText -match "%%%mzn-stat: nodes=(\d+)") { $matches[1] } else { "N/A" }
            $failures = if ($outputText -match "%%%mzn-stat: failures=(\d+)") { $matches[1] } else { "N/A" }
            $propagations = if ($outputText -match "%%%mzn-stat: propagations=(\d+)") { $matches[1] } else { "N/A" }
            $peakDepth = if ($outputText -match "%%%mzn-stat: peakDepth=(\d+)") { $matches[1] } else { "N/A" }
            $restarts = if ($outputText -match "%%%mzn-stat: restarts=(\d+)") { $matches[1] } else { "N/A" }
            $objective = if ($outputText -match "%%%mzn-stat: objective=(\d+)") { $matches[1] } else { "N/A" }
            $variables = if ($outputText -match "%%%mzn-stat: variables=(\d+)") { $matches[1] } else { "N/A" }
            $intVars = if ($outputText -match "%%%mzn-stat: intVars=(\d+)") { $matches[1] } else { "N/A" }
            $boolVariables = if ($outputText -match "%%%mzn-stat: boolVariables=(\d+)") { $matches[1] } else { "N/A" }
            
            if ($isUnsatisfiable) {
                Write-Host "    Status: CAN'T SOLVE (UNSATISFIABLE)" -ForegroundColor Magenta
                Write-Host "    Duration: $($duration)s | Nodes: $nodes | Failures: $failures | Vars: $variables" -ForegroundColor Gray
                $successCount++
                $status = "CAN'T SOLVE"
            } elseif ($exitCode -eq 0) {
                Write-Host "    Status: SUCCESS" -ForegroundColor Green
                Write-Host "    Duration: $($duration)s | Nodes: $nodes | Failures: $failures | Vars: $variables | Objective: $objective" -ForegroundColor Gray
                $successCount++
                $status = "SUCCESS"
            } else {
                Write-Host "    Status: FAILED (exit code: $exitCode)" -ForegroundColor Red
                Write-Host "    Duration: $($duration)s | Nodes: $nodes | Failures: $failures | Vars: $variables" -ForegroundColor Gray
                $failCount++
                $status = "FAILED"
            }
            
            $results += [PSCustomObject]@{
                Test = $testName
                Solver = $solver
                Status = $status
                Duration = $duration
                Nodes = $nodes
                Failures = $failures
                Variables = $variables
                IntVars = $intVars
                BoolVars = $boolVariables
                Propagations = $propagations
                PeakDepth = $peakDepth
                Restarts = $restarts
                Objective = $objective
                ExitCode = $exitCode
            }
        }
        catch {
            Write-Host "    Status: ERROR - $($_.Exception.Message)" -ForegroundColor Red
            $failCount++
            $results += [PSCustomObject]@{
                Test = $testName
                Solver = $solver
                Status = "ERROR"
                Duration = 0
                Nodes = "N/A"
                Failures = "N/A"
                Variables = "N/A"
                IntVars = "N/A"
                BoolVars = "N/A"
                Propagations = "N/A"
                PeakDepth = "N/A"
                Restarts = "N/A"
                Objective = "N/A"
                ExitCode = -1
            }
        }
        
        Write-Host ""
    }
}

# Summary
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "OVERALL TEST SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Total tests: $($testFiles.Count * $solvers.Count)" -ForegroundColor White
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red
Write-Host "Output saved to: $outputDir" -ForegroundColor White
Write-Host ""

# Display results table
$results | Format-Table -AutoSize

# Save results to CSV
$resultsFile = Join-Path $outputDir "test_results.csv"
$results | Export-Csv -Path $resultsFile -NoTypeInformation
Write-Host "Results saved to: $resultsFile" -ForegroundColor White
