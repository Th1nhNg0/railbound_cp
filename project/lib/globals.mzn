% ============================================================
% GLOBAL PARAMETERS, CONSTANTS, AND HELPER PREDICATES
%
% This file defines global data structures, pre-computed
% lookup tables, and utility predicates used throughout the model.
% ============================================================

% ============================================================
% TUNNEL LOOKUP ARRAYS
% ============================================================
% Pre-compute tunnel destinations and exit directions for efficiency.
% These arrays allow for quick lookups of tunnel behavior without
% iterating through the TUNNEL_PAIRS array during constraint solving.

% tunnel_dest[r,c] = (dest_row, dest_col) if (r,c) has a tunnel, else (0,0)
array[1..H, 1..W] of tuple(int, int): tunnel_dest =
  array2d(1..H, 1..W, [
    let {
      % Find if this cell is endpoint A or B of any tunnel pair
      int: idx_A = sum(i in 1..N_TUNNELS where
                       TUNNEL_PAIRS[i].1 = r /\ TUNNEL_PAIRS[i].2 = c)(i);
      int: idx_B = sum(i in 1..N_TUNNELS where
                       TUNNEL_PAIRS[i].4 = r /\ TUNNEL_PAIRS[i].5 = c)(i);
    } in
    if idx_A > 0 then
      (TUNNEL_PAIRS[idx_A].4, TUNNEL_PAIRS[idx_A].5)  % A -> B
    elseif idx_B > 0 then
      (TUNNEL_PAIRS[idx_B].1, TUNNEL_PAIRS[idx_B].2)  % B -> A
    else
      (0, 0)  % No tunnel
    endif
  | r in 1..H, c in 1..W
  ]);

% tunnel_exit_dir[r,c] = exit direction at destination tunnel
array[1..H, 1..W] of int: tunnel_exit_dir =
  array2d(1..H, 1..W, [
    let {
      int: idx_A = sum(i in 1..N_TUNNELS where
                       TUNNEL_PAIRS[i].1 = r /\ TUNNEL_PAIRS[i].2 = c)(i);
      int: idx_B = sum(i in 1..N_TUNNELS where
                       TUNNEL_PAIRS[i].4 = r /\ TUNNEL_PAIRS[i].5 = c)(i);
    } in
    if idx_A > 0 then
      enum2int(TUNNEL_PAIRS[idx_A].6)
    elseif idx_B > 0 then
      enum2int(TUNNEL_PAIRS[idx_B].3)
    else
      1  % Default to TOP (unused for non-tunnel cells)
    endif
  | r in 1..H, c in 1..W
  ]);

% ============================================================
% HELPER CONSTANTS
% ============================================================

% --- Direction Helpers ---
% Arrays for calculating adjacent cell coordinates based on direction.
array[Dir] of int: dr = [ -1,  0,  1,  0 ];  % Row deltas: TOP, RIGHT, DOWN, LEFT
array[Dir] of int: dc = [  0,  1,  0, -1 ];  % Col deltas
array[Dir] of Dir: opposite = [ DOWN, LEFT, TOP, RIGHT ];

% --- Precomputed cell lookups for faster propagation ---
% These arrays pre-calculate information about grid cells, such as whether
% they contain a gate, dswitch, or station, to avoid redundant
% calculations within constraints.

int: GATE_INDEX_UPPER = if N_GATES = 0 then 1 else N_GATES endif;
array[1..H, 1..W] of 1..GATE_INDEX_UPPER: gate_index_at =
  array2d(1..H, 1..W, [
    let {
      int: g_idx = if N_GATES = 0 then 0
                   else sum(g in 1..N_GATES where GATES[g].1 = r /\ GATES[g].2 = c)(g)
                   endif;
    } in
      if g_idx > 0 then g_idx else 1 endif
  | r in 1..H, c in 1..W
  ]);

array[1..H, 1..W] of bool: cell_has_gate =
  array2d(1..H, 1..W, [
    let {
      int: count = if N_GATES = 0 then 0
                   else sum(g in 1..N_GATES where GATES[g].1 = r /\ GATES[g].2 = c)(1)
                   endif;
    } in
      count > 0
  | r in 1..H, c in 1..W
  ]);

int: DSWITCH_INDEX_UPPER = if N_DSWITCHES = 0 then 1 else N_DSWITCHES endif;
array[1..H, 1..W] of 1..DSWITCH_INDEX_UPPER: dswitch_index_at =
  array2d(1..H, 1..W, [
    let {
      int: ds_idx = if N_DSWITCHES = 0 then 0
                    else sum(ds in 1..N_DSWITCHES where DSWITCHES[ds].1 = r /\ DSWITCHES[ds].2 = c)(ds)
                    endif;
    } in
      if ds_idx > 0 then ds_idx else 1 endif
  | r in 1..H, c in 1..W
  ]);

array[1..H, 1..W] of bool: cell_has_dswitch =
  array2d(1..H, 1..W, [
    let {
      int: count = if N_DSWITCHES = 0 then 0
                   else sum(ds in 1..N_DSWITCHES where DSWITCHES[ds].1 = r /\ DSWITCHES[ds].2 = c)(1)
                   endif;
    } in
      count > 0
  | r in 1..H, c in 1..W
  ]);

int: STATION_INDEX_UPPER = if N_STATIONS = 0 then 1 else N_STATIONS endif;
array[1..H, 1..W] of 1..STATION_INDEX_UPPER: station_index_at =
  array2d(1..H, 1..W, [
    let {
      int: st_idx = if N_STATIONS = 0 then 0
                    else sum(st in 1..N_STATIONS where STATIONS[st].1 = r /\ STATIONS[st].2 = c)(st)
                    endif;
    } in
      if st_idx > 0 then st_idx else 1 endif
  | r in 1..H, c in 1..W
  ]);

array[1..H, 1..W] of bool: cell_has_station =
  array2d(1..H, 1..W, [
    let {
      int: count = if N_STATIONS = 0 then 0
                   else sum(st in 1..N_STATIONS where STATIONS[st].1 = r /\ STATIONS[st].2 = c)(1)
                   endif;
    } in
      count > 0
  | r in 1..H, c in 1..W
  ]);

array[1..H, 1..W] of bool: cell_is_init =
  array2d(1..H, 1..W, [
    let {
      int: count = if N_INIT_POS = 0 then 0
                   else sum(i in 1..N_INIT_POS where INIT_POS[i].1 = r /\ INIT_POS[i].2 = c)(1)
                   endif;
    } in
      count > 0
  | r in 1..H, c in 1..W
  ]);

% --- Piece Category Sets ---
% Defines sets of pieces for easier constraint definition.
set of Piece: STRAIGHTS = { STRAIGHT_TD, STRAIGHT_RL };
set of Piece: CORNERS   = { CORNER_TR, CORNER_TL, CORNER_DR, CORNER_DL };
set of Piece: SWITCHES  = { SWITCH_T_D_R, SWITCH_T_D_L, SWITCH_D_T_R, SWITCH_D_T_L,
                            SWITCH_R_L_T, SWITCH_R_L_D, SWITCH_L_R_T, SWITCH_L_R_D };
set of Piece: DSWITCHES_SET = { DSWITCH_T_D_R, DSWITCH_T_D_L, DSWITCH_D_T_R, DSWITCH_D_T_L,
                                DSWITCH_R_L_T, DSWITCH_R_L_D, DSWITCH_L_R_T, DSWITCH_L_R_D };
set of Piece: TUNNELS   = { TUNNEL_T, TUNNEL_R, TUNNEL_D, TUNNEL_L };

% --- Utility Predicate ---
% Checks if a given (r, c) coordinate is within the grid boundaries.
predicate in_bounds(int: r, int: c) =
  r >= 1 /\ r <= H /\ c >= 1 /\ c <= W;