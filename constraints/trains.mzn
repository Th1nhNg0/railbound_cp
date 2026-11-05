% ============================================================
% constraints/trains.mzn - Train Movement & Arrival Constraints
% ============================================================
% Defines train starting positions, movement mechanics through the grid,
% arrival at target, sequencing, and collision avoidance with other trains.
% Positions are cell indices (see lib/globals.mzn).
% ============================================================

% ==== TRAIN INITIAL POSITION ====
% First position (time 0) and first move depend on gate/semaphore blocking.
constraint forall(t in 1..N_TRAINS) (
  let {
    int: p0 = cell(TRAINS[t].1, TRAINS[t].2);
    Dir: dir0 = TRAINS[t].3;
    int: ip = nbr[p0, dir0];
    Dir: ied = opposite[dir0];
  } in
  train_pos[t, 0] = p0 /\
  ip > 0 /\ % The first move must stay on the board.
  can_enter[grid_ext[ip], ied] /\
  train_pos[t, 1] = if blocked[ip, 1] then p0 else ip endif /\
  train_dir[t, 1] = ied
);

% ==== TRAIN MOVEMENT ====
% Follow the (switch-adjusted) track out of the current cell; tunnels are
% folded into move_cell/move_entry.  The next cell must accept the train from
% that side.  A train waits in place at a station or in front of a closed
% gate/semaphore.
constraint forall(t in 1..N_TRAINS, time in 1..MAX_TIME-1 where time < arrival_time[t]) (
  let {
    var CELLS: p = train_pos[t, time];
    var Dir: entry_dir = train_dir[t, time];
    var Dir: exit_dir = exit_of[effective_piece[p, time], entry_dir];
    var CELLS0: ip = move_cell[p, exit_dir]; % 0 = off-board, rejected by can_enter.
    var Dir: ied = move_entry[p, exit_dir];
    var bool: waiting = if N_STATIONS = 0 then false else station_wait_time[t, time] > 0 endif;
  } in
  if waiting then
    train_pos[t, time+1] = p /\
    train_dir[t, time+1] = entry_dir
  else
    can_enter[grid_ext[ip], ied] /\
    if blocked[ip, time+1] then
      train_pos[t, time+1] = p /\
      train_dir[t, time+1] = entry_dir
    else
      train_pos[t, time+1] = ip /\
      train_dir[t, time+1] = ied
    endif
  endif
);

% ==== TRAIN ARRIVAL CONSTRAINT ====
% Once arrived at target, train stays there for all future timesteps.
constraint forall(t in 1..N_TRAINS, time in 1..MAX_TIME where time >= arrival_time[t]) (
    train_pos[t, time] = TARGET_CELL /\
    train_dir[t, time] = LEFT % Assumed arrival orientation.
);

% ==== ARRIVAL CHANNELLING (redundant) ====
% When the target is a fixed straight on the right edge (true for every
% campaign level), a train standing on it before its arrival time would have
% to drive off the board, which the movement rule forbids (unless a station
% on the target let it wait there, hence that guard).  Stating the
% equivalence explicitly lets the solver tie arrival_time to the path.
constraint if init_piece[TARGET_CELL] = STRAIGHT_RL /\ TARGET.2 = W /\
              not exists(st in 1..N_STATIONS)(cell(STATIONS[st].1, STATIONS[st].2) = TARGET_CELL) then
  forall(t in 1..N_TRAINS, time in 1..MAX_TIME)(
    (train_pos[t, time] = TARGET_CELL) <-> (time >= arrival_time[t])
  )
else true endif;

% ==== SEQUENTIAL ARRIVAL ====
% Trains must arrive in order (train 1, then 2, etc.).
constraint forall(t in 1..N_TRAINS) (
  arrival_time[t] >= t /\
  arrival_time[t] <= MAX_TIME - (N_TRAINS - t)
);

constraint forall(t in 1..N_TRAINS-1) (
  arrival_time[t] < arrival_time[t+1] % Strict ordering.
);

% ==== NO TRAIN COLLISIONS ====
% No two trains occupy the same cell at the same time (before either arrives).
constraint forall(t1 in 1..N_TRAINS, t2 in t1 + 1..N_TRAINS, i in 1..MAX_TIME where i < arrival_time[t1])(
    train_pos[t1, i] != train_pos[t2, i]
);

% ==== NO POSITION SWAPS ====
% Trains cannot swap positions between consecutive timesteps (including
% through a tunnel, where the swap is measured between the paired ends).
constraint forall(t1 in 1..N_TRAINS-1, t2 in t1 + 1..N_TRAINS, i in 1..MAX_TIME-1 where i < arrival_time[t1])(
    if N_TUNNELS = 0 then
      train_pos[t1, i] != train_pos[t2, i+1] \/ train_pos[t2, i] != train_pos[t1, i+1]
    else
      tunnel_dest[train_pos[t1, i]] != train_pos[t2, i+1] \/
      tunnel_dest[train_pos[t2, i]] != train_pos[t1, i+1]
    endif
);
