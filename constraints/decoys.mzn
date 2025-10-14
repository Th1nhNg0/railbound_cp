constraint forall(d in 1..N_DECOYS) (
  let {
    int: r0 = DECOYS[d].1;
    int: c0 = DECOYS[d].2;
    Dir: dir0 = DECOYS[d].3;
    int: intended_r = r0 + dr[dir0];
    int: intended_c = c0 + dc[dir0];
    Dir: intended_entry_dir = opposite[dir0];
    var bool: blocked_by_gate =
      if cell_has_gate[intended_r, intended_c] then
        not gate_open[gate_index_at[intended_r, intended_c], 1]
      else false endif;
  } in
  decoy_row[d, 0] = r0 /\
  decoy_col[d, 0] = c0 /\
  can_enter[grid[intended_r, intended_c], intended_entry_dir] /\
  if blocked_by_gate then
    decoy_row[d, 1] = r0 /\
    decoy_col[d, 1] = c0 /\
    decoy_dir[d, 1] = intended_entry_dir
  else
    decoy_row[d, 1] = intended_r /\
    decoy_col[d, 1] = intended_c /\
    decoy_dir[d, 1] = intended_entry_dir
  endif
);


constraint forall(d in 1..N_DECOYS, time in 1..MAX_TIME-1) (
    let {
        var 1..H: r = decoy_row[d, time];
        var 1..W: c = decoy_col[d, time];
        var Dir: entry_dir = decoy_dir[d, time];
        var Piece: piece = grid[r, c];
        var Dir: exit_dir;
        var 1..H: next_r = decoy_row[d, time+1];
        var 1..W: next_c = decoy_col[d, time+1];
        var Dir: next_entry_dir = decoy_dir[d, time+1];
        var 0..H+1: intended_r;
        var 0..W+1: intended_c;
        var Dir: intended_entry_dir;
        var bool: blocked_by_gate = if cell_has_gate[intended_r, intended_c] then
                not gate_open[gate_index_at[intended_r, intended_c], time+1]
            else false endif;
        var Piece: effective_piece = 
            if piece in DSWITCHES_SET then dswitch_effective_piece(piece, dswitch_toggled[dswitch_index_at[r, c], time]) 
            elseif piece in ESWITCHES_SET then eswitch_effective_piece(piece, eswitch_toggled[eswitch_index_at[r, c], time])
            else piece endif;
    } in

    % If the decoy is waiting at a station, it remains stationary.
    if decoy_station_wait_time[d, time] > 0 \/ piece = EMPTY then
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
        if (intended_c >= 1 /\ intended_c <= W /\ intended_r >= 1 /\ intended_r <= H /\
            can_enter[grid[intended_r, intended_c], intended_entry_dir] /\ 
            grid[intended_r,intended_c] !=EMPTY /\ 
            not blocked_by_gate
        ) then
                (next_r, next_c, next_entry_dir) = (intended_r, intended_c, intended_entry_dir)
        else
                (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
        endif
    endif
);


constraint forall(t1 in 1..N_DECOYS, t2 in t1 + 1..N_DECOYS, i in 1..MAX_TIME)(
    (decoy_row[t1, i] != decoy_row[t2, i] \/ decoy_col[t1, i] != decoy_col[t2, i])
);

constraint forall(d in 1..N_DECOYS, t in 1..N_TRAINS, i in 1..MAX_TIME where i<=arrival_time[t])(
    (decoy_row[d, i] != train_row[t, i] \/ decoy_col[d, i] != train_col[t, i])
);
% --- No Position Swap Constraint ---
% Prevents entities from swapping positions in consecutive time steps (including through tunnels).
% Decoy-Decoy position swap prevention
constraint forall(d1 in 1..N_DECOYS, d2 in d1 + 1..N_DECOYS, i in 1..MAX_TIME-1)(
    let {
        var tuple(int, int): eff_pos1 = get_effective_pos(decoy_row[d1, i], decoy_col[d1, i]),
        var tuple(int, int): eff_pos2 = get_effective_pos(decoy_row[d2, i], decoy_col[d2, i])
    } in 
    % They cannot swap positions
    eff_pos1 != (decoy_row[d2, i+1], decoy_col[d2, i+1]) \/
    eff_pos2 != (decoy_row[d1, i+1], decoy_col[d1, i+1])
);

% Decoy-Train position swap prevention
constraint forall(d1 in 1..N_DECOYS, d2 in 1..N_TRAINS, i in 1..MAX_TIME-1 where i <= arrival_time[d2])(
    let {
        var tuple(int, int): eff_pos1 = get_effective_pos(decoy_row[d1, i], decoy_col[d1, i]),
        var tuple(int, int): eff_pos2 = get_effective_pos(train_row[d2, i], train_col[d2, i])
    } in 
    % They cannot swap positions
    eff_pos1 != (train_row[d2, i+1], train_col[d2, i+1]) \/
    eff_pos2 != (decoy_row[d1, i+1], decoy_col[d1, i+1])
);