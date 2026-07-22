include "../lib/types.mzn";

int: W;
int: H;
int: MAX_TIME;
int: MAX_TRACKS;
tuple(int, int): TARGET;
array[int] of tuple(int, int, Dir): TRAINS;
array[int] of tuple(int, int, Dir): DECOYS;
array[int] of tuple(int, int, Piece): INIT_POS;
array[int] of tuple(int, int, Dir, int, int, Dir): TUNNEL_PAIRS;
array[int] of tuple(int, int, int, bool): GATES;
array[int] of tuple(int, int, int): ACTIVATIONS;
array[int] of tuple(int, int, int): DSWITCHES;
array[int] of tuple(int, int, int): STATIONS;
int: SEMAPHORE_SUPPLY;

int: N_TRAINS = length(TRAINS);
int: N_DECOYS = length(DECOYS);
int: N_INIT_POS = length(INIT_POS);
int: N_TUNNELS = length(TUNNEL_PAIRS);
int: N_GATES = length(GATES);
int: N_ACTIVATIONS = length(ACTIVATIONS);
int: N_DSWITCHES = length(DSWITCHES);
int: N_STATIONS = length(STATIONS);
int: N_ESWITCHES = sum(i in 1..N_INIT_POS)(bool2int(INIT_POS[i].3 in ESWITCHES_SET));
include "../lib/globals.mzn";

array[1..H, 1..W] of var Piece: grid;
array[1..N_TRAINS, 0..MAX_TIME] of var 1..H: train_row;
array[1..N_TRAINS, 0..MAX_TIME] of var 1..W: train_col;
array[1..N_TRAINS, 1..MAX_TIME] of var Dir: train_dir;
array[1..N_TRAINS] of var 1..MAX_TIME: arrival_time;
array[1..N_DECOYS, 0..MAX_TIME] of var 1..H: decoy_row;
array[1..N_DECOYS, 0..MAX_TIME] of var 1..W: decoy_col;
array[1..N_DECOYS, 1..MAX_TIME] of var Dir: decoy_dir;

set of int: GATE_INDICES = if N_GATES = 0 then {} else 1..N_GATES endif;
set of int: DSWITCH_INDICES = if N_DSWITCHES = 0 then {} else 1..N_DSWITCHES endif;
set of int: ESWITCH_INDICES = if N_ESWITCHES = 0 then {} else 1..N_ESWITCHES endif;
array[GATE_INDICES, 0..MAX_TIME] of var bool: gate_open;
array[DSWITCH_INDICES, 0..MAX_TIME] of var bool: dswitch_toggled;
array[ESWITCH_INDICES, 0..MAX_TIME] of var bool: eswitch_toggled;

set of int: STATION_TIMES = if N_STATIONS = 0 then {} else 0..MAX_TIME endif;
array[1..N_TRAINS, STATION_TIMES] of var 0..2: station_wait_time;
array[1..N_DECOYS, STATION_TIMES] of var 0..2: decoy_station_wait_time;
array[1..N_STATIONS, 0..MAX_TIME] of var bool: station_visited_by_time;

array[1..H, 1..W] of var bool: semaphore_present;
array[1..H, 1..W] of var 0..(MAX_TIME + 1): semaphore_open_time;

include "../constraints/grid.mzn";
include "../constraints/trains.mzn";
