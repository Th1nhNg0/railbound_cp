#!/bin/bash
# Run full benchmark for both CP-SAT and Chuffed solvers

# Create a 'minizinc' wrapper so bash can call the Windows .exe by name
mkdir -p /tmp/mzn_wrapper
cat > /tmp/mzn_wrapper/minizinc << 'EOF'
#!/bin/bash
exec "/mnt/c/Program Files/MiniZinc/minizinc.exe" "$@"
EOF
chmod +x /tmp/mzn_wrapper/minizinc
export PATH="/tmp/mzn_wrapper:$PATH"

echo "=== MiniZinc version ==="
minizinc --version
echo ""

# Discover all level directories and pass them explicitly.
# (Avoids the IFS newline bug in run_benchmarks.sh level discovery.)
ALL_LEVELS=$(ls -d data/*/ | sed 's|data/||g; s|/||g' | tr '\n' ',' | sed 's/,$//')
echo "=== Levels found: $ALL_LEVELS ==="
echo ""

echo "=== Starting CP-SAT benchmark (8 threads) ==="
bash run_benchmarks.sh -l "$ALL_LEVELS" -a "--solver cp-sat --time-limit 300000 --statistics -p 8"

echo ""
echo "=== Starting Chuffed benchmark ==="
bash run_benchmarks.sh -l "$ALL_LEVELS" -a "--solver chuffed --time-limit 300000 --statistics"

echo ""
echo "=== All benchmarks complete ==="
