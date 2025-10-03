% ============================================================
% Train Routing CSP - Railbound Puzzle Solver
% ============================================================
% Place track pieces on H×W grid for N trains to reach target sequentially,
% without collisions, under track budget.
%
% Key Features:
% - Support for straights, corners, switches, dynamic switches, and tunnels
% - Dynamic switches (DSWITCHes) that reconfigure when activated
% - Gates and activations for blocking and triggering mechanisms
% - Directional entry restrictions for tunnels
% - Sequential train arrival requirements
% - Collision avoidance (cells and position swaps)
% - Track budget constraints
% - Cost minimization to prefer simpler pieces
%
% Conventions:
% - Rows: 1..H (top to bottom), Cols: 1..W (left to right)
% - train_dir[t,time]: entry direction into cell at time step
% - TRAINS[t]: (row, col, initial_exit_direction) for train t
% ============================================================

include "globals.mzn";

% ============================================================
% PARAMETERS
% ============================================================

% --- Grid Dimensions ---
int: W;  % Grid width  (number of columns)
int: H;  % Grid height (number of rows)

% --- Simulation Settings ---
int: N_TRAINS;   % Number of trains
int: MAX_TIME;   % Max number of discrete time steps
int: MAX_TRACKS; % Max number of non-EMPTY pieces that can be placed

% --- Target Location ---
% Unique sink cell all trains must reach, in order
tuple(int, int): TARGET;

% --- Pre-placed Elements ---
int: N_INIT_POS;  % Number of pre-placed pieces
int: N_TUNNELS;   % Number of tunnel pairs (set to 0 if no tunnels)

% --- Gates and Activations ---
int: N_GATES;        % Number of gates
int: N_ACTIVATIONS;  % Number of activations

% --- Dynamic Switches ---
int: N_DSWITCHES;    % Number of dynamic switches

% ============================================================
% TUNNEL LOOKUP ARRAYS
% ============================================================
% Pre-compute tunnel destinations and exit directions for efficiency

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
% TYPE DEFINITIONS
% ============================================================

% --- Directions ---
enum Dir = { TOP, RIGHT, DOWN, LEFT };

% --- Type Aliases for Clarity ---
type Pos = tuple(int, int, Piece);           % (row, col, piece)
type TrainStart = tuple(int, int, Dir);       % (row, col, initial_exit_dir)
type TunnelPair = tuple(int, int, Dir,        % (row_A, col_A, exit_dir_A,
                        int, int, Dir);       %  row_B, col_B, exit_dir_B)
type Gate = tuple(int, int, int, bool);      % (row, col, gate_id, initially_open)
type Activation = tuple(int, int, int);      % (row, col, gate_id)
type DSwitch = tuple(int, int, int);         % (row, col, dswitch_id)

% --- Track Piece Types ---
% Visual guide:
%   STRAIGHT_TD : │ (connects TOP<->DOWN)
%   STRAIGHT_RL : ─ (connects RIGHT<->LEFT)
%   CORNER_*    : └┘┌┐ (two-way, 90° corners)
%   SWITCH_*    : 3-way with one 'single' end and two exits
%                 Naming: SWITCH_<SingleEnd>_<StraightEnd>_<CurveEnd>
%   TUNNEL_*    : Teleport entry (paired with another tunnel)
enum Piece = {
  EMPTY,
  
  % Straights
  STRAIGHT_TD,  % │ connects TOP <-> DOWN
  STRAIGHT_RL,  % ─ connects RIGHT <-> LEFT
  
  % Corners
  CORNER_TR,    % └ connects TOP <-> RIGHT
  CORNER_TL,    % ┘ connects TOP <-> LEFT
  CORNER_DR,    % ┌ connects DOWN <-> RIGHT
  CORNER_DL,    % ┐ connects DOWN <-> LEFT
  
  % Switches: SWITCH_<Single>_<Straight>_<Curve>
  % Rule: Single->Straight, Straight->Curve, Curve->Straight
  SWITCH_T_D_R,  % TOP->DOWN, DOWN->RIGHT, RIGHT->DOWN
  SWITCH_T_D_L,  % TOP->DOWN, DOWN->LEFT, LEFT->DOWN
  SWITCH_D_T_R,  % DOWN->TOP, TOP->RIGHT, RIGHT->TOP
  SWITCH_D_T_L,  % DOWN->TOP, TOP->LEFT, LEFT->TOP
  SWITCH_R_L_T,  % RIGHT->LEFT, LEFT->TOP, TOP->LEFT
  SWITCH_R_L_D,  % RIGHT->LEFT, LEFT->DOWN, DOWN->LEFT
  SWITCH_L_R_T,  % LEFT->RIGHT, RIGHT->TOP, TOP->RIGHT
  SWITCH_L_R_D,  % LEFT->RIGHT, RIGHT->DOWN, DOWN->RIGHT
  
  % Dynamic Switches: DSWITCH_<Single>_<Straight>_<Curve>
  % Can swap Single and Straight connections when activated
  DSWITCH_T_D_R,  % TOP->DOWN, DOWN->RIGHT, RIGHT->DOWN (initial state)
  DSWITCH_T_D_L,  % TOP->DOWN, DOWN->LEFT, LEFT->DOWN
  DSWITCH_D_T_R,  % DOWN->TOP, TOP->RIGHT, RIGHT->TOP
  DSWITCH_D_T_L,  % DOWN->TOP, TOP->LEFT, LEFT->TOP
  DSWITCH_R_L_T,  % RIGHT->LEFT, LEFT->TOP, TOP->LEFT
  DSWITCH_R_L_D,  % RIGHT->LEFT, LEFT->DOWN, DOWN->LEFT
  DSWITCH_L_R_T,  % LEFT->RIGHT, RIGHT->TOP, TOP->RIGHT
  DSWITCH_L_R_D,  % LEFT->RIGHT, RIGHT->DOWN, DOWN->RIGHT
  
  % Tunnels: TUNNEL_X means enter from X, paired tunnel exits in X direction
  TUNNEL_T,     % Enter from TOP only
  TUNNEL_R,     % Enter from RIGHT only
  TUNNEL_D,     % Enter from DOWN only
  TUNNEL_L      % Enter from LEFT only
};

% ============================================================
% INPUT DATA
% ============================================================

array[1..N_TRAINS] of TrainStart: TRAINS;      % Train starting positions
array[1..N_INIT_POS] of Pos: INIT_POS;         % Pre-placed pieces
array[1..N_TUNNELS] of TunnelPair: TUNNEL_PAIRS; % Tunnel pair definitions
array[1..N_GATES] of Gate: GATES;              % Gate definitions
array[1..N_ACTIVATIONS] of Activation: ACTIVATIONS; % Activation cell definitions
array[1..N_DSWITCHES] of DSwitch: DSWITCHES;   % Dynamic switch definitions

% ============================================================
% HELPER CONSTANTS
% ============================================================

% --- Direction Helpers ---
array[Dir] of int: dr = [ -1,  0,  1,  0 ];  % Row deltas: TOP, RIGHT, DOWN, LEFT
array[Dir] of int: dc = [  0,  1,  0, -1 ];  % Col deltas
array[Dir] of Dir: opposite = [ DOWN, LEFT, TOP, RIGHT ];

% --- Precomputed cell lookups for faster propagation ---
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
set of Piece: STRAIGHTS = { STRAIGHT_TD, STRAIGHT_RL };
set of Piece: CORNERS   = { CORNER_TR, CORNER_TL, CORNER_DR, CORNER_DL };
set of Piece: SWITCHES  = { SWITCH_T_D_R, SWITCH_T_D_L, SWITCH_D_T_R, SWITCH_D_T_L,
                            SWITCH_R_L_T, SWITCH_R_L_D, SWITCH_L_R_T, SWITCH_L_R_D };
set of Piece: DSWITCHES_SET = { DSWITCH_T_D_R, DSWITCH_T_D_L, DSWITCH_D_T_R, DSWITCH_D_T_L,
                                DSWITCH_R_L_T, DSWITCH_R_L_D, DSWITCH_L_R_T, DSWITCH_L_R_D };
set of Piece: TUNNELS   = { TUNNEL_T, TUNNEL_R, TUNNEL_D, TUNNEL_L };

% --- Utility Predicate ---
predicate in_bounds(int: r, int: c) = 
  r >= 1 /\ r <= H /\ c >= 1 /\ c <= W;

% ============================================================
% PIECE ROUTING TABLES
% ============================================================
% Define which directions can enter/exit each piece type,
% and where trains go based on entry direction

% --- Entry Permissions ---
% can_enter[piece, dir] = true if piece can be entered from dir
array[Piece, Dir] of bool: can_enter = array2d(Piece, Dir, [
  %              TOP    RIGHT  DOWN   LEFT
  % EMPTY
                 false, false, false, false,
  % STRAIGHT_TD
                 true,  false, true,  false,
  % STRAIGHT_RL
                 false, true,  false, true,
  % CORNER_TR (TOP<->RIGHT)
                 true,  true,  false, false,
  % CORNER_TL (TOP<->LEFT)
                 true,  false, false, true,
  % CORNER_DR (DOWN<->RIGHT)
                 false, true,  true,  false,
  % CORNER_DL (DOWN<->LEFT)
                 false, false, true,  true,
  % SWITCH_T_D_R (entries {TOP,RIGHT,DOWN})
                 true,  true,  true,  false,
  % SWITCH_T_D_L (entries {TOP,LEFT,DOWN})
                 true,  false, true,  true,
  % SWITCH_D_T_R (entries {TOP,RIGHT,DOWN})
                 true,  true,  true,  false,
  % SWITCH_D_T_L (entries {TOP,LEFT,DOWN})
                 true,  false, true,  true,
  % SWITCH_R_L_T (entries {LEFT,TOP,RIGHT})
                 true,  true,  false, true,
  % SWITCH_R_L_D (entries {LEFT,DOWN,RIGHT})
                 false, true,  true,  true,
  % SWITCH_L_R_T (entries {RIGHT,TOP,LEFT})
                 true,  true,  false, true,
  % SWITCH_L_R_D (entries {RIGHT,DOWN,LEFT})
                 false, true,  true,  true,
  % DSWITCH_T_D_R (entries {TOP,RIGHT,DOWN})
                 true,  true,  true,  false,
  % DSWITCH_T_D_L (entries {TOP,LEFT,DOWN})
                 true,  false, true,  true,
  % DSWITCH_D_T_R (entries {TOP,RIGHT,DOWN})
                 true,  true,  true,  false,
  % DSWITCH_D_T_L (entries {TOP,LEFT,DOWN})
                 true,  false, true,  true,
  % DSWITCH_R_L_T (entries {LEFT,TOP,RIGHT})
                 true,  true,  false, true,
  % DSWITCH_R_L_D (entries {LEFT,DOWN,RIGHT})
                 false, true,  true,  true,
  % DSWITCH_L_R_T (entries {RIGHT,TOP,LEFT})
                 true,  true,  false, true,
  % DSWITCH_L_R_D (entries {RIGHT,DOWN,LEFT})
                 false, true,  true,  true,
  % TUNNEL_T (can only enter from TOP)
                 true,  false, false, false,
  % TUNNEL_R (can only enter from RIGHT)
                 false, true,  false, false,
  % TUNNEL_D (can only enter from DOWN)
                 false, false, true,  false,
  % TUNNEL_L (can only enter from LEFT)
                 false, false, false, true
]);

% --- Exit Permissions ---
% can_exit[piece, dir] = true if piece has a physical exit in dir
% (used for first hop from train starting position)
array[Piece, Dir] of bool: can_exit = array2d(Piece, Dir, [
  %              TOP    RIGHT  DOWN   LEFT
  % EMPTY
                 false, false, false, false,
  % STRAIGHT_TD
                 true,  false, true,  false,
  % STRAIGHT_RL
                 false, true,  false, true,
  % CORNER_TR
                 true,  true,  false, false,
  % CORNER_TL
                 true,  false, false, true,
  % CORNER_DR
                 false, true,  true,  false,
  % CORNER_DL
                 false, false, true,  true,
  % SWITCH_T_D_R (exits {DOWN, RIGHT})
                 false, true,  true,  false,
  % SWITCH_T_D_L (exits {DOWN, LEFT})
                 false, false, true,  true,
  % SWITCH_D_T_R (exits {TOP, RIGHT})
                 true,  true,  false, false,
  % SWITCH_D_T_L (exits {TOP, LEFT})
                 true,  false, false, true,
  % SWITCH_R_L_T (exits {LEFT, TOP})
                 true,  false, false, true,
  % SWITCH_R_L_D (exits {LEFT, DOWN})
                 false, false, true,  true,
  % SWITCH_L_R_T (exits {RIGHT, TOP})
                 true,  true,  false, false,
  % SWITCH_L_R_D (exits {RIGHT, DOWN})
                 false, true,  true,  false,
  % DSWITCH_T_D_R (exits {DOWN, RIGHT})
                 false, true,  true,  false,
  % DSWITCH_T_D_L (exits {DOWN, LEFT})
                 false, false, true,  true,
  % DSWITCH_D_T_R (exits {TOP, RIGHT})
                 true,  true,  false, false,
  % DSWITCH_D_T_L (exits {TOP, LEFT})
                 true,  false, false, true,
  % DSWITCH_R_L_T (exits {LEFT, TOP})
                 true,  false, false, true,
  % DSWITCH_R_L_D (exits {LEFT, DOWN})
                 false, false, true,  true,
  % DSWITCH_L_R_T (exits {RIGHT, TOP})
                 true,  true,  false, false,
  % DSWITCH_L_R_D (exits {RIGHT, DOWN})
                 false, true,  true,  false,
  % TUNNEL_T (exit at TOP)
                 true,  false, false, false,
  % TUNNEL_R (exit at RIGHT)
                 false, true,  false, false,
  % TUNNEL_D (exit at DOWN)
                 false, false, true,  false,
  % TUNNEL_L (exit at LEFT)
                 false, false, false, true
]);

% --- Routing Table ---
% exit_of[piece, entry_dir] = exit_dir
% Defines where a train exits based on which direction it entered from
array[Piece, Dir] of Dir: exit_of = array2d(Piece, Dir, [
  %            TOP    RIGHT  DOWN   LEFT   (entry_dir)
  % EMPTY
               TOP,   TOP,   TOP,   TOP,
  % STRAIGHT_TD:  TOP->DOWN, DOWN->TOP
               DOWN,  TOP,   TOP,   TOP,
  % STRAIGHT_RL:  RIGHT->LEFT, LEFT->RIGHT
               TOP,   LEFT,  TOP,   RIGHT,
  % CORNER_TR:    TOP->RIGHT, RIGHT->TOP
               RIGHT, TOP,   TOP,   TOP,
  % CORNER_TL:    TOP->LEFT, LEFT->TOP
               LEFT,  TOP,   TOP,   TOP,
  % CORNER_DR:    DOWN->RIGHT, RIGHT->DOWN
               TOP,   DOWN,  RIGHT, TOP,
  % CORNER_DL:    DOWN->LEFT, LEFT->DOWN
               TOP,   TOP,   LEFT,  DOWN,
  % SWITCH_T_D_R: TOP->DOWN, DOWN->RIGHT, RIGHT->DOWN
               DOWN,  DOWN,  RIGHT, TOP,
  % SWITCH_T_D_L: TOP->DOWN, DOWN->LEFT, LEFT->DOWN
               DOWN,  TOP,   LEFT,  DOWN,
  % SWITCH_D_T_R: DOWN->TOP, TOP->RIGHT, RIGHT->TOP
               RIGHT, TOP,   TOP,   TOP,
  % SWITCH_D_T_L: DOWN->TOP, TOP->LEFT, LEFT->TOP
               LEFT,  TOP,   TOP,   TOP,
  % SWITCH_R_L_T: RIGHT->LEFT, LEFT->TOP, TOP->LEFT
               LEFT,  LEFT,  TOP,   TOP,
  % SWITCH_R_L_D: RIGHT->LEFT, LEFT->DOWN, DOWN->LEFT
               TOP,   LEFT,  LEFT,  DOWN,
  % SWITCH_L_R_T: LEFT->RIGHT, RIGHT->TOP, TOP->RIGHT
               RIGHT, TOP,   TOP,   RIGHT,
  % SWITCH_L_R_D: LEFT->RIGHT, RIGHT->DOWN, DOWN->RIGHT
               TOP,   DOWN,  RIGHT, RIGHT,
  % DSWITCH_T_D_R: TOP->DOWN, DOWN->RIGHT, RIGHT->DOWN (initial state)
               DOWN,  DOWN,  RIGHT, TOP,
  % DSWITCH_T_D_L: TOP->DOWN, DOWN->LEFT, LEFT->DOWN
               DOWN,  TOP,   LEFT,  DOWN,
  % DSWITCH_D_T_R: DOWN->TOP, TOP->RIGHT, RIGHT->TOP
               RIGHT, TOP,   TOP,   TOP,
  % DSWITCH_D_T_L: DOWN->TOP, TOP->LEFT, LEFT->TOP
               LEFT,  TOP,   TOP,   TOP,
  % DSWITCH_R_L_T: RIGHT->LEFT, LEFT->TOP, TOP->LEFT
               LEFT,  LEFT,  TOP,   TOP,
  % DSWITCH_R_L_D: RIGHT->LEFT, LEFT->DOWN, DOWN->LEFT
               TOP,   LEFT,  LEFT,  DOWN,
  % DSWITCH_L_R_T: LEFT->RIGHT, RIGHT->TOP, TOP->RIGHT
               RIGHT, TOP,   TOP,   RIGHT,
  % DSWITCH_L_R_D: LEFT->RIGHT, RIGHT->DOWN, DOWN->RIGHT
               TOP,   DOWN,  RIGHT, RIGHT,
  % TUNNEL_T
               TOP,   TOP,   TOP,   TOP,
  % TUNNEL_R
               RIGHT, RIGHT, RIGHT, RIGHT,
  % TUNNEL_D
               DOWN,  DOWN,  DOWN,  DOWN,
  % TUNNEL_L
               LEFT,  LEFT,  LEFT,  LEFT
]);

% --- Dynamic DSWITCH Routing Function ---
% Returns the exit direction for a DSWITCH piece based on entry direction and swap state
% When swapped: Single and Straight connections swap; Curve connection unchanged
function var Dir: dswitch_exit(var Piece: piece, var Dir: entry_dir, var bool: is_swapped) =
  if not is_swapped then
    % Normal state: use standard exit_of table
    exit_of[piece, entry_dir]
  else
    % Swapped state: Single and Straight are swapped
    if piece == DSWITCH_T_D_R then
      % Normal: TOP(single)->DOWN, DOWN(straight)->RIGHT, RIGHT(curve)->DOWN
      % Swapped: DOWN(single)->TOP, TOP(straight)->RIGHT, RIGHT(curve)->TOP
      if entry_dir == TOP then RIGHT      % Was straight, now goes to curve
      elseif entry_dir == DOWN then TOP   % Was single, now goes to straight
      elseif entry_dir == RIGHT then TOP  % Was curve, now goes to straight
      else TOP endif
    elseif piece == DSWITCH_T_D_L then
      % Normal: TOP->DOWN, DOWN->LEFT, LEFT->DOWN
      % Swapped: DOWN->TOP, TOP->LEFT, LEFT->TOP
      if entry_dir == TOP then LEFT       % Was straight, now goes to curve
      elseif entry_dir == DOWN then TOP   % Was single, now goes to straight
      elseif entry_dir == LEFT then TOP   % Was curve, now goes to straight
      else TOP endif
    elseif piece == DSWITCH_D_T_R then
      % Normal: DOWN->TOP, TOP->RIGHT, RIGHT->TOP
      % Swapped: TOP->DOWN, DOWN->RIGHT, RIGHT->DOWN
      if entry_dir == DOWN then RIGHT     % Was straight, now goes to curve
      elseif entry_dir == TOP then DOWN   % Was single, now goes to straight
      elseif entry_dir == RIGHT then DOWN % Was curve, now goes to straight
      else TOP endif
    elseif piece == DSWITCH_D_T_L then
      % Normal: DOWN->TOP, TOP->LEFT, LEFT->TOP
      % Swapped: TOP->DOWN, DOWN->LEFT, LEFT->DOWN
      if entry_dir == DOWN then LEFT      % Was straight, now goes to curve
      elseif entry_dir == TOP then DOWN   % Was single, now goes to straight
      elseif entry_dir == LEFT then DOWN  % Was curve, now goes to straight
      else TOP endif
    elseif piece == DSWITCH_R_L_T then
      % Normal: RIGHT->LEFT, LEFT->TOP, TOP->LEFT
      % Swapped: LEFT->RIGHT, RIGHT->TOP, TOP->RIGHT
      if entry_dir == RIGHT then TOP      % Was straight, now goes to curve
      elseif entry_dir == LEFT then RIGHT % Was single, now goes to straight
      elseif entry_dir == TOP then RIGHT  % Was curve, now goes to straight
      else TOP endif
    elseif piece == DSWITCH_R_L_D then
      % Normal: RIGHT->LEFT, LEFT->DOWN, DOWN->LEFT
      % Swapped: LEFT->RIGHT, RIGHT->DOWN, DOWN->RIGHT
      if entry_dir == RIGHT then DOWN     % Was straight, now goes to curve
      elseif entry_dir == LEFT then RIGHT % Was single, now goes to straight
      elseif entry_dir == DOWN then RIGHT % Was curve, now goes to straight
      else TOP endif
    elseif piece == DSWITCH_L_R_T then
      % Normal: LEFT->RIGHT, RIGHT->TOP, TOP->RIGHT
      % Swapped: RIGHT->LEFT, LEFT->TOP, TOP->LEFT
      if entry_dir == LEFT then TOP       % Was straight, now goes to curve
      elseif entry_dir == RIGHT then LEFT % Was single, now goes to straight
      elseif entry_dir == TOP then LEFT   % Was curve, now goes to straight
      else TOP endif
    elseif piece == DSWITCH_L_R_D then
      % Normal: LEFT->RIGHT, RIGHT->DOWN, DOWN->RIGHT
      % Swapped: RIGHT->LEFT, LEFT->DOWN, DOWN->LEFT
      if entry_dir == LEFT then DOWN      % Was straight, now goes to curve
      elseif entry_dir == RIGHT then LEFT % Was single, now goes to straight
      elseif entry_dir == DOWN then LEFT  % Was curve, now goes to straight
      else TOP endif
    else
      % Not a DSWITCH, shouldn't happen
      exit_of[piece, entry_dir]
    endif
  endif;


% ========= DECISION VARIABLES ===============================

% The piece placed at each grid cell (may be EMPTY if unused)
array[1..H, 1..W] of var Piece: grid;

% Train positions over time
array[1..N_TRAINS, 0..MAX_TIME] of var 1..H: train_row;
array[1..N_TRAINS, 0..MAX_TIME] of var 1..W: train_col;

% Direction the train had when ENTERING the cell (at each time > 0)
array[1..N_TRAINS, 1..MAX_TIME] of var Dir: train_dir;

% First time each train reaches the target (monotonic “stay” afterwards)
array[1..N_TRAINS] of var 0..MAX_TIME: arrival_time;

% Gate states over time: true = OPEN, false = CLOSED
array[1..N_GATES, 0..MAX_TIME] of var bool: gate_open;

% DSWITCH states over time: false = normal, true = swapped
array[1..N_DSWITCHES, 0..MAX_TIME] of var bool: dswitch_swapped;


% ========= CONSTRAINTS ======================================

% 1) Initial positions: at time 0 each train is at its start cell
constraint forall(t in 1..N_TRAINS) (
  train_row[t, 0] = TRAINS[t].1 /\ 
  train_col[t, 0] = TRAINS[t].2
);

% 2) First movement: from start position using initial exit direction
%    Can be blocked by a closed gate (train waits at start position)
constraint forall(t in 1..N_TRAINS) (
  let {
    int: r0 = TRAINS[t].1;
    int: c0 = TRAINS[t].2;
    Dir: exit0 = TRAINS[t].3;
    int: r1 = r0 + dr[exit0];
    int: c1 = c0 + dc[exit0];
    var Piece: p0 = grid[r0, c0];
    var Piece: p1 = grid[r1, c1];
    % Check if first move is blocked by a closed gate
    bool: dest_has_gate = cell_has_gate[r1, c1];
    var bool: blocked_by_gate =
      if dest_has_gate then not gate_open[gate_index_at[r1, c1], 1] else false endif;
  } in
    can_exit[p0, exit0] /\ 
    can_enter[p1, opposite[exit0]] /\
    if blocked_by_gate then
      % Stay at start position
      train_row[t, 1] = r0 /\ 
      train_col[t, 1] = c0 /\ 
      train_dir[t, 1] = opposite[exit0]
    else
      % Move to next position
      train_row[t, 1] = r1 /\ 
      train_col[t, 1] = c1 /\ 
      train_dir[t, 1] = opposite[exit0]
    endif
);

% 3) Subsequent movements (time >= 1): follow piece routing or stay at target
%    - Normal pieces: move according to exit_of table
%    - DSWITCHes: use dynamic routing based on current swap state
%    - Tunnels: teleport to paired tunnel and exit in specified direction
%    - At target: stay in place (all trains remain at target once arrived)
%    - Blocked by closed gate: stay in place (train waits)
constraint forall(t in 1..N_TRAINS, time in 1..MAX_TIME-1) (
  let {
    var 1..H: r = train_row[t, time];
    var 1..W: c = train_col[t, time];
    var Dir: entry_dir = train_dir[t, time];
    var Piece: piece = grid[r, c];
    var Dir: exit_dir;
    var 1..H: next_r = train_row[t, time+1];
    var 1..W: next_c = train_col[t, time+1];
    var Dir: next_entry_dir = train_dir[t, time+1];
    % Compute the intended next position
    var 1..H: intended_r;
    var 1..W: intended_c;
    var Dir: intended_entry_dir;
    % Check if intended position is blocked by a closed gate
    var bool: blocked_by_gate =
      if N_GATES = 0 then
        false
      else
        if cell_has_gate[intended_r, intended_c] then
          not gate_open[gate_index_at[intended_r, intended_c], time+1]
        else
          false
        endif
      endif;
    % Check if current piece is a DSWITCH and get its swap state
    var bool: is_dswitch = piece in DSWITCHES_SET;
    var bool: dswitch_state =
      if N_DSWITCHES = 0 then
        false
      else
        if is_dswitch then
          if cell_has_dswitch[r, c] then
            dswitch_swapped[dswitch_index_at[r, c], time]
          else
            false
          endif
        else
          false
        endif
      endif;
  } in
  if r == TARGET.1 /\ c == TARGET.2 then
    % Stay at target
    (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
  else
    % Compute intended movement via piece routing
    can_enter[piece, entry_dir] /\ 
    (
      % Compute exit direction based on piece type
      if is_dswitch then
        exit_dir = dswitch_exit(piece, entry_dir, dswitch_state)
      else
        exit_dir = exit_of[piece, entry_dir]
      endif
    ) /\ 
    (
      % Check if current piece is a tunnel
      if piece in TUNNELS then
        % Teleport to the paired tunnel
        let {
          var tuple(int, int): dest = tunnel_dest[r, c];
          var int: dest_exit_dir = tunnel_exit_dir[r, c];
          var Dir: dest_exit_dir_enum = to_enum(Dir, dest_exit_dir);
        } in
        % Intended position after tunnel
        intended_r = dest.1 + dr[dest_exit_dir_enum] /\ 
        intended_c = dest.2 + dc[dest_exit_dir_enum] /\ 
        intended_entry_dir = opposite[dest_exit_dir_enum]
      else
        % Normal movement
        intended_r = r + dr[exit_dir] /\ 
        intended_c = c + dc[exit_dir] /\ 
        intended_entry_dir = opposite[exit_dir]
      endif
    ) /\ 
    can_enter[grid[intended_r, intended_c], intended_entry_dir] /\
    % If blocked by gate, stay in place; otherwise move to intended position
    if blocked_by_gate then
      (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
    else
      (next_r, next_c, next_entry_dir) = (intended_r, intended_c, intended_entry_dir)
    endif
  endif
);

% 4) Arrival ordering: trains arrive sequentially, stay at target
%    Each train reaches the target at a specific time and remains there
%    Trains must arrive in order: train[i] arrives before train[i+1]
constraint forall(t in 1..N_TRAINS)(
  forall(time in 0..MAX_TIME) (
    (train_row[t, time] = TARGET.1 /\ train_col[t, time] = TARGET.2)
    <-> (time >= arrival_time[t])
  )
);

constraint forall(t in 1..N_TRAINS-1) (
  arrival_time[t] < arrival_time[t+1]
);

% 5) Collision avoidance: no two trains at same cell except at target
%    Prevents trains from occupying the same cell simultaneously
%    Exception: multiple trains can be at the target cell
constraint forall(time in 0..MAX_TIME, t1 in 1..N_TRAINS, t2 in t1+1..N_TRAINS) (
  let {
    var 1..H: r1 = train_row[t1, time];
    var 1..W: c1 = train_col[t1, time];
    var 1..H: r2 = train_row[t2, time];
    var 1..W: c2 = train_col[t2, time];
  } in
  (r1, c1) != (r2, c2) \/ (r1 = TARGET.1 /\ c1 = TARGET.2)
);

% 6) Prevent position swaps between timesteps (except at target)
%    Two trains cannot swap positions between consecutive timesteps
%    This prevents "passing through" each other
constraint forall(time in 0..MAX_TIME-1, t1 in 1..N_TRAINS, t2 in t1+1..N_TRAINS) (
  let {
    var 1..H: r1t = train_row[t1, time];
    var 1..W: c1t = train_col[t1, time];
    var 1..H: r2t = train_row[t2, time];
    var 1..W: c2t = train_col[t2, time];
    var 1..H: r1n = train_row[t1, time+1];
    var 1..W: c1n = train_col[t1, time+1];
    var 1..H: r2n = train_row[t2, time+1];
    var 1..W: c2n = train_col[t2, time+1];
  } in
  (
    % Either not swapping,
    not ( (r1t = r2n /\ c1t = c2n) /\ (r2t = r1n /\ c2t = c1n) )
    % or one of the trains is at the target (in either step).
    \/ (r1t = TARGET.1 /\ c1t = TARGET.2)
    \/ (r2t = TARGET.1 /\ c2t = TARGET.2)
    \/ (r1n = TARGET.1 /\ c1n = TARGET.2)
    \/ (r2n = TARGET.1 /\ c2n = TARGET.2)
  )
);

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
  % Place tunnel piece at position A with exit direction dir_A
  grid[r_A, c_A] = if dir_A == TOP then TUNNEL_T
                   elseif dir_A == RIGHT then TUNNEL_R
                   elseif dir_A == DOWN then TUNNEL_D
                   else TUNNEL_L endif
  /\
  % Place tunnel piece at position B with exit direction dir_B
  grid[r_B, c_B] = if dir_B == TOP then TUNNEL_T
                   elseif dir_B == RIGHT then TUNNEL_R
                   elseif dir_B == DOWN then TUNNEL_D
                   else TUNNEL_L endif
);

% 9) Track budget: limit non-EMPTY pieces beyond pre-placed and tunnels
%    Ensures the solution doesn't use more track pieces than allowed
%    Formula: (total_placed - initial_pieces - tunnel_pieces) <= MAX_TRACKS
constraint
  let {
    var int: total_placed_tracks = sum(p in grid where p != EMPTY)(1);
    int: init_tracks = sum(p in INIT_POS where p.3 != EMPTY)(1);
    int: init_tunnels = sum(i in 1..N_TUNNELS)(2);  % Each tunnel pair adds 2 pieces
  } in
  total_placed_tracks - init_tracks - init_tunnels <= MAX_TRACKS;

% 10) Connectivity: corners/switches/dswitches/straights must connect to valid neighbors
%     Each entry point of a corner, switch, dswitch, or straight must connect to:
%     - A non-EMPTY cell within bounds
%     - A cell that can be entered from the opposite direction
%     - OR a tunnel (tunnels have special teleportation logic)
%     Exception: straights at target location or initial train positions are exempt
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
%     Prevents arbitrary tunnel placement - only pre-defined tunnel pairs are allowed
constraint forall(r in 1..H, c in 1..W) (
  let { var Piece: p = grid[r, c] } in
  if p in TUNNELS then
    let { tuple(int, int): dest = tunnel_dest[r, c]; } in dest.1 > 0
  endif
);

% 11b) Restrict DSWITCHes to only those defined in DSWITCHES array
%      Prevents arbitrary DSWITCH placement - only pre-defined DSWITCHes are allowed
constraint forall(r in 1..H, c in 1..W) (
  let { var Piece: p = grid[r, c] } in
  if p in DSWITCHES_SET then
    cell_has_dswitch[r, c]
  endif
);

% ========= GATE AND ACTIVATION CONSTRAINTS ==================

% 12) Gate validation: gates must be on non-EMPTY track pieces
constraint forall(g in GATES) (
  grid[g.1, g.2] != EMPTY
);

% 13) Gate validation: gates only on STRAIGHT, CORNER, or SWITCH tracks
constraint forall(g in GATES) (
  grid[g.1, g.2] in (STRAIGHTS union CORNERS union SWITCHES)
);

% 14) Activation validation: activations must be on non-EMPTY track pieces
constraint forall(a in ACTIVATIONS) (
  grid[a.1, a.2] != EMPTY
);

% 15) Activation validation: activations only on STRAIGHT, CORNER, SWITCH, or DSWITCH tracks
constraint forall(a in ACTIVATIONS) (
  grid[a.1, a.2] in (STRAIGHTS union CORNERS union SWITCHES union DSWITCHES_SET)
);

% 16) No coexistence: gates and activations cannot share the same cell
constraint forall(g in GATES, a in ACTIVATIONS) (
  not (g.1 = a.1 /\ g.2 = a.2)
);

% 17) Initial gate states (at time 0)
constraint forall(g in 1..N_GATES) (
  gate_open[g, 0] = GATES[g].4
);

% 18) Initial position safety: trains cannot start on closed gates
constraint forall(t in 1..N_TRAINS) (
  if N_GATES = 0 then
    true
  elseif cell_has_gate[TRAINS[t].1, TRAINS[t].2] then
    GATES[gate_index_at[TRAINS[t].1, TRAINS[t].2]].4
  else
    true
  endif
);

% 19) Gate state transitions: toggle when activation is triggered
%     Activations trigger if odd number of trains enter activations linked to the gate
constraint forall(g in 1..N_GATES, time in 0..MAX_TIME-1) (
  let {
    int: gate_id = GATES[g].3;
    var int: num_entering = sum(t in 1..N_TRAINS, a in ACTIVATIONS where a.3 = gate_id) (
      bool2int( train_row[t, time] = a.1 /\ train_col[t, time] = a.2 /\
      (time = 0 \/ (train_row[t, time-1] != a.1 \/ train_col[t, time-1] != a.2)) )
    );
  } in
  if num_entering mod 2 = 1 then
    gate_open[g, time+1] = not gate_open[g, time]  % Toggle
  else
    gate_open[g, time+1] = gate_open[g, time]      % No change
  endif
);

% 20) Gate blocking: trains cannot move into cells with closed gates
constraint forall(t in 1..N_TRAINS, time in 0..MAX_TIME) (
  if N_GATES = 0 then
    true
  else
    let {
      var bool: at_gate = cell_has_gate[train_row[t, time], train_col[t, time]];
      var int: gate_idx = gate_index_at[train_row[t, time], train_col[t, time]];
    } in
      if at_gate then gate_open[gate_idx, time] else true endif
  endif
);

% ========= DSWITCH CONSTRAINTS ==============================

% 21) DSWITCH validation: DSWITCHes must be pre-placed via INIT_POS
constraint forall(ds in DSWITCHES) (
  grid[ds.1, ds.2] in DSWITCHES_SET
);

% 22) No coexistence: DSWITCHes cannot share cells with gates or activations
constraint forall(ds in DSWITCHES, g in GATES) (
  not (ds.1 = g.1 /\ ds.2 = g.2)
);
constraint forall(ds in DSWITCHES, a in ACTIVATIONS) (
  not (ds.1 = a.1 /\ ds.2 = a.2)
);

% 23) Initial DSWITCH states (at time 0) - all start in normal state
constraint forall(ds in 1..N_DSWITCHES) (
  dswitch_swapped[ds, 0] = false
);

% 24) DSWITCH state transitions: toggle when linked activation is triggered
%     Activations trigger if odd number of trains enter activations linked to the dswitch
%     All DSWITCHes with the same ID toggle together
constraint forall(ds in 1..N_DSWITCHES, time in 0..MAX_TIME-1) (
  let {
    int: dswitch_id = DSWITCHES[ds].3;
    var int: num_entering = sum(t in 1..N_TRAINS, a in ACTIVATIONS where a.3 = dswitch_id) (
      bool2int( train_row[t, time] = a.1 /\ train_col[t, time] = a.2 /\
      (time = 0 \/ (train_row[t, time-1] != a.1 \/ train_col[t, time-1] != a.2)) )
    );
  } in
  if num_entering mod 2 = 1 then
    dswitch_swapped[ds, time+1] = not dswitch_swapped[ds, time]  % Toggle
  else
    dswitch_swapped[ds, time+1] = dswitch_swapped[ds, time]      % No change
  endif
);


% ========= SOLVE & OUTPUT ===================================

solve:: int_search([grid[r,c] | r in 1..H, c in 1..W],
                    first_fail, indomain_min, complete)
     :: int_search([arrival_time[t] | t in 1..N_TRAINS],
                    first_fail, indomain_min, complete)
satisfy;

% Display results with visualization
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
);
any: solution_data :: output_only = (
  grid:showJSON(grid)
);
output :: vis_server("viz.html",initial_data) solution_data;

% Display results with clear formatting
output [
  "============================================================\n",
  "SOLUTION FOUND\n",
  "============================================================\n\n",
  "GRID LAYOUT:\n",
  show2d(grid), "\n\n",
  "Latest arrival time: \(max(arrival_time))\n"
]
++
["\nTRAIN PATHS:\n"]
++
[
  "Train \(t): arrival at time \(arrival_time[t])\n" ++
  "  Path: " ++ show([ (train_row[t,time], train_col[t,time]) | time in 0..fix(arrival_time[t]) ]) ++ "\n"
  | t in 1..N_TRAINS
];

