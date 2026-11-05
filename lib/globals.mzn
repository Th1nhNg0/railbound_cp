% ============================================================
% lib/globals.mzn - Global Lookup Tables & Helper Structures
% ============================================================
% Pre-computes the parameter tables the constraints index into.
%
% Board cells are addressed by a single row-major index
%   cell(r, c) = (r - 1) * W + c        (1..N_CELLS)
% which matches array1d(grid).  Vehicles are tracked by cell index, so every
% "same position" test is one integer comparison instead of a row/column pair,
% and every neighbour/tunnel lookup is a single 1-D table read.
% Requires lib/types.mzn and the data parameters to be declared first.
% ============================================================

% ==== DIRECTIONAL HELPERS ====
array[Dir] of int: dr = [ -1,  0,  1,  0 ]; % Row offsets [TOP, RIGHT, DOWN, LEFT].
array[Dir] of int: dc = [  0,  1,  0, -1 ]; % Column offsets [TOP, RIGHT, DOWN, LEFT].
array[Dir] of Dir: opposite = [ DOWN, LEFT, TOP, RIGHT ]; % Opposite direction for each entry.

% ==== CELL INDEXING ====
int: N_CELLS = H * W;
set of int: CELLS = 1..N_CELLS;
% Cell 0 is a virtual off-board sink: it always reads as EMPTY (impassable).
set of int: CELLS0 = 0..N_CELLS;

function int: cell(int: r, int: c) = (r - 1) * W + c;
function bool: on_board(int: r, int: c) = r >= 1 /\ r <= H /\ c >= 1 /\ c <= W;

array[CELLS] of 1..H: cell_row = [ (p - 1) div W + 1 | p in CELLS ];
array[CELLS] of 1..W: cell_col = [ (p - 1) mod W + 1 | p in CELLS ];

% nbr[p, d]: cell reached by leaving p towards d (0 when that leaves the board).
array[CELLS, Dir] of CELLS0: nbr = array2d(CELLS, Dir, [
  let { int: r = cell_row[p] + dr[d]; int: c = cell_col[p] + dc[d]; } in
  if on_board(r, c) then cell(r, c) else 0 endif
| p in CELLS, d in Dir ]);

int: TARGET_CELL = cell(TARGET.1, TARGET.2);

% ==== TUNNEL LOOKUP TABLES ====
% tunnel_pair_of[p]: index of the tunnel pair p belongs to (0 if none).
array[CELLS] of 0..N_TUNNELS: tunnel_pair_of = [
  sum(i in 1..N_TUNNELS where
      cell(TUNNEL_PAIRS[i].1, TUNNEL_PAIRS[i].2) = p \/
      cell(TUNNEL_PAIRS[i].4, TUNNEL_PAIRS[i].5) = p)(i)
| p in CELLS ];
array[CELLS] of bool: is_tunnel_cell = [ tunnel_pair_of[p] > 0 | p in CELLS ];

% tunnel_dest[p]: the paired tunnel cell (p itself for non-tunnel cells).
array[CELLS] of CELLS: tunnel_dest = [
  let { int: i = tunnel_pair_of[p]; } in
  if i = 0 then p
  elseif cell(TUNNEL_PAIRS[i].1, TUNNEL_PAIRS[i].2) = p then cell(TUNNEL_PAIRS[i].4, TUNNEL_PAIRS[i].5)
  else cell(TUNNEL_PAIRS[i].1, TUNNEL_PAIRS[i].2) endif
| p in CELLS ];

% tunnel_exit_dir[p]: direction a train leaves the paired tunnel end.
array[CELLS] of Dir: tunnel_exit_dir = [
  let { int: i = tunnel_pair_of[p]; } in
  if i = 0 then TOP
  elseif cell(TUNNEL_PAIRS[i].1, TUNNEL_PAIRS[i].2) = p then TUNNEL_PAIRS[i].6
  else TUNNEL_PAIRS[i].3 endif
| p in CELLS ];

% move_cell[p, e] / move_entry[p, e]: where a vehicle on p ends up when the
% track routes it out through side e.  Tunnels ignore e and teleport to the
% far side of their paired tunnel, so tunnels and normal track share one
% lookup and the movement constraints need no tunnel case split.
array[CELLS, Dir] of CELLS0: move_cell = array2d(CELLS, Dir, [
  if is_tunnel_cell[p] then nbr[tunnel_dest[p], tunnel_exit_dir[p]] else nbr[p, e] endif
| p in CELLS, e in Dir ]);
array[CELLS, Dir] of Dir: move_entry = array2d(CELLS, Dir, [
  if is_tunnel_cell[p] then opposite[tunnel_exit_dir[p]] else opposite[e] endif
| p in CELLS, e in Dir ]);

% ==== GATE / SWITCH / ACTIVATION METADATA ====
array[CELLS] of 0..N_GATES: gate_at = [
  sum(g in 1..N_GATES where cell(GATES[g].1, GATES[g].2) = p)(g) | p in CELLS ];
array[CELLS] of 0..N_DSWITCHES: dswitch_at = [
  sum(ds in 1..N_DSWITCHES where cell(DSWITCHES[ds].1, DSWITCHES[ds].2) = p)(ds) | p in CELLS ];
array[CELLS] of bool: is_activation_cell = [
  exists(a in 1..N_ACTIVATIONS)(cell(ACTIVATIONS[a].1, ACTIVATIONS[a].2) = p) | p in CELLS ];

% Exit-triggered switches are derived from the pre-placed pieces.
array[1..N_ESWITCHES] of CELLS: ESWITCH_CELLS =
  [ cell(INIT_POS[i].1, INIT_POS[i].2) | i in 1..N_INIT_POS where INIT_POS[i].3 in ESWITCHES_SET ];
array[CELLS] of 0..N_ESWITCHES: eswitch_at = [
  sum(es in 1..N_ESWITCHES where ESWITCH_CELLS[es] = p)(es) | p in CELLS ];

% Pre-placed piece at each cell (EMPTY when the cell is free).
array[CELLS] of Piece: init_piece = [
  let { array[int] of Piece: ps = [ INIT_POS[i].3 | i in 1..N_INIT_POS where cell(INIT_POS[i].1, INIT_POS[i].2) = p ]; } in
  if length(ps) > 0 then ps[1] else EMPTY endif
| p in CELLS ];

% ==== PRE-PLACED PIECE TRACKING ====
% Cells holding fixed pieces (INIT_POS entries or tunnel ends).
array[1..H, 1..W] of bool: cell_is_init = array2d(1..H, 1..W, [
  is_tunnel_cell[cell(r, c)] \/ exists(i in 1..N_INIT_POS)(INIT_POS[i].1 = r /\ INIT_POS[i].2 = c)
| r in 1..H, c in 1..W ]);

% ==== ROUTING PERMISSION TABLES ====
% can_enter[p, d]: true if a train entering from direction d can enter piece p.
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

% can_exit[p, d]: true if a train exiting piece p toward direction d can exit.
% This combines routing: a piece permits exit in direction d if it can reach d from entering from opposite.
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

% can_connect[p, d]: true if direction d is relevant to piece p (entry or exit possible).
% Used for routing validation and connectivity checks.
array[Piece, Dir] of bool: can_connect = array2d(Piece, Dir, [can_enter[p, d] \/ can_exit[p, d] | p in Piece, d in Dir]);

% exit_of[p, d]: Determines the exit direction when entering piece p from direction d.
% Core routing: determines where a train ends up after traversing piece p.
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

% ==== SWITCH TOGGLE MAPPING ====
% switch_toggle[p]: the routing a stateful switch takes while toggled.  Dynamic
% and exit-triggered switches swap their entry and straight-exit sides; every
% other piece maps to itself.
array[Piece] of Piece: switch_toggle = [
  if p = DSWITCH_T_D_R then DSWITCH_D_T_R elseif p = DSWITCH_D_T_R then DSWITCH_T_D_R
  elseif p = DSWITCH_T_D_L then DSWITCH_D_T_L elseif p = DSWITCH_D_T_L then DSWITCH_T_D_L
  elseif p = DSWITCH_R_L_T then DSWITCH_L_R_T elseif p = DSWITCH_L_R_T then DSWITCH_R_L_T
  elseif p = DSWITCH_R_L_D then DSWITCH_L_R_D elseif p = DSWITCH_L_R_D then DSWITCH_R_L_D
  elseif p = ESWITCH_T_D_R then ESWITCH_D_T_R elseif p = ESWITCH_D_T_R then ESWITCH_T_D_R
  elseif p = ESWITCH_T_D_L then ESWITCH_D_T_L elseif p = ESWITCH_D_T_L then ESWITCH_T_D_L
  elseif p = ESWITCH_R_L_T then ESWITCH_L_R_T elseif p = ESWITCH_L_R_T then ESWITCH_R_L_T
  elseif p = ESWITCH_R_L_D then ESWITCH_L_R_D elseif p = ESWITCH_L_R_D then ESWITCH_R_L_D
  else p endif
| p in Piece ];

% ==== REACHABILITY (shortest-path distances on the board) ====
% A superset of every move any vehicle can ever make: from cell p a vehicle
% may leave through any side (free cells) or through any side its fixed piece
% can route to in either switch state, then lands on move_cell[p, e] if that
% cell is not a rock and (when fixed) accepts entry from that side.  Shortest
% paths in this graph are therefore valid lower bounds on travel time.
function Piece: tunnel_piece(Dir: d) =
  if d = TOP then TUNNEL_T elseif d = RIGHT then TUNNEL_R elseif d = DOWN then TUNNEL_D else TUNNEL_L endif;

% fixed_piece[p]: piece fixed by the data (EMPTY marks a free cell).
array[CELLS] of Piece: fixed_piece = [
  if is_tunnel_cell[p] then
    tunnel_piece(let { int: i = tunnel_pair_of[p]; } in
      if cell(TUNNEL_PAIRS[i].1, TUNNEL_PAIRS[i].2) = p then TUNNEL_PAIRS[i].3 else TUNNEL_PAIRS[i].6 endif)
  else init_piece[p] endif
| p in CELLS ];

array[CELLS] of set of Piece: piece_states = [
  if fixed_piece[p] = EMPTY then PLACEABLE_SET diff {EMPTY}
  else {fixed_piece[p], switch_toggle[fixed_piece[p]]} endif
| p in CELLS ];

array[CELLS, Dir] of bool: may_move = array2d(CELLS, Dir, [
  let { int: q = move_cell[p, e]; } in
  q > 0 /\ fixed_piece[p] != ROCK /\ fixed_piece[q] != ROCK /\
  exists(x in piece_states[p], d in Dir)(exit_of[x, d] = e) /\
  exists(x in piece_states[q])(can_enter[x, move_entry[p, e]])
| p in CELLS, e in Dir ]);

array[CELLS] of set of CELLS: succs = [ { move_cell[p, e] | e in Dir where may_move[p, e] } | p in CELLS ];
array[CELLS] of set of CELLS: preds = [ { p | p in CELLS where q in succs[p] } | q in CELLS ];

int: UNREACHABLE = N_CELLS + MAX_TIME + 1;

% Bellman-Ford style relaxation to a fixpoint over the given neighbour sets.
function array[CELLS] of int: relax_dist(array[CELLS] of int: d, array[CELLS] of set of CELLS: nb) =
  let { array[CELLS] of int: d2 = [ min([d[q]] ++ [ d[n] + 1 | n in nb[q] ]) | q in CELLS ]; } in
  if d2 = d then d else relax_dist(d2, nb) endif;

% Distance from a vehicle start (row, col, heading): its first move is forced.
function array[CELLS] of int: dist_from_start(int: r, int: c, Dir: d0) =
  let { int: p0 = cell(r, c); int: p1 = nbr[p0, d0]; } in
  relax_dist([ if p = p0 then 0 elseif p = p1 then 1 else UNREACHABLE endif | p in CELLS ], preds);

array[1..N_TRAINS, CELLS] of int: train_dist_from_start = array2d(1..N_TRAINS, CELLS,
  [ dist_from_start(TRAINS[t].1, TRAINS[t].2, TRAINS[t].3)[p] | t in 1..N_TRAINS, p in CELLS ]);
array[1..N_DECOYS, CELLS] of int: decoy_dist_from_start = array2d(1..N_DECOYS, CELLS,
  [ dist_from_start(DECOYS[d].1, DECOYS[d].2, DECOYS[d].3)[p] | d in 1..N_DECOYS, p in CELLS ]);
% Distance from each cell to the target.
array[CELLS] of int: dist_to_target =
  relax_dist([ if p = TARGET_CELL then 0 else UNREACHABLE endif | p in CELLS ], succs);
