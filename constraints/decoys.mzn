% ============================================================
% constraints/decoys.mzn - Decoy Train Movement & Collision Avoidance
% ============================================================
% Defines decoy movement mechanics and collision constraints with
% other decoys and player trains. Decoys are obstacles to navigate around.
% Unlike trains, a decoy that cannot move on crashes and stays put.
% ============================================================

% ==== DECOY MOVEMENT ====
% Each step a decoy looks at the cell its track leads to ("intent") and then
%  * waits in place (direction kept) if that cell is behind a closed gate or
%    semaphore, or while it dwells at a station;
%  * otherwise crashes - stops for good - if its track is missing, leads off
%    the board or into a side the next piece cannot accept, or if the next
%    cell is taken: by a train, by a decoy listed earlier that will be there,
%    by a decoy that is standing there, or by a decoy coming the other way;
%  * otherwise moves on.
% This follows the game, where a decoy that would hit something simply
% crashes in place instead of making the level unsolvable.
% Time 0 uses the starting heading; later steps follow the track.
array[1..N_DECOYS, 0..MAX_TIME] of var bool: decoy_crashed;
% Exit side fixed on entering a cell (see train_heading in trains.mzn).
array[1..N_DECOYS, 1..MAX_TIME] of var Dir: decoy_heading;
constraint forall(d in 1..N_DECOYS, i in 1..MAX_TIME)(
  let { var Dir: on_entry = exit_of[effective_piece[decoy_pos[d, i], i], decoy_dir[d, i]]; } in
  if not SWITCHES_TOGGLE then
    decoy_heading[d, i] = on_entry
  elseif i = 1 then
    decoy_heading[d, 1] = if decoy_pos[d, 1] != decoy_pos[d, 0] then on_entry else DECOYS[d].3 endif
  else
    decoy_heading[d, i] = if decoy_pos[d, i] != decoy_pos[d, i-1] then on_entry else decoy_heading[d, i-1] endif
  endif
);
array[1..N_DECOYS, 0..MAX_TIME-1] of var CELLS0: decoy_intent;

constraint forall(d in 1..N_DECOYS)(
  decoy_pos[d, 0] = cell(DECOYS[d].1, DECOYS[d].2) /\ not decoy_crashed[d, 0]
);

constraint forall(d in 1..N_DECOYS, time in 0..MAX_TIME-1) (
  let {
    var CELLS: p = decoy_pos[d, time];
    var Dir: ied;
    var bool: on_track;
    constraint if time = 0 then
        decoy_intent[d, 0] = move_cell[p, DECOYS[d].3] /\ ied = move_entry[p, DECOYS[d].3] /\ on_track
      else
        let { var Dir: exit_dir = decoy_heading[d, time]; } in
        decoy_intent[d, time] = move_cell[p, exit_dir] /\ ied = move_entry[p, exit_dir] /\
        on_track = (grid_flat[p] != EMPTY)
      endif;
    var CELLS0: ip = decoy_intent[d, time];
    var bool: waiting =
      if N_STATIONS = 0 \/ time = 0 then false else decoy_station_wait_time[d, time] > 0 endif;
    var bool: stalled = blocked[ip, time+1];
    var bool: valid = on_track /\ can_enter[grid_ext[ip], ied]; % 0 / EMPTY are never enterable.
    var bool: occupied =
      exists(t in 1..N_TRAINS)(time + 1 <= arrival_time[t] /\ train_pos[t, time+1] = ip) \/
      exists(d2 in 1..N_DECOYS where d2 < d)(decoy_pos[d2, time+1] = ip) \/
      exists(d2 in 1..N_DECOYS where d2 > d)(
        decoy_pos[d2, time] = ip /\ (decoy_pos[d2, time+1] = ip \/ decoy_intent[d2, time] = p));
    var bool: moves = not decoy_crashed[d, time] /\ not waiting /\ not stalled /\ valid /\ not occupied;
  } in
  decoy_crashed[d, time+1] =
    (decoy_crashed[d, time] \/ (not waiting /\ not stalled /\ (not valid \/ occupied))) /\
  if moves then
    decoy_pos[d, time+1] = ip /\ decoy_dir[d, time+1] = ied
  else
    decoy_pos[d, time+1] = p /\
    decoy_dir[d, time+1] = (if time = 0 then ied else decoy_dir[d, time] endif)
  endif
);

% ==== REACHABILITY PRUNING (redundant) ====
% A decoy can only be on cells it can reach from its start in the elapsed time.
constraint forall(d in 1..N_DECOYS, i in 1..MAX_TIME)(
  decoy_pos[d, i] in { p | p in CELLS where decoy_dist_from_start[d, p] <= i }
);

% The level is won once the last train arrives; what decoys do afterwards
% does not matter, so the interaction rules below only apply until then.
var 1..MAX_TIME: game_end = if N_TRAINS = 0 then MAX_TIME else arrival_time[N_TRAINS] endif;

% ==== DECOY-DECOY COLLISION PREVENTION ====
% No two decoys occupy same cell at same time.
constraint forall(d1 in 1..N_DECOYS, d2 in d1 + 1..N_DECOYS, i in 1..MAX_TIME where i <= game_end)(
    decoy_pos[d1, i] != decoy_pos[d2, i]
);

% ==== DECOY-TRAIN COLLISION PREVENTION ====
% Decoys don't collide with player trains while active.
constraint forall(d in 1..N_DECOYS, t in 1..N_TRAINS, i in 1..MAX_TIME where i <= arrival_time[t])(
    decoy_pos[d, i] != train_pos[t, i]
);

% ==== TARGET PROTECTION ====
% Decoys never occupy the target cell.
constraint forall(d in 1..N_DECOYS, i in 1..MAX_TIME where i <= game_end)(
    decoy_pos[d, i] != TARGET_CELL
);

% ==== DECOY-DECOY POSITION SWAP PREVENTION ====
% No position swaps between consecutive timesteps.
constraint forall(d1 in 1..N_DECOYS, d2 in d1 + 1..N_DECOYS, i in 1..MAX_TIME-1 where i < game_end)(
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
