% ============================================================
% GRID CONSTRAINTS
% ============================================================

% --- Track Limit Constraint ---
% Ensures the number of placed tracks does not exceed MAX_TRACKS.
% Track Limit Constraint: Count only non-empty, non-initial, non-tunnel cells as placed tracks.
int: INIT_EMPTY = W*H - (N_INIT_POS + 2 * N_TUNNELS);
constraint
  INIT_EMPTY - sum(r in 1..H, c in 1..W)(
      bool2int(grid[r, c] == EMPTY)
    ) <= MAX_TRACKS;

% --- Initial Position Constraint ---
% Ensures that pre-placed pieces are correctly placed on the grid.
constraint forall(i in 1..N_INIT_POS)(
    grid[INIT_POS[i].1, INIT_POS[i].2] = INIT_POS[i].3
);

% --- Tunnel Placement Constraint ---
% Ensures that tunnel pairs are correctly placed with the appropriate orientations.
constraint forall(i in 1..N_TUNNELS)(
  let {
    int: r1 = TUNNEL_PAIRS[i].1;
    int: c1 = TUNNEL_PAIRS[i].2;
    Dir: dir1 = TUNNEL_PAIRS[i].3;
    int: r2 = TUNNEL_PAIRS[i].4;
    int: c2 = TUNNEL_PAIRS[i].5;
    Dir: dir2 = TUNNEL_PAIRS[i].6;
  } in
  grid[r1, c1] = (if dir1 == TOP then TUNNEL_T elseif dir1 == DOWN then TUNNEL_D elseif dir1 == LEFT then TUNNEL_L else TUNNEL_R endif) /\
  grid[r2, c2] = (if dir2 == TOP then TUNNEL_T elseif dir2 == DOWN then TUNNEL_D elseif dir2 == LEFT then TUNNEL_L else TUNNEL_R endif)
);

% --- Special Piece Init Constraint ---
% Ensures that switches and tunnels must be pre-placed (cannot be placed dynamically).
constraint forall(r in 1..H, c in 1..W)(
    (grid[r, c] in UNPLACEABLE_PIECES)-> cell_is_init[r, c]
);

% --- Train Path Validity Constraint ---
% Ensures that trains only move on valid track cells (not EMPTY and not ROCK).
constraint forall(t in 1..N_TRAINS, i in 1..arrival_time[t])(
    grid[train_row[t, i], train_col[t, i]] != EMPTY /\
    grid[train_row[t, i], train_col[t, i]] != ROCK
);

% --- Bounds Check Predicate ---
predicate in_bounds(int: r, int: c) =
  r >= 1 /\ r <= H /\ c >= 1 /\ c <= W;

% --- Switch Connectivity Constraint ---
% Ensures that switches have exactly 3 valid connecting neighbors.
constraint forall(r in 1..H, c in 1..W)(
  % If this cell has a switch that's not pre-placed
  ((grid[r, c] in SWITCHES_SET \/ grid[r, c] in DSWITCHES_SET \/ grid[r, c] in ESWITCHES_SET) /\
  not cell_is_init[r, c])
  ->
  % Then the number of directions that have valid connecting neighbors is 3
  sum(d in Dir)(
    let {
      int: nr = r + dr[d];
      int: nc = c + dc[d];
    } in
    bool2int(
      in_bounds(nr, nc) /\
      can_connect[grid[r, c], d] /\
      can_connect[grid[nr, nc], opposite[d]]
    )
  ) = 3
);
