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
    int: ip = move_cell[p0, dir0];
    Dir: ied = move_entry[p0, dir0];
  } in
  train_pos[t, 0] = p0 /\
  ip > 0 /\ % The first move must stay on the board.
  can_enter[grid_ext[ip], ied] /\
  train_pos[t, 1] = if blocked[ip, 1] then p0 else ip endif /\
  train_dir[t, 1] = ied
);

% ==== TRAIN HEADING ====
% train_heading[t, i]: side the train will leave its cell by.  As in the game
% it is fixed when the train enters the cell, so a train waiting on a switch
% keeps its exit even if the switch toggles under it.  Without toggling
% switches routing never changes and the heading is read off the track.
array[1..N_TRAINS, 1..MAX_TIME] of var Dir: train_heading;
constraint forall(t in 1..N_TRAINS, i in 1..MAX_TIME)(
  let { var Dir: on_entry = exit_of[effective_piece[train_pos[t, i], i], train_dir[t, i]]; } in
  if not SWITCHES_TOGGLE then
    train_heading[t, i] = on_entry
  elseif i = 1 then
    train_heading[t, 1] = if train_pos[t, 1] != train_pos[t, 0] then on_entry else TRAINS[t].3 endif
  else
    train_heading[t, i] = if train_pos[t, i] != train_pos[t, i-1] then on_entry else train_heading[t, i-1] endif
  endif
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
    var Dir: exit_dir = train_heading[t, time];
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

% ==== REACHABILITY PRUNING (redundant) ====
% A train can only be on cells it can reach from its start in the elapsed
% time, and (before arriving) must still be able to reach the target in the
% time it has left.  Waiting only delays a train, so these bounds are exact
% consequences of the movement rules (see lib/globals.mzn).
constraint forall(t in 1..N_TRAINS)(
  let { int: latest = MAX_TIME - (N_TRAINS - t); } in
  arrival_time[t] >= train_dist_from_start[t, TARGET_CELL] /\
  forall(i in 1..MAX_TIME)(
    train_pos[t, i] in { p | p in CELLS where
      train_dist_from_start[t, p] <= i /\
      (p = TARGET_CELL \/ dist_to_target[p] <= latest - i) } /\
    (i < arrival_time[t] -> arrival_time[t] >= i + dist_to_target[train_pos[t, i]])
  )
);

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
