% ============================================================
% MOVEMENT CONSTRAINTS
%
% Governs how trains move from cell to cell based on track
% routing, including initial positions and handling of special
% game mechanics like tunnels and dynamic switches.
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
    % Check if first move is blocked by a closed gate
    bool: dest_has_gate = cell_has_gate[r1, c1];
    var bool: blocked_by_gate =
      if dest_has_gate then not gate_open[gate_index_at[r1, c1], 1] else false endif;
  } in
    can_exit[p0, exit0] /\
    can_enter[p1, opposite[exit0]] /\
    if blocked_by_gate then
      % Stay at start position
      train_row[t, 1] = r0 /\
      train_col[t, 1] = c0 /\
      train_dir[t, 1] = opposite[exit0]
    else
      % Move to next position
      train_row[t, 1] = r1 /\
      train_col[t, 1] = c1 /\
      train_dir[t, 1] = opposite[exit0]
    endif
);

% 3) Subsequent movements (time >= 1): follow piece routing or stay at target
%    - Normal pieces: move according to exit_of table
%    - DSWITCHes: use dynamic routing based on current swap state
%    - Tunnels: teleport to paired tunnel and exit in specified direction
%    - At target: stay in place (all trains remain at target once arrived)
%    - Blocked by closed gate: stay in place (train waits)
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
    % Compute the intended next position
    var 1..H: intended_r;
    var 1..W: intended_c;
    var Dir: intended_entry_dir;
    % Check if intended position is blocked by a closed gate
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
    % Check if current piece is a DSWITCH and get its swap state
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
    % Stay at target
    (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
  elseif station_wait_time[t, time] > 0 then
    % Waiting at station - stay in place
    (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
  else
    % Compute intended movement via piece routing
    can_enter[piece, entry_dir] /\
    (
      % Compute exit direction based on piece type
      if is_dswitch then
        exit_dir = dswitch_exit(piece, entry_dir, dswitch_state)
      else
        exit_dir = exit_of[piece, entry_dir]
      endif
    ) /\
    (
      % Check if current piece is a tunnel
      if piece in TUNNELS then
        % Teleport to the paired tunnel
        let {
          var tuple(int, int): dest = tunnel_dest[r, c];
          var int: dest_exit_dir = tunnel_exit_dir[r, c];
          var Dir: dest_exit_dir_enum = to_enum(Dir, dest_exit_dir);
        } in
        % Intended position after tunnel
        intended_r = dest.1 + dr[dest_exit_dir_enum] /\
        intended_c = dest.2 + dc[dest_exit_dir_enum] /\
        intended_entry_dir = opposite[dest_exit_dir_enum]
      else
        % Normal movement
        intended_r = r + dr[exit_dir] /\
        intended_c = c + dc[exit_dir] /\
        intended_entry_dir = opposite[exit_dir]
      endif
    ) /\
    can_enter[grid[intended_r, intended_c], intended_entry_dir] /\
    % If blocked by gate, stay in place; otherwise move to intended position
    if blocked_by_gate then
      (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
    else
      (next_r, next_c, next_entry_dir) = (intended_r, intended_c, intended_entry_dir)
    endif
  endif
);