% ============================================================
% main.mzn - Railbound Constraint Programming Solver
% ============================================================
% Core model that combines grid placement, train movement, decoy behavior,
% and all puzzle mechanics (gates, switches, stations, tunnels, activations).
% Solves Railbound puzzle levels by finding valid track placements and routes.
% ============================================================

include "globals.mzn";
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

% Train Movement: Position and direction of each train at each timestep.
array[1..N_TRAINS, 0..MAX_TIME] of var 1..H: train_row;     % Train row position over time.
array[1..N_TRAINS, 0..MAX_TIME] of var 1..W: train_col;     % Train column position over time.
array[1..N_TRAINS, 1..MAX_TIME] of var Dir: train_dir;      % Direction train enters each cell.
array[1..N_TRAINS] of var 1..MAX_TIME: arrival_time;        % When each train reaches the target.

% Decoy Movement: Position and direction of each decoy train (obstacle to avoid).
array[1..N_DECOYS, 0..MAX_TIME] of var 1..H: decoy_row;     % Decoy row position over time.
array[1..N_DECOYS, 0..MAX_TIME] of var 1..W: decoy_col;     % Decoy column position over time.
array[1..N_DECOYS, 1..MAX_TIME] of var Dir: decoy_dir;      % Direction decoy enters each cell.

% Gate/Switch State: Toggle states for gates, dynamic switches, and exit-triggered switches.
array[1..N_GATES, 0..MAX_TIME] of var bool: gate_open;      % Gate state over time (true=open, false=closed).
array[1..N_DSWITCHES, 0..MAX_TIME] of var bool: dswitch_toggled; % Dswitch toggle state (false=original, true=toggled).
array[1..N_ESWITCHES, 0..MAX_TIME] of var bool: eswitch_toggled; % Eswitch toggle state (false=original, true=toggled).

% Semaphore Placement: Coordinate slots (0,0 means unused) and derived presence grid.
int: SEMAPHORE_SLOT_COUNT = if SEMAPHORE_SUPPLY = 0 then 1 else SEMAPHORE_SUPPLY endif;
set of int: SEMAPHORE_SLOTS = 1..SEMAPHORE_SLOT_COUNT;
array[SEMAPHORE_SLOTS] of var 0..H: semaphore_place_row;    % Row position for each semaphore slot (0 => unused).
array[SEMAPHORE_SLOTS] of var 0..W: semaphore_place_col;    % Column position for each semaphore slot (0 => unused).
array[1..H, 1..W] of var bool: semaphore_present =
  array2d(1..H, 1..W, [
    exists(s in SEMAPHORE_SLOTS)(
      semaphore_place_row[s] = r /\ semaphore_place_col[s] = c
    )
  | r in 1..H, c in 1..W
  ]);                                                        % Derived presence indicator per cell.
array[SEMAPHORE_SLOTS] of var 0..(MAX_TIME + 1): semaphore_slot_open_time; % Opening time associated with each slot.
array[1..H, 1..W] of var 0..(MAX_TIME + 1): semaphore_open_time =
  array2d(1..H, 1..W, [
    sum(s in SEMAPHORE_SLOTS)(
      if semaphore_place_row[s] = r /\ semaphore_place_col[s] = c then
        semaphore_slot_open_time[s]
      else 0
      endif
    )
  | r in 1..H, c in 1..W
  ]);                                                        % Derived opening time per cell (0=no semaphore).

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



solve satisfy;

include "formatting.mzn";
