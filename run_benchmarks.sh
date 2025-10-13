#!/bin/bash
#
# Railbound Benchmark Suite
# ========================
#
# This script automates the process of running the MiniZinc solver against a
# collection of Railbound puzzle files (`.dzn`). It captures performance
# statistics, determines the outcome (e.g., SUCCESS, TIMEOUT), and generates
# a detailed CSV report.
#
# Key Features:
# - Run benchmarks on all or a specified subset of level directories.
# - Customizable solver, time limit, and parallel threads.
# - Parses MiniZinc's statistics output to extract key metrics.
# - Color-coded console output for easy readability.
# - Generates timestamped CSV files for historical tracking.
#
# Usage:
#   ./run_benchmarks.sh [options]
#
# Example:
#   # Run with the default Chuffed solver on all levels
#   ./run_benchmarks.sh
#
#   # Run with Gecode on levels 1 and 3, with a 60s time limit
#   ./run_benchmarks.sh -s gecode -l "1,3" -t 60000
#

# --- Default Parameters ---
SOLVER="chuffed"         # The MiniZinc solver to use.
TIME_LIMIT=300000       # Time limit per puzzle in milliseconds (5 minutes).
LEVELS=""               # Comma-separated list of level directories to run (e.g., "1,2,8"). Default is all.
OUTPUT_DIR="benchmark_results" # Directory to store output files.
MODEL_FILE="main.mzn"   # The main MiniZinc model file.
PARALLEL=4              # Number of parallel threads for the solver.

# --- Colors for Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# --- usage ---
# Prints the help message and exits.
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -s SOLVER     MiniZinc solver to use (default: $SOLVER)"
    echo "  -t TIMELIMIT  Time limit in milliseconds (default: $TIME_LIMIT)"
    echo "  -l LEVELS     Comma-separated list of level directories (e.g., \"1,3\" or \"all\") (default: all)"
    echo "  -o OUTPUTDIR  Output directory (default: $OUTPUT_DIR)"
    echo "  -m MODELFILE  Model file (default: $MODEL_FILE)"
    echo "  -p PARALLEL   Number of parallel threads (default: $PARALLEL)"
    echo "  -h            Show this help"
    exit 1
}

# --- Argument Parsing ---
while getopts "s:t:l:o:m:p:h" opt; do
    case $opt in
        s) SOLVER="$OPTARG" ;;
        t) TIME_LIMIT="$OPTARG" ;;
        l) LEVELS="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        m) MODEL_FILE="$OPTARG" ;;
        p) PARALLEL="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# --- Setup ---
# Ensure the output directory for results exists.
mkdir -p "$OUTPUT_DIR"

# Generate timestamped filenames for the output reports.
timestamp=$(date +%Y%m%d_%H%M%S)
csvfile="$OUTPUT_DIR/benchmark_${SOLVER}_${timestamp}.csv"

# Set the data directory where puzzle files are located.
data_dir="data"
if [ ! -d "$data_dir" ]; then
    echo -e "${RED}Error: Data directory not found: $data_dir${NC}"
    exit 1
fi

# --- Level Discovery ---
# Determine which level directories to process.
if [ -z "$LEVELS" ] || [ "$LEVELS" = "all" ]; then
    # If no levels are specified or "all" is specified, find all directories in `data/`.
    level_dirs=$(ls -d "$data_dir"/*/ 2>/dev/null | sort -V)
else
    # If levels are specified, parse the comma-separated list.
    IFS=',' read -ra LEVEL_ARRAY <<< "$LEVELS"
    level_dirs=""
    for level in "${LEVEL_ARRAY[@]}"; do
        level=$(echo "$level" | xargs)  # Trim whitespace
        if [ -d "$data_dir/$level" ]; then
            level_dirs="$level_dirs $data_dir/$level/"
        fi
    done
fi
# Convert the list of directories into an array.
IFS=' ' read -ra LEVEL_DIRS_ARRAY <<< "$level_dirs"

# --- Print Header ---
echo -e "${CYAN}============================================================"
echo -e "Railbound Benchmark Suite"
echo -e "============================================================"
echo "Model      : $MODEL_FILE"
echo "Solver     : $SOLVER"
echo "Time Limit : $TIME_LIMIT ms"
echo "Levels     : $(echo "${LEVEL_DIRS_ARRAY[@]}" | sed 's|data/||g; s|/||g' | tr '\n' ',' | sed 's/,$//')"
echo "Output CSV : $csvfile"
echo "Command    : minizinc --solver $SOLVER --time-limit $TIME_LIMIT --statistics ${PARALLEL:+ -p $PARALLEL} $MODEL_FILE <Data>${GRAY}"
echo -e "${CYAN}============================================================${NC}\n"

# --- Initialize CSV and Statistics ---
# Write the header row to the CSV file.
csv_header="timestamp,level,puzzle,status,solver,solveTime,failures,propagations,flatBoolVars,flatIntVars,flatBoolConstraints,flatIntConstraints,flatTime,boolVariables"
echo "$csv_header" > "$csvfile"

# Initialize counters for the final summary.
total_puzzles=0
success_count=0
unsat_count=0
timeout_count=0
error_count=0
total_time=0
total_failures=0

# --- extract_stat ---
# Helper function to parse a specific statistic from the MiniZinc output.
# Arguments:
#   $1: The pattern to grep for (e.g., "%%%mzn-stat: solveTime=").
#   $2: The full output from the MiniZinc command.
#   $3: A default value to return if the pattern is not found.
extract_stat() {
    local pattern="$1"
    local output="$2"
    local default="${3:-N/A}"
    echo "$output" | grep "$pattern" | sed "s/.*$pattern//" | head -1 || echo "$default"
}

# --- Main Benchmark Loop ---
for level_dir in "${LEVEL_DIRS_ARRAY[@]}"; do
    level=$(basename "$level_dir")
    puzzle_files=$(ls "$level_dir"*.dzn 2>/dev/null | sort -V)
    
    if [ -z "$puzzle_files" ]; then
        continue
    fi
    
    IFS=$'\n' read -rd '' -a PUZZLE_ARRAY <<< "$puzzle_files"
    
    echo -e "\n${YELLOW}[Level $level] Found ${#PUZZLE_ARRAY[@]} puzzles${NC}"
    echo -e "${CYAN}$(printf '%.0s=' {1..80})${NC}"
    
    for puzzle_file in "${PUZZLE_ARRAY[@]}"; do
        puzzle_name=$(basename "$puzzle_file" .dzn)
        total_puzzles=$((total_puzzles + 1))
        
        echo -n "[$total_puzzles] $level/$puzzle_name ... "
        
        # Execute the MiniZinc solver and capture output, exit code, and timing.
        start_time=$(date +%s)
        output=$(minizinc --solver "$SOLVER" --time-limit "$TIME_LIMIT" --statistics ${PARALLEL:+-p $PARALLEL} "$MODEL_FILE" "$puzzle_file" 2>&1)
        exit_code=$?
        end_time=$(date +%s)
        duration=$(( (end_time - start_time) * 1000 ))
        
        # Determine the status of the run based on the output and exit code.
        if echo "$output" | grep -q "=====UNSATISFIABLE====="; then
            status="UNSAT"
            unsat_count=$((unsat_count + 1))
            color="$MAGENTA"
        elif echo "$output" | grep -q "Time limit exceeded\|time limit"; then
            status="TIMEOUT"
            timeout_count=$((timeout_count + 1))
            color="$YELLOW"
        elif [ $exit_code -eq 0 ] && echo "$output" | grep -q "====="; then
            status="SUCCESS"
            success_count=$((success_count + 1))
            color="$GREEN"
        else
            status="ERROR"
            error_count=$((error_count + 1))
            color="$RED"
        fi
        
        # Extract all relevant statistics from the output.
        solve_time=$(extract_stat "%%%mzn-stat: solveTime=" "$output")
        failures=$(extract_stat "%%%mzn-stat: failures=" "$output" "0")
        propagations=$(extract_stat "%%%mzn-stat: propagations=" "$output" "0")
        flatBoolVars=$(extract_stat "%%%mzn-stat: flatBoolVars=" "$output" "0")
        flatIntVars=$(extract_stat "%%%mzn-stat: flatIntVars=" "$output" "0")
        flatBoolConstraints=$(extract_stat "%%%mzn-stat: flatBoolConstraints=" "$output" "0")
        flatIntConstraints=$(extract_stat "%%%mzn-stat: flatIntConstraints=" "$output" "0")
        flatTime=$(extract_stat "%%%mzn-stat: flatTime=" "$output")
        boolVariables=$(extract_stat "%%%mzn-stat: boolVariables=" "$output" "0")
        
        # Update running totals for the final summary.
        if [ "$solve_time" != "N/A" ]; then
            total_time=$(awk "BEGIN {print $total_time + $solve_time}")
        fi
        if [ "$failures" != "N/A" ] && [ "$failures" -gt 0 ]; then
            total_failures=$((total_failures + failures))
        fi
        
        # Append the results for this puzzle to the CSV file.
        row_ts=$(date +%Y-%m-%dT%H:%M:%S)
        csv_line="$row_ts,$level,$puzzle_name,$status,$SOLVER,$solve_time,$failures,$propagations,$flatBoolVars,$flatIntVars,$flatBoolConstraints,$flatIntConstraints,$flatTime,$boolVariables"
        echo "$csv_line" >> "$csvfile"
        
        # Display the result for this puzzle in the console.
        echo -e "${color}$status${NC} (${solve_time}s, ${failures} fails)${GRAY}"
    done
done

# --- Generate Summary ---
# Calculate averages and percentages for the summary report.
if [ $success_count -gt 0 ]; then
    avg_time=$(awk "BEGIN {printf \"%.3f\", $total_time / $success_count}")
    avg_failures=$((total_failures / success_count))
else
    avg_time="N/A"
    avg_failures="N/A"
fi
success_percent=$(awk "BEGIN {printf \"%.1f\", 100.0 * $success_count / $total_puzzles}")

# Create the summary text block.
summary_text="============================================================
Railbound Benchmark Summary
============================================================
Timestamp  : $(date +%Y-%m-%d\ %H:%M:%S)
Solver     : $SOLVER
Time Limit : $TIME_LIMIT ms
Model      : $MODEL_FILE

RESULTS
------------------------------------------------------------
Total Puzzles  : $total_puzzles
Success        : $success_count (${success_percent}%)
UNSAT          : $unsat_count
Timeout        : $timeout_count
Error          : $error_count

STATISTICS
------------------------------------------------------------
Total Solve Time : $(printf "%.2f" "$total_time") seconds
Avg Solve Time : $avg_time seconds (for successful puzzles)
Total Failures : $total_failures
Avg Failures   : $avg_failures (for successful puzzles)
============================================================
"

# Print the summary to the console.
echo -e "\n${CYAN}$summary_text${NC}"

echo -e "\n${GREEN}Benchmark complete! Results saved to:${NC}"
echo "  CSV:     $csvfile"