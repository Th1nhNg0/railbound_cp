include "ide/vis.mzn";

any: initial_data = (
  grid_width: W,
  grid_height: H,
  target: TARGET,
  trains: [ (TRAINS[t].1, TRAINS[t].2, TRAINS[t].3) | t in 1..N_TRAINS ],
  init_positions: [ (INIT_POS[i].1, INIT_POS[i].2, INIT_POS[i].3) | i in 1..N_INIT_POS ],
  tunnels: [ (TUNNEL_PAIRS[i].1, TUNNEL_PAIRS[i].2, TUNNEL_PAIRS[i].3,
              TUNNEL_PAIRS[i].4, TUNNEL_PAIRS[i].5, TUNNEL_PAIRS[i].6) | i in 1..N_TUNNELS ],
  gates: [ (GATES[g].1, GATES[g].2, GATES[g].3, GATES[g].4) | g in 1..N_GATES ],
  activations: [ (ACTIVATIONS[a].1, ACTIVATIONS[a].2, ACTIVATIONS[a].3) | a in 1..N_ACTIVATIONS ],
  dswitches: [ (DSWITCHES[ds].1, DSWITCHES[ds].2, DSWITCHES[ds].3) | ds in 1..N_DSWITCHES ],
  stations: [ (STATIONS[st].1, STATIONS[st].2, STATIONS[st].3) | st in 1..N_STATIONS ]
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
  train_path_lengths: showJSON([ fix(arrival_time[t]) | t in 1..N_TRAINS ])
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
];
