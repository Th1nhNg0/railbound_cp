% ============================================================
% Railbound Puzzle Solver - Train Routing CSP
% ============================================================
% Place track pieces on H×W grid for N trains to reach target
% sequentially without collisions, under track budget.
% ============================================================

include "globals.mzn";

% ============================================================
% PARAMETERS
% ============================================================

int: W;  int: H;                      % Grid dimensions (width × height)
int: N_TRAINS;   int: MAX_TIME;       % Number of trains & max time steps
int: MAX_TRACKS;                      % Budget: max placeable track pieces
tuple(int, int): TARGET;              % Target cell (row, col)
int: N_INIT_POS;  int: N_TUNNELS;     % Pre-placed pieces & tunnel pairs

% ============================================================
% TYPE DEFINITIONS
% ============================================================

enum Dir = { TOP, RIGHT, DOWN, LEFT };

type Pos = tuple(int, int, Piece);        % (row, col, piece)
type TrainStart = tuple(int, int, Dir);   % (row, col, initial_exit_dir)
type TunnelPair = tuple(int, int, Dir, int, int, Dir);  % (r_A, c_A, exit_A, r_B, c_B, exit_B)

% Track piece types: │ ─ └┘┌┐ switches, tunnels
enum Piece = {
  EMPTY,
  STRAIGHT_TD, STRAIGHT_RL,                                      % │ ─
  CORNER_TR, CORNER_TL, CORNER_DR, CORNER_DL,                   % └ ┘ ┌ ┐
  SWITCH_T_D_R, SWITCH_T_D_L, SWITCH_D_T_R, SWITCH_D_T_L,      % switches
  SWITCH_R_L_T, SWITCH_R_L_D, SWITCH_L_R_T, SWITCH_L_R_D,
  TUNNEL_T, TUNNEL_R, TUNNEL_D, TUNNEL_L                        % tunnels
};

% ============================================================
% INPUT DATA & CONSTANTS
% ============================================================

array[1..N_TRAINS] of TrainStart: TRAINS;
array[1..N_INIT_POS] of Pos: INIT_POS;
array[1..N_TUNNELS] of TunnelPair: TUNNEL_PAIRS;

% Direction deltas and opposites
array[Dir] of int: dr = [-1, 0, 1, 0];  array[Dir] of int: dc = [0, 1, 0, -1];
array[Dir] of Dir: opposite = [DOWN, LEFT, TOP, RIGHT];

% Piece categories
set of Piece: STRAIGHTS = {STRAIGHT_TD, STRAIGHT_RL};
set of Piece: CORNERS = {CORNER_TR, CORNER_TL, CORNER_DR, CORNER_DL};
set of Piece: SWITCHES = {SWITCH_T_D_R, SWITCH_T_D_L, SWITCH_D_T_R, SWITCH_D_T_L,
                          SWITCH_R_L_T, SWITCH_R_L_D, SWITCH_L_R_T, SWITCH_L_R_D};
set of Piece: TUNNELS = {TUNNEL_T, TUNNEL_R, TUNNEL_D, TUNNEL_L};

predicate in_bounds(int: r, int: c) = r >= 1 /\ r <= H /\ c >= 1 /\ c <= W;
predicate at_target(var int: r, var int: c) = r = TARGET.1 /\ c = TARGET.2;

% ============================================================
% PIECE ROUTING TABLES
% ============================================================

% can_enter[piece, dir]: can piece be entered from direction?
array[Piece, Dir] of bool: can_enter = array2d(Piece, Dir, [
  false, false, false, false,  % EMPTY
  true,  false, true,  false,  % STRAIGHT_TD: TOP, DOWN
  false, true,  false, true,   % STRAIGHT_RL: RIGHT, LEFT
  true,  true,  false, false,  % CORNER_TR: TOP, RIGHT
  true,  false, false, true,   % CORNER_TL: TOP, LEFT
  false, true,  true,  false,  % CORNER_DR: DOWN, RIGHT
  false, false, true,  true,   % CORNER_DL: DOWN, LEFT
  true,  true,  true,  false,  % SWITCH_T_D_R: TOP, RIGHT, DOWN
  true,  false, true,  true,   % SWITCH_T_D_L: TOP, DOWN, LEFT
  true,  true,  true,  false,  % SWITCH_D_T_R: TOP, RIGHT, DOWN
  true,  false, true,  true,   % SWITCH_D_T_L: TOP, DOWN, LEFT
  true,  true,  false, true,   % SWITCH_R_L_T: TOP, RIGHT, LEFT
  false, true,  true,  true,   % SWITCH_R_L_D: RIGHT, DOWN, LEFT
  true,  true,  false, true,   % SWITCH_L_R_T: TOP, RIGHT, LEFT
  false, true,  true,  true,   % SWITCH_L_R_D: RIGHT, DOWN, LEFT
  true,  false, false, false,  % TUNNEL_T: TOP only
  false, true,  false, false,  % TUNNEL_R: RIGHT only
  false, false, true,  false,  % TUNNEL_D: DOWN only
  false, false, false, true    % TUNNEL_L: LEFT only
]);

% can_exit[piece, dir]: does piece have physical exit in direction?
array[Piece, Dir] of bool: can_exit = array2d(Piece, Dir, [
  false, false, false, false,  % EMPTY
  true,  false, true,  false,  % STRAIGHT_TD
  false, true,  false, true,   % STRAIGHT_RL
  true,  true,  false, false,  % CORNER_TR
  true,  false, false, true,   % CORNER_TL
  false, true,  true,  false,  % CORNER_DR
  false, false, true,  true,   % CORNER_DL
  false, true,  true,  false,  % SWITCH_T_D_R: exits DOWN, RIGHT
  false, false, true,  true,   % SWITCH_T_D_L: exits DOWN, LEFT
  true,  true,  false, false,  % SWITCH_D_T_R: exits TOP, RIGHT
  true,  false, false, true,   % SWITCH_D_T_L: exits TOP, LEFT
  true,  false, false, true,   % SWITCH_R_L_T: exits TOP, LEFT
  false, false, true,  true,   % SWITCH_R_L_D: exits DOWN, LEFT
  true,  true,  false, false,  % SWITCH_L_R_T: exits TOP, RIGHT
  false, true,  true,  false,  % SWITCH_L_R_D: exits DOWN, RIGHT
  true,  false, false, false,  % TUNNEL_T
  false, true,  false, false,  % TUNNEL_R
  false, false, true,  false,  % TUNNEL_D
  false, false, false, true    % TUNNEL_L
]);

% exit_of[piece, entry_dir]: where does train exit?
array[Piece, Dir] of Dir: exit_of = array2d(Piece, Dir, [
  TOP,   TOP,   TOP,   TOP,    % EMPTY
  DOWN,  TOP,   TOP,   TOP,    % STRAIGHT_TD: TOP→DOWN, DOWN→TOP
  TOP,   LEFT,  TOP,   RIGHT,  % STRAIGHT_RL: RIGHT→LEFT, LEFT→RIGHT
  RIGHT, TOP,   TOP,   TOP,    % CORNER_TR: TOP→RIGHT, RIGHT→TOP
  LEFT,  TOP,   TOP,   TOP,    % CORNER_TL: TOP→LEFT, LEFT→TOP
  TOP,   DOWN,  RIGHT, TOP,    % CORNER_DR: DOWN→RIGHT, RIGHT→DOWN
  TOP,   TOP,   LEFT,  DOWN,   % CORNER_DL: DOWN→LEFT, LEFT→DOWN
  DOWN,  DOWN,  RIGHT, TOP,    % SWITCH_T_D_R: TOP→DOWN, DOWN→RIGHT, RIGHT→DOWN
  DOWN,  TOP,   LEFT,  DOWN,   % SWITCH_T_D_L: TOP→DOWN, DOWN→LEFT, LEFT→DOWN
  RIGHT, TOP,   TOP,   TOP,    % SWITCH_D_T_R: DOWN→TOP, TOP→RIGHT, RIGHT→TOP
  LEFT,  TOP,   TOP,   TOP,    % SWITCH_D_T_L: DOWN→TOP, TOP→LEFT, LEFT→TOP
  LEFT,  LEFT,  TOP,   TOP,    % SWITCH_R_L_T: RIGHT→LEFT, LEFT→TOP, TOP→LEFT
  TOP,   LEFT,  LEFT,  DOWN,   % SWITCH_R_L_D: RIGHT→LEFT, LEFT→DOWN, DOWN→LEFT
  RIGHT, TOP,   TOP,   RIGHT,  % SWITCH_L_R_T: LEFT→RIGHT, RIGHT→TOP, TOP→RIGHT
  TOP,   DOWN,  RIGHT, RIGHT,  % SWITCH_L_R_D: LEFT→RIGHT, RIGHT→DOWN, DOWN→RIGHT
  TOP,   TOP,   TOP,   TOP,    % TUNNEL_T
  RIGHT, RIGHT, RIGHT, RIGHT,  % TUNNEL_R
  DOWN,  DOWN,  DOWN,  DOWN,   % TUNNEL_D
  LEFT,  LEFT,  LEFT,  LEFT    % TUNNEL_L
]);

% Tunnel lookup: precompute destinations and exit directions
array[1..H, 1..W] of tuple(int, int): tunnel_dest =  array2d(1..H, 1..W, [
  let {
    int: idx_A = sum(i in 1..N_TUNNELS where TUNNEL_PAIRS[i].1=r /\ TUNNEL_PAIRS[i].2=c)(i);
    int: idx_B = sum(i in 1..N_TUNNELS where TUNNEL_PAIRS[i].4=r /\ TUNNEL_PAIRS[i].5=c)(i);
  } in
  if idx_A > 0 then (TUNNEL_PAIRS[idx_A].4, TUNNEL_PAIRS[idx_A].5)
  elseif idx_B > 0 then (TUNNEL_PAIRS[idx_B].1, TUNNEL_PAIRS[idx_B].2)
  else (0, 0) endif
  | r in 1..H, c in 1..W
]);

array[1..H, 1..W] of int: tunnel_exit_dir = array2d(1..H, 1..W, [
  let {
    int: idx_A = sum(i in 1..N_TUNNELS where TUNNEL_PAIRS[i].1=r /\ TUNNEL_PAIRS[i].2=c)(i);
    int: idx_B = sum(i in 1..N_TUNNELS where TUNNEL_PAIRS[i].4=r /\ TUNNEL_PAIRS[i].5=c)(i);
  } in
  if idx_A > 0 then enum2int(TUNNEL_PAIRS[idx_A].6)
  elseif idx_B > 0 then enum2int(TUNNEL_PAIRS[idx_B].3)
  else 1 endif
  | r in 1..H, c in 1..W
]);

% ============================================================
% DECISION VARIABLES
% ============================================================

array[1..H, 1..W] of var Piece: grid;                       % Grid layout
array[1..N_TRAINS, 0..MAX_TIME] of var 1..H: train_row;     % Train positions
array[1..N_TRAINS, 0..MAX_TIME] of var 1..W: train_col;
array[1..N_TRAINS, 1..MAX_TIME] of var Dir: train_dir;      % Entry directions
array[1..N_TRAINS] of var 0..MAX_TIME: arrival_time;        % Arrival times

% ============================================================
% CONSTRAINTS
% ============================================================

% 1) Initial train positions
constraint forall(t in 1..N_TRAINS) (
  train_row[t, 0] = TRAINS[t].1 /\ train_col[t, 0] = TRAINS[t].2
);

% 2) First movement from start using initial exit direction
constraint forall(t in 1..N_TRAINS) (
  let {
    int: r0 = TRAINS[t].1; int: c0 = TRAINS[t].2; Dir: exit0 = TRAINS[t].3;
    var 1..H: r1 = r0 + dr[exit0]; var 1..W: c1 = c0 + dc[exit0];
  } in
    train_row[t, 1] = r1 /\ train_col[t, 1] = c1 /\ train_dir[t, 1] = opposite[exit0] /\
    can_exit[grid[r0, c0], exit0] /\ can_enter[grid[r1, c1], opposite[exit0]]
);

% 3) Subsequent movements: follow routing or stay at target
constraint forall(t in 1..N_TRAINS, time in 1..MAX_TIME-1) (
  let {
    var 1..H: r = train_row[t, time]; var 1..H: next_r = train_row[t, time+1];
    var 1..W: c = train_col[t, time]; var 1..W: next_c = train_col[t, time+1];
    var Dir: entry = train_dir[t, time]; var Dir: next_entry = train_dir[t, time+1];
    var Piece: piece = grid[r, c]; var Dir: exit_dir = exit_of[piece, entry];
  } in
  if at_target(r, c) then
    next_r = r /\ next_c = c /\ next_entry = entry  % Stay at target
  else
    can_enter[piece, entry] /\ (
      if piece in TUNNELS then
        let {
          var tuple(int, int): dest = tunnel_dest[r, c];
          var int: dest_exit_int = tunnel_exit_dir[r, c];
          var Dir: dest_exit = to_enum(Dir, dest_exit_int);
        } in
        next_r = dest.1 + dr[dest_exit] /\ next_c = dest.2 + dc[dest_exit] /\
        next_entry = opposite[dest_exit]
      else
        next_r = r + dr[exit_dir] /\ next_c = c + dc[exit_dir] /\
        next_entry = opposite[exit_dir]
      endif
    ) /\ can_enter[grid[next_r, next_c], next_entry]
  endif
);

% 4) Sequential arrival at target
constraint forall(t in 1..N_TRAINS) (
  forall(time in 0..MAX_TIME) (
    at_target(train_row[t, time], train_col[t, time]) <-> time >= arrival_time[t]
  )
);
constraint forall(t in 1..N_TRAINS-1) (arrival_time[t] < arrival_time[t+1]);

% 5) No collisions except at target
constraint forall(time in 0..MAX_TIME, t1 in 1..N_TRAINS, t2 in t1+1..N_TRAINS) (
  let {
    var 1..H: r1 = train_row[t1, time]; var 1..H: r2 = train_row[t2, time];
    var 1..W: c1 = train_col[t1, time]; var 1..W: c2 = train_col[t2, time];
  } in
  (r1, c1) != (r2, c2) \/ at_target(r1, c1)
);

% 6) No position swaps except at target
constraint forall(time in 0..MAX_TIME-1, t1 in 1..N_TRAINS, t2 in t1+1..N_TRAINS) (
  let {
    var 1..H: r1t = train_row[t1, time]; var 1..H: r1n = train_row[t1, time+1];
    var 1..W: c1t = train_col[t1, time]; var 1..W: c1n = train_col[t1, time+1];
    var 1..H: r2t = train_row[t2, time]; var 1..H: r2n = train_row[t2, time+1];
    var 1..W: c2t = train_col[t2, time]; var 1..W: c2n = train_col[t2, time+1];
  } in
  not ((r1t, c1t) = (r2n, c2n) /\ (r2t, c2t) = (r1n, c1n)) \/
  at_target(r1t, c1t) \/ at_target(r2t, c2t) \/ 
  at_target(r1n, c1n) \/ at_target(r2n, c2n)
);

% 7) Respect pre-placed pieces
constraint forall(p in INIT_POS) (grid[p.1, p.2] = p.3);

% 8) Place tunnel pieces at specified locations
constraint forall(i in 1..N_TUNNELS) (
  let {
    int: rA = TUNNEL_PAIRS[i].1; int: cA = TUNNEL_PAIRS[i].2; Dir: dA = TUNNEL_PAIRS[i].3;
    int: rB = TUNNEL_PAIRS[i].4; int: cB = TUNNEL_PAIRS[i].5; Dir: dB = TUNNEL_PAIRS[i].6;
  } in
  grid[rA, cA] = if dA=TOP then TUNNEL_T elseif dA=RIGHT then TUNNEL_R 
                 elseif dA=DOWN then TUNNEL_D else TUNNEL_L endif /\
  grid[rB, cB] = if dB=TOP then TUNNEL_T elseif dB=RIGHT then TUNNEL_R 
                 elseif dB=DOWN then TUNNEL_D else TUNNEL_L endif
);

% 9) Track budget constraint
constraint sum(r in 1..H, c in 1..W where grid[r,c] != EMPTY)(1) - 
           sum(p in INIT_POS where p.3 != EMPTY)(1) - 2*N_TUNNELS <= MAX_TRACKS;

% 10) Connectivity: corners/switches must connect to valid neighbors
constraint forall(r in 1..H, c in 1..W where grid[r,c] in CORNERS \/ grid[r,c] in SWITCHES) (
  forall(d in Dir where can_enter[grid[r,c], d]) (
    let { int: rr = r + dr[d]; int: cc = c + dc[d]; } in
    in_bounds(rr, cc) /\ grid[rr, cc] != EMPTY /\
    (grid[rr, cc] in TUNNELS \/ can_enter[grid[rr, cc], opposite[d]])
  )
);

% 11) Only allow tunnels from TUNNEL_PAIRS
constraint forall(r in 1..H, c in 1..W where grid[r,c] in TUNNELS) (
  exists(i in 1..N_TUNNELS) (
    (r = TUNNEL_PAIRS[i].1 /\ c = TUNNEL_PAIRS[i].2) \/
    (r = TUNNEL_PAIRS[i].4 /\ c = TUNNEL_PAIRS[i].5)
  )
);

% ============================================================
% SOLVE & OUTPUT
% ============================================================

% Piece costs: prefer simpler pieces (straights < corners < switches)
array[Piece] of int: piece_cost = [
  0, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 0, 0, 0, 0
];

solve minimize sum(r in 1..H, c in 1..W)(piece_cost[grid[r,c]]);

% Visualization
include "ide/vis.mzn"; 
output :: vis_server("viz.html", (
  grid_width: W, grid_height: H, target: TARGET,
  trains: [(TRAINS[t].1, TRAINS[t].2, TRAINS[t].3) | t in 1..N_TRAINS],
  init_positions: [(INIT_POS[i].1, INIT_POS[i].2, INIT_POS[i].3) | i in 1..N_INIT_POS],
  tunnels: [(TUNNEL_PAIRS[i].1, TUNNEL_PAIRS[i].2, TUNNEL_PAIRS[i].3,
             TUNNEL_PAIRS[i].4, TUNNEL_PAIRS[i].5, TUNNEL_PAIRS[i].6) | i in 1..N_TUNNELS]
)) (grid: showJSON(grid));

% Text output
output [
  "============================================================\n",
  "SOLUTION FOUND\n",
  "============================================================\n\n",
  "GRID LAYOUT:\n", show2d(grid), "\n\n",
  "Total piece cost: \(sum(r in 1..H, c in 1..W)(piece_cost[grid[r,c]]))\n",
  "Latest arrival: \(max(arrival_time))\n",
  "TRAIN PATHS:\n"
] ++ [
  "Train \(t): arrival at time \(arrival_time[t])\n" ++
  "  Path: " ++ show([(train_row[t,time], train_col[t,time]) | 
                      time in 0..fix(arrival_time[t])]) ++ "\n"
  | t in 1..N_TRAINS
];
