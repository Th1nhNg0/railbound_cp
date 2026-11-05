#!/usr/bin/env python3
"""Solve a Railbound level with a two-strategy MiniZinc portfolio.

Runs main.mzn twice in parallel, once per search order (SEARCH=1 train-major,
SEARCH=2 time-major; see main.mzn), prints the first solution found and stops
the other run.  Neither order dominates across the campaign, so racing them
solves more levels than either alone.

Usage:
  python scripts/solve.py data/8/8-5.dzn [--solver chuffed] [--time-limit 60]
                          [--minizinc minizinc] [-- extra minizinc args]
"""

import argparse
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STRATEGIES = {1: "train-major", 2: "time-major"}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("data", help="level .dzn file")
    ap.add_argument("--solver", default="chuffed")
    ap.add_argument("--time-limit", type=float, default=0, help="seconds per strategy (0 = none)")
    ap.add_argument("--minizinc", default="minizinc", help="MiniZinc executable")
    ap.add_argument("extra", nargs="*", help="extra arguments passed to minizinc (after --)")
    args = ap.parse_args()

    procs = {}
    start = time.monotonic()
    for sid in STRATEGIES:
        cmd = [args.minizinc, "--solver", args.solver, str(ROOT / "main.mzn"), args.data,
               "-D", f"SEARCH={sid};", *args.extra]
        if args.time_limit > 0:
            cmd += ["--time-limit", str(int(args.time_limit * 1000))]
        procs[sid] = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                      start_new_session=True)  # own group, so the solver child dies too

    pending = dict(procs)
    winner = None
    failures = {}
    try:
        while pending and winner is None:
            for sid, p in list(pending.items()):
                if p.poll() is None:
                    continue
                del pending[sid]
                out, err = p.communicate()
                # A strategy is decisive if it found a solution or proved UNSAT.
                if p.returncode == 0 and ("----------" in out or "=====UNSATISFIABLE=====" in out):
                    winner = (sid, out)
                    break
                failures[sid] = (p.returncode, out, err)
            time.sleep(0.02)
    finally:
        for p in pending.values():
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            p.wait()

    elapsed = time.monotonic() - start
    if winner is None:
        for sid, (code, out, err) in failures.items():
            sys.stderr.write(f"[{STRATEGIES[sid]}] exit {code}\n{err}{out}")
        print(f"% no strategy finished ({elapsed:.2f}s)")
        return 1
    sid, out = winner
    sys.stdout.write(out)
    print(f"% solved by {STRATEGIES[sid]} search in {elapsed:.2f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
