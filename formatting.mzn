% ============================================================
% formatting.mzn - Solution Visualization & Output Formatting
% ============================================================
% Prepares solution data for visualization and textual output.
% Formats grid state, train/decoy paths, and switch states for display.
% ============================================================

include "ide/vis.mzn";

% ==== VISUALIZATION DATA ====
% Package all puzzle input data for the visualizer.
any: initial_data = (
  grid_width: W,
  grid_height: H,
  target: TARGET,
  trains: [ (TRAINS[t].1, TRAINS[t].2, TRAINS[t].3) | t in 1..N_TRAINS ],
  decoys: [ (DECOYS[d].1, DECOYS[d].2, DECOYS[d].3) | d in 1..N_DECOYS ],
  init_positions: [ (INIT_POS[i].1, INIT_POS[i].2, INIT_POS[i].3) | i in 1..N_INIT_POS ],
  tunnels: [ (TUNNEL_PAIRS[i].1, TUNNEL_PAIRS[i].2, TUNNEL_PAIRS[i].3,
              TUNNEL_PAIRS[i].4, TUNNEL_PAIRS[i].5, TUNNEL_PAIRS[i].6) | i in 1..N_TUNNELS ],
  gates: [ (GATES[g].1, GATES[g].2, GATES[g].3, GATES[g].4) | g in 1..N_GATES ],
  activations: [ (ACTIVATIONS[a].1, ACTIVATIONS[a].2, ACTIVATIONS[a].3) | a in 1..N_ACTIVATIONS ],
  dswitches: [ (DSWITCHES[ds].1, DSWITCHES[ds].2, DSWITCHES[ds].3) | ds in 1..N_DSWITCHES ],
  stations: [ (STATIONS[st].1, STATIONS[st].2, STATIONS[st].3) | st in 1..N_STATIONS ],
  semaphore_supply: SEMAPHORE_SUPPLY
);
any: solution_data :: output_only = (
  grid: showJSON(grid),
  train_paths: showJSON([
    (
      if fix(arrival_time[t]) > 0 then
        [ [ train_row[t, time], train_col[t, time] ] | time in 1..fix(arrival_time[t]) ]
      else []
      endif
    )
    | t in 1..N_TRAINS
  ]),
  decoy_paths: showJSON(
    if N_DECOYS > 0 then
      [
        (
            [ [ decoy_row[d, time], decoy_col[d, time] ] | time in 1..MAX_TIME ]
        )
        | d in 1..N_DECOYS
      ]
    else []
    endif
  ),
  should_toggle: showJSON(should_toggle),
  eswitch_toggled: showJSON(eswitch_toggled),
  semaphore_present: showJSON(semaphore_present),
  semaphore_open_time: showJSON(semaphore_open_time)
);
output :: vis_server("viz.html", initial_data) solution_data;
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
