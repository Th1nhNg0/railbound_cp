% ============================================================
% Railbound Puzzle Solver (Modular Main)
% ------------------------------------------------------------
% Composes the Railbound constraint model from reusable
% modules for types, helpers, constraints, and output.
% ============================================================

include "globals.mzn";              % MiniZinc global constraint library
include "lib/types.mzn";            % Shared enums and type aliases

% ============================================================
% PARAMETERS
% ============================================================

int: W;             % Grid width
int: H;             % Grid height
int: N_TRAINS;      % Number of trains
int: MAX_TIME;      % Simulation horizon (time steps)
int: MAX_TRACKS;    % Max number of track pieces that can be placed

% Target cell trains must reach sequentially
tuple(int, int): TARGET;

% Pre-placed elements
int: N_INIT_POS;
int: N_TUNNELS;
int: N_GATES;
int: N_ACTIVATIONS;
int: N_DSWITCHES;
int: N_STATIONS;

% ============================================================
% INPUT DATA
% ============================================================

array[1..N_TRAINS] of TrainStart: TRAINS;
array[1..N_INIT_POS] of Pos: INIT_POS;
array[1..N_TUNNELS] of TunnelPair: TUNNEL_PAIRS;
array[1..N_GATES] of Gate: GATES;
array[1..N_ACTIVATIONS] of Activation: ACTIVATIONS;
array[1..N_DSWITCHES] of DSwitch: DSWITCHES;
array[1..N_STATIONS] of Station: STATIONS;

include "lib/globals.mzn";          % Direction helpers and lookup tables
include "lib/predicates.mzn";       % Generic predicates and functions

% ============================================================
% DECISION VARIABLES
% ============================================================

array[1..H, 1..W] of var Piece: grid;
array[1..N_TRAINS, 0..MAX_TIME] of var 1..H: train_row;
array[1..N_TRAINS, 0..MAX_TIME] of var 1..W: train_col;
array[1..N_TRAINS, 1..MAX_TIME] of var Dir: train_dir;
array[1..N_TRAINS] of var 0..MAX_TIME: arrival_time;
array[1..N_GATES, 0..MAX_TIME] of var bool: gate_open;
array[1..N_DSWITCHES, 0..MAX_TIME] of var bool: dswitch_swapped;
array[1..N_TRAINS, 1..N_STATIONS] of var bool: station_visited;
array[1..N_TRAINS, 0..MAX_TIME] of var 0..2: station_wait_time;

% ============================================================
% CONSTRAINT COMPOSITION
% ============================================================

include "constraints/scheduling.mzn";  % Movement and arrival ordering
include "constraints/collision.mzn";   % Collision avoidance
include "constraints/capacity.mzn";    % Track placement and budget
include "constraints/gates.mzn";       % Gate placement and dynamics
include "constraints/dswitch.mzn";     % Dynamic switch behaviour
include "constraints/stations.mzn";    % Station validation and dwell

% ============================================================
% SEARCH AND SOLUTION STRATEGY
% ============================================================

solve:: int_search([grid[r, c] | r in 1..H, c in 1..W],
                    first_fail, indomain_min, complete)
     :: int_search([arrival_time[t] | t in 1..N_TRAINS],
                    first_fail, indomain_min, complete)
satisfy;

include "output/formatting.mzn";     % Textual and visual outputs
