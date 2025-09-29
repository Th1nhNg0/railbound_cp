% ============================================================
% Train Routing CSP
% ============================================================
% Place track pieces on H×W grid for N trains to reach target sequentially,
% without collisions, under track budget.
%
% Conventions:
% - Rows: 1..H (top to bottom), Cols: 1..W (left to right)
% - train_dir[t,time]: entry direction into cell at (t,time)
% - START_DIR[t]: exit direction from start for first move
% ============================================================



% ========= PARAMETERS =======================================

int: W;                  % Grid width  (number of columns)
int: H;                  % Grid height (number of rows)

int: N_TRAINS;           % Number of trains
int: MAX_TIME;           % Max number of discrete time steps
int: MAX_TRACKS;         % Max number of non-EMPTY pieces that can be placed

% Target location (unique sink cell all trains must reach, in order)
int: TARGET_R;
int: TARGET_C;

% Train starting positions and initial EXIT directions
array[1..N_TRAINS] of int: START_R;  % 1-based row index
array[1..N_TRAINS] of int: START_C;  % 1-based col index
array[1..N_TRAINS] of Dir: START_DIR; % EXIT dir for first move from start

% Pre-placed (fixed) pieces already on the grid
int: N_INIT_POS;
array[1..N_INIT_POS] of Pos: INIT_POS; % tuple(row, col, piece)



% ========= ENCODINGS ========================================

% Position tuple: (row, col, piece kind at that cell)
type Pos = tuple(int, int, Piece);

% Directions (relative to the current cell)
enum Dir = { TOP, RIGHT, DOWN, LEFT };

% All track/track-switch piece kinds available
% Visual hints:
%   STRAIGHT_TD : │ (connects TOP<->DOWN)
%   STRAIGHT_RL : ─ (connects RIGHT<->LEFT)
%   CORNER_*    : └┘┌┐ style turns (two-way, 90° corners)
%   SWITCH_*    : 3-way with one 'single' end and two exits.
%                 Naming: SWITCH_<SingleEnd>_<StraightEnd>_<CurveEnd>
enum Piece = {
  EMPTY,

  STRAIGHT_TD,  % │ connects TOP <-> DOWN
  STRAIGHT_RL,  % ─ connects RIGHT <-> LEFT

  CORNER_TR,    % └ connects TOP <-> RIGHT
  CORNER_TL,    % ┘ connects TOP <-> LEFT
  CORNER_DR,    % ┌ connects DOWN <-> RIGHT
  CORNER_DL,    % ┐ connects DOWN <-> LEFT

  % Switches: SWITCH_<Single>_<Straight>_<Curve>
  % Rule: Single->Straight, Straight->Curve, Curve->Straight
  % E.g., SWITCH_T_D_R: TOP->DOWN, DOWN->RIGHT, RIGHT->DOWN

  SWITCH_T_D_R,
  SWITCH_T_D_L,
  SWITCH_D_T_R,
  SWITCH_D_T_L,
  SWITCH_R_L_T,
  SWITCH_R_L_D,
  SWITCH_L_R_T,
  SWITCH_L_R_D
};


% --- Direction helpers ---
array[Dir] of int: dr = [ -1, 0,  1,  0 ];   % TOP, RIGHT, DOWN, LEFT
array[Dir] of int: dc = [  0, 1,  0, -1 ];
array[Dir] of Dir: opposite = [ DOWN, LEFT, TOP, RIGHT ];

% --- Which entries are allowed for each piece? ---
array[Piece, Dir] of bool: can_enter = array2d(Piece, Dir, [
  %              TOP   RIGHT  DOWN  LEFT
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
                 false, true,  true,  true
]);

% --- Which exits are physically present on each piece? (used for first hop) ---
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

  % SWITCH_T_D_R (S=TOP,   T=DOWN,  C=RIGHT)  exits {DOWN, RIGHT}
                 false, true,  true,  false,
  % SWITCH_T_D_L (S=TOP,   T=DOWN,  C=LEFT)   exits {DOWN, LEFT}
                 false, false, true,  true,
  % SWITCH_D_T_R (S=DOWN,  T=TOP,   C=RIGHT)  exits {TOP, RIGHT}
                 true,  true,  false, false,
  % SWITCH_D_T_L (S=DOWN,  T=TOP,   C=LEFT)   exits {TOP, LEFT}
                 true,  false, false, true,
  % SWITCH_R_L_T (S=RIGHT, T=LEFT,  C=TOP)    exits {LEFT, TOP}
                 true,  false, false, true,
  % SWITCH_R_L_D (S=RIGHT, T=LEFT,  C=DOWN)   exits {LEFT, DOWN}
                 false, false, true,  true,
  % SWITCH_L_R_T (S=LEFT,  T=RIGHT, C=TOP)    exits {RIGHT, TOP}
                 true,  true,  false, false,
  % SWITCH_L_R_D (S=LEFT,  T=RIGHT, C=DOWN)   exits {RIGHT, DOWN}
                 false, true,  true,  false
]);

% --- Mapping: given (piece, entry_dir) return the exit_dir.
% For disallowed entries, the value is a dummy (TOP) and guarded by can_enter.
array[Piece, Dir] of Dir: exit_of = array2d(Piece, Dir, [
  %            TOP     RIGHT   DOWN    LEFT   (entry_dir)
  % EMPTY
               TOP,    TOP,    TOP,    TOP,

  % STRAIGHT_TD:  TOP->DOWN, DOWN->TOP
               DOWN,   TOP,    TOP,    TOP,

  % STRAIGHT_RL:  RIGHT->LEFT, LEFT->RIGHT
               TOP,    LEFT,   TOP,    RIGHT,

  % CORNER_TR:    TOP->RIGHT, RIGHT->TOP
               RIGHT,  TOP,    TOP,    TOP,

  % CORNER_TL:    TOP->LEFT, LEFT->TOP
               LEFT,   TOP,    TOP,    TOP,

  % CORNER_DR:    DOWN->RIGHT, RIGHT->DOWN
               TOP,    DOWN,   RIGHT,  TOP,

  % CORNER_DL:    DOWN->LEFT, LEFT->DOWN
               TOP,    TOP,    LEFT,   DOWN,

  % SWITCH_T_D_R: S=TOP,   T=DOWN,  C=RIGHT
  %   TOP->DOWN, DOWN->RIGHT, RIGHT->DOWN
               DOWN,   DOWN,   RIGHT,  TOP,

  % SWITCH_T_D_L: S=TOP,   T=DOWN,  C=LEFT
  %   TOP->DOWN, DOWN->LEFT, LEFT->DOWN
               DOWN,   TOP,    LEFT,   DOWN,

  % SWITCH_D_T_R: S=DOWN,  T=TOP,   C=RIGHT
  %   DOWN->TOP, TOP->RIGHT, RIGHT->TOP
               RIGHT,  TOP,    TOP,    TOP,

  % SWITCH_D_T_L: S=DOWN,  T=TOP,   C=LEFT
  %   DOWN->TOP, TOP->LEFT, LEFT->TOP
               LEFT,   TOP,    TOP,    TOP,

  % SWITCH_R_L_T: S=RIGHT, T=LEFT,  C=TOP
  %   RIGHT->LEFT, LEFT->TOP, TOP->LEFT
               LEFT,   LEFT,   TOP,    TOP,

  % SWITCH_R_L_D: S=RIGHT, T=LEFT,  C=DOWN
  %   RIGHT->LEFT, LEFT->DOWN, DOWN->LEFT
               TOP,    LEFT,   LEFT,   DOWN,

  % SWITCH_L_R_T: S=LEFT,  T=RIGHT, C=TOP
  %   LEFT->RIGHT, RIGHT->TOP, TOP->RIGHT
               RIGHT,  TOP,    TOP,    RIGHT,

  % SWITCH_L_R_D: S=LEFT,  T=RIGHT, C=DOWN
  %   LEFT->RIGHT, RIGHT->DOWN, DOWN->RIGHT
               TOP,    DOWN,   RIGHT,  RIGHT
]);

set of Piece: CORNERS  =
  { CORNER_TR, CORNER_TL, CORNER_DR, CORNER_DL };
set of Piece: SWITCHES =
  { SWITCH_T_D_R, SWITCH_T_D_L, SWITCH_D_T_R, SWITCH_D_T_L,
    SWITCH_R_L_T, SWITCH_R_L_D, SWITCH_L_R_T, SWITCH_L_R_D };

% ========= DECISION VARIABLES ================================

% The piece placed at each grid cell (may be EMPTY if unused)
array[1..H, 1..W] of var Piece: grid;

% Train positions over time
array[1..N_TRAINS, 0..MAX_TIME] of var 1..H: train_row;
array[1..N_TRAINS, 0..MAX_TIME] of var 1..W: train_col;

% Direction the train had when ENTERING the cell (at each time > 0)
array[1..N_TRAINS, 1..MAX_TIME] of var Dir: train_dir;

% First time each train reaches the target (monotonic “stay” afterwards)
array[1..N_TRAINS] of var 0..MAX_TIME: arrival_time;



% ========= CONSTRAINTS ======================================

% --- 1) Initial Position: at time 0 each train is at its start cell.
constraint forall(t in 1..N_TRAINS) (
  train_row[t, 0] = START_R[t] /\ train_col[t, 0] = START_C[t]
);


% --- 2) Movement constraints ---
constraint forall(t in 1..N_TRAINS) (
  let {
    int: r0 = START_R[t]; int: c0 = START_C[t]; Dir: exit0 = START_DIR[t];
    var 1..H: r1 = r0 + dr[exit0]; var 1..W: c1 = c0 + dc[exit0];
    var Piece: p0 = grid[r0, c0]; var Piece: p1 = grid[r1, c1];
  } in
    train_row[t, 1] = r1 /\ train_col[t, 1] = c1 /\ train_dir[t, 1] = opposite[exit0]
 /\ can_exit[p0, exit0] /\ can_enter[p1, opposite[exit0]]
);


% --- Subsequent moves (time >= 1) ---
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
  } in

  if r == TARGET_R /\ c == TARGET_C then
    % Stay at target
    (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
  else
    % Move via piece routing
    can_enter[piece, entry_dir] /\ exit_dir = exit_of[piece, entry_dir]
 /\ next_r = r + dr[exit_dir] /\ next_c = c + dc[exit_dir] /\ next_entry_dir = opposite[exit_dir]
 /\ can_enter[grid[next_r, next_c], next_entry_dir]
  endif
);


% --- 3) Arrival ordering: trains arrive sequentially, stay at target ---
constraint forall(t in 1..N_TRAINS)(
  forall(time in 0..MAX_TIME) (
    (train_row[t, time] = TARGET_R /\ train_col[t, time] = TARGET_C)
    <-> (time >= arrival_time[t])
  )
);

constraint forall(t in 1..N_TRAINS-1) (
  arrival_time[t] < arrival_time[t+1]
);




% --- 4) Collision avoidance: no two trains at same cell except target ---
constraint forall(time in 0..MAX_TIME, t1 in 1..N_TRAINS, t2 in t1+1..N_TRAINS) (
  let {
    var 1..H: r1 = train_row[t1, time];
    var 1..W: c1 = train_col[t1, time];
    var 1..H: r2 = train_row[t2, time];
    var 1..W: c2 = train_col[t2, time];
  } in
  (r1, c1) != (r2, c2) \/ (r1 = TARGET_R /\ c1 = TARGET_C)
);

% Prevent position swaps between timesteps, except at target.
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
    \/ (r1t = TARGET_R /\ c1t = TARGET_C)
    \/ (r2t = TARGET_R /\ c2t = TARGET_C)
    \/ (r1n = TARGET_R /\ c1n = TARGET_C)
    \/ (r2n = TARGET_R /\ c2n = TARGET_C)
  )
);

% --- 5) Respect pre-placed pieces:
% For each INIT_POS entry (row, col, fixed_piece), force that piece.
constraint forall(p in INIT_POS) (
  grid[p.1, p.2] == p.3
);



% --- 6) Track budget: limit non-EMPTY pieces beyond pre-placed ---
constraint
  let {
    var int: total_placed_tracks = sum(p in grid where p != EMPTY)(1);
    var int: init_tracks = sum(p in INIT_POS where p.3 != EMPTY)(1);
  } in
  total_placed_tracks - init_tracks <= MAX_TRACKS
;


% --- 7) Connectivity: corners/switches must connect to valid neighbors ---
predicate in_bounds(int: r, int: c) = r >= 1 /\ r <= H /\ c >= 1 /\ c <= W;
constraint forall(r in 1..H, c in 1..W) (
  let { var Piece: p = grid[r,c] } in
  if p in CORNERS \/ p in SWITCHES then
    forall(d in Dir where can_enter[p, d]) (
      let { int: rr = r + dr[d]; int: cc = c + dc[d] } in
        in_bounds(rr, cc) /\ grid[rr, cc] != EMPTY /\ can_enter[grid[rr, cc], opposite[d]]
    )
  endif
);



% ========= SOLVE & OUTPUT ===================================

solve satisfy;


% solve satisfy;
output [
  "GRID LAYOUT:\n",
  show2d(grid), "\n\n",
  "TRAIN PATHS:\n"
]
++
[
  "Train \(t): arrival at time " ++ show(arrival_time[t]) ++ "\nPath: " ++
  show([ (train_row[t,time],train_col[t,time]) | time in 0..fix(arrival_time[t]) ]) ++ "\n"
  | t in 1..N_TRAINS
];
