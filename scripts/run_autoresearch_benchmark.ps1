[CmdletBinding()]
param(
    [ValidateRange(1, 20)]
    [int]$Repeats = 3,
    [ValidateRange(1000, 3600000)]
    [int]$TimeLimitMilliseconds = 30000,
    [int]$RandomSeed = 1,
    [string]$MiniZincPath = "",
    [string]$ChuffedPath = ""
)

$ErrorActionPreference = "Stop"
$scriptDirectory = Split-Path -Parent $PSCommandPath
$projectRoot = Split-Path -Parent $scriptDirectory

if ([string]::IsNullOrWhiteSpace($MiniZincPath)) {
    $MiniZincPath = (Get-Command minizinc -ErrorAction Stop).Source
}
if ([string]::IsNullOrWhiteSpace($ChuffedPath)) {
    $ChuffedPath = Join-Path (Split-Path -Parent $MiniZincPath) "fzn-chuffed.exe"
    if (-not (Test-Path -LiteralPath $ChuffedPath -PathType Leaf)) {
        $ChuffedPath = Join-Path (Join-Path (Split-Path -Parent $MiniZincPath) "bin") "fzn-chuffed.exe"
    }
}
if (-not (Test-Path -LiteralPath $ChuffedPath -PathType Leaf)) {
    throw "Chuffed executable not found: $ChuffedPath"
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

function Get-Metric {
    param([string]$Output, [string]$Name)

    $match = [regex]::Match($Output, "%%%mzn-stat: $([regex]::Escape($Name))=([^`r`n]+)")
    if (-not $match.Success) { throw "Missing metric '$Name'" }
    return [double]::Parse($match.Groups[1].Value.Trim(), [Globalization.CultureInfo]::InvariantCulture)
}

$cacheRoot = Join-Path ([IO.Path]::GetTempPath()) ("railbound_benchmark_" + [guid]::NewGuid().ToString("N"))
$generatedFiles = [Collections.Generic.List[string]]::new()
$rows = @()
$compileMetrics = @{}

try {
    New-Item -ItemType Directory -Path $cacheRoot | Out-Null

    foreach ($puzzle in $puzzles) {
        $modelPath = Join-Path (Join-Path $projectRoot "benchmark_models") $puzzle.Model
        $dataPath = Join-Path $projectRoot $puzzle.Path
        $fznPath = Join-Path $cacheRoot ($puzzle.Name + ".fzn")
        $generatedFiles.Add($fznPath)

        $compileArguments = @(
            "--solver", "chuffed", "-O0", "--compile", "--statistics",
            "--no-output-ozn", "--fzn", $fznPath, $modelPath, $dataPath
        )
        $compileOutput = (& $MiniZincPath @compileArguments 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $fznPath -PathType Leaf)) {
            throw "Compilation failed for $($puzzle.Name)`n$compileOutput"
        }

        $compileMetrics[$puzzle.Name] = [pscustomobject]@{
            flatTime            = Get-Metric $compileOutput "flatTime"
            flatBoolVars        = Get-Metric $compileOutput "flatBoolVars"
            flatIntVars         = Get-Metric $compileOutput "flatIntVars"
            flatBoolConstraints = Get-Metric $compileOutput "flatBoolConstraints"
            flatIntConstraints  = Get-Metric $compileOutput "flatIntConstraints"
        }

        for ($repeat = 1; $repeat -le $Repeats; $repeat++) {
            $savedErrorActionPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            $solveOutput = (& $ChuffedPath -s -t $TimeLimitMilliseconds --rnd-seed $RandomSeed $fznPath 2>&1 | Out-String)
            $solveExitCode = $LASTEXITCODE
            $ErrorActionPreference = $savedErrorActionPreference
            if ($solveExitCode -ne 0 -or $solveOutput -notmatch "(?m)^----------`r?$") {
                throw "Solve failed for $($puzzle.Name) on repeat $repeat`n$solveOutput"
            }

            $rows += [pscustomobject]@{
                Repeat             = $repeat
                Puzzle             = $puzzle.Name
                solveTime          = Get-Metric $solveOutput "solveTime"
                flatTime           = $compileMetrics[$puzzle.Name].flatTime / $Repeats
                failures           = Get-Metric $solveOutput "failures"
                propagations       = Get-Metric $solveOutput "propagations"
                flatBoolVars       = $compileMetrics[$puzzle.Name].flatBoolVars
                flatIntVars        = $compileMetrics[$puzzle.Name].flatIntVars
                flatBoolConstraints = $compileMetrics[$puzzle.Name].flatBoolConstraints
                flatIntConstraints = $compileMetrics[$puzzle.Name].flatIntConstraints
                boolVariables      = Get-Metric $solveOutput "boolVariables"
            }
        }
    }
}
finally {
    foreach ($generatedFile in $generatedFiles) {
        if (Test-Path -LiteralPath $generatedFile -PathType Leaf) {
            Remove-Item -LiteralPath $generatedFile -Force
        }
    }
    $resolvedCacheRoot = [IO.Path]::GetFullPath($cacheRoot)
    $resolvedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $safePrefix = "railbound_benchmark_"
    if ($resolvedCacheRoot.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedCacheRoot).StartsWith($safePrefix, [StringComparison]::Ordinal)) {
        if (Test-Path -LiteralPath $resolvedCacheRoot -PathType Container) {
            Remove-Item -LiteralPath $resolvedCacheRoot -Force
        }
    }
}

$summary = foreach ($group in ($rows | Group-Object Puzzle)) {
    [pscustomobject]@{
        Puzzle              = $group.Name
        solveTime           = ($group.Group | Measure-Object solveTime -Average).Average
        flatTime            = ($group.Group | Measure-Object flatTime -Average).Average
        failures            = ($group.Group | Measure-Object failures -Average).Average
        propagations        = ($group.Group | Measure-Object propagations -Average).Average
        flatBoolVars        = ($group.Group | Measure-Object flatBoolVars -Average).Average
        flatIntVars         = ($group.Group | Measure-Object flatIntVars -Average).Average
        flatBoolConstraints = ($group.Group | Measure-Object flatBoolConstraints -Average).Average
        flatIntConstraints  = ($group.Group | Measure-Object flatIntConstraints -Average).Average
        boolVariables       = ($group.Group | Measure-Object boolVariables -Average).Average
    }
}

$summary | Sort-Object { $_.solveTime + $_.flatTime } -Descending | Format-Table -AutoSize
$totalMeanSolveTime = ($summary | Measure-Object solveTime -Sum).Sum
$totalMeanFlatTime = ($summary | Measure-Object flatTime -Sum).Sum
$combinedTime = $totalMeanSolveTime + $totalMeanFlatTime
$baselineCombinedTime = 1.5644826666666665
$targetCombinedTime = $baselineCombinedTime * 0.5
$reduction = 1.0 - ($combinedTime / $baselineCombinedTime)

Write-Output ("TOTAL_MEAN_SOLVE_TIME={0:R}" -f $totalMeanSolveTime)
Write-Output ("TOTAL_MEAN_FLAT_TIME={0:R}" -f $totalMeanFlatTime)
Write-Output ("AUTORESEARCH_COMBINED_TIME={0:R}" -f $combinedTime)
Write-Output ("TARGET_COMBINED_TIME={0:R}" -f $targetCombinedTime)
Write-Output ("COMBINED_TIME_REDUCTION={0:P3}" -f $reduction)

$amortizedFlatTime = $totalMeanFlatTime
foreach ($repeatGroup in ($rows | Group-Object Repeat | Sort-Object Name)) {
    $solvePassTime = ($repeatGroup.Group | Measure-Object solveTime -Sum).Sum
    Write-Output ("PASS_{0}_COMBINED_TIME={1:R}" -f $repeatGroup.Name, ($solvePassTime + $amortizedFlatTime))
}

if ($combinedTime -gt $targetCombinedTime) {
    throw "50% reduction target missed: $combinedTime > $targetCombinedTime"
}
