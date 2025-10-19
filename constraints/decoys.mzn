% ============================================================
% constraints/decoys.mzn - Decoy Train Movement & Collision Avoidance
% ============================================================
% Defines decoy movement mechanics and collision constraints with
% other decoys and player trains. Decoys are obstacles to navigate around.
% ============================================================

% ==== DECOY INITIALIZATION ====
% Starting position and first move, considering gate blocking.
constraint forall(d in 1..N_DECOYS) (
  let {
    1..H: r0 = DECOYS[d].1;
    1..W: c0 = DECOYS[d].2;
    Dir: dir0 = DECOYS[d].3;
    0..H+1: raw_intended_r = r0 + dr[dir0];
    0..W+1: raw_intended_c = c0 + dc[dir0];
  } in
  decoy_row[d, 0] = r0 /\
  decoy_col[d, 0] = c0 /\
  raw_intended_r >= 1 /\ raw_intended_r <= H /\
  raw_intended_c >= 1 /\ raw_intended_c <= W /\
  let {
    1..H: intended_r = raw_intended_r;
    1..W: intended_c = raw_intended_c;
    Dir: intended_entry_dir = opposite[dir0];
    var bool: blocked_by_gate = % Check if target is blocked by closed gate.
      if N_GATES >0 /\ cell_has_gate[intended_r, intended_c] then
        not gate_open[gate_index_at[intended_r, intended_c], 1]
      else false endif;
    var bool: blocked_by_semaphore =
      if semaphore_present[intended_r, intended_c] then
        1 < semaphore_open_time[intended_r, intended_c]
      else false endif;
    var bool: blocked = blocked_by_gate \/ blocked_by_semaphore;
  } in
  can_enter[grid[intended_r, intended_c], intended_entry_dir] /\
  if blocked then % Blocked: stay in place.
    decoy_row[d, 1] = r0 /\
    decoy_col[d, 1] = c0 /\
    decoy_dir[d, 1] = intended_entry_dir
  else % Can move: proceed.
    decoy_row[d, 1] = intended_r /\
    decoy_col[d, 1] = intended_c /\
    decoy_dir[d, 1] = intended_entry_dir
  endif
);

% ==== DECOY MOVEMENT ====
% Movement rules: tunnels, switches, gates, stations (same as trains but simpler exit handling).
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
        var bool: blocked_by_gate = if N_GATES >0 /\ cell_has_gate[intended_r, intended_c] then % Check if blocked.
                not gate_open[gate_index_at[intended_r, intended_c], time+1]
            else false endif;
        var bool: blocked_by_semaphore =
            if semaphore_present[intended_r, intended_c] then
                time + 1 < semaphore_open_time[intended_r, intended_c]
            else false endif;
        var bool: blocked = blocked_by_gate \/ blocked_by_semaphore;
        var Piece: effective_piece = % Apply switch state.
            if N_DSWITCHES > 0 /\ cell_has_dswitch[r, c] then dswitch_effective_piece(piece, dswitch_toggled[dswitch_index_at[r, c], time]) 
            elseif N_ESWITCHES > 0 /\ cell_has_eswitch[r, c] then eswitch_effective_piece(piece, eswitch_toggled[eswitch_index_at[r, c], time])
            else piece endif;
    } in

    if piece = EMPTY then % On empty cell: stay.
        (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
    else
        (if piece in TUNNELS_SET then % Tunnel: teleport to exit.
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
        if (intended_c >= 1 /\ intended_c <= W /\ intended_r >= 1 /\ intended_r <= H /\
            can_enter[grid[intended_r, intended_c], intended_entry_dir] /\ 
            grid[intended_r,intended_c] !=EMPTY /\ 
            not blocked
        ) then % Valid move: proceed.
                (next_r, next_c, next_entry_dir) = (intended_r, intended_c, intended_entry_dir)
        else % Invalid move: stay.
                (next_r, next_c, next_entry_dir) = (r, c, entry_dir)
        endif
    endif
);

% ==== DECOY-DECOY COLLISION PREVENTION ====
% No two decoys occupy same cell at same time.
constraint forall(t1 in 1..N_DECOYS, t2 in t1 + 1..N_DECOYS, i in 1..MAX_TIME)(
    (decoy_row[t1, i] != decoy_row[t2, i] \/ decoy_col[t1, i] != decoy_col[t2, i]) % Distinct positions.
);

% ==== DECOY-TRAIN COLLISION PREVENTION ====
% Decoys don't collide with player trains while active.
constraint forall(d in 1..N_DECOYS, t in 1..N_TRAINS, i in 1..MAX_TIME where i<=arrival_time[t])(
    (decoy_row[d, i] != train_row[t, i] \/ decoy_col[d, i] != train_col[t, i]) % Distinct positions.
);

% ==== TARGET PROTECTION ====
% Decoys never occupy the target cell.
constraint forall(d in 1..N_DECOYS, i in 1..MAX_TIME)(
    decoy_row[d, i] != TARGET.1 \/ decoy_col[d, i] != TARGET.2 % Stay away from target.
);

% ==== DECOY-DECOY POSITION SWAP PREVENTION ====
% No position swaps between consecutive timesteps.
constraint forall(d1 in 1..N_DECOYS, d2 in d1 + 1..N_DECOYS, i in 1..MAX_TIME-1)(
    (tunnel_dest_row[decoy_row[d1, i], decoy_col[d1, i]] != decoy_row[d2, i+1] \/
     tunnel_dest_col[decoy_row[d1, i], decoy_col[d1, i]] != decoy_col[d2, i+1]) \/ % d1 did not move to d2's position.
    (tunnel_dest_row[decoy_row[d2, i], decoy_col[d2, i]] != decoy_row[d1, i+1] \/
     tunnel_dest_col[decoy_row[d2, i], decoy_col[d2, i]] != decoy_col[d1, i+1]) % d2 did not move to d1's position.
);

% ==== DECOY-TRAIN POSITION SWAP PREVENTION ====
% Decoys and trains cannot exchange positions.
constraint forall(d in 1..N_DECOYS, t in 1..N_TRAINS, i in 1..MAX_TIME-1 where i < arrival_time[t])(
    (tunnel_dest_row[decoy_row[d, i], decoy_col[d, i]] != train_row[t, i+1] \/
     tunnel_dest_col[decoy_row[d, i], decoy_col[d, i]] != train_col[t, i+1]) \/ % d did not move to t's position.
    (tunnel_dest_row[train_row[t, i], train_col[t, i]] != decoy_row[d, i+1] \/
     tunnel_dest_col[train_row[t, i], train_col[t, i]] != decoy_col[d, i+1]) % t did not move to d's position.
);
