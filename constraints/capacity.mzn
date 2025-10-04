% ============================================================
% Track Placement & Capacity
% ------------------------------------------------------------
% Structural constraints on track pieces, including adherence
% to pre-placed tracks, tunnel definitions, and the global
% track budget.
% ============================================================

% 7) Respect pre-placed pieces
constraint forall(p in INIT_POS) (
  grid[p.1, p.2] == p.3
);

% 8) Place tunnel pieces on the grid based on TUNNEL_PAIRS
constraint forall(i in 1..N_TUNNELS) (
  let {
    int: r_A = TUNNEL_PAIRS[i].1;
    int: c_A = TUNNEL_PAIRS[i].2;
    Dir: dir_A = TUNNEL_PAIRS[i].3;
    int: r_B = TUNNEL_PAIRS[i].4;
    int: c_B = TUNNEL_PAIRS[i].5;
    Dir: dir_B = TUNNEL_PAIRS[i].6;
  } in
  grid[r_A, c_A] =
    if dir_A == TOP then TUNNEL_T
    elseif dir_A == RIGHT then TUNNEL_R
    elseif dir_A == DOWN then TUNNEL_D
    else TUNNEL_L endif
  /\
  grid[r_B, c_B] =
    if dir_B == TOP then TUNNEL_T
    elseif dir_B == RIGHT then TUNNEL_R
    elseif dir_B == DOWN then TUNNEL_D
    else TUNNEL_L endif
);

% 9) Track budget: limit non-EMPTY pieces beyond pre-placed and tunnels
constraint
  let {
    var int: total_placed_tracks = sum(p in grid where p != EMPTY)(1);
    int: init_tracks = sum(p in INIT_POS where p.3 != EMPTY)(1);
    int: init_tunnels = sum(i in 1..N_TUNNELS)(2);
  } in
  total_placed_tracks - init_tracks - init_tunnels <= MAX_TRACKS;

% 10) Connectivity validation
constraint forall(r in 1..H, c in 1..W) (
  let { var Piece: p = grid[r, c]; } in
  if p in (CORNERS union SWITCHES union DSWITCHES_SET union STRAIGHTS) /\
     not (cell_is_init[r, c] \/
          (p in STRAIGHTS /\ r = TARGET.1 /\ c = TARGET.2)) then
    forall(d in Dir where can_enter[p, d]) (
      let { int: rr = r + dr[d]; int: cc = c + dc[d]; } in
      in_bounds(rr, cc) /\ grid[rr, cc] != EMPTY /\
      (grid[rr, cc] in TUNNELS \/ can_enter[grid[rr, cc], opposite[d]])
    )
  endif
);

% 11) Restrict tunnels to only those defined in TUNNEL_PAIRS
constraint forall(r in 1..H, c in 1..W) (
  let { var Piece: p = grid[r, c] } in
  if p in TUNNELS then
    let { tuple(int, int): dest = tunnel_dest[r, c]; } in dest.1 > 0
  endif
);

% 11b) Restrict DSWITCHes to only those defined in DSWITCHES array
constraint forall(r in 1..H, c in 1..W) (
  let { var Piece: p = grid[r, c] } in
  if p in DSWITCHES_SET then
    cell_has_dswitch[r, c]
  endif
);
