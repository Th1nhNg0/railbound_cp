% ============================================================
% TRAIN CONSTRAINTS
% ============================================================

% --- Train Initial Position Constraint ---
% Sets the initial position and first move for each train.
constraint forall(t in 1..N_TRAINS) (
  let {
    int: r0 = TRAINS[t].1;
    int: c0 = TRAINS[t].2;
    Dir: dir0 = TRAINS[t].3;
    int: intended_r = r0 + dr[dir0];
    int: intended_c = c0 + dc[dir0];
    Dir: intended_entry_dir = opposite[dir0];
    var bool: blocked_by_gate =
      if cell_has_gate[intended_r, intended_c] then
        not gate_open[gate_index_at[intended_r, intended_c], 1]
      else false endif;
  } in
  train_row[t, 0] = r0 /\
  train_col[t, 0] = c0 /\
  can_enter[grid[intended_r, intended_c], intended_entry_dir] /\
  if N_GATES>0 /\ blocked_by_gate then
    train_row[t, 1] = r0 /\
    train_col[t, 1] = c0 /\
    train_dir[t, 1] = intended_entry_dir
  else
    train_row[t, 1] = intended_r /\
    train_col[t, 1] = intended_c /\
    train_dir[t, 1] = intended_entry_dir
  endif
);


% --- Train Movement Constraint ---
% Defines how trains move from one cell to the next based on track pieces and gates.
constraint forall(t in 1..N_TRAINS, time in 1..MAX_TIME-1 where time < arrival_time[t]) (
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
    var bool: blocked_by_gate = if N_GATES>0 /\ cell_has_gate[intended_r, intended_c] then
        not gate_open[gate_index_at[intended_r, intended_c], time+1]
      else false endif;
    var Piece: effective_piece = 
      if N_DSWITCHES > 0 /\ cell_has_dswitch[r, c] then dswitch_effective_piece(piece, dswitch_toggled[dswitch_index_at[r, c], time]) 
      elseif N_ESWITCHES > 0 /\ cell_has_eswitch[r, c] then eswitch_effective_piece(piece, eswitch_toggled[eswitch_index_at[r, c], time])
      else piece endif;
  } in

  % If the train is waiting at a station, it remains stationary.
  if station_wait_time[t, time] > 0 then
    (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
  else
    (if piece in TUNNELS_SET then
       let {
         var tuple(int, int): dest = tunnel_dest[r, c];
         var int: dest_exit_dir = tunnel_exit_dir[r, c];
         var Dir: dest_exit_dir_enum = to_enum(Dir, dest_exit_dir);
         var int: dest_r = dest.1;
         var int: dest_c = dest.2;
       } in
       intended_r = dest_r + dr[dest_exit_dir_enum] /\
       intended_c = dest_c + dc[dest_exit_dir_enum] /\
       intended_entry_dir = opposite[dest_exit_dir_enum]
     else
       exit_dir = exit_of[effective_piece, entry_dir] /\
       intended_r = r + dr[exit_dir] /\
       intended_c = c + dc[exit_dir] /\
       intended_entry_dir = opposite[exit_dir]
     endif) /\
    can_enter[grid[intended_r, intended_c], intended_entry_dir] /\
    if blocked_by_gate then
      (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
    else
      (next_r, next_c, next_entry_dir) = (intended_r, intended_c, intended_entry_dir)
    endif  
  endif
);

% --- Train Arrival Constraint ---
% A train is considered arrived when it reaches the target and remains there for all subsequent timesteps.
constraint forall(t in 1..N_TRAINS, time in 1..MAX_TIME where time >= arrival_time[t]) (
    (train_row[t, time] = TARGET.1 /\ train_col[t, time] = TARGET.2 /\ train_dir[t, time] = LEFT)
);

% --- Sequential Arrival Constraint ---
% Trains must arrive in sequential order (train 1, then train 2, etc.).
constraint forall(t in 1..N_TRAINS-1) (
  arrival_time[t] < arrival_time[t+1]
);

% --- No Collision Constraint ---
% Ensures that no two trains occupy the same cell at the same time (before either arrives).
constraint forall(t1 in 1..N_TRAINS, t2 in t1 + 1..N_TRAINS, i in 1..MAX_TIME where i < arrival_time[t1])(
    (train_row[t1, i] != train_row[t2, i] \/ train_col[t1, i] != train_col[t2, i])
);

% --- No Position Swap Constraint ---
% Prevents trains from swapping positions in consecutive time steps (including through tunnels).
constraint forall(t1 in 1..N_TRAINS, t2 in t1 + 1..N_TRAINS, i in 1..MAX_TIME-1 where i < arrival_time[t1])(
    let {
        var tuple(int, int): eff_pos1 = get_effective_pos(train_row[t1, i], train_col[t1, i]),
        var tuple(int, int): eff_pos2 = get_effective_pos(train_row[t2, i], train_col[t2, i])
    } in 
    % They cannot swap positions
    eff_pos1 != (train_row[t2, i+1], train_col[t2, i+1]) \/
    eff_pos2 != (train_row[t1, i+1], train_col[t1, i+1])
);