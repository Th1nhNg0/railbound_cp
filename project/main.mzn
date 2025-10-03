% ============================================================
% Railbound Puzzle Solver - Main Model
%
% This is the main MiniZinc model file. It defines the core
% parameters, decision variables, and includes all the modular
% components (types, constraints, output) to build the full model.
%
% To run the model, use:
%   minizinc --solver Gecode main.mzn data/instances/<puzzle>.dzn
%
% ============================================================

% ============================================================
% INCLUDES
% ============================================================

% --- Core Libraries ---
% These files define the fundamental building blocks of the model.
include "lib/types.mzn";      % Custom types and enums (Piece, Dir, etc.)
include "lib/globals.mzn";    % Global constants and helper lookups
include "lib/routing.mzn";    % Piece routing tables and logic

% --- Constraint Modules ---
% Each file contains a thematic group of constraints.
include "constraints/grid.mzn";       % Grid layout, budget, connectivity
include "constraints/movement.mzn";   % Train movement logic
include "constraints/sequencing.mzn"; % Arrival order and collision avoidance
include "constraints/gates.mzn";      % Gate and activation logic
include "constraints/dswitch.mzn";    % Dynamic switch logic
include "constraints/stations.mzn";   % Station logic

% --- Output Formatting ---
% Handles how the solution is displayed.
include "output/formatting.mzn";

% ============================================================
% PARAMETERS
% (Loaded from .dzn data files)
% ============================================================

% --- Grid Dimensions ---
int: W;  % Grid width (number of columns)
int: H;  % Grid height (number of rows)

% --- Simulation Settings ---
int: N_TRAINS;   % Number of trains
int: MAX_TIME;   % Max number of discrete time steps
int: MAX_TRACKS; % Max number of non-EMPTY pieces that can be placed

% --- Target Location ---
tuple(int, int): TARGET;

% --- Pre-placed Elements ---
int: N_INIT_POS;
int: N_TUNNELS;
int: N_GATES;
int: N_ACTIVATIONS;
int: N_DSWITCHES;
int: N_STATIONS;

% ============================================================
% INPUT DATA
% (Loaded from .dzn data files)
% ============================================================

array[1..N_TRAINS] of TrainStart: TRAINS;
array[1..N_INIT_POS] of Pos: INIT_POS;
array[1..N_TUNNELS] of TunnelPair: TUNNEL_PAIRS;
array[1..N_GATES] of Gate: GATES;
array[1..N_ACTIVATIONS] of Activation: ACTIVATIONS;
array[1..N_DSWITCHES] of DSwitch: DSWITCHES;
array[1..N_STATIONS] of Station: STATIONS;

% ============================================================
% DECISION VARIABLES
% ============================================================

% The piece placed at each grid cell
array[1..H, 1..W] of var Piece: grid;

% Train state variables
array[1..N_TRAINS, 0..MAX_TIME] of var 1..H: train_row;
array[1..N_TRAINS, 0..MAX_TIME] of var 1..W: train_col;
array[1..N_TRAINS, 1..MAX_TIME] of var Dir: train_dir;
array[1..N_TRAINS] of var 0..MAX_TIME: arrival_time;

% Game mechanic state variables
array[1..N_GATES, 0..MAX_TIME] of var bool: gate_open;
array[1..N_DSWITCHES, 0..MAX_TIME] of var bool: dswitch_swapped;
array[1..N_TRAINS, 1..N_STATIONS] of var bool: station_visited;
array[1..N_TRAINS, 0..MAX_TIME] of var 0..2: station_wait_time;

% ============================================================
% SOLVE
% ============================================================

% Search for a satisfying solution
solve satisfy;