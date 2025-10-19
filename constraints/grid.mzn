% ============================================================
% constraints/grid.mzn - Grid Placement & Track Constraints
% ============================================================
% Enforces grid composition rules: track limits, pre-placed pieces,
% tunnel placements, and connectivity of manually placed tracks.
% ============================================================

% ==== TRACK LIMIT CONSTRAINT ====
% Ensures the number of placed tracks does not exceed MAX_TRACKS.
% Counts only non-empty, non-initial, non-tunnel cells as placed tracks.
int: INIT_EMPTY = W*H - (N_INIT_POS + 2 * N_TUNNELS); % Initial empty count.
constraint
  INIT_EMPTY - sum(r in 1..H, c in 1..W)(
      bool2int(grid[r, c] == EMPTY)
    ) <= MAX_TRACKS; % Placed tracks ≤ limit.

% ==== INITIAL POSITION CONSTRAINT ====
% Pre-placed pieces from INIT_POS must appear exactly as specified.
constraint forall(i in 1..N_INIT_POS)(
    grid[INIT_POS[i].1, INIT_POS[i].2] = INIT_POS[i].3 % Fixed pieces.
);

% ==== TUNNEL PLACEMENT CONSTRAINT ====
% Tunnel entrance and exit must match their paired orientations.
constraint forall(i in 1..N_TUNNELS)(
    let {
      1..H: r1 = TUNNEL_PAIRS[i].1;
      1..W: c1 = TUNNEL_PAIRS[i].2;
      Dir: dir1 = TUNNEL_PAIRS[i].3;
      1..H: r2 = TUNNEL_PAIRS[i].4;
      1..W: c2 = TUNNEL_PAIRS[i].5;
      Dir: dir2 = TUNNEL_PAIRS[i].6;
    } in
  grid[r1, c1] = (if dir1 == TOP then TUNNEL_T elseif dir1 == DOWN then TUNNEL_D elseif dir1 == LEFT then TUNNEL_L else TUNNEL_R endif) /\
  grid[r2, c2] = (if dir2 == TOP then TUNNEL_T elseif dir2 == DOWN then TUNNEL_D elseif dir2 == LEFT then TUNNEL_L else TUNNEL_R endif) % Tunnels placed with correct orientation.
);

% ==== SPECIAL PIECES MUST BE PRE-PLACED ====
% Dswitches, Eswitches, and Tunnels cannot be placed dynamically.
constraint forall(r in 1..H, c in 1..W)(
    (grid[r, c] in UNPLACEABLE_PIECES)-> cell_is_init[r, c] % Only pre-placed allowed.
);

% ==== TRAIN PATH VALIDITY ====
% Trains move only on valid track (not EMPTY, not ROCK).
constraint forall(t in 1..N_TRAINS, i in 1..arrival_time[t])(
    grid[train_row[t, i], train_col[t, i]] != EMPTY /\
    grid[train_row[t, i], train_col[t, i]] != ROCK % Valid track required.
);

% ==== CONNECTIVITY CONSTRAINT ====
% Manually placed switches must have 3 neighbors; corners must have 2.
constraint forall(r in 1..H, c in 1..W)(
  (((grid[r, c] in SWITCHES_SET) \/ (grid[r, c] in CORNERS_SET)) /\
  not cell_is_init[r, c]) % Only if manually placed.
  ->
  sum(d in Dir)(
    let {
      0..H+1: nr = r + dr[d];
      0..W+1: nc = c + dc[d];
    } in
    bool2int(
      can_connect[grid[r, c], d] /\
      if nr >= 1 /\ nr <= H /\ nc >= 1 /\ nc <= W then
        can_connect[grid[nr, nc], opposite[d]] % Neighbors must match connectivity.
      else false endif
    )
  ) = (if grid[r, c] in SWITCHES_SET then 3 else 2 endif)
);

% ==== PLACED PIECE USAGE CONSTRAINT ====
% Manually placed pieces must be traversed by at least one train or decoy.
constraint forall(r in 1..H, c in 1..W)(
 grid[r,c] != EMPTY /\ not cell_is_init[r, c] -> exists(t in 1..N_TRAINS, i in 1..arrival_time[t])(train_row[t,i]=r /\ train_col[t,i]=c)
 \/ exists(d in 1..N_DECOYS, i in 1..MAX_TIME)(decoy_row[d,i]=r /\ decoy_col[d,i]=c) % Piece must be used.
);
