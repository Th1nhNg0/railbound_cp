% ============================================================
% formatting.mzn - Solution Output
% ============================================================
% Human-readable summary of a solution: the board, track usage, and the path
% of every train / decoy as (row, col) pairs.  Output is only evaluated once a
% solution is found, so it does not affect solving time.  Use
% `--output-mode json` (or dzn) to get the raw decision variables instead.
% ============================================================

function string: show_cell(int: p) = "(\(cell_row[p]),\(cell_col[p]))";

output [
  "SOLUTION FOUND\n",
  "GRID LAYOUT:\n", show2d(grid), "\n",
  "TIME_USED: \(max(arrival_time))\n",
  "TRACK_USED: \(sum(r in 1..H, c in 1..W where not cell_is_init[r, c])(bool2int(fix(grid[r, c]) != EMPTY)))\n",
  "\nTRAIN PATHS:\n"
] ++ [
  "Train \(t): arrival at time \(arrival_time[t])\n  Path: " ++
  join(" ", [ show_cell(fix(train_pos[t, i])) | i in 0..fix(arrival_time[t]) ]) ++ "\n"
| t in 1..N_TRAINS
] ++ (if N_DECOYS = 0 then [] else
  ["\nDECOY PATHS:\n"] ++ [
    "Decoy \(d):\n  Path: " ++ join(" ", [ show_cell(fix(decoy_pos[d, i])) | i in 0..MAX_TIME ]) ++ "\n"
  | d in 1..N_DECOYS ]
endif) ++ (if SEMAPHORE_SUPPLY = 0 then [] else
  ["\nSEMAPHORES:"] ++
  [ " (\(r),\(c)) opens at t=\(semaphore_open_time[r, c])" | r in 1..H, c in 1..W where fix(semaphore_present[r, c]) ] ++
  ["\n"]
endif);
