# PowerShell script to run MiniZinc on all test files with Chuffed solver
# Usage: .\run_all_tests.ps1 [-TestCount <number>]

param(
    [int]$TestCount
)

# Configuration
$modelFile = ".\railbound.mzn"
$testDir = ".\test"
$solvers = @("cp-sat", "chuffed")
$outputDir = ".\results"
# OR-Tools CP-SAT optimized for speed with 4 threads and 15 second timeout
$parallelFlag = "--parallel"
$parallelThreads = "8"
$timeLimitMs = 600000  # Time limit in milliseconds

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
        
        # Build command with -f only for chuffed
        $command = "minizinc --solver $solver"
        if ($solver -eq "chuffed") {
            $command += " -f"
        }
        $command += " $parallelFlag $parallelThreads --statistics --time-limit $($timeLimitMs) $modelFile $testPath"
        
        Write-Host "    Command: $command" -ForegroundColor Gray
        
        # Run MiniZinc and capture output
        try {
            $measured = Measure-Command {
                $output = Invoke-Expression $command 2>&1
            }
            $exitCode = $LASTEXITCODE
            $duration = [math]::Round($measured.TotalSeconds, 3)
            
            # Save output to file
            $output | Out-File -FilePath $outputFile -Encoding utf8
            
            # Check if output contains UNSATISFIABLE or UNKNOWN
            $outputText = $output | Out-String
            $isUnsatisfiable = $outputText -match "=====UNSATISFIABLE====="
            $isUnknown = $outputText -match "=====UNKNOWN====="
            $isTimeout = $outputText -match "% Time limit exceeded!"
            
            # Extract additional statistics (only include fields that exist in output)
            
            # Extract additional statistics (only include fields that exist in output)
            $failures = if ($outputText -match "%%%mzn-stat: failures=(\d+)") { $matches[1] } else { "N/A" }
            $propagations = if ($outputText -match "%%%mzn-stat: propagations=(\d+)") { $matches[1] } else { "N/A" }
            $objective = if ($outputText -match "%%%mzn-stat: objective=(\d+)") { $matches[1] } else { "N/A" }
            $boolVariables = if ($outputText -match "%%%mzn-stat: boolVariables=(\d+)") { $matches[1] } else { "N/A" }
            $nSolutions = if ($outputText -match "%%%mzn-stat: nSolutions=(\d+)") { $matches[1] } else { "N/A" }
            $objectiveBound = if ($outputText -match "%%%mzn-stat: objectiveBound=(\d+)") { $matches[1] } else { "N/A" }
            $nodes = if ($outputText -match "%%%mzn-stat: nodes=(\d+)") { $matches[1] } else { "N/A" }
            $restarts = if ($outputText -match "%%%mzn-stat: restarts=(\d+)") { $matches[1] } else { "N/A" }
            $variables = if ($outputText -match "%%%mzn-stat: variables=(\d+)") { $matches[1] } else { "N/A" }
            $intVars = if ($outputText -match "%%%mzn-stat: intVars=(\d+)") { $matches[1] } else { "N/A" }
            $propagators = if ($outputText -match "%%%mzn-stat: propagators=(\d+)") { $matches[1] } else { "N/A" }
            $peakDepth = if ($outputText -match "%%%mzn-stat: peakDepth=(\d+)") { $matches[1] } else { "N/A" }
            
            if ($isUnsatisfiable) {
                Write-Host "    Status: CAN'T SOLVE (UNSATISFIABLE)" -ForegroundColor Magenta
                Write-Host "    Duration: $($duration)s | Failures: $failures | BoolVars: $boolVariables | Propagations: $propagations" -ForegroundColor Gray
                $successCount++
                $status = "CAN'T SOLVE"
            } elseif ($isTimeout -or $isUnknown) {
                Write-Host "    Status: TIMEOUT" -ForegroundColor Yellow
                Write-Host "    Duration: $($duration)s | Failures: $failures | BoolVars: $boolVariables | Propagations: $propagations" -ForegroundColor Gray
                $failCount++
                $status = "TIMEOUT"
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
                Nodes = $nodes
                Restarts = $restarts
                Variables = $variables
                IntVars = $intVars
                Propagators = $propagators
                PeakDepth = $peakDepth
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

# Generate Markdown
$markdownFile = Join-Path $outputDir "test_results.md"
$markdown = "# MiniZinc Test Results`n"
$markdown += "Model: $modelFile`n"
$markdown += "Solvers: $($solvers -join ', ')`n"
$markdown += "Total tests: $($testFiles.Count * $solvers.Count)`n"
$markdown += "Successful: $successCount`n"
$markdown += "Failed: $failCount`n`n"

$markdown += "## Column Explanations`n`n"
$markdown += "- **Test**: The test case file name`n"
$markdown += "- **Solver**: The constraint solver used`n"
$markdown += "- **Status**: Outcome of the solving process (SUCCESS, TIMEOUT, etc.)`n"
$markdown += "- **Duration**: Time taken to solve the problem (seconds)`n`n`n"

$markdown += "## Combined Results`n`n"
$tableProperties = @("Test", "Solver", "Status", "Duration", "Propagations")

$markdown += "| " + ($tableProperties -join " | ") + " |`n"
$markdown += "| " + ("--- |" * $tableProperties.Count) + "`n"
foreach ($result in $results) {
    $rowValues = $tableProperties | ForEach-Object { $result.$_ }
    $markdown += "| " + ($rowValues -join " | ") + " |`n"
}

$markdown | Out-File -FilePath $markdownFile -Encoding utf8
Write-Host "Markdown results saved to: $markdownFile" -ForegroundColor White
