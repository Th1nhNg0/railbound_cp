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
      if N_GATES > 0 /\ cell_has_gate[intended_r, intended_c] then
        not gate_open[gate_index_at[intended_r, intended_c], 1]
      else false endif;
  } in
  train_row[t, 0] = r0 /\
  train_col[t, 0] = c0 /\
  if blocked_by_gate then
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
      if N_GATES = 0 then false
      else
        if cell_has_gate[intended_r, intended_c] then
          not gate_open[gate_index_at[intended_r, intended_c], time+1]
        else false endif
      endif;
    var bool: is_dswitch = piece in DSWITCHES_SET;
    % var bool: is_eswitch = piece in ESWITCHES_SET;
    var bool: dswitch_state =
      if N_DSWITCHES > 0 /\ is_dswitch /\ cell_has_dswitch[r, c] then
        dswitch_toggled[dswitch_index_at[r, c], time]
      else false endif;
    % var bool: eswitch_state =
    %   if N_ESWITCHES > 0 /\ is_eswitch /\ cell_has_eswitch[r, c] then
    %     eswitch_swapped[eswitch_index_at[r, c], time]
    %   else false endif;
    var Piece: effective_piece = if is_dswitch then dswitch_effective_piece(piece, dswitch_state) else piece endif;
  } in
  % If the train has reached the target, it remains stationary.
  if r == TARGET.1 /\ c == TARGET.2 then
    (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
  % elseif station_wait_time[t, time] > 0 then
  %   (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
  else
    % Verify that the train can enter the current piece from its entry direction.
    can_enter[piece, entry_dir] /\
    % Determine exit direction using the effective piece (which accounts for dswitch toggle state).
    exit_dir = exit_of[effective_piece, entry_dir] /\
    % Determine the intended next cell based on the exit direction or tunnel destination.
    (if piece in TUNNELS_SET then
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
     endif) /\
    % The train must be able to enter the piece at the intended next cell.
    can_enter[grid[intended_r, intended_c], intended_entry_dir] /\
    % If the path is blocked by a gate, the train waits; otherwise, it moves.
    if blocked_by_gate then
      (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
    else
      (next_r, next_c, next_entry_dir) = (intended_r, intended_c, intended_entry_dir)
    endif
  endif
);

% --- Train Arrival Constraint ---
% A train is considered arrived when it reaches the target and remains there for all subsequent timesteps.
constraint forall(t in 1..N_TRAINS, time in 0..MAX_TIME) (
    (train_row[t, time] = TARGET.1 /\ train_col[t, time] = TARGET.2)
    <-> (time >= arrival_time[t])
);

% --- Sequential Arrival Constraint ---
% Trains must arrive in sequential order (train 1, then train 2, etc.).
constraint forall(t in 1..N_TRAINS-1) (
  arrival_time[t] < arrival_time[t+1]
);

% --- Solver Hints for Better Performance ---
% Add implicit constraint to guide search towards earlier arrivals
constraint forall(t in 1..N_TRAINS-1)(
    arrival_time[t] + 1 <= arrival_time[t+1]
);

% --- No Collision Constraint ---
% Ensures that no two trains occupy the same cell at the same time (before either arrives).
constraint forall(t1 in 1..N_TRAINS, t2 in t1 + 1..N_TRAINS, i in 1..MAX_TIME)(
    (i <= arrival_time[t1] /\ i <= arrival_time[t2]) ->
    (train_row[t1, i] != train_row[t2, i] \/ train_col[t1, i] != train_col[t2, i])
);

% --- No Position Swap Constraint ---
% Prevents trains from swapping positions in consecutive time steps (including through tunnels).
constraint forall(t1 in 1..N_TRAINS, t2 in t1 + 1..N_TRAINS)(
    forall(i in 1..MAX_TIME-1)(
        if i < arrival_time[t1] /\ i < arrival_time[t2] then
            let {
                var 1..H: r1_i = train_row[t1, i];
                var 1..W: c1_i = train_col[t1, i];
                var 1..H: r1_i1 = train_row[t1, i+1];
                var 1..W: c1_i1 = train_col[t1, i+1];

                var 1..H: r2_i = train_row[t2, i];
                var 1..W: c2_i = train_col[t2, i];
                var 1..H: r2_i1 = train_row[t2, i+1];
                var 1..W: c2_i1 = train_col[t2, i+1];

                var Piece: p1_i = grid[r1_i, c1_i];
                var Piece: p2_i = grid[r2_i, c2_i];

                % Get the effective position after tunnel teleportation for the time step i->i+1
                var 1..H: eff_r1_i = if p1_i in TUNNELS_SET then tunnel_dest[r1_i, c1_i].1 else r1_i endif;
                var 1..W: eff_c1_i = if p1_i in TUNNELS_SET then tunnel_dest[r1_i, c1_i].2 else c1_i endif;
                var 1..H: eff_r2_i = if p2_i in TUNNELS_SET then tunnel_dest[r2_i, c2_i].1 else r2_i endif;
                var 1..W: eff_c2_i = if p2_i in TUNNELS_SET then tunnel_dest[r2_i, c2_i].2 else c2_i endif;

            } in
            % If both trains are active, they cannot swap positions.
            (eff_r1_i, eff_c1_i) != (r2_i1, c2_i1) \/
            (eff_r2_i, eff_c2_i) != (r1_i1, c1_i1)
        else
            true
        endif
    )
);