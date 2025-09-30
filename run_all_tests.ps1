# PowerShell script to run MiniZinc on all test files with Chuffed solver
# Usage: .\run_all_tests.ps1

# Configuration
$modelFile = ".\railbound.mzn"
$testDir = ".\test"
$solver = "chuffed"
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
Write-Host "Running MiniZinc tests with Chuffed solver" -ForegroundColor Cyan
Write-Host "Model: $modelFile" -ForegroundColor Cyan
Write-Host "Solver: $solver" -ForegroundColor Cyan
Write-Host "Test files found: $($testFiles.Count)" -ForegroundColor Cyan
Write-Host "============================================================`n" -ForegroundColor Cyan

$successCount = 0
$failCount = 0
$results = @()

foreach ($testFile in $testFiles) {
    $testName = $testFile.Name
    $testPath = $testFile.FullName
    $outputFile = Join-Path $outputDir "$($testFile.BaseName)_output.txt"
    
    Write-Host "Running: $testName" -ForegroundColor Yellow
    Write-Host "  Command: minizinc --solver $solver $modelFile $testPath" -ForegroundColor Gray
    
    $startTime = Get-Date
    
    # Run MiniZinc and capture output
    try {
        $output = & minizinc --solver $solver $modelFile $testPath 2>&1
        $exitCode = $LASTEXITCODE
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds
        
        # Save output to file
        $output | Out-File -FilePath $outputFile -Encoding utf8
        
        if ($exitCode -eq 0) {
            Write-Host "  Status: SUCCESS" -ForegroundColor Green
            Write-Host "  Duration: $([math]::Round($duration, 2))s" -ForegroundColor Gray
            $successCount++
            $status = "SUCCESS"
        } else {
            Write-Host "  Status: FAILED (exit code: $exitCode)" -ForegroundColor Red
            Write-Host "  Duration: $([math]::Round($duration, 2))s" -ForegroundColor Gray
            $failCount++
            $status = "FAILED"
        }
        
        $results += [PSCustomObject]@{
            Test = $testName
            Status = $status
            Duration = [math]::Round($duration, 2)
            ExitCode = $exitCode
        }
    }
    catch {
        Write-Host "  Status: ERROR - $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
        $results += [PSCustomObject]@{
            Test = $testName
            Status = "ERROR"
            Duration = 0
            ExitCode = -1
        }
    }
    
    Write-Host ""
}

# Summary
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Total tests: $($testFiles.Count)" -ForegroundColor White
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
