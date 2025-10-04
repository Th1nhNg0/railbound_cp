#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options] LEVEL

Run MiniZinc benchmarks for a specific level and output results to CSV.

Arguments:
  LEVEL               Level number (1-9)

Options:
  --solver NAME        MiniZinc solver id (default: chuffed)
  --time-limit MS      MiniZinc time limit in milliseconds (default: 15000)
  --count N            Run only the first N data files (default: all)
  --wall-time SEC      Hard wall-clock timeout per instance, passed to 'timeout'
  --model PATH         Model file to solve (default: main.mzn)
  --csv PATH           CSV file to output results (default: benchmark_results.csv)
  -h, --help           Show this help message
USAGE
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

level="$1"
shift

# Validate level is between 1 and 9
if ! [[ "$level" =~ ^[1-9]$ ]]; then
  echo "Error: Level must be a number between 1 and 9" >&2
  exit 1
fi

solver="chuffed"
time_limit=60000
max_tests=0
wall_time=""
model_file="main.mzn"
csv_file="benchmark_results.csv"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --solver)
      solver="$2"; shift 2 ;;
    --time-limit)
      time_limit="$2"; shift 2 ;;
    --count)
      max_tests="$2"; shift 2 ;;
    --wall-time)
      wall_time="$2"; shift 2 ;;
    --model)
      model_file="$2"; shift 2 ;;
    --csv)
      csv_file="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1 ;;
  esac
done

data_dir="data/$level"

if [[ ! -f "$model_file" ]]; then
  echo "Model file not found: $model_file" >&2
  exit 1
fi

if [[ ! -d "$data_dir" ]]; then
  echo "Data directory not found: $data_dir" >&2
  exit 1
fi

if [[ -n "$wall_time" ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Warning: python3 is required for --wall-time; ignoring wall timeout" >&2
    wall_time=""
  fi
fi

test_files=()
while IFS= read -r file; do
  test_files+=("$file")
done < <(find "$data_dir" -type f -name '*.dzn' | sort)

total_tests=${#test_files[@]}
if [[ $total_tests -eq 0 ]]; then
  echo "No .dzn files found under $data_dir" >&2
  exit 1
fi

if [[ $max_tests -gt 0 && $max_tests -lt $total_tests ]]; then
  total_tests=$max_tests
else
  max_tests=$total_tests
fi

echo "============================================================"
echo "Running MiniZinc benchmarks for level $level"
echo "Model   : $model_file"
echo "Solver  : $solver"
echo "Data dir: $data_dir"
echo "CSV     : $csv_file"
echo "Count   : $max_tests"$( [[ -n "$wall_time" ]] && echo " (wall $wall_time s)" )
echo "============================================================"

# Initialize CSV file
echo "level,file,status,time,solver,failures,boolVars,propagations,nSolutions,objective,objectiveBound,nodes,restarts,variables,intVars,propagators,peakDepth" > "$csv_file"

success=0
unsat=0
timeouts=0
failed=0

for ((idx=0; idx<max_tests; idx++)); do
  file="${test_files[$idx]}"
  rel_file="${file#./}"
  base_name=$(basename "$file" .dzn)

  echo
  echo "[${idx+1}/$max_tests] $rel_file"

  start_secs=$(date +%s)
  if [[ -n "$wall_time" ]]; then
    set +e
    output=$(python3 - "$wall_time" minizinc --solver "$solver" --time-limit "$time_limit" --statistics "$model_file" "$file" <<'PY'
import subprocess
import sys

timeout = float(sys.argv[1])
cmd = sys.argv[2:]

def _write(data):
    if not data:
        return
    if isinstance(data, bytes):
        data = data.decode()
    sys.stdout.write(data)

try:
    completed = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )
    _write(completed.stdout)
    sys.exit(completed.returncode)
except subprocess.TimeoutExpired as exc:
    _write(exc.stdout)
    _write(exc.stderr)
    sys.stdout.write("% Time limit exceeded!\n")
    sys.exit(124)
PY
)
    exit_code=$?
    set -e
  else
    set +e
    output=$(minizinc --solver "$solver" --time-limit "$time_limit" --statistics "$model_file" "$file" 2>&1)
    exit_code=$?
    set -e
  fi
  end_secs=$(date +%s)
  duration=$(( end_secs - start_secs ))

  status=""
  if echo "$output" | grep -q "=====UNSATISFIABLE====="; then
    status="UNSAT"
    ((unsat++))
  elif [[ $exit_code -eq 124 ]] || echo "$output" | grep -qi "time limit exceeded"; then
    status="TIMEOUT"
    ((timeouts++))
  elif [[ $exit_code -eq 0 ]]; then
    status="SUCCESS"
    ((success++))
  else
    status="FAILED"
    ((failed++))
  fi

  # Extract statistics
  failures=$(echo "$output" | sed -n 's/.*%%%mzn-stat: failures=\([0-9]*\).*/\1/p' || echo "N/A")
  boolVars=$(echo "$output" | sed -n 's/.*%%%mzn-stat: boolVariables=\([0-9]*\).*/\1/p' || echo "N/A")
  propagations=$(echo "$output" | sed -n 's/.*%%%mzn-stat: propagations=\([0-9]*\).*/\1/p' || echo "N/A")
  nSolutions=$(echo "$output" | sed -n 's/.*%%%mzn-stat: nSolutions=\([0-9]*\).*/\1/p' || echo "N/A")
  objective=$(echo "$output" | sed -n 's/.*%%%mzn-stat: objective=\([0-9]*\).*/\1/p' || echo "N/A")
  objectiveBound=$(echo "$output" | sed -n 's/.*%%%mzn-stat: objectiveBound=\([0-9]*\).*/\1/p' || echo "N/A")
  nodes=$(echo "$output" | sed -n 's/.*%%%mzn-stat: nodes=\([0-9]*\).*/\1/p' || echo "N/A")
  restarts=$(echo "$output" | sed -n 's/.*%%%mzn-stat: restarts=\([0-9]*\).*/\1/p' || echo "N/A")
  variables=$(echo "$output" | sed -n 's/.*%%%mzn-stat: variables=\([0-9]*\).*/\1/p' || echo "N/A")
  intVars=$(echo "$output" | sed -n 's/.*%%%mzn-stat: intVars=\([0-9]*\).*/\1/p' || echo "N/A")
  propagators=$(echo "$output" | sed -n 's/.*%%%mzn-stat: propagators=\([0-9]*\).*/\1/p' || echo "N/A")
  peakDepth=$(echo "$output" | sed -n 's/.*%%%mzn-stat: peakDepth=\([0-9]*\).*/\1/p' || echo "N/A")

  time=$(echo "$output" | sed -n 's/.*%%%mzn-stat: time=\([0-9.]*\).*/\1/p' || echo "N/A")

  # Append to CSV
  echo "$level,$base_name,$status,$time,$solver,$failures,$boolVars,$propagations,$nSolutions,$objective,$objectiveBound,$nodes,$restarts,$variables,$intVars,$propagators,$peakDepth" >> "$csv_file"

  echo "Status  : $status"
  echo "Time: ${time}s"
done

ran=$((success + unsat + timeouts + failed))
echo
echo "============================================================"
echo "Summary"
echo "============================================================"
echo "Ran       : $ran"
echo "Success   : $success"
echo "UNSAT     : $unsat"
echo "Timeouts  : $timeouts"
echo "Failures  : $failed"
echo "============================================================"
echo "Results saved to $csv_file"