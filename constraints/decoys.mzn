% ============================================================
% constraints/decoys.mzn - Decoy Train Movement & Collision Avoidance
% ============================================================
% Defines decoy movement mechanics and collision constraints with
% other decoys and player trains. Decoys are obstacles to navigate around.
% Unlike trains, a decoy that cannot move (dead end, board edge, closed
% gate/semaphore, empty cell) simply stays where it is.
% ============================================================

% ==== DECOY INITIALIZATION ====
% Starting position and first move, considering gate/semaphore blocking.
constraint forall(d in 1..N_DECOYS) (
  let {
    int: p0 = cell(DECOYS[d].1, DECOYS[d].2);
    Dir: dir0 = DECOYS[d].3;
    int: ip = nbr[p0, dir0];
    Dir: ied = opposite[dir0];
  } in
  decoy_pos[d, 0] = p0 /\
  ip > 0 /\ % The first move must stay on the board.
  can_enter[grid_ext[ip], ied] /\
  decoy_pos[d, 1] = if blocked[ip, 1] then p0 else ip endif /\
  decoy_dir[d, 1] = ied
);

% ==== DECOY MOVEMENT ====
constraint forall(d in 1..N_DECOYS, time in 1..MAX_TIME-1) (
  let {
    var CELLS: p = decoy_pos[d, time];
    var Dir: entry_dir = decoy_dir[d, time];
    var Dir: exit_dir = exit_of[effective_piece[p, time], entry_dir];
    var CELLS0: ip = move_cell[p, exit_dir]; % 0 = off-board: can_enter fails, decoy stays.
    var Dir: ied = move_entry[p, exit_dir];
    var bool: waiting = if N_STATIONS = 0 then false else decoy_station_wait_time[d, time] > 0 endif;
    var bool: moves =
      not waiting /\
      grid_flat[p] != EMPTY /\
      can_enter[grid_ext[ip], ied] /\ % Also rejects EMPTY and off-board targets.
      not blocked[ip, time+1];
  } in
  if moves then
    decoy_pos[d, time+1] = ip /\
    decoy_dir[d, time+1] = ied
  else
    decoy_pos[d, time+1] = p /\
    decoy_dir[d, time+1] = entry_dir
  endif
);

% ==== DECOY-DECOY COLLISION PREVENTION ====
% No two decoys occupy same cell at same time.
constraint forall(d1 in 1..N_DECOYS, d2 in d1 + 1..N_DECOYS, i in 1..MAX_TIME)(
    decoy_pos[d1, i] != decoy_pos[d2, i]
);

% ==== DECOY-TRAIN COLLISION PREVENTION ====
% Decoys don't collide with player trains while active.
constraint forall(d in 1..N_DECOYS, t in 1..N_TRAINS, i in 1..MAX_TIME where i <= arrival_time[t])(
    decoy_pos[d, i] != train_pos[t, i]
);

% ==== TARGET PROTECTION ====
% Decoys never occupy the target cell.
constraint forall(d in 1..N_DECOYS, i in 1..MAX_TIME)(
    decoy_pos[d, i] != TARGET_CELL
);

% ==== DECOY-DECOY POSITION SWAP PREVENTION ====
% No position swaps between consecutive timesteps.
constraint forall(d1 in 1..N_DECOYS, d2 in d1 + 1..N_DECOYS, i in 1..MAX_TIME-1)(
    if N_TUNNELS = 0 then
      decoy_pos[d1, i] != decoy_pos[d2, i+1] \/ decoy_pos[d2, i] != decoy_pos[d1, i+1]
    else
      tunnel_dest[decoy_pos[d1, i]] != decoy_pos[d2, i+1] \/
      tunnel_dest[decoy_pos[d2, i]] != decoy_pos[d1, i+1]
    endif
);

% ==== DECOY-TRAIN POSITION SWAP PREVENTION ====
% Decoys and trains cannot exchange positions.
constraint forall(d in 1..N_DECOYS, t in 1..N_TRAINS, i in 1..MAX_TIME-1 where i < arrival_time[t])(
    if N_TUNNELS = 0 then
      decoy_pos[d, i] != train_pos[t, i+1] \/ train_pos[t, i] != decoy_pos[d, i+1]
    else
      tunnel_dest[decoy_pos[d, i]] != train_pos[t, i+1] \/
      tunnel_dest[train_pos[t, i]] != decoy_pos[d, i+1]
    endif
);
