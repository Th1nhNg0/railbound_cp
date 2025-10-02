# PowerShell script to run MiniZinc on all test files with Chuffed solver
# Usage: .\run_all_tests.ps1 [-TestCount <number>]

param(
    [int]$TestCount
)

# Configuration
$modelFile = ".\railbound.mzn"
$testDir = ".\test"
$solvers = @("chuffed")
$outputDir = ".\results"
# OR-Tools CP-SAT optimized for speed with 4 threads and 60 second timeout
$parallelFlag = "--parallel"
$parallelThreads = "4"

# Create output directory if it doesn't exist
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# Get all .dzn files in the test directory
$testFiles = Get-ChildItem -Path $testDir -Filter "*.dzn" | Sort-Object Name

# List of test files to ignore 3-10
$ignoreTests = @("3-10C.dzn")

# Filter out ignored tests
$testFiles = $testFiles | Where-Object { $_.Name -notin $ignoreTests }

# If TestCount not provided, run all tests
if (-not $PSBoundParameters.ContainsKey('TestCount')) {
    $TestCount = $testFiles.Count
}

# Take only the first N tests
$testFiles = $testFiles | Select-Object -First $TestCount

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
    Write-Host "    Command: minizinc --solver $solver $parallelFlag $parallelThreads --statistics $modelFile $testPath" -ForegroundColor Gray
        
        # Run MiniZinc and capture output
        try {
            $output = & minizinc --solver $solver $parallelFlag $parallelThreads --statistics $modelFile $testPath 2>&1
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
            
            # Extract additional statistics (only include fields that exist in output)
            $failures = if ($outputText -match "%%%mzn-stat: failures=(\d+)") { $matches[1] } else { "" }
            $propagations = if ($outputText -match "%%%mzn-stat: propagations=(\d+)") { $matches[1] } else { "" }
            $objective = if ($outputText -match "%%%mzn-stat: objective=(\d+)") { $matches[1] } else { "" }
            $boolVariables = if ($outputText -match "%%%mzn-stat: boolVariables=(\d+)") { $matches[1] } else { "" }
            $nSolutions = if ($outputText -match "%%%mzn-stat: nSolutions=(\d+)") { $matches[1] } else { "" }
            $objectiveBound = if ($outputText -match "%%%mzn-stat: objectiveBound=(\d+)") { $matches[1] } else { "" }
            
            if ($isUnsatisfiable) {
                Write-Host "    Status: CAN'T SOLVE (UNSATISFIABLE)" -ForegroundColor Magenta
                Write-Host "    Duration: $($duration)s | Failures: $failures | BoolVars: $boolVariables | Propagations: $propagations" -ForegroundColor Gray
                $successCount++
                $status = "CAN'T SOLVE"
            } elseif ($exitCode -eq 0) {
                Write-Host "    Status: SUCCESS" -ForegroundColor Green
                Write-Host "    Duration: $($duration)s | Failures: $failures | BoolVars: $boolVariables | Propagations: $propagations | Objective: $objective" -ForegroundColor Gray
                $successCount++
                $status = "SUCCESS"
            } else {
                Write-Host "    Status: FAILED (exit code: $exitCode)" -ForegroundColor Red
                Write-Host "    Duration: $($duration)s | Failures: $failures | BoolVars: $boolVariables | Propagations: $propagations" -ForegroundColor Gray
                $failCount++
                $status = "FAILED"
            }
            
            $results += [PSCustomObject]@{
                Test = $testName
                Solver = $solver
                Status = $status
                Duration = $duration
                Failures = $failures
                BoolVars = $boolVariables
                Propagations = $propagations
                NSolutions = $nSolutions
                Objective = $objective
                ObjectiveBound = $objectiveBound
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
                Failures = ""
                BoolVars = ""
                Propagations = ""
                NSolutions = ""
                Objective = ""
                ObjectiveBound = ""
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
