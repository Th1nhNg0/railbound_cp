% main.mzn
%
% Main MiniZinc model file for solving Railbound puzzles.
%
% This file serves as the entry point for the constraint programming solver. It orchestrates
% the entire solving process by:
% 1. Including the necessary library files (types.mzn, globals.mzn, predicates.mzn).
% 2. Declaring the model's core parameters (e.g., grid size, track limits) and input data arrays.
% 3. Defining the decision variables that the solver will determine (e.g., grid layout, train paths).
% 4. Including all constraint modules from the `constraints/` directory to enforce game rules.
% 5. Specifying a search strategy to guide the solver towards a solution efficiently.
% 6. Including the output formatter to present the solution in a human-readable format.

include "lib/types.mzn";

% ============================================================
% PARAMETERS
% Puzzle-specific constants defined in `.dzn` data files.
% ============================================================

int: W;           % Grid width (number of columns).
int: H;           % Grid height (number of rows).
int: MAX_TIME;    % Maximum number of timesteps allowed for the simulation.
int: MAX_TRACKS;  % Maximum number of track pieces the player can place.

tuple(int, int): TARGET; % The single target cell `(row, col)` for all trains.

% ============================================================
% INPUT DATA
% Arrays defining the initial state of the puzzle.
% ============================================================

array[int] of TrainStart: TRAINS;      % Initial positions and directions of all trains.
array[int] of Pos: INIT_POS;           % Pre-placed, unmovable track pieces.
array[int] of TunnelPair: TUNNEL_PAIRS;% Defines connections between tunnel pieces.
array[int] of Gate: GATES;             % Gate locations, IDs, and initial states.
array[int] of Activation: ACTIVATIONS;% Cells that toggle the state of gates.
array[int] of DSwitch: DSWITCHES;      % Locations and IDs of dynamic switches.
array[int] of Station: STATIONS;       % Mandatory waypoints for specific trains.

% ============================================================
% COMPUTED PARAMETERS
% Derived constants calculated from the input data.
% ============================================================

int: N_TRAINS = length(TRAINS);
int: N_INIT_POS = length(INIT_POS);
int: N_TUNNELS = length(TUNNEL_PAIRS);
int: N_GATES = length(GATES);
int: N_ACTIVATIONS = length(ACTIVATIONS);
int: N_DSWITCHES = length(DSWITCHES);
int: N_STATIONS = length(STATIONS);

% Include global helpers after main parameters are defined.
include "lib/globals.mzn";
include "lib/predicates.mzn";

% ============================================================
% DECISION VARIABLES
% The core variables the solver needs to find values for.
% ============================================================

% The final layout of the track pieces on the HxW grid.
array[1..H, 1..W] of var Piece: grid;

% The row and column coordinate of each train `t` at each timestep `i`.
array[1..N_TRAINS, 0..MAX_TIME] of var 1..H: train_row;
array[1..N_TRAINS, 0..MAX_TIME] of var 1..W: train_col;
% The direction of travel of each train `t` at each timestep `i`.
array[1..N_TRAINS, 1..MAX_TIME] of var Dir: train_dir;

% The timestep at which each train `t` reaches the `TARGET`.
array[1..N_TRAINS] of var 0..MAX_TIME: arrival_time;

% The state (true=open, false=closed) of each gate `g` at each timestep `i`.
array[1..max(1, N_GATES), 0..MAX_TIME] of var bool: gate_open;
% The state (true=swapped, false=default) of each dynamic switch `ds` at each timestep `i`.
array[1..max(1, N_DSWITCHES), 0..MAX_TIME] of var bool: dswitch_swapped;
% The state of each exit-triggered switch `es` at each timestep `i`.
array[1..max(1, N_ESWITCHES), 0..MAX_TIME] of var bool: eswitch_swapped;

% Records whether train `t` has visited station `s`.
array[1..N_TRAINS, 1..max(1, N_STATIONS)] of var bool: station_visited;
% Manages the wait counter for a train at a station.
array[1..N_TRAINS, 0..MAX_TIME] of var 0..2: station_wait_time;


% ============================================================
% CONSTRAINT COMPOSITION
% Includes all game logic and rules from separate modules.
% ============================================================

include "constraints/capacity.mzn";
include "constraints/scheduling.mzn";
include "constraints/collision.mzn";
include "constraints/gates.mzn";
include "constraints/dswitch.mzn";
include "constraints/eswitch.mzn";
include "constraints/stations.mzn";

% ============================================================
% SEARCH STRATEGY
% Guides the solver on how to search for a solution.
% ============================================================

% This strategy is optimized to find solutions faster by prioritizing the
% most impactful decisions first.
solve
  % Phase 1: Determine the grid layout. This is the most constrained part of the
  % problem, so solving it first drastically reduces the search space.
  % `first_fail`: Prioritizes variables with the smallest domain.
  % `indomain_min`: Tries the smallest value in the domain first.
  :: int_search([grid[r, c] | r in 1..H, c in 1..W],
                 first_fail, indomain_min)

  % Phase 2: Determine the arrival times for the trains.
  % `input_order`: Tries variables in the order they are given.
  :: int_search(arrival_time, input_order, indomain_min)

  satisfy;

% ============================================================
% OUTPUT
% Includes the formatting file to print the solution nicely.
% ============================================================

include "output/formatting.mzn";