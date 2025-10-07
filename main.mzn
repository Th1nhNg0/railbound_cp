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
array[1..N_TRAINS] of var 0..MAX_TIME: arrival_time;
% The state (true=open, false=closed) of each gate `g` at each timestep `i`.
array[0..N_GATES, 0..MAX_TIME] of var bool: gate_open;

% ============================================================
% CONSTRAINTS
% ============================================================

include "constraints/grid.mzn";
include "constraints/trains.mzn";
include "constraints/gates.mzn";


solve minimize sum(r in 1..H, c in 1..W)(
  bool2int(grid[r, c] != EMPTY /\
       not exists(i in 1..N_INIT_POS)(
         INIT_POS[i].1 = r /\ INIT_POS[i].2 = c
       )
        /\ not (grid[r, c] in TUNNELS_SET)
       )
);

include "formatting.mzn";
