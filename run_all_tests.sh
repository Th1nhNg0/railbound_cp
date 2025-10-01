#!/bin/bash
# Bash script to run MiniZinc on all test files with Chuffed solver
# Usage: ./run_all_tests.sh

# Configuration
MODEL_FILE="./railbound.mzn"
TEST_DIR="./test"
SOLVERS=("chuffed")
OUTPUT_DIR="./results"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
GRAY='\033[0;37m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Get all .dzn files in the test directory and sort them
TEST_FILES=()
while IFS= read -r -d '' file; do
    TEST_FILES+=("$file")
done < <(find "$TEST_DIR" -name "*.dzn" -print0 | sort -z)

# List of test files to ignore
IGNORE_TESTS=("3-10C.dzn")

# Filter out ignored tests
FILTERED_FILES=()
for file in "${TEST_FILES[@]}"; do
    basename=$(basename "$file")
    skip=false
    for ignore in "${IGNORE_TESTS[@]}"; do
        if [ "$basename" = "$ignore" ]; then
            skip=true
            break
        fi
    done
    if [ "$skip" = false ]; then
        FILTERED_FILES+=("$file")
    fi
done
TEST_FILES=("${FILTERED_FILES[@]}")

if [ ${#TEST_FILES[@]} -eq 0 ]; then
    echo -e "${RED}No test files found in $TEST_DIR${NC}"
    exit 1
fi

echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}Running MiniZinc tests with multiple solvers${NC}"
echo -e "${CYAN}Model: $MODEL_FILE${NC}"
echo -e "${CYAN}Solvers: ${SOLVERS[*]}${NC}"
echo -e "${CYAN}Test files found: ${#TEST_FILES[@]}${NC}"
echo -e "${CYAN}============================================================${NC}\n"

SUCCESS_COUNT=0
FAIL_COUNT=0
RESULTS=()

# CSV header
echo "Test,Solver,Status,Duration,Nodes,Failures,Variables,IntVars,BoolVars,Propagations,PeakDepth,Restarts,Objective,ExitCode" > "$OUTPUT_DIR/test_results.csv"

for test_file in "${TEST_FILES[@]}"; do
    test_name=$(basename "$test_file")
    
    echo -e "\n${CYAN}============================================================${NC}"
    echo -e "${CYAN}TEST: $test_name${NC}"
    echo -e "${CYAN}============================================================${NC}"
    
    for solver in "${SOLVERS[@]}"; do
        base_name="${test_name%.dzn}"
        output_file="$OUTPUT_DIR/${base_name}_${solver}_output.txt"
        
        echo -e "  ${YELLOW}Solver: $solver${NC}"
        echo -e "    ${GRAY}Command: minizinc --solver $solver --statistics $MODEL_FILE $test_file${NC}"
        
        # Run MiniZinc and capture output
        output=$(minizinc --solver "$solver" --statistics "$MODEL_FILE" "$test_file" 2>&1)
        exit_code=$?
        
        # Save output to file
        echo "$output" > "$output_file"
        
        # Check if output contains UNSATISFIABLE
        is_unsatisfiable=$(echo "$output" | grep -c "=====UNSATISFIABLE=====")
        
        # Extract solving time from statistics (already in seconds)
        duration=0
        if echo "$output" | grep -q "%%%mzn-stat: solveTime="; then
            duration=$(echo "$output" | grep "%%%mzn-stat: solveTime=" | sed 's/.*solveTime=\([0-9.]*\).*/\1/')
        elif echo "$output" | grep -q "%%%mzn-stat: time="; then
            duration=$(echo "$output" | grep "%%%mzn-stat: time=" | sed 's/.*time=\([0-9.]*\).*/\1/')
        fi
        
        # Extract additional statistics
        nodes=$(echo "$output" | grep "%%%mzn-stat: nodes=" | sed 's/.*nodes=\([0-9]*\).*/\1/')
        [ -z "$nodes" ] && nodes="N/A"
        
        failures=$(echo "$output" | grep "%%%mzn-stat: failures=" | sed 's/.*failures=\([0-9]*\).*/\1/')
        [ -z "$failures" ] && failures="N/A"
        
        propagations=$(echo "$output" | grep "%%%mzn-stat: propagations=" | sed 's/.*propagations=\([0-9]*\).*/\1/')
        [ -z "$propagations" ] && propagations="N/A"
        
        peak_depth=$(echo "$output" | grep "%%%mzn-stat: peakDepth=" | sed 's/.*peakDepth=\([0-9]*\).*/\1/')
        [ -z "$peak_depth" ] && peak_depth="N/A"
        
        restarts=$(echo "$output" | grep "%%%mzn-stat: restarts=" | sed 's/.*restarts=\([0-9]*\).*/\1/')
        [ -z "$restarts" ] && restarts="N/A"
        
        objective=$(echo "$output" | grep "%%%mzn-stat: objective=" | sed 's/.*objective=\([0-9]*\).*/\1/')
        [ -z "$objective" ] && objective="N/A"
        
        variables=$(echo "$output" | grep "%%%mzn-stat: variables=" | sed 's/.*variables=\([0-9]*\).*/\1/')
        [ -z "$variables" ] && variables="N/A"
        
        int_vars=$(echo "$output" | grep "%%%mzn-stat: intVars=" | sed 's/.*intVars=\([0-9]*\).*/\1/')
        [ -z "$int_vars" ] && int_vars="N/A"
        
        bool_variables=$(echo "$output" | grep "%%%mzn-stat: boolVariables=" | sed 's/.*boolVariables=\([0-9]*\).*/\1/')
        [ -z "$bool_variables" ] && bool_variables="N/A"
        
        if [ "$is_unsatisfiable" -gt 0 ]; then
            echo -e "    ${MAGENTA}Status: CAN'T SOLVE (UNSATISFIABLE)${NC}"
            echo -e "    ${GRAY}Duration: ${duration}s | Nodes: $nodes | Failures: $failures | Vars: $variables${NC}"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            status="CAN'T SOLVE"
        elif [ $exit_code -eq 0 ]; then
            echo -e "    ${GREEN}Status: SUCCESS${NC}"
            echo -e "    ${GRAY}Duration: ${duration}s | Nodes: $nodes | Failures: $failures | Vars: $variables | Objective: $objective${NC}"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            status="SUCCESS"
        else
            echo -e "    ${RED}Status: FAILED (exit code: $exit_code)${NC}"
            echo -e "    ${GRAY}Duration: ${duration}s | Nodes: $nodes | Failures: $failures | Vars: $variables${NC}"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            status="FAILED"
        fi
        
        # Append to CSV
        echo "$test_name,$solver,$status,$duration,$nodes,$failures,$variables,$int_vars,$bool_variables,$propagations,$peak_depth,$restarts,$objective,$exit_code" >> "$OUTPUT_DIR/test_results.csv"
        
        echo ""
    done
done

# Summary
total_tests=$((${#TEST_FILES[@]} * ${#SOLVERS[@]}))
echo -e "\n${CYAN}============================================================${NC}"
echo -e "${CYAN}OVERALL TEST SUMMARY${NC}"
echo -e "${CYAN}============================================================${NC}"
echo -e "${WHITE}Total tests: $total_tests${NC}"
echo -e "${GREEN}Successful: $SUCCESS_COUNT${NC}"
echo -e "${RED}Failed: $FAIL_COUNT${NC}"
echo -e "${WHITE}Output saved to: $OUTPUT_DIR${NC}"
echo ""

# Display results table
echo -e "${CYAN}Results summary (see $OUTPUT_DIR/test_results.csv for full details):${NC}"
column -t -s',' "$OUTPUT_DIR/test_results.csv" | head -n 20

results_file="$OUTPUT_DIR/test_results.csv"
echo -e "\n${WHITE}Results saved to: $results_file${NC}"
