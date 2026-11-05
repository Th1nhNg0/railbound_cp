% ============================================================
% main.mzn - Railbound Constraint Programming Solver
% ============================================================
% Core model that combines grid placement, train movement, decoy behavior,
% and all puzzle mechanics (gates, switches, stations, tunnels, activations).
% Solves Railbound puzzle levels by finding valid track placements and routes.
% ============================================================
include "lib/types.mzn";

% ==== INPUT PARAMETERS (from puzzle data file) ====
int: W;          % Grid width (columns).
int: H;          % Grid height (rows).
int: MAX_TIME;   % Maximum time horizon for solving.
int: MAX_TRACKS; % Max tracks allowed to be placed (puzzle constraint).
tuple(int, int): TARGET; % Target destination for trains.
array[int] of tuple(int, int, Dir): TRAINS;    % Train starting positions and initial directions.
array[int] of tuple(int, int, Dir): DECOYS;    % Decoy train starting positions and initial directions.
array[int] of tuple(int, int, Piece): INIT_POS; % Pre-placed tracks that cannot be moved.
array[int] of tuple(int, int, Dir, int, int, Dir): TUNNEL_PAIRS; % Tunnel entrance-exit pairs.
array[int] of tuple(int, int, int, bool): GATES; % Gates: (row, col, activation_id, initial_state).
array[int] of tuple(int, int, int): ACTIVATIONS; % Activation cells: (row, col, activation_id).
array[int] of tuple(int, int, int): DSWITCHES; % Dynamic switches: (row, col, activation_id).
array[int] of tuple(int, int, int): STATIONS; % Stations: (row, col, train_id).
int: SEMAPHORE_SUPPLY; % Available semaphore placements the player can use.
array[int] of tuple(int, int): FIXED_SEMAPHORES; % Semaphores pre-placed by the level (not counted in the supply).

% ==== DERIVED COUNTS (computed from input) ====
int: N_TRAINS = length(TRAINS);          % Number of player trains to solve for.
int: N_DECOYS = length(DECOYS);          % Number of decoy trains to avoid.
int: N_INIT_POS = length(INIT_POS);      % Number of pre-placed track pieces.
int: N_TUNNELS = length(TUNNEL_PAIRS);   % Number of tunnel pairs.
int: N_GATES = length(GATES);            % Number of gates.
int: N_ACTIVATIONS = length(ACTIVATIONS); % Number of activation tiles.
int: N_DSWITCHES = length(DSWITCHES);    % Number of dynamic switches.
int: N_STATIONS = length(STATIONS);      % Number of stations.
int: N_ESWITCHES = sum(i in 1..N_INIT_POS)(bool2int(INIT_POS[i].3 in ESWITCHES_SET)); % Number of exit-triggered switches.
include "lib/globals.mzn";

% ==== DECISION VARIABLES ====

% Grid: Tracks and pieces to place on the puzzle board.
array[1..H, 1..W] of var Piece: grid; % Grid cells contain track pieces (straights, corners, switches, etc.).
% Row-major view of the grid (index = cell(r, c)), plus the off-board sink 0.
array[CELLS] of var Piece: grid_flat = array1d(grid);
array[CELLS0] of var Piece: grid_ext = array1d(CELLS0, [EMPTY] ++ grid_flat);

% Train Movement: Cell and entry direction of each train at each timestep.
array[1..N_TRAINS, 0..MAX_TIME] of var CELLS: train_pos;    % Train cell index over time.
array[1..N_TRAINS, 1..MAX_TIME] of var Dir: train_dir;      % Direction train enters each cell.
% Arrival bounds must remain independent of geometric distance: a tunnel can
% move a train farther than its Manhattan distance permits in one timestep.
array[1..N_TRAINS] of var 1..MAX_TIME: arrival_time;

% Decoy Movement: Cell and entry direction of each decoy (obstacle to avoid).
array[1..N_DECOYS, 0..MAX_TIME] of var CELLS: decoy_pos;
array[1..N_DECOYS, 1..MAX_TIME] of var Dir: decoy_dir;

% Gate/Switch State: Toggle states for gates, dynamic switches, and exit-triggered switches.
set of int: GATE_INDICES = 1..N_GATES;
set of int: DSWITCH_INDICES = 1..N_DSWITCHES;
set of int: ESWITCH_INDICES = 1..N_ESWITCHES;
array[GATE_INDICES, 0..MAX_TIME] of var bool: gate_open;
array[DSWITCH_INDICES, 0..MAX_TIME] of var bool: dswitch_toggled;
array[ESWITCH_INDICES, 0..MAX_TIME] of var bool: eswitch_toggled;

% Station state (index sets are empty when the level has no stations).
set of int: STATION_TIMES = if N_STATIONS = 0 then {} else 0..MAX_TIME endif;
array[1..N_TRAINS, STATION_TIMES] of var 0..2: station_wait_time;
array[1..N_DECOYS, STATION_TIMES] of var 0..2: decoy_station_wait_time;
array[1..N_STATIONS, 0..MAX_TIME] of var bool: station_visited_by_time;

% Semaphore Placement: presence indicator and opening time per cell
% (opening time 0 = no semaphore; MAX_TIME + 1 = never opens).
array[1..H, 1..W] of var bool: semaphore_present;
array[1..H, 1..W] of var 0..(MAX_TIME + 1): semaphore_open_time;

% ==== DERIVED PER-CELL STATE (shared by trains and decoys) ====

% Cells that may host a semaphore: any straight or corner tile without another
% feature (gate, activation tile, station, tunnel, car start or the target).
array[CELLS] of bool: fixed_semaphore = [
  exists(i in index_set(FIXED_SEMAPHORES))(cell(FIXED_SEMAPHORES[i].1, FIXED_SEMAPHORES[i].2) = p) | p in CELLS ];
bool: HAS_SEMAPHORES = SEMAPHORE_SUPPLY > 0 \/ length(FIXED_SEMAPHORES) > 0;
array[CELLS] of bool: semaphore_candidate = [
  fixed_semaphore[p] \/
  SEMAPHORE_SUPPLY > 0 /\ gate_at[p] = 0 /\ not is_activation_cell[p] /\
  not is_tunnel_cell[p] /\ p != TARGET_CELL /\
  not exists(st in 1..N_STATIONS)(cell(STATIONS[st].1, STATIONS[st].2) = p) /\
  not exists(t in 1..N_TRAINS)(cell(TRAINS[t].1, TRAINS[t].2) = p) /\
  not exists(d in 1..N_DECOYS)(cell(DECOYS[d].1, DECOYS[d].2) = p)
| p in CELLS ];

% effective_piece[p, t]: routing of cell p at time t, i.e. the placed piece
% with any dynamic / exit-triggered switch toggle applied.  Switch cells are
% pre-placed, so their two possible routings are parameters.
array[CELLS, 0..MAX_TIME] of var Piece: effective_piece = array2d(CELLS, 0..MAX_TIME, [
  if dswitch_at[p] > 0 then
    (if dswitch_toggled[dswitch_at[p], t] then switch_toggle[init_piece[p]] else init_piece[p] endif)
  elseif eswitch_at[p] > 0 then
    (if eswitch_toggled[eswitch_at[p], t] then switch_toggle[init_piece[p]] else init_piece[p] endif)
  else grid_flat[p] endif
| p in CELLS, t in 0..MAX_TIME ]);

% Whether any switch changes routing during the run.  Only then can a vehicle
% waiting on a cell see its exit change, which the heading variables below
% guard against (a vehicle keeps the exit it got when it entered the cell).
bool: SWITCHES_TOGGLE = N_DSWITCHES + N_ESWITCHES > 0;

% blocked[p, t]: entering cell p on the move that lands at time t is refused
% by a closed gate or a semaphore that has not opened yet.  Cell 0 (off-board)
% is never "blocked"; it is rejected by can_enter instead.
array[CELLS0, 1..MAX_TIME] of var bool: blocked = array2d(CELLS0, 1..MAX_TIME, [
  if p = 0 then false
  else
    (if gate_at[p] > 0 then not gate_open[gate_at[p], t] else false endif) \/
    (if semaphore_candidate[p] then t < semaphore_open_time[cell_row[p], cell_col[p]] else false endif)
  endif
| p in CELLS0, t in 1..MAX_TIME ]);

% ============================================================
% CONSTRAINTS
% ============================================================

include "constraints/grid.mzn";
include "constraints/trains.mzn";
include "constraints/decoys.mzn";
include "constraints/activations.mzn";
include "constraints/eswitches.mzn";
include "constraints/semaphores.mzn";
include "constraints/stations.mzn";

% ==== SEARCH ====
% Two complementary orders; pick one with -D "SEARCH=1;" or "SEARCH=2;"
% (default 1).  scripts/solve.py runs both in parallel and keeps the first
% answer, since neither order dominates across the campaign.
%
%  1 (train-major): earliest arrival schedule first, then each train's route
%    step by step, one train after another.  Best on large boards where
%    trains interact little (most of world 8).
%  2 (time-major): advance all trains together one timestep at a time, like a
%    game simulation, trying the cell closest to the target first.  Best when
%    trains must cooperate through gates, decoys or semaphores (e.g. 3-11B,
%    7-5A).
% Given the grid, movement is deterministic, so committing to positions lets
% propagation lay the track the route needs; remaining cells are filled last.
opt int: SEARCH;
int: SEARCH_ORDER = if occurs(SEARCH) then deopt(SEARCH) else 1 endif;
constraint assert(SEARCH_ORDER in 1..2, "SEARCH must be 1 or 2");

ann: train_major = seq_search([
  int_search(arrival_time, input_order, indomain_min),
  int_search([train_pos[t, i] | t in 1..N_TRAINS, i in 1..MAX_TIME], input_order, indomain_min),
  int_search(grid_flat, input_order, indomain_min)
]);
ann: time_major = seq_search([
  int_search([ if k = 1 then dist_to_target[train_pos[t, i]] else train_pos[t, i] endif
             | i in 1..MAX_TIME, t in 1..N_TRAINS, k in 1..2 ], input_order, indomain_min),
  int_search(arrival_time, input_order, indomain_min),
  int_search(grid_flat, input_order, indomain_min)
]);

solve :: if SEARCH_ORDER = 1 then train_major else time_major endif satisfy;

include "formatting.mzn";
