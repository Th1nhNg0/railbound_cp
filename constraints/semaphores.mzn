% ============================================================
% constraints/semaphores.mzn - Semaphore Placement & Behavior
% ============================================================
% Models user-placeable semaphores that act like gates on track cells
% adjacent to switches. Semaphores start closed, then flip open one timestep
% after any train enters a connected switch that feeds their guarded track,
% remaining open for the rest of the run.
% ============================================================

function var bool: semaphore_trigger(int: r, int: c, var int: t) =
  if t < 2 then false
  else
    exists(d in Dir)(
      let {
        int: sr = r + dr[d];
        int: sc = c + dc[d];
      } in
      sr >= 1 /\ sr <= H /\ sc >= 1 /\ sc <= W /\
      can_connect[grid[r, c], d] /\
      grid[sr, sc] in SWITCH_VARIANTS_SET /\
      can_connect[grid[sr, sc], opposite[d]] /\
      (
        exists(tr in 1..N_TRAINS)(
          arrival_time[tr] >= t - 1 /\
          train_row[tr, t - 1] = sr /\
          train_col[tr, t - 1] = sc /\
          (train_row[tr, t - 2] != sr \/ train_col[tr, t - 2] != sc)
        ) \/
        exists(dq in 1..N_DECOYS)(
          decoy_row[dq, t - 1] = sr /\
          decoy_col[dq, t - 1] = sc /\
          (decoy_row[dq, t - 2] != sr \/ decoy_col[dq, t - 2] != sc)
        )
      )
    )
  endif;

% ==== SUPPLY CONSTRAINT ====
% Player cannot place more semaphores than provided by the puzzle.
constraint
  sum(r in 1..H, c in 1..W)(bool2int(semaphore_present[r, c])) <= SEMAPHORE_SUPPLY;

% If no semaphores are available, force all placement variables to false.
constraint SEMAPHORE_SUPPLY = 0 -> forall(r in 1..H, c in 1..W)(not semaphore_present[r, c]);

% ==== VALID PLACEMENT RULES ====
% Semaphores may only be placed on straights or corners that connect to at least one switch variant.
constraint forall(r in 1..H, c in 1..W)(
  semaphore_present[r, c] ->
    grid[r, c] in SEMAPHORE_ELIGIBLE_SET /\
    exists(d in Dir)(
      let {
        int: sr = r + dr[d];
        int: sc = c + dc[d];
      } in
      if sr >= 1 /\ sr <= H /\ sc >= 1 /\ sc <= W then
        can_connect[grid[r, c], d] /\
        grid[sr, sc] in SWITCH_VARIANTS_SET /\
        can_connect[grid[sr, sc], opposite[d]]
      else false endif
    )
);

% ==== BASE STATE ====
% Cells without a semaphore behave as always-open (open time = 0). Placed semaphores
% have an opening time of at least 2 (cannot open before the trigger timestep).
constraint forall(r in 1..H, c in 1..W)(
  (not semaphore_present[r, c]) -> semaphore_open_time[r, c] = 0
);
constraint forall(r in 1..H, c in 1..W)(
  semaphore_present[r, c] ->
    semaphore_open_time[r, c] >= 2 /\
    semaphore_open_time[r, c] <= MAX_TIME + 1
);

% ==== STATE EVOLUTION ====
% A placed semaphore opens at the earliest trigger timestep if one occurs, otherwise stays closed.
constraint forall(r in 1..H, c in 1..W)(
  semaphore_present[r, c] /\
  semaphore_open_time[r, c] <= MAX_TIME ->
    semaphore_trigger(r, c, semaphore_open_time[r, c])
);
constraint forall(r in 1..H, c in 1..W)(
  semaphore_present[r, c] ->
    forall(t in 2..MAX_TIME)(
      (t < semaphore_open_time[r, c]) -> not semaphore_trigger(r, c, t)
    )
);
