% ============================================================
% formatting.mzn - Solution Visualization & Output Formatting
% ============================================================
% Prepares solution data for visualization and textual output.
% Formats grid state, train/decoy paths, and switch states for display.
% ============================================================

% output :: vis_server("viz.html", initial_data) solution_data;
output [
  "============================================================\n",
  "SOLUTION FOUND\n",
  "============================================================\n\n",
  "GRID LAYOUT:\n",
  show2d(grid), "\n\n",
  "TIME_USED: \(max(arrival_time))\n",
  "TRACK_USED: \(sum(r in 1..H, c in 1..W)(
  bool2int(grid[r, c] != EMPTY /\
       not exists(i in 1..N_INIT_POS)(
         INIT_POS[i].1 = r /\ INIT_POS[i].2 = c
       )
        /\ not (grid[r, c] in TUNNELS_SET)
       )))"
]
++
["\nTRAIN PATHS:\n"]
++
[
  "Train \(t): arrival at time \(arrival_time[t])\n" ++
  "  Path: " ++ show(
    (
      if fix(arrival_time[t]) > 0 then
        [ (train_row[t, time], train_col[t, time]) | time in 1..fix(arrival_time[t]) ]
      else []
      endif
    )
  ) ++ "\n"
  | t in 1..N_TRAINS
]
++
(if N_DECOYS > 0 then
  ["\nDECOY PATHS:\n"]
  ++
  [
    "Decoy \(d):\n" ++
    "  Path: " ++ show(
      (
          [ (decoy_row[d, time], decoy_col[d, time]) | time in 1..MAX_TIME ]
      )
    ) ++ "\n"
    | d in 1..N_DECOYS
  ]
else [] endif)
++
(if SEMAPHORE_SUPPLY > 0 then
  ["\nSEMAPHORES: "]
  ++ (if fix(sum(r in 1..H, c in 1..W)(bool2int(semaphore_present[r,c]))) > 0 then
        [ "  (" ++ show(r) ++ "," ++ show(c) ++ ")\n" | r in 1..H, c in 1..W where fix(semaphore_present[r,c]) ]
      else [] endif)
else [] endif);
