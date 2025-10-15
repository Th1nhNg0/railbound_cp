% lib/globals.mzn
%
% Defines global lookup tables and derived data structures for the Railbound model.
%
% This file uses the parameters and input arrays (e.g., `TUNNEL_PAIRS`, `GATES`)
% to compute helper arrays and lookup tables. These structures are essential for
% efficient constraint formulation, providing pre-calculated information about
% grid features like tunnel destinations, gate locations, and switch indices.
% It requires `lib/types.mzn` to be included first.

% ============================================================
% Global Lookup Tables
% ============================================================

% --- Directional Helpers ---

% dr: row offset for each direction [TOP, RIGHT, DOWN, LEFT].
array[Dir] of int: dr = [ -1,  0,  1,  0 ];
% dc: column offset for each direction [TOP, RIGHT, DOWN, LEFT].
array[Dir] of int: dc = [  0,  1,  0, -1 ];
% opposite: lookup table for the opposing direction.
array[Dir] of Dir: opposite = [ DOWN, LEFT, TOP, RIGHT ];

% --- Tunnel Lookup Tables ---

% Maps each cell to its tunnel destination (row, col).
% Returns (0,0) if the cell is not a tunnel.
array[1..H, 1..W] of tuple(int, int): tunnel_dest =
  array2d(1..H, 1..W, [
    let {
      int: idx_A = sum(i in 1..N_TUNNELS where TUNNEL_PAIRS[i].1 = r /\ TUNNEL_PAIRS[i].2 = c)(i);
      int: idx_B = sum(i in 1..N_TUNNELS where TUNNEL_PAIRS[i].4 = r /\ TUNNEL_PAIRS[i].5 = c)(i);
    } in
    if idx_A > 0 then (TUNNEL_PAIRS[idx_A].4, TUNNEL_PAIRS[idx_A].5)
    elseif idx_B > 0 then (TUNNEL_PAIRS[idx_B].1, TUNNEL_PAIRS[idx_B].2)
    else (0, 0)
    endif
  | r in 1..H, c in 1..W
  ]);

% Maps each cell to its tunnel exit direction (as an integer).
% Defaults to 1 (TOP) for non-tunnels.
array[1..H, 1..W] of int: tunnel_exit_dir =
  array2d(1..H, 1..W, [
    let {
      int: idx_A = sum(i in 1..N_TUNNELS where TUNNEL_PAIRS[i].1 = r /\ TUNNEL_PAIRS[i].2 = c)(i);
      int: idx_B = sum(i in 1..N_TUNNELS where TUNNEL_PAIRS[i].4 = r /\ TUNNEL_PAIRS[i].5 = c)(i);
    } in
    if idx_A > 0 then enum2int(TUNNEL_PAIRS[idx_A].6)
    elseif idx_B > 0 then enum2int(TUNNEL_PAIRS[idx_B].3)
    else 1
    endif
  | r in 1..H, c in 1..W
  ]);

% --- Gate Metadata ---

% Upper bound for the gate index, ensuring it's at least 1.
int: GATE_INDEX_UPPER = if N_GATES = 0 then 1 else N_GATES endif;
% Maps each cell (r,c) to the index of the gate at that location. Returns 1 for cells without gates.
array[1..H, 1..W] of 1..GATE_INDEX_UPPER: gate_index_at =
  array2d(1..H, 1..W, [ let { int: g_idx = if N_GATES = 0 then 0 else sum(g in 1..N_GATES where GATES[g].1 = r /\ GATES[g].2 = c)(g) endif; } in if g_idx > 0 then g_idx else 1 endif | r in 1..H, c in 1..W ]);
% A boolean grid indicating if a cell contains a gate.
array[1..H, 1..W] of bool: cell_has_gate =
  array2d(1..H, 1..W, [ let { int: count = if N_GATES = 0 then 0 else sum(g in 1..N_GATES where GATES[g].1 = r /\ GATES[g].2 = c)(1) endif; } in count > 0 | r in 1..H, c in 1..W ]);

% --- Dynamic Switch Metadata ---

% Upper bound for the dynamic switch index, ensuring it's at least 1.
int: DSWITCH_INDEX_UPPER = if N_DSWITCHES = 0 then 1 else N_DSWITCHES endif;
% Maps each cell (r,c) to the index of the dynamic switch at that location. Returns 1 for cells without dynamic switches.
array[1..H, 1..W] of 1..DSWITCH_INDEX_UPPER: dswitch_index_at =
  array2d(1..H, 1..W, [ let { int: ds_idx = if N_DSWITCHES = 0 then 0 else sum(ds in 1..N_DSWITCHES where DSWITCHES[ds].1 = r /\ DSWITCHES[ds].2 = c)(ds) endif; } in if ds_idx > 0 then ds_idx else 1 endif | r in 1..H, c in 1..W ]);
% A boolean grid indicating if a cell contains a dynamic switch.
array[1..H, 1..W] of bool: cell_has_dswitch =
  array2d(1..H, 1..W, [ let { int: count = if N_DSWITCHES = 0 then 0 else sum(ds in 1..N_DSWITCHES where DSWITCHES[ds].1 = r /\ DSWITCHES[ds].2 = c)(1) endif; } in count > 0 | r in 1..H, c in 1..W ]);

% --- Exit-triggered Switch Metadata ---

% Array of coordinates for all exit-triggered switches, derived from INIT_POS.
array[1..N_ESWITCHES] of tuple(int, int): ESWITCHES_DERIVED =
  [(INIT_POS[i].1, INIT_POS[i].2) | i in 1..N_INIT_POS where INIT_POS[i].3 in ESWITCHES_SET];
% Upper bound for the exit-triggered switch index, ensuring it's at least 1.
int: ESWITCH_INDEX_UPPER = if N_ESWITCHES = 0 then 1 else N_ESWITCHES endif;
% Maps each cell (r,c) to the index of the exit-triggered switch at that location. Returns 1 for cells without exit-triggered switches.
array[1..H, 1..W] of 1..ESWITCH_INDEX_UPPER: eswitch_index_at =
  array2d(1..H, 1..W, [ let { int: es_idx = if N_ESWITCHES = 0 then 0 else sum(es in 1..N_ESWITCHES where ESWITCHES_DERIVED[es].1 = r /\ ESWITCHES_DERIVED[es].2 = c)(es) endif; } in if es_idx > 0 then es_idx else 1 endif | r in 1..H, c in 1..W ]);
% A boolean grid indicating if a cell contains an exit-triggered switch.
array[1..H, 1..W] of bool: cell_has_eswitch =
  array2d(1..H, 1..W, [ let { int: count = if N_ESWITCHES = 0 then 0 else sum(es in 1..N_ESWITCHES where ESWITCHES_DERIVED[es].1 = r /\ ESWITCHES_DERIVED[es].2 = c)(1) endif; } in count > 0 | r in 1..H, c in 1..W ]);

% --- Station Metadata ---

% Upper bound for the station index, ensuring it's at least 1.
int: STATION_INDEX_UPPER = if N_STATIONS = 0 then 1 else N_STATIONS endif;
% Maps each cell (r,c) to the index of the station at that location. Returns 1 for cells without stations.
array[1..H, 1..W] of 1..STATION_INDEX_UPPER: station_index_at =
  array2d(1..H, 1..W, [ let { int: st_idx = if N_STATIONS = 0 then 0 else sum(st in 1..N_STATIONS where STATIONS[st].1 = r /\ STATIONS[st].2 = c)(st) endif; } in if st_idx > 0 then st_idx else 1 endif | r in 1..H, c in 1..W ]);
% A boolean grid indicating if a cell contains a station.
array[1..H, 1..W] of bool: cell_has_station =
  array2d(1..H, 1..W, [ let { int: count = if N_STATIONS = 0 then 0 else sum(st in 1..N_STATIONS where STATIONS[st].1 = r /\ STATIONS[st].2 = c)(1) endif; } in count > 0 | r in 1..H, c in 1..W ]);

% --- Pre-placed Piece Lookup ---

% A boolean grid indicating if a cell contains a pre-placed, unmovable piece (from INIT_POS or tunnels).
  array[1..H, 1..W] of bool: cell_is_init =
    array2d(1..H, 1..W, [ let { 
      int: init_count = if N_INIT_POS = 0 then 0 else sum(i in 1..N_INIT_POS where INIT_POS[i].1 = r /\ INIT_POS[i].2 = c)(1) endif;
      int: tunnel_count = if N_TUNNELS = 0 then 0 else sum(i in 1..N_TUNNELS where (TUNNEL_PAIRS[i].1 = r /\ TUNNEL_PAIRS[i].2 = c) \/ (TUNNEL_PAIRS[i].4 = r /\ TUNNEL_PAIRS[i].5 = c))(1) endif;
    } in init_count > 0 \/ tunnel_count > 0 | r in 1..H, c in 1..W ]);
% --- Routing Permission Tables ---

% can_enter[p, d] is true if a train can enter a piece `p` from direction `d`.
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
  true,  true,  true,  false,  % ESWITCH_T_D_R
  true,  false, true,  true,   % ESWITCH_T_D_L
  true,  true,  true,  false,  % ESWITCH_D_T_R
  true,  false, true,  true,   % ESWITCH_D_T_L
  true,  true,  false, true,   % ESWITCH_R_L_T
  false, true,  true,  true,   % ESWITCH_R_L_D
  true,  true,  false, true,   % ESWITCH_L_R_T
  false, true,  true,  true,   % ESWITCH_L_R_D
  true,  false, false, false,  % TUNNEL_T
  false, true,  false, false,  % TUNNEL_R
  false, false, true,  false,  % TUNNEL_D
  false, false, false, true,   % TUNNEL_L
  false, false, false, false   % ROCK
]);

% can_exit[p, d] is true if a train can exit a piece `p` towards direction `d`.
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
  false, true,  true,  false,  % ESWITCH_T_D_R
  false, false, true,  true,   % ESWITCH_T_D_L
  true,  true,  false, false,  % ESWITCH_D_T_R
  true,  false, false, true,   % ESWITCH_D_T_L
  true,  false, false, true,   % ESWITCH_R_L_T
  false, false, true,  true,   % ESWITCH_R_L_D
  true,  true,  false, false,  % ESWITCH_L_R_T
  false, true,  true,  false,  % ESWITCH_L_R_D
  true,  false, false, false,  % TUNNEL_T
  false, true,  false, false,  % TUNNEL_R
  false, false, true,  false,  % TUNNEL_D
  false, false, false, true,   % TUNNEL_L
  false, false, false, false   % ROCK
]);

% can_connect[p, d] is true if a train can connect to piece `p` from direction `d`.
% This combines can_enter and can_exit: a piece can be connected from direction d
% if it can either enter from d or exit towards d.
array[Piece, Dir] of bool: can_connect = array2d(Piece, Dir, [can_enter[p, d] \/ can_exit[p, d] | p in Piece, d in Dir]);

% exit_of[p, d] determines the exit direction when entering piece `p` from direction `d`.
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
  DOWN,  DOWN,  RIGHT, TOP,   % ESWITCH_T_D_R
  DOWN,  TOP,   LEFT,  DOWN,  % ESWITCH_T_D_L
  RIGHT, TOP,   TOP,   TOP,   % ESWITCH_D_T_R
  LEFT,  TOP,   TOP,   TOP,   % ESWITCH_D_T_L
  LEFT,  LEFT,  TOP,   TOP,   % ESWITCH_R_L_T
  TOP,   LEFT,  LEFT,  DOWN,  % ESWITCH_R_L_D
  RIGHT, TOP,   TOP,   RIGHT, % ESWITCH_L_R_T
  TOP,   DOWN,  RIGHT, RIGHT, % ESWITCH_L_R_D
  TOP,   TOP,   TOP,   TOP,   % TUNNEL_T
  RIGHT, RIGHT, RIGHT, RIGHT, % TUNNEL_R
  DOWN,  DOWN,  DOWN,  DOWN,  % TUNNEL_D
  LEFT,  LEFT,  LEFT,  LEFT,  % TUNNEL_L
  TOP,   TOP,   TOP,   TOP    % ROCK
]);

% --- Dynamic Switch Toggle Mapping ---
% Maps a DSWITCH piece to its toggled counterpart.
array[Piece] of Piece: dswitch_toggle = [
  EMPTY,         % EMPTY
  STRAIGHT_TD,   % STRAIGHT_TD
  STRAIGHT_RL,   % STRAIGHT_RL
  CORNER_TR,     % CORNER_TR
  CORNER_TL,     % CORNER_TL
  CORNER_DR,     % CORNER_DR
  CORNER_DL,     % CORNER_DL
  SWITCH_T_D_R,  % SWITCH_T_D_R
  SWITCH_T_D_L,  % SWITCH_T_D_L
  SWITCH_D_T_R,  % SWITCH_D_T_R
  SWITCH_D_T_L,  % SWITCH_D_T_L
  SWITCH_R_L_T,  % SWITCH_R_L_T
  SWITCH_R_L_D,  % SWITCH_R_L_D
  SWITCH_L_R_T,  % SWITCH_L_R_T
  SWITCH_L_R_D,  % SWITCH_L_R_D
  DSWITCH_D_T_R, % DSWITCH_T_D_R -> DSWITCH_D_T_R
  DSWITCH_D_T_L, % DSWITCH_T_D_L -> DSWITCH_D_T_L
  DSWITCH_T_D_R, % DSWITCH_D_T_R -> DSWITCH_T_D_R
  DSWITCH_T_D_L, % DSWITCH_D_T_L -> DSWITCH_T_D_L
  DSWITCH_L_R_T, % DSWITCH_R_L_T -> DSWITCH_L_R_T
  DSWITCH_L_R_D, % DSWITCH_R_L_D -> DSWITCH_L_R_D
  DSWITCH_R_L_T, % DSWITCH_L_R_T -> DSWITCH_R_L_T
  DSWITCH_R_L_D, % DSWITCH_L_R_D -> DSWITCH_R_L_D
  ESWITCH_T_D_R, % ESWITCH_T_D_R
  ESWITCH_T_D_L, % ESWITCH_T_D_L
  ESWITCH_D_T_R, % ESWITCH_D_T_R
  ESWITCH_D_T_L, % ESWITCH_D_T_L
  ESWITCH_R_L_T, % ESWITCH_R_L_T
  ESWITCH_R_L_D, % ESWITCH_R_L_D
  ESWITCH_L_R_T, % ESWITCH_L_R_T
  ESWITCH_L_R_D, % ESWITCH_L_R_D
  TUNNEL_T,      % TUNNEL_T
  TUNNEL_R,      % TUNNEL_R
  TUNNEL_D,      % TUNNEL_D
  TUNNEL_L,      % TUNNEL_L
  ROCK           % ROCK
];

% --- Exit-triggered Switch Toggle Mapping ---
% Maps an ESWITCH piece to its toggled counterpart.
array[Piece] of Piece: eswitch_toggle = [
  EMPTY,         % EMPTY
  STRAIGHT_TD,   % STRAIGHT_TD
  STRAIGHT_RL,   % STRAIGHT_RL
  CORNER_TR,     % CORNER_TR
  CORNER_TL,     % CORNER_TL
  CORNER_DR,     % CORNER_DR
  CORNER_DL,     % CORNER_DL
  SWITCH_T_D_R,  % SWITCH_T_D_R
  SWITCH_T_D_L,  % SWITCH_T_D_L
  SWITCH_D_T_R,  % SWITCH_D_T_R
  SWITCH_D_T_L,  % SWITCH_D_T_L
  SWITCH_R_L_T,  % SWITCH_R_L_T
  SWITCH_R_L_D,  % SWITCH_R_L_D
  SWITCH_L_R_T,  % SWITCH_L_R_T
  SWITCH_L_R_D,  % SWITCH_L_R_D
  DSWITCH_T_D_R, % DSWITCH_T_D_R
  DSWITCH_T_D_L, % DSWITCH_T_D_L
  DSWITCH_D_T_R, % DSWITCH_D_T_R
  DSWITCH_D_T_L, % DSWITCH_D_T_L
  DSWITCH_R_L_T, % DSWITCH_R_L_T
  DSWITCH_R_L_D, % DSWITCH_R_L_D
  DSWITCH_L_R_T, % DSWITCH_L_R_T
  DSWITCH_L_R_D, % DSWITCH_L_R_D
  ESWITCH_D_T_R, % ESWITCH_T_D_R -> ESWITCH_D_T_R
  ESWITCH_D_T_L, % ESWITCH_T_D_L -> ESWITCH_D_T_L
  ESWITCH_T_D_R, % ESWITCH_D_T_R -> ESWITCH_T_D_R
  ESWITCH_T_D_L, % ESWITCH_D_T_L -> ESWITCH_T_D_L
  ESWITCH_L_R_T, % ESWITCH_R_L_T -> ESWITCH_L_R_T
  ESWITCH_L_R_D, % ESWITCH_R_L_D -> ESWITCH_L_R_D
  ESWITCH_R_L_T, % ESWITCH_L_R_T -> ESWITCH_R_L_T
  ESWITCH_R_L_D, % ESWITCH_L_R_D -> ESWITCH_R_L_D
  TUNNEL_T,      % TUNNEL_T
  TUNNEL_R,      % TUNNEL_R
  TUNNEL_D,      % TUNNEL_D
  TUNNEL_L,      % TUNNEL_L
  ROCK           % ROCK
];

% Function to get the effective piece type for a DSWITCH based on its toggle state.
function var Piece: dswitch_effective_piece(var Piece: base_piece, var bool: toggled) =
  if toggled then dswitch_toggle[base_piece] else base_piece endif;

% Function to get the effective piece type for an ESWITCH based on its toggle state.
function var Piece: eswitch_effective_piece(var Piece: base_piece, var bool: toggled) =
  if toggled then eswitch_toggle[base_piece] else base_piece endif;

% --- Position Utilities ---

% Helper function to get effective position (considering tunnels)
function var tuple(1..W, 1..H): get_effective_pos(var 1..W: r, var 1..H: c) = 
    if grid[r, c] in TUNNELS_SET then tunnel_dest[r, c] else (r, c) endif;