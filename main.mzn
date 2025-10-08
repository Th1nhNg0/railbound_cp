include "lib/types.mzn";

int: W;        
int: H;          
int: MAX_TIME;   
int: MAX_TRACKS; 
tuple(int, int): TARGET;
array[int] of tuple(int, int, Dir): TRAINS;    
array[int] of tuple(int, int, Piece): INIT_POS;
array[int] of tuple(int, int, Dir, int, int, Dir): TUNNEL_PAIRS;
array[int] of tuple(int, int, int, bool): GATES;             
array[int] of tuple(int, int, int): ACTIVATIONS;
array[int] of tuple(int, int, int): DSWITCHES;   
array[int] of tuple(int, int, int): STATIONS;    

% ============================================================
% COMPUTED PARAMETERS
% ============================================================

int: N_TRAINS = length(TRAINS);
int: N_INIT_POS = length(INIT_POS);
int: N_TUNNELS = length(TUNNEL_PAIRS);
int: N_GATES = length(GATES);
int: N_ACTIVATIONS = length(ACTIVATIONS);
int: N_DSWITCHES = length(DSWITCHES);
int: N_STATIONS = length(STATIONS);
int: N_ESWITCHES = sum(i in 1..N_INIT_POS)(bool2int(INIT_POS[i].3 in ESWITCHES_SET));

include "lib/globals.mzn";

% ============================================================
% DECISION VARIABLES
% ============================================================
array[1..H, 1..W] of var Piece: grid;
array[1..N_TRAINS, 0..MAX_TIME] of var 1..H: train_row;
array[1..N_TRAINS, 0..MAX_TIME] of var 1..W: train_col;
array[1..N_TRAINS, 1..MAX_TIME] of var Dir: train_dir;
array[1..N_TRAINS] of var N_TRAINS..MAX_TIME: arrival_time;
% The state (true=open, false=closed) of each gate `g` at each timestep `i`.
array[0..max(1, N_GATES), 0..MAX_TIME] of var bool: gate_open;
% The state of each dynamic switch at each timestep.
% A DSWITCH has two possible states representing its toggled configuration.
% For example, DSWITCH_T_D_R can toggle to DSWITCH_D_T_R.
% We track this as a boolean: false=original orientation, true=toggled orientation.
array[1..max(1, N_DSWITCHES), 0..MAX_TIME] of var bool: dswitch_toggled;

% ============================================================
% CONSTRAINTS
% ============================================================

include "constraints/grid.mzn";
include "constraints/trains.mzn";
include "constraints/gates.mzn";
include "constraints/dswitches.mzn";
include "constraints/stations.mzn";



solve satisfy;

include "formatting.mzn";
