% ============================================================
% constraints/semaphores.mzn - Semaphore Placement & Behavior
% ============================================================
% Models user-placeable semaphores that act like gates on track cells
% adjacent to switches. Semaphores start closed, then flip open one timestep
% after any train enters a connected switch that feeds their guarded track,
% remaining open for the rest of the run.
% ============================================================

constraint forall(r in 1..H, c in 1..W where not semaphore_candidate[cell(r, c)])(
  % Inert cells: fixing the state lets the flattener eliminate it entirely.
  not semaphore_present[r, c] /\ semaphore_open_time[r, c] = 0
);

constraint if SEMAPHORE_SUPPLY > 0 then
  let {
    % linked[q, d]: cell q's track connects through side d to an adjacent switch.
    array[CELLS, Dir] of var bool: linked = array2d(CELLS, Dir, [
      if semaphore_candidate[q] /\ nbr[q, d] > 0 then
        can_connect[grid_flat[q], d] /\
        grid_flat[nbr[q, d]] in SWITCH_VARIANTS_SET /\
        can_connect[grid_flat[nbr[q, d]], opposite[d]]
      else false endif
    | q in CELLS, d in Dir ]);

    % trigger[q, t]: some vehicle entered a switch linked to q at time t - 1.
    % Column MAX_TIME + 1 stands for "never opens" and is trivially true.
    array[CELLS, 1..MAX_TIME + 1] of var bool: trigger = array2d(CELLS, 1..MAX_TIME + 1, [
      if t > MAX_TIME \/ not semaphore_candidate[q] then true
      else
        exists(d in Dir where nbr[q, d] > 0)(
          linked[q, d] /\ (
            exists(tr in 1..N_TRAINS)(train_entered(tr, nbr[q, d], t)) \/
            exists(dq in 1..N_DECOYS)(decoy_entered(dq, nbr[q, d], t))
          )
        )
      endif
    | q in CELLS, t in 1..MAX_TIME + 1 ]);
  } in

  % ==== SUPPLY CONSTRAINT ====
  sum(r in 1..H, c in 1..W)(bool2int(semaphore_present[r, c])) <= SEMAPHORE_SUPPLY /\

  forall(r in 1..H, c in 1..W where semaphore_candidate[cell(r, c)])(
    let { int: q = cell(r, c); var 0..(MAX_TIME + 1): open = semaphore_open_time[r, c]; } in
    if semaphore_present[r, c] then
      % ==== PLACEMENT ELIGIBILITY ====
      grid[r, c] in SEMAPHORE_ELIGIBLE_SET /\
      exists(d in Dir)(linked[q, d]) /\
      % ==== TIMING ====
      % Opens at the first trigger (or never, encoded as MAX_TIME + 1).
      open >= 1 /\
      trigger[q, open] /\
      forall(t in 1..MAX_TIME)(t < open -> not trigger[q, t])
    else
      open = 0
    endif
  )
else true endif;
