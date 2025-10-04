% ============================================================
% Railbound Puzzle Solver (Optimized Version)
% ------------------------------------------------------------
% Enhanced version with improved search strategies and
% constraint ordering to minimize node exploration.
% ============================================================

include "globals.mzn";
include "lib/types.mzn";

% ============================================================
% PARAMETERS
% ============================================================

int: W;
int: H;
int: N_TRAINS;
int: MAX_TIME;
int: MAX_TRACKS;

tuple(int, int): TARGET;

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

include "lib/globals.mzn";
include "lib/predicates.mzn";

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

include "constraints/capacity.mzn";
include "constraints/scheduling.mzn";
include "constraints/collision.mzn";
include "constraints/gates.mzn";
include "constraints/dswitch.mzn";
include "constraints/stations.mzn";

% ============================================================
% OPTIMIZED SEARCH STRATEGY (OR-Tools Compatible)
% ============================================================

% Key optimizations:
% 1. Grid-first search strategy to prune early
% 2. Use first_fail for grid to focus on constrained cells
% 3. Input order for arrival times respects sequential constraint
% 4. Parallel search with OR-Tools for best performance

solve
  % Phase 1: Place grid pieces first (most constrained)
  :: int_search([grid[r, c] | r in 1..H, c in 1..W],
                 first_fail, indomain_min)
  
  % Phase 2: Fix arrival times
  :: int_search(arrival_time, input_order, indomain_min)
  
  satisfy;

include "output/formatting.mzn";
