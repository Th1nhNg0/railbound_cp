#!/usr/bin/env python3
"""Check this model against the FoxtrotOnce/RailboundSolver C++ simulator.

For each level, run the C++ solver, translate the board it finds into a
MiniZinc constraint that pins every free cell (and the semaphores), and ask
main.mzn whether that board is a valid solution.  A rejected board means the
two disagree on a game rule (or on the level data), which is what this script
is for.  The horizon is lengthened (--time-scale) because the C++ search finds
valid but often slower solutions than the tuned MAX_TIME values.

Usage:
  python scripts/crosscheck_cpp.py --cpp-repo ../RailboundSolver [levels...]
      [--minizinc minizinc] [--solver chuffed] [--time-scale 3] [--timeout 30]

The C++ solver must be built first (cmake -B build cpp && cmake --build build,
see that repository's cpp/README.md); levels default to every file in data/.
"""

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIRS = ["TOP", "RIGHT", "DOWN", "LEFT"]
SEM_TRACKS = {23: 1, 24: 2, 25: 5, 26: 6, 27: 7, 28: 8}  # SEM_* track -> plain track
MOD_SEMAPHORE, MOD_DEACTIVATED = 8, 9


def piece_table(globals_src: str, name: str) -> dict:
    body = globals_src[globals_src.index(f"{name} = array2d(Piece, Dir, ["):]
    body = body[body.index("[") + 1: body.index("]);")]
    rows = {}
    for line in body.splitlines():
        m = re.match(r"\s*(.*?)%\s*(\w+)\s*$", line)
        if m:
            vals = [v.strip() for v in m.group(1).split(",") if v.strip()]
            if len(vals) == 4:
                rows[m.group(2)] = vals
    return rows


def tile_mapping(cpp_repo: Path) -> dict:
    """Map C++ track ids to Piece names by comparing routing behaviour."""
    g = (ROOT / "lib" / "globals.mzn").read_text()
    exit_of, can_enter = piece_table(g, "exit_of"), piece_table(g, "can_enter")
    t = (cpp_repo / "cpp" / "include" / "railbound" / "types.hpp").read_text()
    td = t[t.index("TRACK_DIRECTIONS[static_cast"):]
    td = td[:td.index("};")]
    theirs = [[x.split("::")[1] for x in r.split(", ")]
              for r in re.findall(r"\{(Direction::\w+, Direction::\w+, Direction::\w+, Direction::\w+)\}", td)]
    heading = ["LEFT", "RIGHT", "DOWN", "UP"]             # C++ index order
    entry_side = {"LEFT": "RIGHT", "RIGHT": "LEFT", "DOWN": "TOP", "UP": "DOWN"}
    exit_side = {"LEFT": "LEFT", "RIGHT": "RIGHT", "DOWN": "DOWN", "UP": "TOP"}
    ours = {p: {d: exit_of[p][i] for i, d in enumerate(DIRS) if can_enter[p][i] == "true"}
            for p in exit_of if p.startswith(("STRAIGHT", "CORNER", "SWITCH_"))}
    mapping = {0: "EMPTY"}
    for tid in [1, 2] + list(range(5, 17)):
        routes = {entry_side[h]: exit_side[r] for h, r in zip(heading, theirs[tid]) if r not in ("CRASH", "UNKNOWN")}
        hits = [p for p, m in ours.items() if m == routes]
        if len(hits) != 1:
            raise SystemExit(f"cannot map C++ track {tid}: {hits}")
        mapping[tid] = hits[0]
    return mapping


def grids(text: str, header: str, stop: str) -> list:
    part = text.split(header, 1)[1].split(stop, 1)[0]
    return [list(map(int, r.split(","))) for r in re.findall(r"\[([\d,]+)\]", part)]


def fixed_cells(dzn: str) -> set:
    init = dzn.split("INIT_POS", 1)[1].split(";", 1)[0]
    cells = {(int(a), int(b)) for a, b in re.findall(r"\((\d+)\s*,\s*(\d+)\s*,\s*[A-Z_]+\s*\)", init)}
    tun = dzn.split("TUNNEL_PAIRS", 1)[1].split(";", 1)[0]
    for a, b, _, c, d, _ in re.findall(r"\((\d+)\s*,\s*(\d+)\s*,\s*(\w+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\w+)\s*\)", tun):
        cells |= {(int(a), int(b)), (int(c), int(d))}
    return cells


def pin_constraints(cpp_out: str, dzn: str, mapping: dict) -> str:
    board = grids(cpp_out, "Solution Board:", "Solution Mods:")
    mods = grids(cpp_out, "Solution Mods:", "----")[:len(board)]
    init_mods = grids(cpp_out, "Initial Mods:", "Solving")
    fixed = fixed_cells(dzn)
    H, W = len(board), len(board[0])
    lines, sem = [], []
    for r in range(H):
        for c in range(W):
            v = board[r][c]
            placed_sem = v in SEM_TRACKS or init_mods[r][c] == MOD_SEMAPHORE or (
                init_mods[r][c] == 0 and mods[r][c] in (MOD_SEMAPHORE, MOD_DEACTIVATED))
            sem.append("true" if placed_sem else "false")
            v = SEM_TRACKS.get(v, v)
            if (r + 1, c + 1) in fixed:
                continue
            if v not in mapping:
                raise ValueError(f"unmapped C++ track {v} at ({r + 1},{c + 1})")
            lines.append(f"constraint grid[{r + 1},{c + 1}] = {mapping[v]};")
    lines.append(f"constraint semaphore_present = array2d(1..{H},1..{W},[{','.join(sem)}]);")
    return "\n".join(lines)


def scaled_horizon(dzn: str, scale: float) -> str:
    w = int(re.search(r"\bW\s*=\s*(\d+)", dzn).group(1))
    h = int(re.search(r"\bH\s*=\s*(\d+)", dzn).group(1))
    expr = re.search(r"MAX_TIME\s*=\s*([^;]*);", dzn).group(1)
    t = eval(expr.replace("W", str(w)).replace("H", str(h)), {"__builtins__": {}})
    return re.sub(r"MAX_TIME\s*=\s*[^;]*;", f"MAX_TIME={int(-(-t * scale // 1))};", dzn)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("levels", nargs="*", help="level .dzn files (default: data/*/*.dzn)")
    ap.add_argument("--cpp-repo", type=Path, required=True, help="RailboundSolver checkout with cpp/build built")
    ap.add_argument("--minizinc", default="minizinc")
    ap.add_argument("--solver", default="chuffed")
    ap.add_argument("--time-scale", type=float, default=3.0)
    ap.add_argument("--timeout", type=float, default=30.0, help="seconds for each solver run")
    args = ap.parse_args()

    exe = args.cpp_repo / "cpp" / "build" / "railbound_solver"
    mapping = tile_mapping(args.cpp_repo)
    levels = [Path(p) for p in args.levels] or sorted(ROOT.glob("data/*/*.dzn"))
    counts = {"accepted": 0, "REJECTED": 0, "cpp-unsolved": 0, "error": 0}
    with tempfile.TemporaryDirectory() as tmp:
        for dzn_path in levels:
            name = dzn_path.stem
            try:
                cpp = subprocess.run([str(exe), name, "--timeout", str(args.timeout)], cwd=args.cpp_repo,
                                     capture_output=True, text=True, timeout=args.timeout + 30).stdout
            except subprocess.TimeoutExpired:
                cpp = ""
            if "SOLVED!" not in cpp:
                verdict = "cpp-unsolved"
            else:
                dzn = dzn_path.read_text()
                data = Path(tmp, f"{name}.dzn")
                pins = Path(tmp, f"{name}-pins.mzn")
                data.write_text(scaled_horizon(dzn, args.time_scale))
                pins.write_text(pin_constraints(cpp, dzn, mapping) + "\n")
                res = subprocess.run([args.minizinc, "--solver", args.solver, str(ROOT / "main.mzn"), str(pins),
                                      str(data), "--time-limit", str(int(args.timeout * 1000))],
                                     capture_output=True, text=True)
                if "----------" in res.stdout:
                    verdict = "accepted"
                elif "=====UNSATISFIABLE=====" in res.stdout:
                    verdict = "REJECTED"
                else:
                    verdict = "error"
                    sys.stderr.write(res.stderr[-500:])
            counts[verdict] += 1
            print(f"{name:8s} {verdict}", flush=True)
    print(", ".join(f"{k}: {v}" for k, v in counts.items()))
    return 1 if counts["REJECTED"] or counts["error"] else 0


if __name__ == "__main__":
    sys.exit(main())
