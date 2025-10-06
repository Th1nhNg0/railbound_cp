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

constraint sum(r in 1..H, c in 1..W)(
  bool2int(grid[r, c] != EMPTY /\
       not exists(i in 1..N_INIT_POS)(
         INIT_POS[i].1 = r /\ INIT_POS[i].2 = c
       ))
) <= MAX_TRACKS;

constraint forall(i in 1..N_INIT_POS)(
    grid[INIT_POS[i].1, INIT_POS[i].2] = INIT_POS[i].3
);

constraint forall(r in 1..H, c in 1..W)(
    grid[r, c] in DSWITCHES_SET \/ grid[r, c] in ESWITCHES_SET \/ grid[r,c] in TUNNELS_SET->
    exists(i in 1..N_INIT_POS)(
        INIT_POS[i].1 = r /\ INIT_POS[i].2 = c /\ 
        (INIT_POS[i].3 in DSWITCHES_SET \/ INIT_POS[i].3 in ESWITCHES_SET \/ INIT_POS[i].3 in TUNNELS_SET)
    )
);

constraint forall(t in 1..N_TRAINS, i in 1..arrival_time[t])(
    grid[train_row[t, i], train_col[t, i]] != EMPTY
);
predicate in_bounds(int: r, int: c) =
  r >= 1 /\ r <= H /\ c >= 1 /\ c <= W;

  
constraint forall(r in 1..H, c in 1..W)(
    % If this cell has a switch that's not pre-placed
    ((grid[r, c] in SWITCHES_SET \/ grid[r, c] in DSWITCHES_SET \/ grid[r, c] in ESWITCHES_SET) /\
    not cell_is_init[r, c])
    ->
    % Then all directions that the switch can accept entry from or exit to
    % must have valid connecting neighbors
    forall(d in Dir)(
        (can_enter[grid[r, c], d] \/ can_exit[grid[r, c], d]) ->
        let {
            int: nr = r + dr[d];
            int: nc = c + dc[d];
        } in
        in_bounds(nr, nc) /\ grid[nr, nc] != EMPTY /\
        (can_enter[grid[nr, nc], d] \/ can_exit[grid[nr, nc], opposite[d]])
    )
);

constraint forall(t in 1..N_TRAINS) (
  train_row[t, 0] = TRAINS[t].1 /\
  train_col[t, 0] = TRAINS[t].2 /\
  train_row[t, 1] = TRAINS[t].1 + dr[TRAINS[t].3] /\
  train_col[t, 1] = TRAINS[t].2 + dc[TRAINS[t].3] /\
  train_dir[t, 1] = opposite[TRAINS[t].3]
);


constraint forall(t in 1..N_TRAINS, time in 1..MAX_TIME-1) (
  let {
    var 1..H: r = train_row[t, time];
    var 1..W: c = train_col[t, time];
    var Dir: entry_dir = train_dir[t, time];
    var Piece: piece = grid[r, c];
    var Dir: exit_dir;
    var 1..H: next_r = train_row[t, time+1];
    var 1..W: next_c = train_col[t, time+1];
    var Dir: next_entry_dir = train_dir[t, time+1];
    var 1..H: intended_r;
    var 1..W: intended_c;
    var Dir: intended_entry_dir;
    % var bool: blocked_by_gate =
    %   if N_GATES = 0 then false
    %   else
    %     if cell_has_gate[intended_r, intended_c] then
    %       not gate_open[gate_index_at[intended_r, intended_c], time+1]
    %     else false endif
    %   endif;
    % var bool: is_dswitch = piece in DSWITCHES_SET;
    % var bool: is_eswitch = piece in ESWITCHES_SET;
    % var bool: dswitch_state =
    %   if N_DSWITCHES > 0 /\ is_dswitch /\ cell_has_dswitch[r, c] then
    %     dswitch_swapped[dswitch_index_at[r, c], time]
    %   else false endif;
    % var bool: eswitch_state =
    %   if N_ESWITCHES > 0 /\ is_eswitch /\ cell_has_eswitch[r, c] then
    %     eswitch_swapped[eswitch_index_at[r, c], time]
    %   else false endif;
  } in
  % If the train is already at the target or waiting at a station, it does not move.
  if r == TARGET.1 /\ c == TARGET.2 then
    (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
  % elseif station_wait_time[t, time] > 0 then
  %   (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
  else
    % Determine the exit direction based on the piece type (standard, dswitch, or eswitch).
    can_enter[piece, entry_dir] /\
    % (if is_dswitch then exit_dir = dswitch_exit(piece, entry_dir, dswitch_state)
    %  elseif is_eswitch then exit_dir = eswitch_exit(piece, entry_dir, eswitch_state)
    %  else 
    exit_dir = exit_of[piece, entry_dir] /\
    %  endif) /\
    % Determine the intended next cell based on the exit direction or tunnel destination.
    % (if piece in TUNNELS then
    %    let {
    %      var tuple(int, int): dest = tunnel_dest[r, c];
    %      var int: dest_exit_dir = tunnel_exit_dir[r, c];
    %      var Dir: dest_exit_dir_enum = to_enum(Dir, dest_exit_dir);
    %    } in
    %    intended_r = dest.1 + dr[dest_exit_dir_enum] /\
    %    intended_c = dest.2 + dc[dest_exit_dir_enum] /\
    %    intended_entry_dir = opposite[dest_exit_dir_enum]
    %  else
       intended_r = r + dr[exit_dir] /\
       intended_c = c + dc[exit_dir] /\
       intended_entry_dir = opposite[exit_dir] /\
    %  endif) /\
    % The train must be able to enter the piece at the intended next cell.
    can_enter[grid[intended_r, intended_c], intended_entry_dir] /\
    % If the path is blocked by a gate, the train waits; otherwise, it moves.
    % if blocked_by_gate then
    %   (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
    % else
      (next_r, next_c, next_entry_dir) = (intended_r, intended_c, intended_entry_dir)
    % endif
  endif
);

% A train has arrived if and only if its position is the target.
constraint forall(t in 1..N_TRAINS, time in 0..MAX_TIME) (
    (train_row[t, time] = TARGET.1 /\ train_col[t, time] = TARGET.2)
    <-> (time >= arrival_time[t])
);
% Trains must arrive in sequential order (train 1, then train 2, etc.).
constraint forall(t in 1..N_TRAINS-1) (
  arrival_time[t] < arrival_time[t+1]
);

% Ensures that no two trains are in the same cell at the same time.
constraint forall(t1 in 1..N_TRAINS, t2 in t1 + 1..N_TRAINS)(
    forall(i in 1..max(arrival_time[t1], arrival_time[t2]))(
        if i <= arrival_time[t1] /\ i <= arrival_time[t2] then
            % If both trains are active, their positions must not be the same.
            (train_row[t1, i], train_col[t1, i]) != (train_row[t2, i], train_col[t2, i])
        else
            true
        endif
    )
);



include "formatting.mzn";