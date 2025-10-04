% ============================================================
% Global Lookup Tables
% ------------------------------------------------------------
% Derived helper structures for navigation, tunnel routing,
% and cell metadata. Requires parameters and input arrays to be
% declared beforehand.
% ============================================================

% Direction helpers for navigating the grid
array[Dir] of int: dr = [ -1,  0,  1,  0 ];
array[Dir] of int: dc = [  0,  1,  0, -1 ];
array[Dir] of Dir: opposite = [ DOWN, LEFT, TOP, RIGHT ];

% Tunnel lookup tables ------------------------------------------------------
array[1..H, 1..W] of tuple(int, int): tunnel_dest =
  array2d(1..H, 1..W, [
    let {
      int: idx_A = sum(i in 1..N_TUNNELS where
                       TUNNEL_PAIRS[i].1 = r /\ TUNNEL_PAIRS[i].2 = c)(i);
      int: idx_B = sum(i in 1..N_TUNNELS where
                       TUNNEL_PAIRS[i].4 = r /\ TUNNEL_PAIRS[i].5 = c)(i);
    } in
    if idx_A > 0 then
      (TUNNEL_PAIRS[idx_A].4, TUNNEL_PAIRS[idx_A].5)
    elseif idx_B > 0 then
      (TUNNEL_PAIRS[idx_B].1, TUNNEL_PAIRS[idx_B].2)
    else
      (0, 0)
    endif
  | r in 1..H, c in 1..W
  ]);

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
      1 % Default TOP for non-tunnel cells
    endif
  | r in 1..H, c in 1..W
  ]);

% Gate metadata -------------------------------------------------------------
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

% Dynamic switch metadata ---------------------------------------------------
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

% Station metadata ----------------------------------------------------------
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

% Pre-placed piece lookup ---------------------------------------------------
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

% Routing permissions -------------------------------------------------------
array[Piece, Dir] of bool: can_enter = array2d(Piece, Dir, [
  %              TOP    RIGHT  DOWN   LEFT
  false, false, false, false,  % EMPTY
  true,  false, true,  false,  % STRAIGHT_TD
  false, true,  false, true,   % STRAIGHT_RL
  true,  true,  false, false,  % CORNER_TR
  true,  false, false, true,   % CORNER_TL
  false, true,  true,  false,  % CORNER_DR
  false, false, true,  true,   % CORNER_DL
  true,  true,  true,  false,  % SWITCH_T_D_R
  true,  false, true,  true,   % SWITCH_T_D_L
  true,  true,  true,  false,  % SWITCH_D_T_R
  true,  false, true,  true,   % SWITCH_D_T_L
  true,  true,  false, true,   % SWITCH_R_L_T
  false, true,  true,  true,   % SWITCH_R_L_D
  true,  true,  false, true,   % SWITCH_L_R_T
  false, true,  true,  true,   % SWITCH_L_R_D
  true,  true,  true,  false,  % DSWITCH_T_D_R
  true,  false, true,  true,   % DSWITCH_T_D_L
  true,  true,  true,  false,  % DSWITCH_D_T_R
  true,  false, true,  true,   % DSWITCH_D_T_L
  true,  true,  false, true,   % DSWITCH_R_L_T
  false, true,  true,  true,   % DSWITCH_R_L_D
  true,  true,  false, true,   % DSWITCH_L_R_T
  false, true,  true,  true,   % DSWITCH_L_R_D
  true,  false, false, false,  % TUNNEL_T
  false, true,  false, false,  % TUNNEL_R
  false, false, true,  false,  % TUNNEL_D
  false, false, false, true    % TUNNEL_L
]);

array[Piece, Dir] of bool: can_exit = array2d(Piece, Dir, [
  %              TOP    RIGHT  DOWN   LEFT
  false, false, false, false,  % EMPTY
  true,  false, true,  false,  % STRAIGHT_TD
  false, true,  false, true,   % STRAIGHT_RL
  true,  true,  false, false,  % CORNER_TR
  true,  false, false, true,   % CORNER_TL
  false, true,  true,  false,  % CORNER_DR
  false, false, true,  true,   % CORNER_DL
  false, true,  true,  false,  % SWITCH_T_D_R
  false, false, true,  true,   % SWITCH_T_D_L
  true,  true,  false, false,  % SWITCH_D_T_R
  true,  false, false, true,   % SWITCH_D_T_L
  true,  false, false, true,   % SWITCH_R_L_T
  false, false, true,  true,   % SWITCH_R_L_D
  true,  true,  false, false,  % SWITCH_L_R_T
  false, true,  true,  false,  % SWITCH_L_R_D
  false, true,  true,  false,  % DSWITCH_T_D_R
  false, false, true,  true,   % DSWITCH_T_D_L
  true,  true,  false, false,  % DSWITCH_D_T_R
  true,  false, false, true,   % DSWITCH_D_T_L
  true,  false, false, true,   % DSWITCH_R_L_T
  false, false, true,  true,   % DSWITCH_R_L_D
  true,  true,  false, false,  % DSWITCH_L_R_T
  false, true,  true,  false,  % DSWITCH_L_R_D
  true,  false, false, false,  % TUNNEL_T
  false, true,  false, false,  % TUNNEL_R
  false, false, true,  false,  % TUNNEL_D
  false, false, false, true    % TUNNEL_L
]);

array[Piece, Dir] of Dir: exit_of = array2d(Piece, Dir, [
  %            TOP    RIGHT  DOWN   LEFT
  TOP,   TOP,   TOP,   TOP,   % EMPTY
  DOWN,  TOP,   TOP,   TOP,   % STRAIGHT_TD
  TOP,   LEFT,  TOP,   RIGHT, % STRAIGHT_RL
  RIGHT, TOP,   TOP,   TOP,   % CORNER_TR
  LEFT,  TOP,   TOP,   TOP,   % CORNER_TL
  TOP,   DOWN,  RIGHT, TOP,   % CORNER_DR
  TOP,   TOP,   LEFT,  DOWN,  % CORNER_DL
  DOWN,  DOWN,  RIGHT, TOP,   % SWITCH_T_D_R
  DOWN,  TOP,   LEFT,  DOWN,  % SWITCH_T_D_L
  RIGHT, TOP,   TOP,   TOP,   % SWITCH_D_T_R
  LEFT,  TOP,   TOP,   TOP,   % SWITCH_D_T_L
  LEFT,  LEFT,  TOP,   TOP,   % SWITCH_R_L_T
  TOP,   LEFT,  LEFT,  DOWN,  % SWITCH_R_L_D
  RIGHT, TOP,   TOP,   RIGHT, % SWITCH_L_R_T
  TOP,   DOWN,  RIGHT, RIGHT, % SWITCH_L_R_D
  DOWN,  DOWN,  RIGHT, TOP,   % DSWITCH_T_D_R
  DOWN,  TOP,   LEFT,  DOWN,  % DSWITCH_T_D_L
  RIGHT, TOP,   TOP,   TOP,   % DSWITCH_D_T_R
  LEFT,  TOP,   TOP,   TOP,   % DSWITCH_D_T_L
  LEFT,  LEFT,  TOP,   TOP,   % DSWITCH_R_L_T
  TOP,   LEFT,  LEFT,  DOWN,  % DSWITCH_R_L_D
  RIGHT, TOP,   TOP,   RIGHT, % DSWITCH_L_R_T
  TOP,   DOWN,  RIGHT, RIGHT, % DSWITCH_L_R_D
  TOP,   TOP,   TOP,   TOP,   % TUNNEL_T
  RIGHT, RIGHT, RIGHT, RIGHT, % TUNNEL_R
  DOWN,  DOWN,  DOWN,  DOWN,  % TUNNEL_D
  LEFT,  LEFT,  LEFT,  LEFT   % TUNNEL_L
]);
