% ============================================================
% constraints/semaphores.mzn - Semaphore Placement & Behavior
% ============================================================
% The player may place up to SEMAPHORE_SUPPLY semaphores on straight or
% corner tiles.  A semaphore starts closed: a vehicle about to enter it waits
% in front of it.  It opens for good as soon as, while some vehicle faces it,
% another vehicle stands on one of the two cells its track connects and is
% not itself heading into the semaphore - i.e. a car has come round to the
% other side.  Opening at step k lets the waiting vehicle move on k -> k+1,
% so semaphore_open_time = k + 1 (MAX_TIME + 1 = never opens).
% ============================================================

constraint forall(r in 1..H, c in 1..W where not semaphore_candidate[cell(r, c)])(
  % Inert cells: fixing the state lets the flattener eliminate it entirely.
  not semaphore_present[r, c] /\ semaphore_open_time[r, c] = 0
);

constraint if HAS_SEMAPHORES then
  let {
    % All vehicles, trains first then decoys, as (position, heading, active).
    int: NV = N_TRAINS + N_DECOYS;
    array[1..NV, 0..MAX_TIME - 1] of var CELLS: v_pos = array2d(1..NV, 0..MAX_TIME - 1, [
      if v <= N_TRAINS then train_pos[v, k] else decoy_pos[v - N_TRAINS, k] endif
    | v in 1..NV, k in 0..MAX_TIME - 1 ]);
    array[1..NV, 0..MAX_TIME - 1] of var Dir: v_head = array2d(1..NV, 0..MAX_TIME - 1, [
      if v <= N_TRAINS then (if k = 0 then TRAINS[v].3 else train_heading[v, k] endif)
      else (if k = 0 then DECOYS[v - N_TRAINS].3 else decoy_heading[v - N_TRAINS, k] endif) endif
    | v in 1..NV, k in 0..MAX_TIME - 1 ]);
    array[1..NV, 0..MAX_TIME - 1] of var bool: v_active = array2d(1..NV, 0..MAX_TIME - 1, [
      if v <= N_TRAINS then k < arrival_time[v] else not decoy_crashed[v - N_TRAINS, k] endif
    | v in 1..NV, k in 0..MAX_TIME - 1 ]);

    % trigger[q, k]: the opening condition for a semaphore on q holds at step k.
    % Column MAX_TIME stands for "never" and is trivially true.
    array[CELLS, 0..MAX_TIME] of var bool: trigger = array2d(CELLS, 0..MAX_TIME, [
      if k = MAX_TIME \/ not semaphore_candidate[q] then true
      else
        exists(a in 1..NV)(
          v_active[a, k] /\ nbr[v_pos[a, k], v_head[a, k]] = q /\ % a faces the semaphore
          exists(b in 1..NV where b != a)(
            v_active[b, k] /\
            exists(d in Dir where nbr[q, d] > 0)(
              can_connect[grid_flat[q], d] /\ v_pos[b, k] = nbr[q, d]) /\
            nbr[v_pos[b, k], v_head[b, k]] != q                     % b not heading in
          )
        )
      endif
    | q in CELLS, k in 0..MAX_TIME ]);
  } in

  % ==== SUPPLY CONSTRAINT ====
  sum(r in 1..H, c in 1..W where not fixed_semaphore[cell(r, c)])(bool2int(semaphore_present[r, c])) <= SEMAPHORE_SUPPLY /\
  forall(r in 1..H, c in 1..W where fixed_semaphore[cell(r, c)])(semaphore_present[r, c]) /\

  forall(r in 1..H, c in 1..W where semaphore_candidate[cell(r, c)])(
    let { int: q = cell(r, c); var 0..(MAX_TIME + 1): open = semaphore_open_time[r, c]; } in
    if semaphore_present[r, c] then
      grid[r, c] in SEMAPHORE_ELIGIBLE_SET /\
      % Opens right after the first step at which the trigger holds.
      open >= 1 /\
      trigger[q, open - 1] /\
      forall(k in 0..MAX_TIME - 1)(k < open - 1 -> not trigger[q, k])
    else
      open = 0
    endif
  )
else true endif;
