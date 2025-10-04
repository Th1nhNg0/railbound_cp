% ============================================================
% Scheduling Constraints
% ------------------------------------------------------------
% Movement logic for trains, covering initial placement,
% movement through the grid, and arrival ordering.
% ============================================================

% 1) Initial positions: at time 0 each train is at its start cell
constraint forall(t in 1..N_TRAINS) (
  train_row[t, 0] = TRAINS[t].1 /\
  train_col[t, 0] = TRAINS[t].2
);

% 2) First movement: from start position using initial exit direction
%    Can be blocked by a closed gate (train waits at start position)
constraint forall(t in 1..N_TRAINS) (
  let {
    int: r0 = TRAINS[t].1;
    int: c0 = TRAINS[t].2;
    Dir: exit0 = TRAINS[t].3;
    int: r1 = r0 + dr[exit0];
    int: c1 = c0 + dc[exit0];
    var Piece: p0 = grid[r0, c0];
    var Piece: p1 = grid[r1, c1];
    bool: dest_has_gate = cell_has_gate[r1, c1];
    var bool: blocked_by_gate =
      if dest_has_gate then not gate_open[gate_index_at[r1, c1], 1] else false endif;
  } in
    can_exit[p0, exit0] /\
    can_enter[p1, opposite[exit0]] /\
    if blocked_by_gate then
      (train_row[t, 1], train_col[t, 1], train_dir[t, 1]) = (r0, c0, opposite[exit0])
    else
      (train_row[t, 1], train_col[t, 1], train_dir[t, 1]) = (r1, c1, opposite[exit0])
    endif
);

% 3) Subsequent movements (time >= 1): follow piece routing or stay at target
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
    var bool: blocked_by_gate =
      if N_GATES = 0 then
        false
      else
        if cell_has_gate[intended_r, intended_c] then
          not gate_open[gate_index_at[intended_r, intended_c], time+1]
        else
          false
        endif
      endif;
    var bool: is_dswitch = piece in DSWITCHES_SET;
    var bool: dswitch_state =
      if N_DSWITCHES = 0 then
        false
      else
        if is_dswitch then
          if cell_has_dswitch[r, c] then
            dswitch_swapped[dswitch_index_at[r, c], time]
          else
            false
          endif
        else
          false
        endif
      endif;
  } in
  if r == TARGET.1 /\ c == TARGET.2 then
    (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
  elseif station_wait_time[t, time] > 0 then
    (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
  else
    can_enter[piece, entry_dir] /\
    (
      if is_dswitch then
        exit_dir = dswitch_exit(piece, entry_dir, dswitch_state)
      else
        exit_dir = exit_of[piece, entry_dir]
      endif
    ) /\
    (
      if piece in TUNNELS then
        let {
          var tuple(int, int): dest = tunnel_dest[r, c];
          var int: dest_exit_dir = tunnel_exit_dir[r, c];
          var Dir: dest_exit_dir_enum = to_enum(Dir, dest_exit_dir);
        } in
        intended_r = dest.1 + dr[dest_exit_dir_enum] /\
        intended_c = dest.2 + dc[dest_exit_dir_enum] /\
        intended_entry_dir = opposite[dest_exit_dir_enum]
      else
        intended_r = r + dr[exit_dir] /\
        intended_c = c + dc[exit_dir] /\
        intended_entry_dir = opposite[exit_dir]
      endif
    ) /\
    can_enter[grid[intended_r, intended_c], intended_entry_dir] /\
    if blocked_by_gate then
      (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
    else
      (next_r, next_c, next_entry_dir) = (intended_r, intended_c, intended_entry_dir)
    endif
  endif
);

% 4) Arrival ordering: trains arrive sequentially and remain at the target
constraint forall(t in 1..N_TRAINS) (
  forall(time in 0..MAX_TIME) (
    (train_row[t, time] = TARGET.1 /\ train_col[t, time] = TARGET.2)
    <-> (time >= arrival_time[t])
  )
);

constraint forall(t in 1..N_TRAINS-1) (
  arrival_time[t] < arrival_time[t+1]
);
