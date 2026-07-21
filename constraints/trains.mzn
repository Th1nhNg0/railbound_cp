% ============================================================
% constraints/trains.mzn - Train Movement & Arrival Constraints
% ============================================================
% Defines train starting positions, movement mechanics through the grid,
% arrival at target, sequencing, and collision avoidance with other trains.
% ============================================================

% ==== TRAIN INITIAL POSITION ====
% First position (time 0) and first move depend on gate blocking.
constraint forall(t in 1..N_TRAINS) (
  let {
    1..H: r0 = TRAINS[t].1;
    1..W: c0 = TRAINS[t].2;
    Dir: dir0 = TRAINS[t].3;
    0..H+1: raw_intended_r = r0 + dr[dir0];
    0..W+1: raw_intended_c = c0 + dc[dir0];
  } in
  train_row[t, 0] = r0 /\
  train_col[t, 0] = c0 /\
  raw_intended_r >= 1 /\ raw_intended_r <= H /\
  raw_intended_c >= 1 /\ raw_intended_c <= W /\
  let {
    1..H: intended_r = raw_intended_r;
    1..W: intended_c = raw_intended_c;
    Dir: intended_entry_dir = opposite[dir0];
    var bool: blocked_by_gate = % Check if target cell is blocked by closed gate.
      if N_GATES = 0 then false
      elseif cell_has_gate[intended_r, intended_c] then
        not gate_open[gate_index_at[intended_r, intended_c], 1]
      else false endif;
    var bool: blocked_by_semaphore =
      if SEMAPHORE_SUPPLY > 0 /\ semaphore_present[intended_r, intended_c] then
        1 < semaphore_open_time[intended_r, intended_c]
      else false endif;
    var bool: blocked = blocked_by_gate \/ blocked_by_semaphore;
  } in
  can_enter[grid[intended_r, intended_c], intended_entry_dir] /\
  if blocked then
    train_row[t, 1] = r0 /\ % Blocked: stay in place.
    train_col[t, 1] = c0 /\
    train_dir[t, 1] = intended_entry_dir
  else
    train_row[t, 1] = intended_r /\ % Can move: proceed.
    train_col[t, 1] = intended_c /\
    train_dir[t, 1] = intended_entry_dir
  endif
);

% ==== TRAIN MOVEMENT ====
% Movement based on current track piece, handling tunnels, gates, stations, and switches.
constraint forall(t in 1..N_TRAINS, time in 1..(MAX_ARRIVAL[t] - 1) where time < arrival_time[t]) (
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
    var bool: blocked_by_gate = if N_GATES = 0 then false
      elseif cell_has_gate[intended_r, intended_c] then % Check if target is blocked.
        not gate_open[gate_index_at[intended_r, intended_c], time+1]
      else false endif;
    var bool: blocked_by_semaphore =
      if SEMAPHORE_SUPPLY > 0 /\ semaphore_present[intended_r, intended_c] then
        time + 1 < semaphore_open_time[intended_r, intended_c]
      else false endif;
    var bool: blocked = blocked_by_gate \/ blocked_by_semaphore;
    var Piece: effective_piece = % Apply switch state to get actual routing.
      if N_DSWITCHES = 0 then
        if N_ESWITCHES = 0 then piece
        elseif cell_has_eswitch[r, c] then eswitch_effective_piece(piece, eswitch_toggled[eswitch_index_at[r, c], time])
        else piece endif
      elseif cell_has_dswitch[r, c] then dswitch_effective_piece(piece, dswitch_toggled[dswitch_index_at[r, c], time])
      elseif N_ESWITCHES = 0 then piece
      elseif cell_has_eswitch[r, c] then eswitch_effective_piece(piece, eswitch_toggled[eswitch_index_at[r, c], time])
      else piece endif;
  } in

  let {
    var bool: waiting = if N_STATIONS = 0 then false else station_wait_time[t, time] > 0 endif;
  } in
  if waiting then % Wait at station: don't move.
    next_r = r /\
    next_c = c /\
    next_entry_dir = entry_dir
  else
    (if N_TUNNELS > 0 /\ piece in TUNNELS_SET then % Tunnel: teleport to exit.
       let {
         var 1..H: dest_r = tunnel_dest_row[r, c];
         var 1..W: dest_c = tunnel_dest_col[r, c];
         var Dir: dest_exit_dir_enum = to_enum(Dir, tunnel_exit_dir[r, c]);
       } in
       intended_r = dest_r + dr[dest_exit_dir_enum] /\
       intended_c = dest_c + dc[dest_exit_dir_enum] /\
       intended_entry_dir = opposite[dest_exit_dir_enum]
     else % Normal track: follow routing.
       exit_dir = exit_of[effective_piece, entry_dir] /\
       intended_r = r + dr[exit_dir] /\
       intended_c = c + dc[exit_dir] /\
       intended_entry_dir = opposite[exit_dir]
    endif) /\
    can_enter[grid[intended_r, intended_c], intended_entry_dir] /\
    if blocked then % Blocked by gate or semaphore: stay.
      next_r = r /\
      next_c = c /\
      next_entry_dir = entry_dir
    else % Move forward.
      next_r = intended_r /\
      next_c = intended_c /\
      next_entry_dir = intended_entry_dir
    endif  
  endif
);

% ==== TRAIN ARRIVAL CONSTRAINT ====
% Once arrived at target, train stays there for all future timesteps.
constraint forall(t in 1..N_TRAINS, time in 1..MAX_ARRIVAL[t] where time >= arrival_time[t]) (
    train_row[t, time] = TARGET.1 /\
    train_col[t, time] = TARGET.2 /\
    train_dir[t, time] = LEFT % Assumed arrival orientation.
);

% ==== SEQUENTIAL ARRIVAL ====
% Trains must arrive in order (train 1, then 2, etc.).
constraint forall(t in 1..N_TRAINS-1) (
  arrival_time[t] < arrival_time[t+1] % Strict ordering.
);

% ==== NO TRAIN COLLISIONS ====
% No two trains occupy the same cell at the same time (before either arrives).
constraint forall(t1 in 1..N_TRAINS, t2 in t1 + 1..N_TRAINS, i in 1..MAX_ARRIVAL[t1])(
    train_cell[t1, i] != train_cell[t2, i] \/ i >= arrival_time[t1]
);

% ==== NO POSITION SWAPS ====
% Trains cannot swap positions between consecutive timesteps (including tunnels).
constraint forall(t1 in 1..N_TRAINS-1, t2 in t1 + 1..N_TRAINS, i in 1..(MAX_ARRIVAL[t1] - 1))(
    (if N_TUNNELS = 0 then train_cell[t1, i] else tunnel_dest_cell[train_cell[t1, i]] endif) != train_cell[t2, i+1] \/
    (if N_TUNNELS = 0 then train_cell[t2, i] else tunnel_dest_cell[train_cell[t2, i]] endif) != train_cell[t1, i+1] \/
    i >= arrival_time[t1]
);

% ==== REACHABILITY CONES ====
% A train can be at most 'time' steps away from its start position.
constraint forall(t in 1..N_TRAINS, time in 0..MAX_ARRIVAL[t])(
  abs(train_row[t, time] - TRAINS[t].1) + abs(train_col[t, time] - TRAINS[t].2) <= time
);

% A train must be close enough to target to reach it by arrival_time[t].
constraint forall(t in 1..N_TRAINS, time in 0..MAX_ARRIVAL[t] where time < arrival_time[t])(
  abs(train_row[t, time] - TARGET.1) + abs(train_col[t, time] - TARGET.2) <= arrival_time[t] - time
);

% ==== STATIC PARITY-FILTERED ARRIVAL TIME DOMAINS ====
% arrival_time[t] must have correct parity AND be within [MIN_ARRIVAL[t], MAX_ARRIVAL[t]].
% Express this as a set membership constraint to eliminate int_mod at runtime.
array[1..N_TRAINS] of set of int: ARRIVAL_DOMAIN = [
  { v | v in MIN_ARRIVAL[t]..MAX_ARRIVAL[t] where v mod 2 = TRAIN_DIST[t] mod 2 }
| t in 1..N_TRAINS];

constraint forall(t in 1..N_TRAINS)(
  arrival_time[t] in ARRIVAL_DOMAIN[t]
);

% ==== PARITY-AWARE SEQUENTIAL ARRIVAL INCREMENT ====
constraint forall(t in 1..N_TRAINS-1)(
  arrival_time[t+1] >= arrival_time[t] + MIN_STEP_BETWEEN[t]
);


