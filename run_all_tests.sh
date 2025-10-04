#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --solver NAME        MiniZinc solver id (default: chuffed)
  --time-limit MS      MiniZinc time limit in milliseconds (default: 15000)
  --count N            Run only the first N data files (default: all)
  --wall-time SEC      Hard wall-clock timeout per instance, passed to 'timeout'
  --model PATH         Model file to solve (default: main.mzn)
  --data-dir PATH      Root directory containing .dzn files (default: data)
  --results PATH       Directory to store solver outputs (default: results)
  -h, --help           Show this help message
USAGE
}

solver="chuffed"
time_limit=15000
max_tests=0
wall_time=""
model_file="main.mzn"
data_dir="data"
results_dir="results"

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
    --data-dir)
      data_dir="$2"; shift 2 ;;
    --results)
      results_dir="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1 ;;
  esac
done

if [[ ! -f "$model_file" ]]; then
  echo "Model file not found: $model_file" >&2
  exit 1
fi

if [[ ! -d "$data_dir" ]]; then
  echo "Data directory not found: $data_dir" >&2
  exit 1
fi

mkdir -p "$results_dir"

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
echo "Running MiniZinc tests"
echo "Model   : $model_file"
echo "Solver  : $solver"
echo "Data dir: $data_dir"
echo "Results : $results_dir"
echo "Count   : $max_tests"$( [[ -n "$wall_time" ]] && echo " (wall $wall_time s)" )
echo "============================================================"

success=0
unsat=0
timeouts=0
failed=0

for ((idx=0; idx<max_tests; idx++)); do
  file="${test_files[$idx]}"
  rel_file="${file#./}"
  base_name=$(basename "$file" .dzn)
  output_file="$results_dir/${base_name}_${solver}_output.txt"

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

  printf '%s
' "$output" > "$output_file"

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

  echo "Status  : $status"
  echo "Duration: ${duration}s"
  echo "Output  : $output_file"
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
